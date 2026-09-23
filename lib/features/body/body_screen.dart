import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/body_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/nutrition.dart';
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
    final interval = profile?.measureIntervalDays ?? 21;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuerpo'),
        actions: [
          IconButton(
            tooltip: 'Fotos de progreso',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotosScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          AppCard(
            title: 'Peso',
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _addWeight(context, ref),
            ),
            children: [
              weights.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? const EmptyHint('Sin pesajes.')
                    : Column(
                        children: [
                          for (final w in list.take(8))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text('${fmtDec(w.kg)} kg'),
                              subtitle: Text('${formatLong(parseDay(w.date))}'
                                  ' · ${w.fasted ? 'en ayunas' : 'sin ayunas'}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => ref.read(bodyRepositoryProvider).deleteWeight(w.id),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          AppCard(
            title: 'Medidas',
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _openMeasurement(context, ref, null),
            ),
            children: [
              checkIns.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) {
                  if (list.isEmpty) return const EmptyHint('Sin tomas de medidas.');
                  final last = list.first.date;
                  final due = interval - daysBetween(last, dateOnly(DateTime.now()));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        due > 0
                            ? 'Próxima medición recomendada en $due días'
                            : 'Ya puedes medir (última hace ${daysBetween(last, dateOnly(DateTime.now()))} días)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      for (final c in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${formatLong(c.date)} · ${c.fasted ? 'ayunas' : 'sin ayunas'}'),
                          subtitle: Text(_summary(c, unit)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openMeasurement(context, ref, c),
                        ),
                    ],
                  );
                },
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
    final result = await showDialog<(double, bool)>(context: context, builder: (_) => const _WeightDialog());
    if (result == null) return;
    await ref.read(bodyRepositoryProvider).addWeight(dateOnly(DateTime.now()), result.$1, fasted: result.$2);
  }
}

class _WeightDialog extends StatefulWidget {
  const _WeightDialog();

  @override
  State<_WeightDialog> createState() => _WeightDialogState();
}

class _WeightDialogState extends State<_WeightDialog> {
  final _kg = TextEditingController();
  bool _fasted = true;

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
          NumberField(controller: _kg, label: 'Peso', suffix: 'kg', decimal: true),
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
            Navigator.pop(context, (kg, _fasted));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
