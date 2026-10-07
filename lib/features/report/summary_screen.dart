import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/progress.dart';
import '../../domain/report/period_summary.dart';
import '../../ui/hero.dart';
import '../../ui/progress_ring.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'charts.dart';

enum SummaryPeriod { semana, mes, todo }

const _monthNames = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// Tu progreso en números: semana, mes o desde el inicio. Lo que el informe
/// cuenta en texto, aquí se ve: repeticiones por ejercicio, pasos, kilómetros,
/// gasto aproximado y cómo comiste, siempre contra el periodo anterior.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key, this.initial = SummaryPeriod.semana});

  final SummaryPeriod initial;

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  late SummaryPeriod _period = widget.initial;

  /// Desplazamiento desde el periodo actual (0 = este, -1 = el anterior…).
  int _offset = 0;

  (DateTime, DateTime) _range(DateTime start, DateTime today) {
    switch (_period) {
      case SummaryPeriod.semana:
        final w = weekRange(start, weekIndexFor(start, today) + _offset);
        return (w.start, w.end);
      case SummaryPeriod.mes:
        final first = DateTime(today.year, today.month + _offset, 1);
        return (first, DateTime(first.year, first.month + 1, 0));
      case SummaryPeriod.todo:
        return (dateOnly(start), dateOnly(today));
    }
  }

  bool _canGoBack(DateTime start, DateTime from) => _period != SummaryPeriod.todo && from.isAfter(dateOnly(start));

  String _title(DateTime start, DateTime from, DateTime to) => switch (_period) {
        SummaryPeriod.semana => 'Semana ${weekIndexFor(start, from)}',
        SummaryPeriod.mes => '${_monthNames[from.month - 1]} ${from.year}',
        SummaryPeriod.todo => 'Desde el inicio',
      };

  /// Contra qué se compara. Vacío mientras el periodo no termina: una semana
  /// a medias contra una entera siempre "baja", y eso no dice nada.
  String _versus(DateTime to, DateTime today) {
    if (to.isAfter(dateOnly(today))) return '';
    return switch (_period) {
      SummaryPeriod.semana => 'vs semana anterior',
      SummaryPeriod.mes => 'vs mes anterior',
      SummaryPeriod.todo => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final today = ref.watch(todayProvider);
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final start = profile.programStart;
    final (from, to) = _range(start, today);
    final key = (dayKey(from), dayKey(to));
    final summary = ref.watch(periodSummaryProvider(key));
    final color = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Tu progreso')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Siempre a la vista: el mes en curso o el que empieza con la app no
          // deben hacer parecer que se entrena hace pocos días (§16.16).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(trainingAgeLine(start, today), style: text.titleSmall, textAlign: TextAlign.center),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<SummaryPeriod>(
              segments: const [
                ButtonSegment(value: SummaryPeriod.semana, label: Text('Semana')),
                ButtonSegment(value: SummaryPeriod.mes, label: Text('Mes')),
                ButtonSegment(value: SummaryPeriod.todo, label: Text('Todo')),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() {
                _period = s.first;
                _offset = 0;
              }),
            ),
          ),
          HeroCard(
            color: color,
            overline: _period == SummaryPeriod.todo ? 'Programa' : (_offset == 0 ? 'En curso' : 'Anterior'),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Anterior',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _canGoBack(start, from) ? () => setState(() => _offset--) : null,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(_title(start, from, to).toUpperCase(),
                            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
                        Text('${formatShort(from)} – ${formatLong(to)}', style: text.titleSmall),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Siguiente',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _offset < 0 ? () => setState(() => _offset++) : null,
                  ),
                ],
              ),
              if (_period != SummaryPeriod.todo && to.isAfter(dateOnly(today)))
                Text(
                  '${_period == SummaryPeriod.mes ? 'Mes' : 'Semana'} en curso: hoy es el día '
                  '${daysBetween(from, today) + 1} de ${daysBetween(from, to) + 1}. '
                  'La comparación con el periodo anterior sale al cerrarlo.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              const SizedBox(height: 8),
              summary.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (s) => _Headline(summary: s, versus: _versus(to, today), inProgress: to.isAfter(dateOnly(today))),
              ),
            ],
          ),
          ...summary.maybeWhen(
            data: (s) => s.isEmpty
                ? [const AppCard(children: [EmptyHint('Nada registrado en este periodo todavía.')])]
                : [
                    _ExercisesCard(summary: s, versus: _versus(to, today)),
                    _StepsCard(summary: s, stepsGoal: profile.targets.stepsTarget),
                    _EnergyCard(summary: s),
                    _FoodCard(summary: s, proteinMin: profile.proteinMin, kcalTarget: profile.kcalTarget),
                  ],
            orElse: () => const <Widget>[],
          ),
        ],
      ),
    );
  }
}

/// Cuatro números grandes: sesiones, tiempo activo, repeticiones y pasos.
class _Headline extends StatelessWidget {
  const _Headline({required this.summary, required this.versus, this.inProgress = false});

  final PeriodSummary summary;
  final String versus;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final p = s.previous;
    final text = Theme.of(context).textTheme;
    // Denominador justo (§16.16): en curso, los días hábiles transcurridos con
    // datos posibles; cerrado, los del periodo desde el primer dato. Los
    // anteriores a la app no son faltas.
    final planned = inProgress ? s.plannedElapsed : s.plannedSessions - s.plannedWithoutData;
    final games = s.footballGames == 0 ? '' : ' + ${s.footballGames} ${s.footballGames == 1 ? 'partido' : 'partidos'}';
    final grid = GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.1,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _BigStat(
          icon: Icons.fitness_center,
          color: Theme.of(context).colorScheme.primary,
          value: planned > 0 ? '${s.trainingSessions}/$planned' : '${s.trainingSessions}',
          label: inProgress && s.plannedSessions > 0
              ? 'días hábiles hasta hoy · ${s.plannedSessions} en el periodo$games'
              : 'sesiones$games',
        ),
        _BigStat(
          icon: Icons.timer_outlined,
          color: AppColors.kcal,
          value: _hours(s.activeSec),
          label: 'activo',
          delta: p == null || versus.isEmpty ? null : _pct(s.activeSec, p.activeSec),
        ),
        _BigStat(
          icon: Icons.repeat,
          color: AppColors.record,
          value: fmtInt(s.totalReps),
          label: 'repeticiones',
          delta: p == null || versus.isEmpty ? null : _pct(s.totalReps, p.totalReps),
        ),
        _BigStat(
          icon: Icons.directions_walk,
          color: AppColors.steps,
          value: fmtInt(s.stepsTotal),
          label: 'pasos · ${fmtDec(s.distanceKm)} km',
          delta: p == null || versus.isEmpty ? null : _pct(s.stepsTotal, p.stepsTotal),
        ),
      ],
    );
    if (s.plannedWithoutData == 0 || s.dataStart == null) return grid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        grid,
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Sin datos en la app: ${s.plannedWithoutData} '
            '${s.plannedWithoutData == 1 ? 'día hábil' : 'días hábiles'} antes del ${formatShort(s.dataStart!)}. '
            'No cuentan como faltas.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// "Llevas 6 semanas (desde el 26 ago)" (§16.16).
String trainingAgeLine(DateTime start, DateTime today) {
  final days = daysBetween(dateOnly(start), dateOnly(today)) + 1;
  if (days <= 0) return 'El programa empieza el ${formatShort(start)}';
  final weeks = (days / 7).ceil();
  return 'Llevas $weeks ${weeks == 1 ? 'semana' : 'semanas'} (desde el ${formatShort(start)})';
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.icon, required this.color, required this.value, required this.label, this.delta});

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  /// Variación en % contra el periodo anterior.
  final int? delta;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(value, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      if (delta != null) ...[const SizedBox(width: 6), _DeltaChip(percent: delta!)],
                    ],
                  ),
                ),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ▲ 12 % / ▼ 8 %. Verde si sube, apagado si baja: bajar no siempre es malo
/// (una semana de descarga), así que no se pinta de rojo.
class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final up = percent > 0;
    final flat = percent == 0;
    final color = flat ? Theme.of(context).colorScheme.onSurfaceVariant : (up ? AppColors.body : AppColors.kcal);
    return Text(
      flat ? '=' : '${up ? '▲' : '▼'} ${percent.abs()} %',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
    );
  }
}

/// Repeticiones por ejercicio con barra relativa y cambio contra el periodo
/// anterior. Lo que más se repite, arriba.
class _ExercisesCard extends StatelessWidget {
  const _ExercisesCard({required this.summary, required this.versus});

  final PeriodSummary summary;
  final String versus;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final text = Theme.of(context).textTheme;
    final reps = s.exercises.where((e) => !e.isHold).toList();
    final holds = s.exercises.where((e) => e.isHold).toList();
    final maxReps = reps.isEmpty ? 1 : reps.first.amount;
    return AppCard(
      title: 'Ejercicio hecho',
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _Fact('Trabajo neto', _hours(s.workSec)),
            _Fact('Entrenando', _hours(s.trainingSec)),
            if (s.footballMinutes > 0) _Fact('Fútbol', '${s.footballMinutes} min'),
            if (s.mobilitySessions > 0) _Fact('Movilidad', '${s.mobilitySessions}×'),
            if (s.maxRounds != null) _Fact('Mejor circuito', '${s.maxRounds} ${s.maxRounds == 1 ? 'ronda' : 'rondas'}'),
          ],
        ),
        if (reps.isEmpty && holds.isEmpty) const EmptyHint('Sin series registradas en el periodo.'),
        if (reps.isNotEmpty) const SizedBox(height: 12),
        for (final e in reps)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(e.name, style: text.titleSmall)),
                    Text(fmtInt(e.amount), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(width: 4),
                    Text('reps · ${e.sets} ${e.sets == 1 ? 'serie' : 'series'}', style: text.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                _Bar(e.amount / maxReps, AppColors.record),
                if (e.delta case final d? when versus.isNotEmpty && e.previous! > 0)
                  Text('${d >= 0 ? '+' : ''}${fmtInt(d)} $versus', style: text.bodySmall)
                else if (versus.isNotEmpty && e.previous == 0)
                  Text('Nuevo en este periodo', style: text.bodySmall),
              ],
            ),
          ),
        if (holds.isNotEmpty) ...[
          const Divider(),
          for (final e in holds)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text(e.name)),
                  Text('${fmtInt(e.amount)} s', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(' · ${e.sets} ${e.sets == 1 ? 'serie' : 'series'}', style: text.bodySmall),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.summary, required this.stepsGoal});

  final PeriodSummary summary;
  final int stepsGoal;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final text = Theme.of(context).textTheme;
    final best = s.bestStepsDay;
    return AppCard(
      title: 'Pasos',
      children: [
        if (s.stepsDays == 0)
          const EmptyHint('Sin pasos en el periodo. Conecta el reloj en Ajustes o anótalos en Hoy.')
        else ...[
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Fact('Total', fmtInt(s.stepsTotal)),
              _Fact('Promedio', '${fmtInt(s.stepsAvg!)}/día'),
              _Fact('Distancia', '≈ ${fmtDec(s.distanceKm)} km'),
              if (best != null) _Fact('Mejor día', '${fmtInt(best.$2)} (${weekdayShort(best.$1.weekday)} ${formatShort(best.$1)})'),
            ],
          ),
          if (s.weekdaysWithSteps > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Meta de ${fmtInt(stepsGoal)} entre semana: ${s.weekdaysAtGoal} de ${s.weekdaysWithSteps} días.',
                style: text.bodyMedium,
              ),
            ),
          if (s.days.length <= 62) ...[
            const SizedBox(height: 12),
            DailyBarsChart(
              points: [for (final d in s.days) SeriesPoint(d.date, (d.steps ?? 0).toDouble())],
              color: AppColors.steps,
              goal: stepsGoal.toDouble(),
              unit: 'pasos',
              emptyText: 'Sin pasos en el periodo.',
            ),
          ],
        ],
      ],
    );
  }
}

/// Gasto aproximado por actividad. No es el gasto del día (falta el
/// metabolismo en reposo): es lo que sumó moverse.
class _EnergyCard extends StatelessWidget {
  const _EnergyCard({required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final text = Theme.of(context).textTheme;
    final total = s.kcalBurned;
    if (total == null) {
      return const AppCard(
        title: 'Gasto por actividad',
        children: [EmptyHint('Registra tu peso en Cuerpo para estimar las kcal que gastas al moverte.')],
      );
    }
    final parts = [
      ('Entrenamiento', s.kcalTraining ?? 0, Icons.fitness_center),
      ('Fútbol', s.kcalFootball ?? 0, Icons.sports_soccer),
      ('Caminar', s.kcalSteps ?? 0, Icons.directions_walk),
    ];
    final days = s.days.where((d) => !d.date.isAfter(DateTime.now())).length;
    return AppCard(
      title: 'Gasto por actividad',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('≈ ${fmtInt(total)}', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.kcal)),
            const SizedBox(width: 6),
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('kcal', style: text.titleSmall)),
            const Spacer(),
            if (days > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('≈ ${fmtInt(total / days)} al día', style: text.bodyMedium),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final (label, kcal, icon) in parts)
          if (kcal > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  SizedBox(width: 110, child: Text(label)),
                  Expanded(child: _Bar(total == 0 ? 0 : kcal / total, AppColors.kcal)),
                  const SizedBox(width: 8),
                  SizedBox(width: 64, child: Text(fmtInt(kcal), textAlign: TextAlign.end)),
                ],
              ),
            ),
        Text(
          'Estimación con tu peso (${fmtDec(s.weightKg!)} kg): MET por fase en las sesiones, 7 MET en el fútbol y '
          '0,5 kcal por kg y km al caminar (lo que suma sobre el reposo; el día de partido no se cuentan los pasos '
          'para no duplicar). Puede errar ±30 %.',
          style: text.bodySmall,
        ),
      ],
    );
  }
}

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.summary, required this.proteinMin, required this.kcalTarget});

  final PeriodSummary summary;
  final int proteinMin;
  final int kcalTarget;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final text = Theme.of(context).textTheme;
    if (s.closedDays == 0) {
      return const AppCard(
        title: 'Comida',
        children: [EmptyHint('Ningún día cerrado en el periodo: con desayuno, almuerzo y cena (o cerrado a mano) entra aquí.')],
      );
    }
    return AppCard(
      title: 'Comida',
      children: [
        Row(
          children: [
            Expanded(
              child: ProgressRing(
                progress: goalProgress(s.avgKcalIn!, kcalTarget),
                value: fmtInt(s.avgKcalIn!),
                label: 'kcal/día',
                sublabel: 'meta ${fmtInt(kcalTarget)}',
                size: 110,
                stroke: 10,
                color: AppColors.kcal,
              ),
            ),
            Expanded(
              child: ProgressRing(
                progress: goalProgress(s.avgProtein!, proteinMin),
                value: '${fmtInt(s.avgProtein!)} g',
                label: 'proteína/día',
                sublabel: 'mín ${fmtInt(proteinMin)} g',
                size: 110,
                stroke: 10,
                color: AppColors.protein,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Promedio de ${s.closedDays} ${s.closedDays == 1 ? 'día cerrado' : 'días cerrados'}. '
          'Proteína en meta: ${s.proteinDaysAtMin} de ${s.closedDays}.',
          style: text.bodyMedium,
        ),
      ],
    );
  }
}

/// Barra delgada de proporción.
class _Bar extends StatelessWidget {
  const _Bar(this.value, this.color);

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1).toDouble(),
          minHeight: 8,
          color: color,
          backgroundColor: color.withOpacity(0.15),
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelSmall),
        Text(value, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// "3 h 25 min", "45 min".
String _hours(int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Variación en % (redondeada); null si no hay base para comparar.
int? _pct(num now, num before) => before <= 0 ? null : (((now - before) / before) * 100).round();
