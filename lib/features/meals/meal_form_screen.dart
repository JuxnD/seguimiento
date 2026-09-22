import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/nutrition.dart';
import '../../ui/widgets.dart';

class MealFormScreen extends ConsumerStatefulWidget {
  const MealFormScreen({super.key, required this.draft});

  final MealDraft draft;

  @override
  ConsumerState<MealFormScreen> createState() => _MealFormScreenState();
}

class _MealFormScreenState extends ConsumerState<MealFormScreen> {
  late final MealDraft d = widget.draft;
  late final _notes = TextEditingController(text: d.notes ?? '');

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addFromCatalog() async {
    final foods = await ref.read(nutritionRepositoryProvider).foodsByRecentUse();
    if (!mounted) return;
    final item = await showModalBottomSheet<MealItemDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FoodPicker(foods: foods),
    );
    if (item != null) setState(() => d.items.add(item));
  }

  Future<void> _addFree() async {
    final item = await showDialog<MealItemDraft>(context: context, builder: (_) => const _FreeItemDialog());
    if (item != null) setState(() => d.items.add(item));
  }

  Future<void> _save() async {
    d.notes = _notes.text;
    await ref.read(nutritionRepositoryProvider).saveMeal(d);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final m = d.macros;
    return Scaffold(
      appBar: AppBar(
        title: Text(d.id == null ? 'Nueva comida' : 'Editar comida'),
        actions: [
          if (d.id != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDelete(context, 'la comida')) {
                  await ref.read(nutritionRepositoryProvider).deleteMeal(d.id!);
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
              DateTile(date: d.date, onChanged: (v) => setState(() => d.date = v)),
              TimeTile(time: d.time, onChanged: (v) => setState(() => d.time = v)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in MealSlot.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: d.slot == s,
                      onSelected: (_) => setState(() => d.slot = s),
                    ),
                ],
              ),
            ],
          ),
          AppCard(
            title: 'Alimentos',
            trailing: Wrap(
              children: [
                IconButton(
                    tooltip: 'Del catálogo', icon: const Icon(Icons.list_alt), onPressed: _addFromCatalog),
                IconButton(tooltip: 'Entrada libre', icon: const Icon(Icons.edit), onPressed: _addFree),
              ],
            ),
            children: [
              if (d.items.isEmpty) const EmptyHint('Añade alimentos del catálogo o una entrada libre.'),
              for (final item in d.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${item.label}${item.quantityLabel == null ? '' : ' ${item.quantityLabel}'}'),
                  subtitle: Text('${fmtInt(item.macros.kcal)} kcal · P ${fmtDec(item.macros.protein)} g · '
                      'C ${fmtDec(item.macros.carbs)} g · G ${fmtDec(item.macros.fat)} g'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => d.items.remove(item)),
                  ),
                ),
              const Divider(),
              Text(
                'Total: ${fmtInt(m.kcal)} kcal · P ${fmtInt(m.protein)} g · C ${fmtInt(m.carbs)} g · G ${fmtInt(m.fat)} g',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          AppCard(
            children: [
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: d.items.isEmpty ? null : _save,
        icon: const Icon(Icons.save),
        label: const Text('Guardar'),
      ),
    );
  }
}

/// Lista de alimentos ordenada por uso reciente + cantidad.
class _FoodPicker extends StatefulWidget {
  const _FoodPicker({required this.foods});

  final List<FoodRow> foods;

  @override
  State<_FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<_FoodPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.foods
        .where((f) => f.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Buscar alimento', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (list.isEmpty)
              const Expanded(child: EmptyHint('Sin resultados. Añádelo en el catálogo (pestaña Comidas → Catálogo).'))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final f = list[i];
                    return ListTile(
                      title: Text(f.name),
                      subtitle: Text('${fmtInt(f.kcal)} kcal · P ${fmtDec(f.protein)} g ${f.basisLabel}'),
                      onTap: () async {
                        final qty = await showDialog<double>(
                          context: context,
                          builder: (_) => _QuantityDialog(food: f),
                        );
                        if (qty != null && context.mounted) {
                          Navigator.pop(context, MealItemDraft.fromFood(f, qty));
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.food});

  final FoodRow food;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _qty = TextEditingController(text: fmtDec(widget.food.defaultQuantity));

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = parseNum(_qty.text) ?? 0;
    final macros = macrosFor(basis: widget.food.basis, perBasis: widget.food.macros, quantity: q);
    return AlertDialog(
      title: Text(widget.food.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NumberField(
            controller: _qty,
            label: 'Cantidad',
            suffix: widget.food.basis == FoodBasis.unit ? widget.food.unitLabel : widget.food.unitLabel,
            decimal: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('${fmtInt(macros.kcal)} kcal · P ${fmtDec(macros.protein)} g'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: q <= 0 ? null : () => Navigator.pop(context, q), child: const Text('Añadir')),
      ],
    );
  }
}

/// Plato de fuera: proteína y kcal a ojo, sin catálogo.
class _FreeItemDialog extends StatefulWidget {
  const _FreeItemDialog();

  @override
  State<_FreeItemDialog> createState() => _FreeItemDialogState();
}

class _FreeItemDialogState extends State<_FreeItemDialog> {
  final _label = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();

  @override
  void dispose() {
    for (final c in [_label, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Entrada libre'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                  labelText: 'Qué comiste', hintText: 'Bandeja paisa', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
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
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            if (label.isEmpty) return;
            Navigator.pop(
              context,
              MealItemDraft(
                label: label,
                macros: Macros(
                  kcal: parseNum(_kcal.text) ?? 0,
                  protein: parseNum(_protein.text) ?? 0,
                  carbs: parseNum(_carbs.text) ?? 0,
                  fat: parseNum(_fat.text) ?? 0,
                ),
              ),
            );
          },
          child: const Text('Añadir'),
        ),
      ],
    );
  }
}
