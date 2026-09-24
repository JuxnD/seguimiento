import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/body_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/nutrition.dart';
import '../../ui/widgets.dart';

/// Toma de medidas. Se escribe en la unidad elegida y se guarda siempre en cm.
class MeasurementFormScreen extends ConsumerStatefulWidget {
  const MeasurementFormScreen({super.key, this.existing});

  final MeasurementCheckIn? existing;

  @override
  ConsumerState<MeasurementFormScreen> createState() => _MeasurementFormScreenState();
}

class _MeasurementFormScreenState extends ConsumerState<MeasurementFormScreen> {
  late DateTime _date = widget.existing?.date ?? dateOnly(DateTime.now());
  late bool _fasted = widget.existing?.fasted ?? true;
  late LengthUnit _unit = ref.read(profileProvider).value?.lengthUnit ?? LengthUnit.cm;
  late final Map<MeasureSite, TextEditingController> _fields = {
    for (final site in MeasureSite.values)
      site: TextEditingController(
        text: widget.existing?.valuesCm[site] == null
            ? ''
            : fmtDec(fromCm(widget.existing!.valuesCm[site]!, _unit), decimals: 2),
      ),
  };

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _convertFields(LengthUnit from, LengthUnit to) {
    for (final c in _fields.values) {
      final v = parseNum(c.text);
      if (v == null) continue;
      c.text = fmtDec(fromCm(toCm(v, from), to), decimals: 2);
    }
  }

  Future<void> _save() async {
    final values = <MeasureSite, double>{};
    for (final e in _fields.entries) {
      final v = parseNum(e.value.text);
      if (v != null && v > 0) values[e.key] = toCm(v, _unit);
    }
    if (values.isEmpty) {
      showSnack(context, 'No hay ninguna medida');
      return;
    }
    final repo = ref.read(bodyRepositoryProvider);
    final previous = await repo.lastCheckInBefore(_date);
    final minDays = ref.read(profileProvider).value?.measureIntervalDays ?? 21;
    if (previous != null && daysBetween(previous, _date) < minDays && mounted) {
      final gap = daysBetween(previous, _date);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Medición antes de tiempo'),
          content: Text('La anterior fue hace $gap días (mínimo recomendado: $minDays). '
              'Los cambios reales no se ven en tan poco tiempo.\n\n¿Guardar igual?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar igual')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final ok = await guarded(
      context,
      () => repo.saveCheckIn(_date, _fasted, values, replacing: widget.existing?.date),
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Nueva medición' : 'Editar medición'),
        actions: [
          if (widget.existing != null)
            IconButton(tooltip: 'Borrar', 
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDelete(context, 'la medición')) {
                  await ref.read(bodyRepositoryProvider).deleteCheckIn(widget.existing!.date);
                  if (context.mounted) Navigator.pop(context, true);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          AppCard(
            children: [
              DateTile(date: _date, onChanged: (v) => setState(() => _date = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('En ayunas'),
                value: _fasted,
                onChanged: (v) => setState(() => _fasted = v),
              ),
              SegmentedButton<LengthUnit>(
                segments: const [
                  ButtonSegment(value: LengthUnit.cm, label: Text('cm')),
                  ButtonSegment(value: LengthUnit.inch, label: Text('pulgadas')),
                ],
                selected: {_unit},
                onSelectionChanged: (s) => setState(() {
                  final from = _unit;
                  _unit = s.first;
                  _convertFields(from, _unit);
                }),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Se guarda siempre en cm; la unidad solo cambia cómo escribes y lees.'),
              ),
            ],
          ),
          AppCard(
            title: 'Medidas (${_unit.label})',
            children: [
              for (final site in MeasureSite.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: NumberField(
                    controller: _fields[site]!,
                    label: site.label,
                    suffix: _unit.label,
                    decimal: true,
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: const Text('Guardar'),
      ),
    );
  }
}
