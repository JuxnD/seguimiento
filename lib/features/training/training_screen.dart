import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/local_flags.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/active_session.dart';
import '../../data/guided_plan_snapshot.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/plan_v3.dart';
import '../../domain/progress.dart';
import '../../domain/recovery.dart' show planBTorso;
import '../../domain/session_math.dart';
import '../../domain/session_script.dart' show preBlocks, tabataBlock, warmupBlock;
import '../../ui/hero.dart';
import '../../ui/session_style.dart';
import '../../ui/widgets.dart';
import '../../data/repositories/plan_repository.dart';
import '../../data/seed_plan.dart';
import '../plan/plan_screen.dart';
import 'active_session_banner.dart';
import 'football_form_screen.dart';
import 'guided_session_screen.dart';
import 'mobility_screen.dart';
import 'round_counter_screen.dart';
import 'session_form_screen.dart';
import 'v3_timers.dart';

/// Arranca el cronómetro con el plan del día ya cargado: si toca circuito
/// cuenta rondas, si tocan bloques cuenta series. Sin plan, cae al cronómetro
/// libre, que no inventa rondas.
/// `light`: true arranca con la versión ligera marcada (botón de Hoy); null
/// la sugiere si el día anterior hubo un partido intenso o con golpe.
Future<void> startGuidedSession(BuildContext context, WidgetRef ref, {DateTime? date, bool? light}) async {
  final canStart = await _noPendingSession(context, ref);
  if (!canStart || !context.mounted) return;
  final day = date ?? dateOnly(DateTime.now());
  final view = await ref.read(planRepositoryProvider).dayFor(day);

  if (view == null || view.day.exercises.isEmpty) {
    if (!context.mounted) return;
    final libre = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sin plan para hoy'),
        content: const Text('No hay ejercicios planificados para este día. '
            'Puedes usar el cronómetro libre y registrar la sesión a mano.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cronómetro libre')),
        ],
      ),
    );
    if (libre == true && context.mounted) await startFreeCounter(context, ref, date: day);
    return;
  }

  final planDay = view.day;
  if (!planDay.type.isTraining) {
    if (!context.mounted) return;
    final seguir = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Hoy toca ${planDay.type.label.toLowerCase()}'),
        content: const Text('Si entrenas igual, la sesión queda marcada como fuera de plan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Entrenar igual')),
        ],
      ),
    );
    if (seguir != true || !context.mounted) return;
    await startFreeCounter(context, ref, date: day, outOfPlan: true);
    return;
  }

  if (!context.mounted) return;
  // Plan v3 / v3.1: lo que toca depende de la semana del bloque (§18.6,
  // §19.4). El viernes del v3.1 pasa a Cindy o Tabata tras 10 limpias.
  final v3 = await ref.read(trainingRepositoryProvider).blockDay(view, day);
  if (!context.mounted) return;
  if (planDay.type == DayType.resistencia || (v3 != null && v3.isV31 && v3.resistance != null)) {
    await _startResistance(context, ref, day, view, v3?.resistance ?? ResistanceMode.cindy,
        cindyTest: v3?.cindyTest ?? false);
    return;
  }
  final (deloaded, note) = _v3Adjust(planDay, v3);
  final adjusted = await ref.read(trainingRepositoryProvider).withV31Blocks(deloaded, day, v3,
      planche: ref.read(localFlagsProvider).get<bool>(FlagKeys.hasParallettes) == true);
  if (!context.mounted) return;

  // Antes de arrancar: rondas objetivo y, si el bloque alterna, qué variante.
  final variants = adjusted.exercises.map((e) => e.variant).whereType<String>().toSet().toList()..sort();
  // El día de progresión propone la meta según la regla; no la sube solo.
  final proposal =
      planDay.type == DayType.progresion ? await ref.read(trainingRepositoryProvider).progressionProposal(day) : null;
  if (!context.mounted) return;
  final suggestLight = light ?? await ref.read(dashboardRepositoryProvider).hardGameBefore(day);
  if (!context.mounted) return;
  final setup = await showDialog<_SessionSetup>(
    context: context,
    builder: (_) => _SetupDialog(
      day: adjusted,
      variants: variants,
      proposal: proposal,
      light: suggestLight,
      onRecordCriteria: (p) => recordProgressionCriteria(context, ref, p, day),
    ),
  );
  if (setup == null || !context.mounted) return;

  await _runGuided(
    context,
    GuidedSessionScreen(
      day: setup.light ? lightVersion(adjusted) : adjusted,
      date: day,
      planDayId: view.dayId,
      coreVariant: setup.variant,
      roundsOverride: setup.rounds,
      light: setup.light,
      note: note,
    ),
  );
}

/// Plan B de solo torso (§16.15): con 3 días intensos seguidos o molestia en
/// la pierna, el día de hoy sin pierna. Todo a RIR 2; queda anotado.
Future<void> startPlanB(BuildContext context, WidgetRef ref) async {
  final canStart = await _noPendingSession(context, ref);
  if (!canStart || !context.mounted) return;
  final day = dateOnly(DateTime.now());
  await _runGuided(
    context,
    GuidedSessionScreen(
      day: PlanDayDraft(
        weekday: day.weekday,
        type: DayType.trenSuperior,
        exercises: [
          for (final (name, sets, min, max, hold, perSide) in planBTorso)
            PlanExerciseDraft(
              name: name,
              sets: sets,
              repsMin: min,
              repsMax: max,
              holdSecMin: hold,
              perSide: perSide,
              rirMin: hold == null ? 2 : null,
              restSec: 90,
              grip: name == 'Dominadas' ? 'supina' : null,
            ),
        ],
      ),
      date: day,
      sessionType: SessionType.trenSuperior,
      note: 'Plan B (solo torso): carga alta o molestia en la pierna; piernas hasta 48 h después',
    ),
  );
}

/// Semana de descarga del v3 (y lunes a miércoles de la semana del test):
/// una serie menos y sin lastre, anotado en la sesión.
(PlanDayDraft, String?) _v3Adjust(PlanDayDraft day, V3Day? v3) {
  if (v3 == null || !v3.reducedVolume) return (day, null);
  return (deloadVersion(day, half: v3.isV31), v3.deloadNote);
}

/// Miércoles de resistencia del v3: Cindy, Tabata o 10 rondas por tiempo.
/// Se propone lo de la semana y se puede cambiar.
Future<void> _startResistance(
    BuildContext context, WidgetRef ref, DateTime day, PlanDayView view, ResistanceMode suggested,
    {bool cindyTest = false}) async {
  final mode = await showDialog<ResistanceMode>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Resistencia'),
      children: [
        for (final m in [suggested, ...ResistanceMode.values.where((m) => m != suggested)])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, m),
            child: Text(m == suggested ? '${m.label} · toca esta semana' : m.label,
                style: m == suggested ? const TextStyle(fontWeight: FontWeight.w700) : null),
          ),
      ],
    ),
  );
  if (mode == null || !context.mounted) return;
  // Al guardar, Hoy se recarga y el widget que lanzó esto puede desmontarse:
  // el navegador, el aviso y el repositorio se toman antes.
  switch (mode) {
    case ResistanceMode.cindy:
      await _runTimer(context, ref, date: day, mode: 'cindy', cindyTest: cindyTest && mode == suggested);
    case ResistanceMode.tabata:
      final names = [
        for (final e in view.day.exercises)
          if (e.block == tabataBlock) e.name
      ];
      await _runTimer(context, ref, date: day, mode: 'tabata', exercises: names.isEmpty ? tabataExercises : names);
    case ResistanceMode.porTiempo:
      await _runGuided(
        context,
        GuidedSessionScreen(
          day: PlanDayDraft(
            weekday: view.day.weekday,
            type: DayType.circuito,
            targetRounds: 10,
            restBetweenRoundsSec: 30,
            exercises: view.day.main,
          ),
          date: day,
          sessionType: SessionType.resistencia,
          mode: 'porTiempo',
          note: '10 rondas por tiempo: la métrica es el trabajo neto (bajarlo)',
        ),
      );
  }
}

/// Cindy o Tabata con foto en disco: si Android cierra la app a mitad, Hoy
/// ofrece retomarlo donde iba. Al terminar se guarda (sin revisar) y se abre
/// el formulario.
Future<void> _runTimer(
  BuildContext context,
  WidgetRef ref, {
  required DateTime date,
  required String mode,
  List<String> exercises = const [],
  bool cindyTest = false,
  TimerSnapshot? resume,
}) async {
  // Al guardar, Hoy se recarga y el widget que lanzó esto puede desmontarse:
  // el navegador, el aviso y los repositorios se toman antes.
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(trainingRepositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final store = ref.read(activeSessionStoreProvider);
  void save(TimerSnapshot s) => unawaited(store.save(s));
  final draft = await nav.push<SessionDraft>(MaterialPageRoute(
    builder: (_) => mode == 'cindy'
        ? AmrapScreen(date: date, resume: resume, onSnapshot: save)
        : TabataScreen(date: date, exercises: exercises, resume: resume, onSnapshot: save),
  ));
  await _clearActive(container);
  if (draft == null) return;
  // Cindy de prueba (línea base o la de cada 4 semanas): queda anotado.
  if (cindyTest) {
    draft.context = [if ((draft.context ?? '').trim().isNotEmpty) draft.context!.trim(), 'Cindy de prueba'].join('. ');
  }
  await _saveThenReview(nav, messenger, repo, draft);
}

/// Guarda primero (sin revisar) y luego abre el formulario: si se sale sin
/// guardar, la sesión no se pierde (§16.9).
Future<void> _saveThenReview(
    NavigatorState nav, ScaffoldMessengerState messenger, TrainingRepository repo, SessionDraft draft) async {
  draft.pendingReview = true;
  try {
    await repo.save(draft);
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    return;
  }
  final stored = await repo.load(draft.id!);
  if (!nav.mounted) return;
  final saved = await nav.push<bool>(
    MaterialPageRoute(builder: (_) => SessionFormScreen(draft: stored, celebrate: false)),
  );
  if (saved != true) {
    messenger.showSnackBar(const SnackBar(content: Text('Quedó guardada sin revisar: falta el RPE. Está en Hoy.')));
  }
}

/// EMOM de burpees del viernes (§18.10): se suma a la sesión de densidad del
/// día (o crea una si no hay).
Future<void> startBurpeesEmom(BuildContext context, WidgetRef ref, DateTime day, int minutes, int reps) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(trainingRepositoryProvider);
  final result = await Navigator.push<EmomResult>(
    context,
    MaterialPageRoute(builder: (_) => EmomScreen(minutes: minutes, reps: reps)),
  );
  if (result == null) return;
  final note = 'EMOM $minutes × $reps burpees: ${result.completeMinutes}/$minutes minutos completos';
  try {
    final existing = await repo.sessionsOn(day, SessionType.densidad);
    final draft = existing == null
        ? SessionDraft(date: day, type: SessionType.densidad, pendingReview: true)
        : await repo.load(existing);
    draft.sets.addAll([for (final r in result.perMinute) SetDraft(exercise: 'Burpees', reps: r)]);
    draft.context = [if ((draft.context ?? '').trim().isNotEmpty) draft.context!.trim(), note].join('. ');
    await repo.save(draft);
    messenger.showSnackBar(SnackBar(content: Text(note)));
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo guardar el EMOM: $e')));
  }
}

/// Cronómetro guiado → formulario. La foto de la sesión en curso se borra
/// solo cuando se guarda o se descarta: si se sale del formulario sin
/// guardar, la sesión terminada queda pendiente en Hoy (§16.9). Antes se
/// borraba siempre y la sesión se perdía.
Future<void> _runGuided(BuildContext context, GuidedSessionScreen screen) async {
  final container = ProviderScope.containerOf(context, listen: false);
  // La sesión se guarda sola al terminar y Hoy se recarga: el widget que
  // lanzó esto puede desmontarse. Navegador y aviso se toman antes.
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final draft = await nav.push<SessionDraft>(MaterialPageRoute(builder: (_) => screen));
  if (draft == null) {
    // Descartada desde el cronómetro.
    await _clearActive(container);
    return;
  }
  if (!nav.mounted) return;
  // El cierre del cronómetro ya celebró: el formulario no lo repite.
  final saved = await nav.push<bool>(
    MaterialPageRoute(builder: (_) => SessionFormScreen(draft: draft, celebrate: false)),
  );
  if (saved == true) {
    await _clearActive(container);
    return;
  }
  container.invalidate(activeSessionProvider);
  messenger.showSnackBar(SnackBar(
    content: Text(draft.id != null
        ? 'Quedó guardada sin revisar: falta el RPE. Está en Hoy.'
        : 'La sesión quedó pendiente en Hoy: guárdala o descártala desde ahí.'),
  ));
}

Future<void> _clearActive(ProviderContainer container) async {
  await container.read(activeSessionStoreProvider).clear();
  container.invalidate(activeSessionProvider);
}

/// Antes de empezar otra: si quedó una sesión a medias, se ofrece retomarla.
/// Devuelve true si se puede empezar una nueva.
Future<bool> _noPendingSession(BuildContext context, WidgetRef ref) async {
  final pending = await ref.read(activeSessionProvider.future);
  if (pending == null || !context.mounted) return true;
  final choice = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Hay una sesión sin terminar'),
      content: Text('Empezó ${describeActiveSession(pending)}. Si empiezas otra, esa se descarta.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Descartarla')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Retomarla')),
      ],
    ),
  );
  if (choice == null || !context.mounted) return false;
  if (choice) {
    await resumeActiveSession(context, ref, pending);
    return false;
  }
  await _clearActive(ProviderScope.containerOf(context, listen: false));
  return true;
}

/// "el mar 23 sep a las 15:10".
String describeActiveSession(ActiveSession s) {
  final d = parseDay(s.date);
  return 'el ${weekdayShort(d.weekday)} ${formatShort(d)} a las ${timeKey(s.startedAt.hour, s.startedAt.minute)}';
}

/// Retoma el cronómetro que Android cerró, en el punto exacto donde iba.
Future<void> resumeActiveSession(BuildContext context, WidgetRef ref, ActiveSession session) async {
  switch (session) {
    case final GuidedSnapshot s:
      final view = await ref.read(planRepositoryProvider).dayById(s.planDayId);
      if (!context.mounted) return;
      if (view == null) {
        showSnack(context, 'El día del plan de esa sesión ya no existe; se descarta.');
        await _clearActive(ProviderScope.containerOf(context, listen: false));
        return;
      }
      final v3 = await ref.read(trainingRepositoryProvider).blockDay(view, parseDay(s.date));
      final (deloaded, note) = _v3Adjust(view.day, v3);
      // Legado1.20 no incluía escaleras. Añadirlas aquí desplazaría índices
      // de una sesión anterior. Las sesiones nuevas llevan día efectivo.
      final adjusted = await ref.read(trainingRepositoryProvider).withPlanche(deloaded, parseDay(s.date), v3,
          enabled: ref.read(localFlagsProvider).get<bool>(FlagKeys.hasParallettes) == true);
      if (!context.mounted) return;
      PlanDayDraft effective;
      try {
        effective =
            s.effectiveDay == null ? (s.light ? lightVersion(adjusted) : adjusted) : thawGuidedDay(s.effectiveDay!);
      } on Object {
        if (!context.mounted) return;
        showSnack(context, 'La sesión guardada tiene un guion inválido; se descarta para poder empezar otra.');
        await _clearActive(ProviderScope.containerOf(context, listen: false));
        return;
      }
      if (!context.mounted) return;
      await _runGuided(
        context,
        GuidedSessionScreen(
          day: effective,
          note: s.effectiveDay == null ? note : s.note,
          mode: s.mode,
          date: parseDay(s.date),
          planDayId: s.planDayId,
          sessionType: s.sessionType,
          coreVariant: s.coreVariant,
          roundsOverride: s.roundsOverride,
          light: s.light,
          resume: s,
        ),
      );
    case final CounterSnapshot s:
      await _runCounter(context, date: parseDay(s.date), outOfPlan: s.outOfPlan, resume: s);
    case final TimerSnapshot s:
      final date = parseDay(s.date);
      final v3 = await ref
          .read(trainingRepositoryProvider)
          .blockDay(await ref.read(planRepositoryProvider).dayFor(date), date);
      if (!context.mounted) return;
      await _runTimer(context, ref,
          date: date,
          mode: s.mode,
          exercises: s.exercises.isEmpty ? tabataExercises : s.exercises,
          cindyTest: s.mode == 'cindy' && (v3?.cindyTest ?? false),
          resume: s);
  }
}

class _SessionSetup {
  const _SessionSetup(this.rounds, this.variant, {this.light = false});

  final int? rounds;
  final String? variant;
  final bool light;
}

class _SetupDialog extends StatefulWidget {
  const _SetupDialog({
    required this.day,
    required this.variants,
    this.proposal,
    this.light = false,
    this.onRecordCriteria,
  });

  final PlanDayDraft day;
  final List<String> variants;
  final ProgressionProposal? proposal;

  /// Anota los criterios que faltan y devuelve la propuesta recalculada.
  final Future<ProgressionProposal?> Function(ProgressionProposal)? onRecordCriteria;

  /// Empieza con la versión ligera marcada.
  final bool light;

  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<_SetupDialog> {
  late bool _light = widget.light;
  late ProgressionProposal? _proposal = widget.proposal;
  late final _rounds = TextEditingController(text: _roundsFor(_light));
  late String? _variant = widget.variants.isEmpty ? null : widget.variants.first;

  PlanDayDraft get _day => _light ? lightVersion(widget.day) : widget.day;

  /// Meta por defecto: la que propone la regla si es día de progresión (el
  /// plan tiene un número fijo que no avanza); si no, la del plan. La versión
  /// ligera quita una ronda.
  String _roundsFor(bool light) {
    final proposed = _proposal?.rounds;
    if (proposed != null) return '${light && proposed > 1 ? proposed - 1 : proposed}';
    return (light ? lightVersion(widget.day) : widget.day).targetRounds?.toString() ?? '';
  }

  Future<void> _recordCriteria(ProgressionProposal p) async {
    final updated = await widget.onRecordCriteria?.call(p);
    if (updated == null || !mounted) return;
    setState(() {
      _proposal = updated;
      _rounds.text = _roundsFor(_light);
    });
  }

  @override
  void dispose() {
    _rounds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCircuit = widget.day.type.isCircuit;
    final day = _day;
    // Bloques que recorre el cronómetro, agrupados: el pino va antes, el
    // calentamiento del día se hace en la fase de calentamiento y el Tabata
    // tiene su cronómetro.
    final groups = <String, List<PlanExerciseDraft>>{};
    for (final e in day.exercises) {
      if (e.block == null || e.block == tabataBlock || !(e.variant == null || e.variant == _variant)) continue;
      groups.putIfAbsent(e.block!, () => []).add(e);
    }
    String title(String block) => block == warmupBlock
        ? 'Para calentar:'
        : preBlocks.contains(block)
            ? 'Antes, sin fatiga:'
            : 'Después, $block:';
    Widget group(String block) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(title(block), style: Theme.of(context).textTheme.labelLarge),
            for (final e in groups[block]!) Text('• ${e.name} ${e.targetLabel}'.trimRight()),
          ],
        );
    final before = groups.keys.where((b) => b == warmupBlock || preBlocks.contains(b)).toList();
    final after = groups.keys.where((b) => !before.contains(b)).toList();
    return AlertDialog(
      title: Text(widget.day.type.label),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final b in before) group(b),
            if (before.isNotEmpty) const SizedBox(height: 8),
            for (final e in day.main) Text('• ${e.name} ${e.targetLabel}'.trimRight()),
            for (final b in after) group(b),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Versión ligera'),
              subtitle: Text(widget.light
                  ? 'Sugerida: ayer hubo un partido intenso o con golpe'
                  : isCircuit
                      ? 'Una ronda menos y el bloque con una serie menos'
                      : 'Una serie menos en lo que tenga 3 o más, y el rango recortado arriba'),
              value: _light,
              onChanged: (v) => setState(() {
                _light = v;
                _rounds.text = _roundsFor(v);
              }),
            ),
            if (isCircuit) ...[
              const SizedBox(height: 12),
              if (_proposal case final p?)
                _ProposalCard(
                  proposal: p,
                  onUse: (r) => _rounds.text = '$r',
                  onRecord: widget.onRecordCriteria == null || p.sessionId == null ? null : () => _recordCriteria(p),
                ),
              NumberField(controller: _rounds, label: 'Rondas objetivo'),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Bájalas si vienes de un domingo intenso.'),
              ),
            ],
            if (widget.variants.length > 1) ...[
              const SizedBox(height: 12),
              const Text('Variante del bloque'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [for (final v in widget.variants) ButtonSegment(value: v, label: Text(v))],
                selected: {_variant!},
                onSelectionChanged: (s) => setState(() => _variant = s.first),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            // 0 rondas o vacío: se usa la meta del plan.
            _SessionSetup(isCircuit ? _positiveOrNull(int.tryParse(_rounds.text)) : null, _variant, light: _light),
          ),
          child: const Text('Empezar'),
        ),
      ],
    );
  }
}

/// Qué propone la regla de progresión y por qué.
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal, required this.onUse, this.onRecord});

  final ProgressionProposal proposal;
  final ValueChanged<int> onUse;

  /// Anotar los criterios que quedaron sin registrar.
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final text = Theme.of(context).textTheme;
    final when = p.lastDate == null ? 'la última' : 'la del ${formatShort(p.lastDate!)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.canProgress ? 'Propuesta: ${p.rounds} rondas' : 'Propuesta: mantener ${p.rounds}',
              style: text.titleSmall),
          Text(
            p.canProgress
                ? '$when (${p.lastRounds}) cumplió los 5 criterios de la regla.'
                : '$when (${p.lastRounds}): ${p.unmet.join(', ')}.',
            style: text.bodySmall,
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(onPressed: () => onUse(p.rounds), child: Text('Usar ${p.rounds}')),
              if (onRecord != null && p.unmet.any((u) => u.endsWith('sin registrar')))
                TextButton.icon(
                  onPressed: onRecord,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Anotar cómo fue'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Anota técnica, rango y recuperación de la sesión de la que sale la
/// propuesta y devuelve la propuesta recalculada (null si se canceló). Sin
/// estos tres datos la regla nunca deja subir: la meta del viernes se
/// quedaba fija (§16.9).
Future<ProgressionProposal?> recordProgressionCriteria(
    BuildContext context, WidgetRef ref, ProgressionProposal proposal, DateTime day) async {
  final id = proposal.sessionId;
  if (id == null) return null;
  final repo = ref.read(trainingRepositoryProvider);
  final last = await repo.load(id);
  if (!context.mounted) return null;
  final result = await showDialog<(bool?, bool?, bool?)>(
    context: context,
    builder: (_) => _CriteriaDialog(
      date: proposal.lastDate,
      rounds: proposal.lastRounds,
      initial: (last.techniqueOk, last.fullRange, last.recoveryOk),
    ),
  );
  if (result == null) return null;
  await repo.setProgressionCriteria(id, techniqueOk: result.$1, fullRange: result.$2, recoveryOk: result.$3);
  ref.invalidate(dashboardProvider);
  return repo.progressionProposal(day);
}

class _CriteriaDialog extends StatefulWidget {
  const _CriteriaDialog({required this.date, required this.rounds, required this.initial});

  final DateTime? date;
  final int rounds;
  final (bool?, bool?, bool?) initial;

  @override
  State<_CriteriaDialog> createState() => _CriteriaDialogState();
}

class _CriteriaDialogState extends State<_CriteriaDialog> {
  late bool? _technique = widget.initial.$1;
  late bool? _range = widget.initial.$2;
  late bool? _recovery = widget.initial.$3;

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    final when = date == null ? 'la última sesión' : 'el ${weekdayShort(date.weekday)} ${formatShort(date)}';
    return AlertDialog(
      title: const Text('¿Cómo fue?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Las ${widget.rounds} rondas de $when. Con las tres en "Sí" la regla propone subir una.'),
            const SizedBox(height: 8),
            TriToggle(
                label: 'Técnica buena en la última ronda',
                value: _technique,
                onChanged: (v) => setState(() => _technique = v)),
            TriToggle(label: 'Rango completo', value: _range, onChanged: (v) => setState(() => _range = v)),
            TriToggle(label: 'Recuperación normal', value: _recovery, onChanged: (v) => setState(() => _recovery = v)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, (_technique, _range, _recovery)), child: const Text('Guardar')),
      ],
    );
  }
}

/// Cronómetro sin plan: mide tiempos y cuenta vueltas genéricas.
Future<void> startFreeCounter(BuildContext context, WidgetRef ref, {DateTime? date, bool outOfPlan = false}) async {
  final canStart = await _noPendingSession(context, ref);
  if (!canStart || !context.mounted) return;
  await _runCounter(context, date: date ?? dateOnly(DateTime.now()), outOfPlan: outOfPlan);
}

Future<void> _runCounter(BuildContext context,
    {required DateTime date, required bool outOfPlan, CounterSnapshot? resume}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final result = await Navigator.push<CounterResult>(
      context,
      MaterialPageRoute(builder: (_) => RoundCounterScreen(date: date, outOfPlan: outOfPlan, resume: resume)),
    );
    if (result == null || !context.mounted) return;
    final draft = SessionDraft(
      date: date,
      startTime: result.startTime,
      type: SessionType.otro,
      totalSec: result.totalSec,
      warmupSec: result.warmupSec,
      cooldownSec: result.cooldownSec,
      roundsDone: result.rounds == 0 ? null : result.rounds,
      roundMarksSec: result.roundMarksSec,
      outOfPlan: outOfPlan,
    );
    await openSessionForm(context, draft);
  } finally {
    await _clearActive(container);
  }
}

/// true si se guardó (o se borró) la sesión; null si se salió sin guardar.
Future<bool?> openSessionForm(BuildContext context, SessionDraft draft, {bool celebrate = true}) =>
    Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => SessionFormScreen(draft: draft, celebrate: celebrate)));

class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final football = ref.watch(footballProvider);
    final dashboard = ref.watch(dashboardProvider).value;
    final dayType = dashboard?.dayType ?? DayType.descanso;
    final style = styleForDay(dayType);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entreno'),
        actions: [
          IconButton(
            tooltip: 'Plan semanal',
            icon: const Icon(Icons.calendar_view_week),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const ActiveSessionBanner(),
          HeroCard(
            color: style.color,
            overline: dashboard == null ? 'Hoy' : 'Hoy · semana ${dashboard.weekIndex}',
            // Mientras carga no se muestra "Descanso": parpadeaba en gris al abrir.
            title: dashboard == null ? ' ' : dayType.label,
            subtitle: dashboard?.targetRounds == null ? null : 'Meta: ${dashboard!.targetRounds} rondas',
            icon: style.icon,
            pills: [
              if (dashboard != null)
                StatPill(
                  icon: Icons.local_fire_department,
                  label: dashboard.streak == 0
                      ? 'Sin racha'
                      : '${dashboard.streak} ${dashboard.streak == 1 ? 'día' : 'días'}',
                  color: dashboard.streak >= 3 ? style.color : null,
                ),
              if (dashboard?.roundsRecord != null)
                StatPill(icon: Icons.emoji_events_outlined, label: 'Récord ${dashboard!.roundsRecord}'),
            ],
            children: [
              FilledButton.icon(
                onPressed: () => startGuidedSession(context, ref),
                style: FilledButton.styleFrom(backgroundColor: style.color),
                icon: const Icon(Icons.play_arrow),
                label: Text(dayType.isTraining ? 'Empezar ${dayType.label.toLowerCase()}' : 'Empezar sesión'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ActionButton(
                      icon: Icons.edit_note,
                      label: 'A mano',
                      onPressed: () => openSessionForm(context, SessionDraft(date: dateOnly(DateTime.now()))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ActionButton(
                      icon: Icons.sports_soccer,
                      label: 'Fútbol',
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const FootballFormScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => startMobility(context, ref),
                  icon: const Icon(Icons.self_improvement),
                  label: const Text('Movilidad nocturna · opcional'),
                ),
              ),
            ],
          ),
          AppCard(
            title: 'Sesiones',
            children: [
              sessions.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.fitness_center,
                        text: 'Aún no hay sesiones. La primera marca la línea base.',
                        actionLabel: 'Empezar ahora',
                        onAction: () => startGuidedSession(context, ref),
                      )
                    : Column(children: [for (final s in list) _SessionTile(summary: s)]),
              ),
            ],
          ),
          AppCard(
            title: 'Fútbol',
            children: [
              football.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.sports_soccer,
                        text: 'Sin partidos registrados.',
                        actionLabel: 'Registrar partido',
                        onAction: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const FootballFormScreen())),
                      )
                    : Column(children: [for (final g in list) _FootballTile(game: g)]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary.row;
    final date = parseDay(s.date);
    final style = styleForSession(s.type);
    final net =
        circuitNetSec(totalSec: s.totalSec, warmupSec: s.warmupSec, cooldownSec: s.cooldownSec, restSec: s.restSec);
    final flags = [
      if (s.pendingReview) '⚠ sin revisar: falta RPE',
      if (s.outOfPlan) 'fuera de plan',
      if (s.incomplete) 'incompleta',
      if (summary.splitSets > 0) '${summary.splitSets} partidas',
    ];
    return TypedTile(
      icon: style.icon,
      color: style.color,
      title: '${s.type.label} · ${weekdayShort(date.weekday)} ${formatShort(date)}',
      subtitle: [
        'Neto ${formatDuration(net)}',
        if (s.rpe != null) 'RPE ${s.rpe}',
        ...flags,
      ].join(' · '),
      value: s.roundsDone == null ? null : '${s.roundsEstimated ? '~' : ''}${s.roundsDone}',
      valueLabel: s.roundsDone == null ? null : (s.plannedRounds == null ? 'rondas' : 'de ${s.plannedRounds}'),
      onTap: () async {
        final draft = await ref.read(trainingRepositoryProvider).load(s.id);
        if (context.mounted) await openSessionForm(context, draft);
      },
    );
  }
}

class _FootballTile extends StatelessWidget {
  const _FootballTile({required this.game});

  final FootballGameRow game;

  @override
  Widget build(BuildContext context) {
    final date = parseDay(game.date);
    final style = styleForDay(DayType.futbol);
    return TypedTile(
      icon: style.icon,
      color: style.color,
      title: 'Fútbol ${game.format} · ${weekdayShort(date.weekday)} ${formatShort(date)}',
      subtitle: [
        if (game.steps != null) '${game.steps} pasos',
        if (game.intensity != null) 'intensidad ${game.intensity}',
        if (game.fatigueAfter != null) 'fatiga ${game.fatigueAfter}',
      ].join(' · '),
      value: '${game.minutes}',
      valueLabel: 'min',
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FootballFormScreen(existing: game))),
    );
  }
}

int? _positiveOrNull(int? v) => v == null || v <= 0 ? null : v;
