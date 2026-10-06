import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/body_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/habits.dart';
import '../../domain/progress.dart';
import '../../domain/nutrition.dart';
import '../../domain/recovery.dart';
import '../../data/database.dart';
import '../../ui/hero.dart';
import '../../ui/widgets.dart';
import 'measurement_form_screen.dart';
import 'photos_screen.dart';
import '../../ui/theme.dart';

class BodyScreen extends ConsumerWidget {
  const BodyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weights = ref.watch(weightsProvider);
    final checkIns = ref.watch(checkInsProvider);
    final profile = ref.watch(profileProvider).value;
    final unit = profile?.lengthUnit ?? LengthUnit.cm;
    final lastCheck = (checkIns.value ?? const []).isEmpty ? null : checkIns.value!.first.date;
    final due = measurementDue(
      today: ref.watch(todayProvider),
      lastMeasurement: lastCheck,
      agreed: profile?.nextMeasurementDate == null ? null : parseDay(profile!.nextMeasurementDate!),
      minDays: profile?.measureIntervalDays ?? 21,
      maxDays: profile?.measureIntervalMaxDays ?? 28,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Cuerpo')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _BodyHero(
            weights: weights.value ?? const [],
            firstWeight: ref.watch(firstWeightProvider).valueOrNull,
            checkIns: checkIns.value ?? const [],
            due: due,
            onWeight: () => _addWeight(context, ref),
            onMeasure: () => _openMeasurement(context, ref, null),
          ),
          _DecisionCard(weights: weights.value ?? const [], checkIns: checkIns.value ?? const []),
          AppCard(
            title: 'Peso',
            trailing: IconButton(
              tooltip: 'Registrar peso',
              icon: const Icon(Icons.add),
              onPressed: () => _addWeight(context, ref),
            ),
            children: [
              weights.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? const EmptyState(
                        icon: Icons.monitor_weight_outlined,
                        text: 'Sin pesajes. Mejor en ayunas, a la misma hora.',
                      )
                    : Column(
                        children: [
                          for (final w in list.take(8))
                            TypedTile(
                              icon: Icons.monitor_weight_outlined,
                              color: _bodyColor,
                              title: formatLong(parseDay(w.date)),
                              subtitle: [
                                weighMomentOf(w.moment, fasted: w.fasted).label.toLowerCase(),
                                if (w.time != null) w.time!,
                              ].join(' · '),
                              value: fmtDec(w.kg),
                              valueLabel: 'kg',
                              onLongPress: () async {
                                final repo = ref.read(bodyRepositoryProvider);
                                final ok =
                                    await guarded(context, () => repo.deleteWeight(w.id), failure: 'No se pudo borrar');
                                if (ok && context.mounted) {
                                  showUndoSnack(context, 'Pesaje borrado',
                                      () => repo.addWeight(parseDay(w.date), w.kg,
                                          moment: weighMomentOf(w.moment, fasted: w.fasted), time: w.time));
                                }
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
          AppCard(
            title: 'Medidas',
            trailing: IconButton(
              tooltip: 'Tomar medidas',
              icon: const Icon(Icons.add),
              onPressed: () => _openMeasurement(context, ref, null),
            ),
            children: [
              checkIns.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? const EmptyState(
                        icon: Icons.straighten,
                        text: 'Sin tomas de medidas. La primera es tu línea base.',
                      )
                    : Column(
                        children: [
                          for (final c in list)
                            TypedTile(
                              icon: Icons.straighten,
                              color: _bodyColor,
                              title: '${formatLong(c.date)}${c.time == null ? '' : ' ${c.time}'} · '
                                  '${c.fasted ? 'ayunas' : 'después de comer'}',
                              subtitle: [
                                _summary(c, unit),
                                if (c.shoulderWaistRatio case final r?)
                                  'Hombros ÷ cintura ${fmtDec(r, decimals: 2)} (referencia ≈ 1,6)',
                              ].join('\n'),
                              value: '${c.valuesCm.length}',
                              valueLabel: 'medidas',
                              onTap: () => _openMeasurement(context, ref, c),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          AppCard(
            children: [
              TypedTile(
                icon: Icons.photo_library_outlined,
                color: _bodyColor,
                title: 'Fotos de progreso',
                subtitle: 'Frente, perfil y espalda, con comparador lado a lado',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotosScreen())),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _summary(MeasurementCheckIn c, LengthUnit unit) => c.valuesCm.entries
      .map((e) => '${e.key.shortLabel} ${fmtDec(fromCm(e.value, unit))}')
      .join(' · ');

  Future<void> _openMeasurement(BuildContext context, WidgetRef ref, MeasurementCheckIn? existing) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => MeasurementFormScreen(existing: existing)));

  Future<void> _addWeight(BuildContext context, WidgetRef ref) => addWeightDialog(context, ref);
}

/// Anotar un pesaje con su momento (§18.10). `date`: el día propuesto (hoy
/// si no se da).
Future<void> addWeightDialog(BuildContext context, WidgetRef ref, {DateTime? date}) async {
  final result = await showDialog<(DateTime, double, WeighMoment)>(
    context: context,
    builder: (_) => _WeightDialog(today: date ?? ref.read(todayProvider)),
  );
  if (result == null || !context.mounted) return;
  final now = TimeOfDay.now();
  await guarded(
    context,
    () => ref
        .read(bodyRepositoryProvider)
        .addWeight(result.$1, result.$2, moment: result.$3, time: timeKey(now.hour, now.minute)),
    ok: result.$3 == WeighMoment.ayunas ? 'Peso en ayunas guardado' : 'Peso guardado como referencia (${result.$3.label.toLowerCase()})',
  );
  ref.invalidate(dashboardProvider);
}

/// Regla de cada 2 semanas (§19.3): el promedio semanal de peso y el
/// abdomen dicen si tocar las kcal. La báscula decide, no la sensación.
class _DecisionCard extends ConsumerWidget {
  const _DecisionCard({required this.weights, required this.checkIns});

  final List<BodyWeightRow> weights;
  final List<MeasurementCheckIn> checkIns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (weights.isEmpty) return const SizedBox.shrink();
    final reading = twoWeekRule(
      weeks: weeklyWeightAverages([for (final w in weights) (parseDay(w.date), w.kg, w.fasted)]),
      abdomen: [
        for (final c in checkIns)
          if (c.fasted && c.valuesCm[MeasureSite.abdomen] != null) (c.date, c.valuesCm[MeasureSite.abdomen]!),
      ],
      today: ref.watch(todayProvider),
    );
    final text = Theme.of(context).textTheme;
    final (icon, color) = switch (reading.action) {
      KcalAction.subir => (Icons.arrow_upward, AppColors.kcal),
      KcalAction.bajar => (Icons.arrow_downward, AppColors.kcal),
      KcalAction.mantener => (Icons.check_circle_outline, AppColors.protein),
      KcalAction.faltanDatos => (Icons.hourglass_empty, null),
    };
    return AppCard(
      title: 'Regla de las 2 semanas',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(reading.message, style: text.bodyLarge)),
          ],
        ),
        const SizedBox(height: 6),
        Text('Compara el promedio semanal en ayunas con el de 2 semanas antes. Si caen las repeticiones, '
            'también se suben 150–200 kcal.', style: text.bodySmall),
      ],
    );
  }
}

class _WeightDialog extends StatefulWidget {
  const _WeightDialog({required this.today});

  final DateTime today;

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  final _kg = TextEditingController();
  WeighMoment _moment = WeighMoment.ayunas;
  late DateTime _date = widget.today;

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar peso'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NumberField(controller: _kg, label: 'Peso', suffix: 'kg', decimal: true, autofocus: true),
          DateTile(date: _date, onChanged: (v) => setState(() => _date = v)),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final m in WeighMoment.values)
                ChoiceChip(label: Text(m.label), selected: _moment == m, onSelected: (_) => setState(() => _moment = m)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _moment == WeighMoment.ayunas
                ? 'Entra en el promedio semanal.'
                : 'Queda como referencia: solo en ayunas entra en el promedio.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final kg = parseNum(_kg.text);
            if (kg == null || kg <= 0) return;
            Navigator.pop(context, (_date, kg, _moment));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Color de la sección Cuerpo: el verde del progreso físico.
const _bodyColor = AppColors.body;

/// Resumen de Cuerpo: último peso, cambio desde el primero y cuándo medir.
class _BodyHero extends StatelessWidget {
  const _BodyHero({
    required this.weights,
    required this.firstWeight,
    required this.checkIns,
    required this.due,
    required this.onWeight,
    required this.onMeasure,
  });

  final List<BodyWeightRow> weights;

  /// El primer pesaje de todos, no el más viejo de los que carga la lista.
  final BodyWeightRow? firstWeight;
  final List<MeasurementCheckIn> checkIns;
  final MeasurementDue? due;
  final VoidCallback onWeight;
  final VoidCallback onMeasure;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final latest = weights.isEmpty ? null : weights.first;
    final first = firstWeight;
    final delta = latest == null || first == null || latest.id == first.id ? null : latest.kg - first.kg;
    // El peso sube y baja día a día: lo que dice algo es el promedio de la
    // semana y su tendencia (§18.10).
    final weeks = weeklyWeightAverages([for (final w in weights) (parseDay(w.date), w.kg, w.fasted)]);
    final week = weeks.isEmpty ? null : weeks.last;
    final prevWeek = weeks.length < 2 ? null : weeks[weeks.length - 2];

    return HeroCard(
      color: _bodyColor,
      overline: 'Cuerpo',
      title: week == null ? 'Sin pesajes' : '${fmtDec(week.kg)} kg',
      subtitle: week == null
          ? 'Registra tu primer peso'
          : [
              'Promedio de la semana del ${formatShort(week.monday)} '
                  '(${week.count} ${week.count == 1 ? 'pesaje' : 'pesajes'})',
              if (prevWeek != null) '${fmtDelta(week.kg - prevWeek.kg)} kg vs la anterior',
              if (delta != null && prevWeek == null) '${fmtDelta(delta)} kg desde ${formatShort(parseDay(first!.date))}',
            ].join(' · '),
      icon: Icons.accessibility_new,
      pills: [
        StatPill(
          icon: Icons.straighten,
          label: due == null ? 'Sin medidas' : (due!.isDue ? 'Toca medir' : 'Medir en ${due!.daysLeft} d'),
          color: due?.isDue == true ? _bodyColor : null,
        ),
      ],
      children: [
        Row(
          children: [
            Expanded(child: ActionButton(icon: Icons.monitor_weight_outlined, label: 'Peso', onPressed: onWeight)),
            const SizedBox(width: 8),
            Expanded(child: ActionButton(icon: Icons.straighten, label: 'Medidas', onPressed: onMeasure)),
          ],
        ),
        if (due?.isDue == true)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(measurementLabel(due!), style: text.bodySmall),
          ),
      ],
    );
  }
}
