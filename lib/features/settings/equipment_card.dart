import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/catalog_updates.dart' show applyExerciseGuides;
import '../../data/database.dart' show EquipmentRow;
import '../../domain/equipment.dart';
import '../../domain/format.dart';
import '../../ui/widgets.dart';

/// Plan 052 (§16.27.4): el material que hay en casa. Sin nada guardado,
/// barra, banda y báscula salen como "tengo"; colchoneta y mochila, como
/// "no tengo"; mini paralelas y anillas, como dicen los interruptores de Plan.
/// Cambiarlas aquí también cambia esos interruptores.
class EquipmentCard extends ConsumerStatefulWidget {
  const EquipmentCard({super.key});

  @override
  ConsumerState<EquipmentCard> createState() => _EquipmentCardState();
}

class _EquipmentCardState extends ConsumerState<EquipmentCard> {
  @override
  void initState() {
    super.initState();
    // Tras restaurar un respaldo las banderas siguen al inventario guardado.
    // Si falla, la tarjeta sigue igual: es sólo un ajuste de coherencia.
    unawaited(ref
        .read(equipmentRepositoryProvider)
        .syncFlagsFromInventory()
        .then((_) {}, onError: (Object _) {}));
  }

  Future<void> _save(EquipmentItem item, String status, {double? kg}) async {
    try {
      await ref.read(equipmentRepositoryProvider).set(item.key, status, kg: kg);
      // Igual que el interruptor de Plan: con paralelas llegan sus guías.
      if (item.key == EquipmentKeys.parallettes &&
          status == EquipmentStatus.tengo) {
        await applyExerciseGuides(ref.read(databaseProvider));
      }
    } on Object catch (e) {
      if (mounted) showSnack(context, 'No se guardó el material: $e');
      return;
    }
    ref.invalidate(dashboardProvider);
    if (item.key == EquipmentKeys.rings) {
      ref.invalidate(ladderAdviceProvider);
      ref.invalidate(ladderDecisionsProvider);
    }
  }

  Future<void> _editKg(EquipmentItem item, double? current) async {
    final kg = await showDialog<double>(
        context: context, builder: (_) => _KgDialog(initial: current));
    if (kg == null || !mounted) return;
    await _save(item, EquipmentStatus.tengo, kg: kg);
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(equipmentRowsProvider);
    final repo = ref.watch(equipmentRepositoryProvider);
    return AppCard(
      title: 'Material',
      children: [
        const Text(
            'Lo que tienes en casa. Un ejercicio que necesita algo que falta no se ofrece; si sólo le sirve, '
            'lleva una nota.'),
        const SizedBox(height: 8),
        rows.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('No se pudo leer el material: $e'),
          data: (list) {
            final byKey = <String, EquipmentRow>{
              for (final r in list) r.key: r
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in equipmentCatalog)
                  _EquipmentTile(
                    item: item,
                    status: byKey[item.key]?.status ??
                        repo.defaultStatus(item.key),
                    kg: byKey[item.key]?.kg,
                    onStatus: (status) =>
                        _save(item, status, kg: byKey[item.key]?.kg),
                    onKg: () => _editKg(item, byKey[item.key]?.kg),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EquipmentTile extends StatelessWidget {
  const _EquipmentTile(
      {required this.item,
      required this.status,
      required this.kg,
      required this.onStatus,
      required this.onKg});

  final EquipmentItem item;
  final String status;
  final double? kg;
  final ValueChanged<String> onStatus;
  final VoidCallback onKg;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // La mochila es sí/no (y kg); el resto, tengo / en compra / no tengo.
    final options = item.weighted
        ? const [EquipmentStatus.tengo, EquipmentStatus.noTengo]
        : EquipmentStatus.all;
    final selected = options.contains(status)
        ? status
        : EquipmentStatus.noTengo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label, style: text.titleSmall),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final option in options)
                ButtonSegment<String>(
                  value: option,
                  label: Text(
                    item.weighted
                        ? (option == EquipmentStatus.tengo ? 'Sí' : 'No')
                        : EquipmentStatus.label(option),
                    key: ValueKey('material:${item.key}:$option'),
                  ),
                ),
            ],
            selected: {selected},
            onSelectionChanged: (s) {
              if (s.isNotEmpty && s.first != selected) onStatus(s.first);
            },
          ),
          if (item.weighted && selected == EquipmentStatus.tengo)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('material:${item.key}:kg'),
                onPressed: onKg,
                icon: const Icon(Icons.fitness_center, size: 18),
                label: Text(kg == null
                    ? 'Anotar los kg'
                    : '${fmtDec(kg!)} kg · cambiar'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Peso de la mochila. Devuelve los kg o null si se cancela.
class _KgDialog extends StatefulWidget {
  const _KgDialog({this.initial});

  final double? initial;

  @override
  State<_KgDialog> createState() => _KgDialogState();
}

class _KgDialogState extends State<_KgDialog> {
  late final _controller = TextEditingController(
      text: widget.initial == null ? '' : fmtDec(widget.initial!));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final kg = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (kg == null || !kg.isFinite || kg < 0.5 || kg > 60) {
      setState(() => _error = 'Entre 0,5 y 60 kg.');
      return;
    }
    Navigator.pop(context, kg);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Peso de la mochila'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: 'kg', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(onPressed: _submit, child: const Text('Guardar')),
        ],
      );
}
