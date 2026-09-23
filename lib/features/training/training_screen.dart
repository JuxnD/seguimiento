import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/session_math.dart';
import '../../ui/widgets.dart';
import '../../data/repositories/plan_repository.dart';
import '../plan/plan_screen.dart';
import 'football_form_screen.dart';
import 'guided_session_screen.dart';
import 'round_counter_screen.dart';
import 'session_form_screen.dart';

/// Arranca el cronómetro con el plan del día ya cargado: si toca circuito
/// cuenta rondas, si tocan bloques cuenta series. Sin plan, cae al cronómetro
/// libre, que no inventa rondas.
Future<void> startGuidedSession(BuildContext context, WidgetRef ref, {DateTime? date}) async {
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
  // Antes de arrancar: rondas objetivo y, si el bloque alterna, qué variante.
  final variants = planDay.exercises.map((e) => e.variant).whereType<String>().toSet().toList()..sort();
  final setup = await showDialog<_SessionSetup>(
    context: context,
    builder: (_) => _SetupDialog(day: planDay, variants: variants),
  );
  if (setup == null || !context.mounted) return;

  final draft = await Navigator.push<SessionDraft>(
    context,
    MaterialPageRoute(
      builder: (_) => GuidedSessionScreen(
        day: planDay,
        date: day,
        planDayId: view.dayId,
        coreVariant: setup.variant,
        roundsOverride: setup.rounds,
      ),
    ),
  );
  if (draft == null || !context.mounted) return;
  await openSessionForm(context, draft);
}

class _SessionSetup {
  const _SessionSetup(this.rounds, this.variant);

  final int? rounds;
  final String? variant;
}

class _SetupDialog extends StatefulWidget {
  const _SetupDialog({required this.day, required this.variants});

  final PlanDayDraft day;
  final List<String> variants;

  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<_SetupDialog> {
  late final _rounds = TextEditingController(text: widget.day.targetRounds?.toString() ?? '');
  late String? _variant = widget.variants.isEmpty ? null : widget.variants.first;

  @override
  void dispose() {
    _rounds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCircuit = widget.day.type.isCircuit;
    return AlertDialog(
      title: Text(widget.day.type.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in widget.day.main) Text('• ${e.name} ${e.targetLabel}'.trimRight()),
          if (isCircuit) ...[
            const SizedBox(height: 12),
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _SessionSetup(isCircuit ? int.tryParse(_rounds.text) : null, _variant),
          ),
          child: const Text('Empezar'),
        ),
      ],
    );
  }
}

/// Cronómetro sin plan: mide tiempos y cuenta vueltas genéricas.
Future<void> startFreeCounter(BuildContext context, WidgetRef ref,
    {DateTime? date, bool outOfPlan = false}) async {
  final result = await Navigator.push<CounterResult>(
    context,
    MaterialPageRoute(builder: (_) => const RoundCounterScreen()),
  );
  if (result == null || !context.mounted) return;
  final draft = SessionDraft(
    date: date ?? dateOnly(DateTime.now()),
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
}


Future<void> openSessionForm(BuildContext context, SessionDraft draft) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => SessionFormScreen(draft: draft)));

class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final football = ref.watch(footballProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entreno'),
        actions: [
          IconButton(
            tooltip: 'Plan',
            icon: const Icon(Icons.calendar_view_week),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          AppCard(
            children: [
              FilledButton.icon(
                onPressed: () => startGuidedSession(context, ref),
                icon: const Icon(Icons.timer),
                label: const Text('Empezar sesión guiada'),
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
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const FootballFormScreen())),
                    ),
                  ),
                ],
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
                    ? const EmptyHint('Aún no hay sesiones.')
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
                    ? const EmptyHint('Sin partidos registrados.')
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
    final net = circuitNetSec(totalSec: s.totalSec, warmupSec: s.warmupSec, cooldownSec: s.cooldownSec);
    final rounds = s.roundsDone == null ? '—' : '${s.roundsEstimated ? '~' : ''}${s.roundsDone}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${weekdayShort(date.weekday)} ${formatShort(date)}'
          '${s.startTime == null ? '' : ' · ${s.startTime}'} · ${s.type.label}'),
      subtitle: Text('Total ${formatDuration(s.totalSec)} · neto ${formatDuration(net)} · '
          'rondas $rounds${s.rpe == null ? '' : ' · RPE ${s.rpe}'}'
          '${summary.splitSets > 0 ? ' · ${summary.splitSets} partidas' : ''}'),
      trailing: const Icon(Icons.chevron_right),
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${weekdayShort(date.weekday)} ${formatShort(date)} · Fútbol ${game.format}'),
      subtitle: Text('${game.minutes} min'
          '${game.steps == null ? '' : ' · ${game.steps} pasos'}'
          '${game.intensity == null ? '' : ' · intensidad ${game.intensity}'}'
          '${game.fatigueAfter == null ? '' : ' · fatiga ${game.fatigueAfter}'}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => FootballFormScreen(existing: game))),
    );
  }
}
