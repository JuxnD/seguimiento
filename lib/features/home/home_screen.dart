import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart' show FoodRow;
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/habits.dart';
import '../../domain/meal_slots.dart';
import '../../domain/nutrition.dart';
import '../../domain/plan_v3.dart';
import '../plan/v3_activation.dart';
import '../../domain/progress.dart';
import '../../ui/progress_ring.dart';
import '../../ui/session_style.dart';
import '../../ui/widgets.dart';
import '../body/measurement_form_screen.dart';
import '../meals/meal_form_screen.dart';
import 'steps_source_line.dart';
import 'walk_screen.dart';
import '../report/summary_screen.dart';
import '../../data/local_flags.dart';
import '../settings/corrections_screen.dart';
import '../settings/custom_reminders.dart';
import '../settings/settings_screen.dart';
import '../settings/updates_card.dart';
import '../training/active_session_banner.dart';
import '../training/football_form_screen.dart';
import '../training/mobility_screen.dart';
import '../training/training_screen.dart';
import '../../ui/theme.dart';

/// Pantalla de entrada: qué toca hoy, cómo voy y cómo registrarlo rápido.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoy'),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (d) => RefreshIndicator(
          // Deslizar hacia abajo trae los pasos del reloj al instante.
          onRefresh: () async {
            await ref.read(syncStepsProvider)();
            ref.invalidate(dashboardProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const ActiveSessionBanner(),
              UpdateBanner(
                onOpenSettings: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
              _PlanHero(dashboard: d),
              _RingsCard(dashboard: d),
              const _PendingReviewCard(),
              _YesterdayCheckCard(today: today),
              const _CorrectionsBanner(),
              const TodayCustomRemindersCard(),
              _WeekGlanceCard(today: today),
              if (d.v3Suggestion != null) _V3SuggestionCard(monday: d.v3Suggestion!),
              _ActionsCard(
                date: today,
                dayType: d.dayType,
                burpees: d.dayType == DayType.densidad ? d.v3?.burpees : null,
              ),
              if (d.measurement != null) _MeasurementCard(due: d.measurement!),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo primero que se ve: qué toca hoy, con color e icono del tipo.
class _PlanHero extends StatelessWidget {
  const _PlanHero({required this.dashboard});

  final TodayDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final style = styleForDay(dashboard.dayType);
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [style.color.withOpacity(0.22), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${weekdayLong(dashboard.date.weekday)} ${formatShort(dashboard.date)}'.toUpperCase(),
                    style: text.labelSmall?.copyWith(letterSpacing: 1)),
                const Spacer(),
                _Chip(
                  icon: Icons.local_fire_department,
                  label: dashboard.streak == 0
                      ? 'Sin racha'
                      : '${dashboard.streak} ${dashboard.streak == 1 ? 'día' : 'días'}',
                  color: dashboard.streak >= 3 ? style.color : null,
                ),
                const SizedBox(width: 6),
                _Chip(icon: Icons.calendar_today_outlined, label: 'Sem ${dashboard.weekIndex}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: style.color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(style.icon, size: 30, color: style.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dashboard.dayType.label.toUpperCase(),
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: style.color,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (dashboard.targetRounds != null)
                        Text('Meta: ${dashboard.targetRounds} rondas', style: text.titleSmall),
                      if (dashboard.planVersion != null) Text('Plan v${dashboard.planVersion}', style: text.bodySmall),
                    ],
                  ),
                ),
                if (dashboard.trained) Icon(Icons.check_circle, color: style.color, size: 28),
              ],
            ),
            if (dashboard.mainExercises.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final e in dashboard.mainExercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('• $e', style: text.bodyMedium),
                ),
            ],
            if (dashboard.blockExercises.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                dashboard.blockExercises.any((l) => l.contains(' A:')) &&
                        dashboard.blockExercises.any((l) => l.contains(' B:'))
                    ? 'Además (A y B se alternan por semana):'
                    : 'Además:',
                style: text.labelLarge,
              ),
              for (final line in dashboard.blockExercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('• $line', style: text.bodyMedium),
                ),
            ],
            if (dashboard.hardFootballYesterday case final game? when dashboard.dayType.isTraining)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ayer fútbol ${game.knock == true ? 'con golpe o molestia' : 'intenso (${game.intensity}/10)'}: '
                  'hoy conviene la versión ligera (una ronda menos, el bloque con una serie menos).',
                  style: text.bodyMedium?.copyWith(color: style.color),
                ),
              ),
            if (dashboard.proposal case final p? when !dashboard.trained)
              _ProposalLine(proposal: p, date: dashboard.date, color: style.color),
            if (dashboard.v3 case final v3?) _V3Strip(v3: v3, dashboard: dashboard, color: style.color),
            if (dashboard.dayType == DayType.descanso)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Día de descanso. La racha no se rompe.', style: text.bodyMedium),
              ),
            // Lo de todos los días, a la vista: con el v3.1 el día tiene 8–12
            // ejercicios y "Empezar" quedaba debajo de varias tarjetas.
            if (dashboard.dayType.isTraining) ...[
              const SizedBox(height: 14),
              _StartButtons(dashboard: dashboard, color: style.color),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empezar la sesión del día (y la versión ligera si ayer hubo partido
/// intenso), dentro de la tarjeta principal.
class _StartButtons extends ConsumerWidget {
  const _StartButtons({required this.dashboard, required this.color});

  final TodayDashboard dashboard;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dashboard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => startGuidedSession(context, ref),
          style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(52)),
          icon: Icon(d.trained ? Icons.replay : Icons.play_arrow),
          label: Text('${d.trained ? 'Otra sesión de' : 'Empezar'} ${d.dayType.label.toLowerCase()}'),
        ),
        if (d.hardFootballYesterday != null && !d.trained) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => startGuidedSession(context, ref, light: true),
            icon: const Icon(Icons.battery_charging_full),
            label: const Text('Aplicar versión ligera'),
          ),
        ],
      ],
    );
  }
}

/// Sesiones guardadas solas al terminar el cronómetro y todavía sin revisar:
/// ya cuentan, pero les falta el RPE (§16.9). No se pierden por no tocar un
/// botón.
class _PendingReviewCard extends ConsumerWidget {
  const _PendingReviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingReviewProvider).valueOrNull ?? const [];
    if (pending.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in pending)
              Row(
                children: [
                  Icon(Icons.pending_actions, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sesión sin revisar', style: text.titleSmall),
                        Text(
                          [
                            '${s.type.label} ${weekdayShort(parseDay(s.date).weekday)} ${formatShort(parseDay(s.date))}',
                            if (s.roundsDone case final n?) '$n ${n == 1 ? 'ronda' : 'rondas'}',
                            'falta RPE',
                          ].join(' · '),
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final draft = await ref.read(trainingRepositoryProvider).load(s.id);
                      if (context.mounted) await openSessionForm(context, draft);
                    },
                    child: const Text('Revisar'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Mientras haya correcciones del traspaso sin aplicar (y el usuario no haya
/// dicho que no), Hoy las ofrece una vez.
class _CorrectionsBanner extends ConsumerWidget {
  const _CorrectionsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingCorrectionsProvider);
    if (pending == 0) return const SizedBox.shrink();
    return AppCard(
      title: 'Correcciones del traspaso',
      children: [
        Text('$pending ${pending == 1 ? 'corrección' : 'correcciones'} del traspaso por aplicar '
            '(sesiones, comidas y medidas). Revísalas antes: solo se toca lo que coincide exacto.'),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: () async {
                await ref.read(localFlagsProvider).set(FlagKeys.corrections29SepDismissed, true);
                ref.invalidate(pendingCorrectionsProvider);
              },
              child: const Text('No aplicar'),
            ),
            const Spacer(),
            FilledButton(onPressed: () => openCorrections(context), child: const Text('Revisar')),
          ],
        ),
      ],
    );
  }
}

/// La semana del programa en tres números, con entrada al resumen completo.
class _WeekGlanceCard extends ConsumerWidget {
  const _WeekGlanceCard({required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = ref.watch(profileProvider).valueOrNull?.programStart;
    if (start == null) return const SizedBox.shrink();
    final week = weekContaining(start, today);
    final s = ref.watch(periodSummaryProvider((dayKey(week.start), dayKey(week.end)))).valueOrNull;
    if (s == null || s.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final top = s.exercises.where((e) => !e.isHold).take(3).toList();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SummaryScreen())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('ESTA SEMANA', style: text.labelSmall?.copyWith(letterSpacing: 1)),
                  const Spacer(),
                  Text('Ver más', style: text.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
                  Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.primary),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  for (final e in top) _GlanceNumber(value: fmtInt(e.amount), label: e.name.toLowerCase()),
                  if (s.stepsTotal > 0) _GlanceNumber(value: fmtInt(s.stepsTotal), label: 'pasos'),
                  if (s.kcalBurned case final k?) _GlanceNumber(value: '≈ ${fmtInt(k)}', label: 'kcal moviéndote'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlanceNumber extends StatelessWidget {
  const _GlanceNumber({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: text.bodySmall),
      ],
    );
  }
}

/// Día de progresión: de dónde sale la meta. Si la regla no deja subir solo
/// porque faltó anotar cómo fue la última, se anota aquí mismo.
class _ProposalLine extends ConsumerWidget {
  const _ProposalLine({required this.proposal, required this.date, required this.color});

  final ProgressionProposal proposal;
  final DateTime date;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = proposal;
    final text = Theme.of(context).textTheme;
    final last = p.lastDate == null ? 'la última' : 'la del ${formatShort(p.lastDate!)}';
    final missing = p.unmet.any((u) => u.endsWith('sin registrar'));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.canProgress
                ? 'Toca intentar ${p.rounds}: $last (${p.lastRounds}) cumplió la regla.'
                : 'Se mantiene en ${p.rounds} ($last: ${p.unmet.join(', ')}).',
            style: text.bodyMedium?.copyWith(color: p.canProgress ? color : null),
          ),
          if (missing && p.sessionId != null)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => recordProgressionCriteria(context, ref, p, date),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Anotar cómo fue'),
            ),
        ],
      ),
    );
  }
}

/// Anillos: proteína, kcal y rondas. El progreso se ve, no se lee.
class _RingsCard extends StatelessWidget {
  const _RingsCard({required this.dashboard});

  final TodayDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    final style = styleForDay(d.dayType);
    final showRounds = d.targetRounds != null;
    // Cuatro anillos en un teléfono de 360 dp: más pequeños que los tres de antes.
    const size = 74.0;
    return AppCard(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ProgressRing(
              size: size,
              progress: d.proteinProgress,
              value: fmtInt(d.macros.protein),
              sublabel: 'de ${d.proteinMin}',
              label: 'Proteína',
              color: AppColors.protein,
            ),
            ProgressRing(
              size: size,
              progress: d.kcalProgress,
              value: fmtInt(d.macros.kcal),
              sublabel: 'de ${fmtInt(d.kcalTarget)}',
              label: 'kcal',
              color: AppColors.kcal,
            ),
            _StepsRing(dashboard: d, size: size),
            if (showRounds)
              ProgressRing(
                size: size,
                progress: d.roundsProgress,
                value: '${d.roundsDone ?? 0}',
                sublabel: 'de ${d.targetRounds}',
                label: 'Rondas',
                color: style.color,
              )
            else if (d.footballToday case final game? when d.sessionsToday == 0)
              ProgressRing(
                size: size,
                progress: 1,
                value: "${game.minutes}'",
                sublabel: game.intensity == null ? 'fútbol ${game.format}' : 'intensidad ${game.intensity}',
                label: 'Fútbol',
                color: style.color,
              )
            else
              ProgressRing(
                size: size,
                progress: d.trained ? 1 : 0,
                value: d.trained ? '✓' : '—',
                label: 'Sesión',
                color: style.color,
              ),
          ],
        ),
        if (d.roundsRecord != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(d.recentRecord ? Icons.emoji_events : Icons.emoji_events_outlined,
                  size: 18, color: d.recentRecord ? AppColors.record : null),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.recentRecord
                      ? '¡Récord nuevo! ${d.roundsRecord} rondas el '
                          '${weekdayShort(d.recordDate!.weekday)} ${formatShort(d.recordDate!)}'
                      : 'Récord de rondas: ${d.roundsRecord}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: d.recentRecord ? AppColors.record : null,
                        fontWeight: d.recentRecord ? FontWeight.w700 : null,
                      ),
                ),
              ),
            ],
          ),
          if (d.recordSuspect != null) _RecordSuspectTile(suspect: d.recordSuspect!),
        ],
        _WalksLine(dashboard: d),
        const StepsSourceLine(),
        _SleepLine(date: d.date),
        _EggsLine(date: d.date),
        _CloseDayLine(dashboard: d),
      ],
    );
  }
}

/// Sueño (§19.3): por la mañana, si no se anotó, las horas en cama de un
/// toque; después, la cifra (tocarla la cambia).
class _SleepLine extends ConsumerWidget {
  const _SleepLine({required this.date});

  final DateTime date;

  static const _options = [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0];

  Future<void> _set(WidgetRef ref, double hours) => ref.read(sleepRepositoryProvider).set(date, hours);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hours = ref.watch(sleepDayProvider(dayKey(date))).valueOrNull;
    final text = Theme.of(context).textTheme;
    if (hours != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InkWell(
          onTap: () => ref.read(sleepRepositoryProvider).remove(date),
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined, size: 18, color: hours >= sleepGoalHours ? AppColors.protein : null),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Anoche: ${fmtDec(hours)} h en cama${hours >= sleepGoalHours ? '' : ' · meta ${fmtInt(sleepGoalHours)} h'}',
                    style: text.bodyMedium),
              ),
            ],
          ),
        ),
      );
    }
    if (DateTime.now().hour >= 14 && dateOnly(DateTime.now()) == date) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.bedtime_outlined, size: 18),
            const SizedBox(width: 8),
            Text('¿Cuántas horas en cama anoche?', style: text.bodyMedium),
          ]),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final h in _options)
                ActionChip(label: Text(fmtDec(h)), onPressed: () => _set(ref, h)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Huevos enteros del día (§19.6): la meta es 2–3 más claras; a partir de 5
/// avisa.
class _EggsLine extends ConsumerWidget {
  const _EggsLine({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(mealsForDayProvider(dayKey(date))).valueOrNull ?? const [];
    // Huevos por porción de cada alimento del catálogo: cuentan aunque vengan
    // dentro de un plato o un combo (§16.15).
    final eggsPer = {
      for (final f in ref.watch(foodsProvider).valueOrNull ?? const <FoodRow>[])
        if (f.eggsPerUnit != null) f.id: f.eggsPerUnit!,
    };
    final eggs = wholeEggs([
      for (final m in meals)
        for (final i in m.items)
          (label: i.label, quantity: i.quantity, unit: i.quantityUnit, eggsPerUnit: eggsPer[i.foodId]),
    ]);
    if (eggs < 1) return const SizedBox.shrink();
    final warn = eggs >= eggWarnAt;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.egg_outlined, size: 18, color: warn ? AppColors.kcal : null),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Huevos enteros hoy: ${fmtDec(eggs)}${warn ? ' · la meta es 2–3 y el resto claras' : ''}',
              style: text.bodyMedium?.copyWith(color: warn ? AppColors.kcal : null),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pasos de hoy. Tocarlo abre el registro: se leen del reloj y se anotan.
class _StepsRing extends ConsumerWidget {
  const _StepsRing({required this.dashboard, required this.size});

  final TodayDashboard dashboard;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dashboard;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => editStepsDialog(context, ref, d.date, d.stepsToday),
      child: ProgressRing(
        size: size,
        progress: d.stepsProgress,
        value: d.stepsToday == null ? '—' : compactSteps(d.stepsToday!),
        sublabel: d.stepsGoal == null ? 'sin meta' : 'de ${compactSteps(d.stepsGoal!)}',
        label: 'Pasos',
        color: AppColors.steps,
      ),
    );
  }
}

/// 7.500 → "7,5k"; 950 → "950". Cabe en el anillo pequeño.
String compactSteps(int steps) => steps < 1000 ? '$steps' : '${fmtDec(steps / 1000)}k';

/// Anotar los pasos de un día. Vacío borra la cifra.
Future<void> editStepsDialog(BuildContext context, WidgetRef ref, DateTime date, int? current) async {
  final result = await showDialog<String>(context: context, builder: (_) => _StepsDialog(date: date, current: current));
  if (result == null || !context.mounted) return;
  final repo = ref.read(stepsRepositoryProvider);
  final steps = int.tryParse(result.replaceAll(RegExp(r'[.\s]'), ''));
  if (result.trim().isEmpty) {
    await guarded(context, () => repo.clear(date));
  } else if (steps == null || steps < 0) {
    showSnack(context, 'Escribe solo el número de pasos');
  } else {
    await guarded(context, () => repo.setSteps(date, steps));
  }
}

/// Dueño de su controller: se libera cuando el diálogo termina de cerrarse,
/// no mientras todavía anima la salida.
class _StepsDialog extends StatefulWidget {
  const _StepsDialog({required this.date, this.current});

  final DateTime date;
  final int? current;

  @override
  State<_StepsDialog> createState() => _StepsDialogState();
}

class _StepsDialogState extends State<_StepsDialog> {
  late final _controller = TextEditingController(text: widget.current?.toString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Pasos del ${weekdayLong(widget.date.weekday).toLowerCase()} ${formatShort(widget.date)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NumberField(controller: _controller, label: 'Pasos', autofocus: true),
            const SizedBox(height: 8),
            const Text('Léelos del reloj o del teléfono. Registrar otra vez reemplaza la cifra del día.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Guardar')),
        ],
      );
}

/// El récord viene de un día que el plan no marca como circuito: casi siempre
/// un día de bloques guardado como circuito. Corregir el tipo lo saca.
class _RecordSuspectTile extends ConsumerWidget {
  const _RecordSuspectTile({required this.suspect});

  final RecordSuspect suspect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sale del ${weekdayLong(suspect.date.weekday)} ${formatShort(suspect.date)}, '
              'que en el plan era de ${suspect.plannedType.label.toLowerCase()}. '
              'Si fue ${suspect.plannedType.label.toLowerCase()}, corrige el tipo y el récord se recalcula.',
              style: text.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () async {
              final draft = await ref.read(trainingRepositoryProvider).load(suspect.sessionId);
              if (context.mounted) await openSessionForm(context, draft, celebrate: false);
            },
            child: const Text('Revisar'),
          ),
        ],
      ),
    );
  }
}

class _ActionsCard extends ConsumerStatefulWidget {
  const _ActionsCard({required this.date, required this.dayType, this.burpees});

  final DateTime date;
  final DayType dayType;

  /// Viernes del v3: EMOM de burpees (minutos, burpees por minuto).
  final (int, int)? burpees;


  @override
  ConsumerState<_ActionsCard> createState() => _ActionsCardState();
}

/// Registrar: el cronómetro es siempre para hoy; sesión, fútbol, comida y
/// medición se pueden anotar en cualquiera de los últimos 7 días (§16.12:
/// el 4 oct no se pudo registrar la cena ni el fútbol del sábado).
class _ActionsCardState extends ConsumerState<_ActionsCard> {
  late DateTime _target = widget.date;

  @override
  void didUpdateWidget(_ActionsCard old) {
    super.didUpdateWidget(old);
    // Pasó la medianoche: "hoy" es otro día.
    if (old.date != widget.date && _target == old.date) _target = widget.date;
  }

  DateTime get _today => widget.date;
  DateTime get _yesterday => addDays(_today, -1);

  Future<void> _pickOther() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _target,
      firstDate: addDays(_today, -7),
      lastDate: _today,
      helpText: 'Registrar en…',
    );
    if (picked != null) setState(() => _target = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final style = styleForDay(widget.dayType);
    final text = Theme.of(context).textTheme;
    final isToday = _target == _today;
    final other = !isToday && _target != _yesterday;
    final targetLabel = isToday ? 'hoy' : '${weekdayShort(_target.weekday)} ${formatShort(_target)}';
    return AppCard(
      title: 'Registrar',
      children: [
        // En días de entrenamiento "Empezar" está en la tarjeta principal; aquí
        // queda el cronómetro para entrenar igual un día de fútbol o descanso.
        if (!widget.dayType.isTraining)
          FilledButton.icon(
            onPressed: () => startGuidedSession(context, ref),
            style: FilledButton.styleFrom(backgroundColor: style.color),
            icon: const Icon(Icons.timer),
            label: const Text('Empezar sesión'),
          ),
        if (widget.burpees case (final minutes, final reps)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => startBurpeesEmom(context, ref, widget.date, minutes, reps),
            icon: const Icon(Icons.local_fire_department),
            label: Text('Finisher: EMOM $minutes min · $reps burpees'),
          ),
        ],
        const SizedBox(height: 12),
        Text('Anotar en', style: text.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            ChoiceChip(label: const Text('Hoy'), selected: isToday, onSelected: (_) => setState(() => _target = _today)),
            ChoiceChip(
              label: const Text('Ayer'),
              selected: _target == _yesterday,
              onSelected: (_) => setState(() => _target = _yesterday),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.calendar_month, size: 16),
              label: Text(other ? '${weekdayShort(_target.weekday)} ${formatShort(_target)}' : 'Otro día'),
              selected: other,
              onSelected: (_) => _pickOther(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.edit_note,
                label: 'Sesión',
                onPressed: () => openSessionForm(context, SessionDraft(date: _target)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.sports_soccer,
                label: 'Fútbol',
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => FootballFormScreen(date: _target))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.restaurant,
                label: 'Comida',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MealFormScreen(draft: _mealNow(_target))),
                ),
              ),
            ),
          ],
        ),
        if (!isToday)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Se anota el $targetLabel: cuenta en ese día, en la racha y en el informe.',
                style: text.bodySmall),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => MeasurementFormScreen(initialDate: _target))),
              icon: const Icon(Icons.straighten),
              label: const Text('Medición'),
            ),
            TextButton.icon(
              onPressed: () => startMobility(context, ref),
              icon: const Icon(Icons.self_improvement),
              label: const Text('Movilidad nocturna · opcional'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Plan v3 en Hoy: semana y fase del bloque, qué toca el miércoles, aviso de
/// descarga y cuenta atrás al test final (§18.6, §18.9).
class _V3Strip extends StatelessWidget {
  const _V3Strip({required this.v3, required this.dashboard, required this.color});

  final V3Day v3;
  final TodayDashboard dashboard;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final daysToTest = daysBetween(dashboard.date, v3.testDate);
    final total = v3.totalWeeks;
    final week = v3.week > total ? 'después del test' : 'semana ${v3.week} de $total';
    final resistance = v3.resistance;
    final fridayCircuit = v3.isV31 && dashboard.dayType == DayType.progresion;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${v3.title} · $week · ${v3.phase.label}', style: text.labelLarge?.copyWith(color: color)),
          if (v3.reducedVolume || (v3.isV31 && v3.week == 1)) Text(v3.hint, style: text.bodyMedium),
          if (dashboard.dayType == DayType.resistencia && resistance != null)
            Text(
                '${v3.isV31 ? 'Hoy' : 'Esta semana'}: ${resistance.label}'
                '${v3.cindyTest && resistance == ResistanceMode.cindy ? ' · de prueba' : ''}',
                style: text.bodyMedium),
          if (fridayCircuit)
            Text('Circuito hasta cerrar 10 rondas limpias; después, Cindy y Tabata en semanas alternas.',
                style: text.bodySmall),
          if (dashboard.midweekGame)
            Text('Hubo partido entre semana: reemplaza la sesión metabólica de hoy. Pino, habilidades y movilidad.',
                style: text.bodyMedium?.copyWith(color: color)),
          if (dashboard.dayType == DayType.densidad && v3.burpees == null && !v3.reducedVolume)
            Text('Sin burpees esta semana.', style: text.bodySmall),
          if (daysToTest > 0)
            Text('Faltan $daysToTest días para ${v3.isV31 ? 'las pruebas' : 'el test final'} '
                '(${weekdayShort(v3.testDate.weekday)} ${formatShort(v3.testDate)})', style: text.bodySmall)
          else if (daysToTest == 0)
            Text(
                v3.isV31
                    ? 'Hoy son las pruebas: Cindy, máximo de dominadas estrictas y L-sit máximo. '
                        'Mañana, medidas finales en ayunas antes del fútbol.'
                    : 'Hoy es el test final: medidas en ayunas, dominadas y flexiones máximas, flexión a una mano y L-sit.',
                style: text.bodyMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// El Plan v3.1 está listo para el próximo lunes (§19).
class _V3SuggestionCard extends ConsumerWidget {
  const _V3SuggestionCard({required this.monday});

  final DateTime monday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      title: 'Plan v3.1 listo',
      children: [
        Text('Tirón + hombro, empuje + brazos, piernas el miércoles, torso B y el viernes de referencia. '
            'Series a RIR 0–3 con doble progresión. 9 semanas hasta las pruebas del '
            '${formatShort(v31TestDate(monday))}.', style: text.bodyMedium),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => activateV31(context, ref, monday),
          icon: const Icon(Icons.rocket_launch),
          label: Text('Activar desde el ${weekdayShort(monday.weekday)} ${formatShort(monday)}'),
        ),
      ],
    );
  }
}

/// Desde las 20:00, si el día no está cerrado: cerrarlo de un toque con lo
/// que se lleva (§16.6.3).
class _CloseDayLine extends ConsumerWidget {
  const _CloseDayLine({required this.dashboard});

  final TodayDashboard dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dashboard;
    if (DateTime.now().hour < 20) return const SizedBox.shrink();
    final meals = ref.watch(mealsForDayProvider(dayKey(d.date))).valueOrNull ?? const [];
    final manual = ref.watch(dayClosedProvider(dayKey(d.date))).valueOrNull ?? false;
    final closed = isDayClosed({for (final m in meals) m.meal.slot},
        manuallyClosed: manual, mealCount: meals.length, kcal: d.macros.kcal);
    if (closed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.nightlight_round, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('¿Ya no comes más? ${fmtInt(d.macros.kcal)} kcal · ${fmtInt(d.macros.protein)} g',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          TextButton(
            onPressed: () => guarded(context, () => ref.read(nutritionRepositoryProvider).setClosed(d.date, true),
                ok: 'Día cerrado: cuenta en los promedios'),
            child: const Text('Cerrar el día'),
          ),
        ],
      ),
    );
  }
}

/// Día por el que ya se respondió "está bien así".
final _yesterdayDismissedProvider =
    Provider<String?>((ref) => ref.watch(localFlagsProvider).get<String>(FlagKeys.yesterdayCheckDismissed));

/// Al día siguiente, si ayer quedó abierto o con muy pocas kcal: "¿Te faltó
/// registrar algo de ayer?" con acceso directo (§16.12, §16.6.3).
class _YesterdayCheckCard extends ConsumerWidget {
  const _YesterdayCheckCard({required this.today});

  final DateTime today;

  static const _lowKcal = 1200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yesterday = addDays(today, -1);
    final key = dayKey(yesterday);
    if (ref.watch(_yesterdayDismissedProvider) == key) return const SizedBox.shrink();
    // Antes del inicio del programa no hay nada que reclamar (instalación nueva).
    final start = ref.watch(profileProvider).valueOrNull?.programStart;
    if (start == null || yesterday.isBefore(dateOnly(start))) return const SizedBox.shrink();
    final mealsAsync = ref.watch(mealsForDayProvider(key));
    final manualAsync = ref.watch(dayClosedProvider(key));
    if (!mealsAsync.hasValue || !manualAsync.hasValue) return const SizedBox.shrink();
    final meals = mealsAsync.value!;
    final kcal = meals.fold(0.0, (a, m) => a + m.macros.kcal);
    final closed = isDayClosed({for (final m in meals) m.meal.slot},
        manuallyClosed: manualAsync.value ?? false, mealCount: meals.length, kcal: kcal);
    if (closed && kcal >= _lowKcal) return const SizedBox.shrink();
    final missing = missingMainMeals({for (final m in meals) m.meal.slot}).map((s) => s.label.toLowerCase());
    final text = Theme.of(context).textTheme;
    final repo = ref.read(nutritionRepositoryProvider);
    return AppCard(
      title: '¿Te faltó registrar algo de ayer?',
      children: [
        Text(
          meals.isEmpty
              ? 'Ayer (${weekdayShort(yesterday.weekday)} ${formatShort(yesterday)}) no tiene comidas.'
              : 'Ayer: ${fmtInt(kcal)} kcal en ${meals.length} ${meals.length == 1 ? 'comida' : 'comidas'}'
                  '${missing.isEmpty ? '' : ' · sin ${missing.join(', ')}'}.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MealFormScreen(draft: MealDraft(date: yesterday, slot: MealSlot.cena)),
                ),
              ),
              icon: const Icon(Icons.restaurant, size: 18),
              label: const Text('Comida de ayer'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FootballFormScreen(date: yesterday))),
              icon: const Icon(Icons.sports_soccer, size: 18),
              label: const Text('Fútbol de ayer'),
            ),
            if (!closed && meals.isNotEmpty)
              TextButton(
                onPressed: () => guarded(context, () => repo.setClosed(yesterday, true), ok: 'Ayer quedó cerrado'),
                child: const Text('Cerrar ayer así'),
              ),
            TextButton(
              onPressed: () async {
                await ref.read(localFlagsProvider).set(FlagKeys.yesterdayCheckDismissed, key);
                ref.invalidate(_yesterdayDismissedProvider);
              },
              child: const Text('Está bien así'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pasos que faltan en caminatas de 10 min, con el botón para hacer una
/// (§18.10: "Te faltan 3 caminatas de 10 min").
class _WalksLine extends StatelessWidget {
  const _WalksLine({required this.dashboard});

  final TodayDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final goal = dashboard.stepsGoal;
    if (goal == null) return const SizedBox.shrink();
    final left = walksLeft(dashboard.stepsToday ?? 0, goal);
    if (left == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.directions_walk, size: 18, color: AppColors.steps),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Te ${left == 1 ? 'falta 1 caminata' : 'faltan $left caminatas'} de 10 min',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalkScreen())),
            child: const Text('Caminata 10 min'),
          ),
        ],
      ),
    );
  }
}

/// Comida de ahora: la franja sale de la hora, igual que en la pestaña
/// Comidas, para no tener que corregirla a las 8 p. m.
MealDraft _mealNow(DateTime date) {
  final now = DateTime.now();
  return MealDraft(date: date, slot: slotForTime(now.hour, now.minute), time: timeKey(now.hour, now.minute));
}

class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard({required this.due});

  final MeasurementDue due;

  @override
  Widget build(BuildContext context) => AppCard(
        children: [
          Row(
            children: [
              const Icon(Icons.straighten, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(measurementLabel(due)),
              ),
            ],
          ),
        ],
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
        ],
      ),
    );
  }
}
