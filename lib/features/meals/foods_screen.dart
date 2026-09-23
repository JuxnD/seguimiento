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
                    title: Row(
                      children: [
                        Flexible(child: Text(f.name, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        _SourceBadge(source: f.source),
                      ],
                    ),
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
    final data = await showDialog<FoodsCompanion>(context: context, builder: (_) => FoodDialog(food: food));
    if (data != null) await ref.read(nutritionRepositoryProvider).saveFood(data);
  }
}

/// Distingue lo verificado contra la etiqueta de lo que es un promedio.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final MacroSource source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verified = source.isVerified;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: verified ? scheme.primary.withOpacity(0.18) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: verified ? scheme.primary : scheme.outline),
      ),
      child: Text(
        source.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: verified ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Alta y edición de un alimento. Se usa desde el catálogo y desde el
/// registro de comidas, para no tener que salir del flujo.
class FoodDialog extends StatefulWidget {
  const FoodDialog({super.key, this.food, this.initialName});

  final FoodRow? food;

  /// Nombre prellenado (lo que se estaba buscando).
  final String? initialName;

  @override
  State<FoodDialog> createState() => _FoodDialogState();
}

class _FoodDialogState extends State<FoodDialog> {
  late final _name = TextEditingController(text: widget.food?.name ?? widget.initialName ?? '');
  late final _unit = TextEditingController(text: widget.food?.unitLabel ?? 'unidad');
  late final _kcal = TextEditingController(text: widget.food == null ? '' : fmtDec(widget.food!.kcal));
  late final _protein = TextEditingController(text: widget.food == null ? '' : fmtDec(widget.food!.protein));
  late final _carbs = TextEditingController(text: widget.food == null ? '' : fmtDec(widget.food!.carbs));
  late final _fat = TextEditingController(text: widget.food == null ? '' : fmtDec(widget.food!.fat));
  late final _qty = TextEditingController(text: fmtDec(widget.food?.defaultQuantity ?? 1));
  late FoodBasis _basis = widget.food?.basis ?? FoodBasis.unit;
  late MacroSource _source = widget.food?.source ?? MacroSource.referencia;

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
            const SizedBox(height: 12),
            SegmentedButton<MacroSource>(
              segments: const [
                ButtonSegment(value: MacroSource.etiqueta, label: Text('De la etiqueta')),
                ButtonSegment(value: MacroSource.referencia, label: Text('De referencia')),
              ],
              selected: {_source},
              onSelectionChanged: (s) => setState(() => _source = s.first),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('"De referencia" son promedios: el informe los arrastra con esa incertidumbre.'),
            ),
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
                source: Value(_source),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
