import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/body_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/progress.dart';
import '../../domain/nutrition.dart';
import '../../data/database.dart';
import '../../ui/hero.dart';
import '../../ui/widgets.dart';
import 'measurement_form_screen.dart';
import 'photos_screen.dart';

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
                              subtitle: w.fasted ? 'en ayunas' : 'sin ayunas',
                              value: fmtDec(w.kg),
                              valueLabel: 'kg',
                              onLongPress: () async {
                                final repo = ref.read(bodyRepositoryProvider);
                                await repo.deleteWeight(w.id);
                                if (context.mounted) {
                                  showUndoSnack(context, 'Pesaje borrado',
                                      () => repo.addWeight(parseDay(w.date), w.kg, fasted: w.fasted));
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
                              title: '${formatLong(c.date)} · ${c.fasted ? 'ayunas' : 'sin ayunas'}',
                              subtitle: _summary(c, unit),
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
      .map((e) => '${e.key.label.split(' ').first} ${fmtDec(fromCm(e.value, unit))}')
      .join(' · ');

  Future<void> _openMeasurement(BuildContext context, WidgetRef ref, MeasurementCheckIn? existing) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => MeasurementFormScreen(existing: existing)));

  Future<void> _addWeight(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(DateTime, double, bool)>(
      context: context,
      builder: (_) => _WeightDialog(today: ref.read(todayProvider)),
    );
    if (result == null || !context.mounted) return;
    await guarded(context, () => ref.read(bodyRepositoryProvider).addWeight(result.$1, result.$2, fasted: result.$3));
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
  bool _fasted = true;
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('En ayunas'),
            value: _fasted,
            onChanged: (v) => setState(() => _fasted = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final kg = parseNum(_kg.text);
            if (kg == null || kg <= 0) return;
            Navigator.pop(context, (_date, kg, _fasted));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Color de la sección Cuerpo: el verde del progreso físico.
const _bodyColor = Color(0xFF7ED957);

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

    return HeroCard(
      color: _bodyColor,
      overline: 'Cuerpo',
      title: latest == null ? 'Sin pesajes' : '${fmtDec(latest.kg)} kg',
      subtitle: delta == null
          ? (latest == null ? 'Registra tu primer peso' : 'Último pesaje')
          : '${fmtDelta(delta)} kg desde ${formatShort(parseDay(first!.date))}',
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
