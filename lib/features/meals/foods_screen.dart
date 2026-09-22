import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../ui/widgets.dart';

/// Catálogo de alimentos frecuentes: se llena una vez desde las etiquetas.
class FoodsScreen extends ConsumerWidget {
  const FoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foods = ref.watch(foodsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de alimentos')),
      body: foods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? const EmptyHint('Vacío. Añade huevo, atún, Klim, leche, arroz…')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final f = list[i];
                  return ListTile(
                    title: Text(f.name),
                    subtitle: Text('${fmtInt(f.kcal)} kcal · P ${fmtDec(f.protein)} · C ${fmtDec(f.carbs)} · '
                        'G ${fmtDec(f.fat)} ${f.basisLabel}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirmDelete(context, f.name)) {
                          await ref.read(nutritionRepositoryProvider).deleteFood(f.id);
                        }
                      },
                    ),
                    onTap: () => _edit(context, ref, f),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Alimento'),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, FoodRow? food) async {
    final data = await showDialog<FoodsCompanion>(context: context, builder: (_) => _FoodDialog(food: food));
    if (data != null) await ref.read(nutritionRepositoryProvider).saveFood(data);
  }
}

class _FoodDialog extends StatefulWidget {
  const _FoodDialog({this.food});

  final FoodRow? food;

  @override
  State<_FoodDialog> createState() => _FoodDialogState();
}

class _FoodDialogState extends State<_FoodDialog> {
  late final _name = TextEditingController(text: widget.food?.name ?? '');
  late final _unit = TextEditingController(text: widget.food?.unitLabel ?? 'unidad');
  late final _kcal = TextEditingController(text: widget.food == null ? '' : fmtDec(widget.food!.kcal));
  late final _protein = TextEditingController(text: widget.food == null ? '' : fmtDec(widget.food!.protein));
  late final _carbs = TextEditingController(text: widget.food == null ? '' : fmtDec(widget.food!.carbs));
  late final _fat = TextEditingController(text: widget.food == null ? '' : fmtDec(widget.food!.fat));
  late final _qty = TextEditingController(text: fmtDec(widget.food?.defaultQuantity ?? 1));
  late FoodBasis _basis = widget.food?.basis ?? FoodBasis.unit;

  @override
  void dispose() {
    for (final c in [_name, _unit, _kcal, _protein, _carbs, _fat, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.food == null ? 'Nuevo alimento' : 'Editar alimento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            SegmentedButton<FoodBasis>(
              segments: const [
                ButtonSegment(value: FoodBasis.unit, label: Text('Por unidad')),
                ButtonSegment(value: FoodBasis.per100, label: Text('Por 100 g/ml')),
              ],
              selected: {_basis},
              onSelectionChanged: (s) => setState(() {
                _basis = s.first;
                if (_basis == FoodBasis.per100 && (_unit.text == 'unidad' || _unit.text.isEmpty)) {
                  _unit.text = 'g';
                  _qty.text = '100';
                }
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: InputDecoration(
                labelText: _basis == FoodBasis.unit ? 'Unidad (huevo, lata, scoop)' : 'g o ml',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _basis == FoodBasis.unit
                  ? 'Macros de 1 ${_unit.text.isEmpty ? 'unidad' : _unit.text}'
                  : 'Macros por 100 ${_unit.text.isEmpty ? 'g' : _unit.text}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: NumberField(controller: _kcal, label: 'kcal', decimal: true)),
                const SizedBox(width: 8),
                Expanded(child: NumberField(controller: _protein, label: 'Proteína', suffix: 'g', decimal: true)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: NumberField(controller: _carbs, label: 'Carbos', suffix: 'g', decimal: true)),
                const SizedBox(width: 8),
                Expanded(child: NumberField(controller: _fat, label: 'Grasa', suffix: 'g', decimal: true)),
              ],
            ),
            const SizedBox(height: 8),
            NumberField(controller: _qty, label: 'Cantidad por defecto', decimal: true),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final kcal = parseNum(_kcal.text);
            final protein = parseNum(_protein.text);
            if (name.isEmpty || kcal == null || protein == null) {
              showSnack(context, 'Faltan nombre, kcal o proteína');
              return;
            }
            Navigator.pop(
              context,
              FoodsCompanion(
                id: widget.food == null ? const Value.absent() : Value(widget.food!.id),
                name: Value(name),
                basis: Value(_basis),
                unitLabel: Value(_unit.text.trim().isEmpty ? 'unidad' : _unit.text.trim()),
                kcal: Value(kcal),
                protein: Value(protein),
                carbs: Value(parseNum(_carbs.text) ?? 0),
                fat: Value(parseNum(_fat.text) ?? 0),
                defaultQuantity: Value(parseNum(_qty.text) ?? 1),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
