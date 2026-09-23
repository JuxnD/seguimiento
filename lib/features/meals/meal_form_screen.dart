import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/meal_slots.dart';
import '../../domain/nutrition.dart';
import '../../domain/search.dart';
import '../../ui/widgets.dart';
import 'foods_screen.dart';

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
      builder: (_) => _FoodPicker(foods: foods, onCreate: _createFood),
    );
    if (item != null) setState(() => d.items.add(item));
  }

  /// Alta de un alimento sin salir del registro. Devuelve el alimento ya
  /// guardado para poder elegir la cantidad enseguida.
  Future<FoodRow?> _createFood(BuildContext sheetContext, String name) async {
    final data = await showDialog<FoodsCompanion>(
      context: sheetContext,
      builder: (_) => FoodDialog(initialName: name.trim().isEmpty ? null : name.trim()),
    );
    if (data == null) return null;
    final repo = ref.read(nutritionRepositoryProvider);
    final id = await repo.saveFood(data);
    return repo.foodById(id);
  }

  /// Tocar un ítem permite corregir la cantidad (catálogo) o las cifras
  /// (entrada libre). Así un combo se ajusta antes de guardar.
  Future<void> _editItem(MealItemDraft item) async {
    final index = d.items.indexOf(item);
    if (index < 0) return;
    MealItemDraft? updated;
    if (item.foodId != null) {
      final food = await ref.read(nutritionRepositoryProvider).foodById(item.foodId!);
      if (!mounted) return;
      if (food == null) {
        showSnack(context, 'Ese alimento ya no está en el catálogo; se conservan sus cifras');
        return;
      }
      final qty = await showDialog<double>(
        context: context,
        builder: (_) => _QuantityDialog(food: food, initial: item.quantity, action: 'Actualizar'),
      );
      if (qty != null) updated = MealItemDraft.fromFood(food, qty);
    } else {
      updated =
          await showDialog<MealItemDraft>(context: context, builder: (_) => _FreeItemDialog(initial: item));
    }
    if (updated != null) setState(() => d.items[index] = updated!);
  }

  /// Guarda los alimentos del catálogo de esta comida como combo de un toque.
  Future<void> _saveAsTemplate() async {
    final fromCatalog = d.items.where((i) => i.foodId != null && i.quantity != null).toList();
    if (fromCatalog.isEmpty) {
      showSnack(context, 'Un combo necesita al menos un alimento del catálogo');
      return;
    }
    final skipped = d.items.length - fromCatalog.length;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TemplateNameDialog(skipped: skipped),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(nutritionRepositoryProvider).saveTemplate(
      name,
      d.slot == MealSlot.otro ? null : d.slot,
      [for (final i in fromCatalog) (i.foodId!, i.quantity!)],
    );
    if (mounted) showSnack(context, 'Combo "${name.trim()}" guardado');
  }

  /// Un desayuno a las 14:57 casi siempre es un error de franja: se pregunta.
  Future<bool> _confirmSlot() async {
    final suggested = slotMismatch(d.slot, d.time);
    if (suggested == null) return true;
    final choice = await showDialog<MealSlot>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('La hora no cuadra con la franja'),
        content: Text('${d.slot.label} a las ${d.time}. ¿Lo guardo como ${suggested.label.toLowerCase()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, d.slot), child: Text('Dejar ${d.slot.label.toLowerCase()}')),
          FilledButton(
              onPressed: () => Navigator.pop(c, suggested),
              child: Text('Cambiar a ${suggested.label.toLowerCase()}')),
        ],
      ),
    );
    if (choice == null) return false;
    setState(() => d.slot = choice);
    return true;
  }

  /// Añade de un toque los alimentos de un combo frecuente.
  Future<void> _addTemplate() async {
    final templates = await ref.read(nutritionRepositoryProvider).templates();
    if (!mounted) return;
    if (templates.isEmpty) {
      showSnack(context, 'No hay combos guardados');
      return;
    }
    final chosen = await showModalBottomSheet<MealTemplate>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final t in templates)
              ListTile(
                leading: const Icon(Icons.bolt),
                title: Text(t.name),
                subtitle: Text('${fmtInt(t.macros.kcal)} kcal · P ${fmtInt(t.macros.protein)} g'),
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => d.items.addAll(chosen.toDrafts()));
  }

  Future<void> _addFree() async {
    final item = await showDialog<MealItemDraft>(context: context, builder: (_) => const _FreeItemDialog());
    if (item != null) setState(() => d.items.add(item));
  }

  Future<void> _save() async {
    if (!await _confirmSlot()) return;
    d.notes = _notes.text;
    if (!mounted) return;
    final ok = await guarded(context, () => ref.read(nutritionRepositoryProvider).saveMeal(d));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final m = d.macros;
    return Scaffold(
      appBar: AppBar(
        title: Text(d.id == null ? 'Nueva comida' : 'Editar comida'),
        actions: [
          IconButton(
            tooltip: 'Guardar como combo',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: d.items.isEmpty ? null : _saveAsTemplate,
          ),
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
                IconButton(tooltip: 'Combo', icon: const Icon(Icons.bolt), onPressed: _addTemplate),
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
                  onTap: () => _editItem(item),
                  title: Text('${item.label}${item.quantityLabel == null ? '' : ' ${item.quantityLabel}'}'),
                  subtitle: Text('${item.isFree ? 'estimado · ' : ''}'
                      '${fmtInt(item.macros.kcal)} kcal · P ${fmtDec(item.macros.protein)} g · '
                      'C ${fmtDec(item.macros.carbs)} g · G ${fmtDec(item.macros.fat)} g'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => d.items.remove(item)),
                  ),
                ),
              if (d.items.isNotEmpty)
                Text('Toca un alimento para cambiar la cantidad.',
                    style: Theme.of(context).textTheme.bodySmall),
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
  const _FoodPicker({required this.foods, required this.onCreate});

  final List<FoodRow> foods;

  /// Crea un alimento nuevo sin salir del registro.
  final Future<FoodRow?> Function(BuildContext context, String name) onCreate;

  @override
  State<_FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<_FoodPicker> {
  String _query = '';

  Future<void> _create() async {
    final food = await widget.onCreate(context, _query);
    if (food == null || !mounted) return;
    final qty = await showDialog<double>(context: context, builder: (_) => _QuantityDialog(food: food));
    if (qty != null && mounted) Navigator.pop(context, MealItemDraft.fromFood(food, qty));
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.foods.where((f) => matchesQuery(f.name, _query)).toList();
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
                    labelText: 'Buscar alimento',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: Text(_query.trim().isEmpty ? 'Nuevo alimento' : 'Crear "${_query.trim()}"'),
                ),
              ),
            ),
            if (list.isEmpty)
              const Expanded(child: EmptyHint('Sin resultados. Créalo aquí mismo con el botón de arriba.'))
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
  const _QuantityDialog({required this.food, this.initial, this.action = 'Añadir'});

  final FoodRow food;
  final double? initial;
  final String action;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _qty = TextEditingController(text: fmtDec(widget.initial ?? widget.food.defaultQuantity));

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
            suffix: widget.food.unitLabel,
            decimal: true,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('${fmtInt(macros.kcal)} kcal · P ${fmtDec(macros.protein)} g'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: q <= 0 ? null : () => Navigator.pop(context, q), child: Text(widget.action)),
      ],
    );
  }
}

/// Plato de fuera: proteína y kcal a ojo, sin catálogo.
class _FreeItemDialog extends StatefulWidget {
  const _FreeItemDialog({this.initial});

  /// Para corregir una entrada libre ya añadida.
  final MealItemDraft? initial;

  @override
  State<_FreeItemDialog> createState() => _FreeItemDialogState();
}

class _FreeItemDialogState extends State<_FreeItemDialog> {
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late final _kcal = TextEditingController(text: _num(widget.initial?.macros.kcal));
  late final _protein = TextEditingController(text: _num(widget.initial?.macros.protein));
  late final _carbs = TextEditingController(text: _num(widget.initial?.macros.carbs));
  late final _fat = TextEditingController(text: _num(widget.initial?.macros.fat));

  static String _num(double? v) => v == null || v == 0 ? '' : fmtDec(v);

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
              autofocus: widget.initial == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Qué comiste', hintText: 'Bandeja paisa', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: NumberField(controller: _kcal, label: 'kcal', decimal: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: NumberField(controller: _protein, label: 'Proteína', suffix: 'g', decimal: true)),
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
            final kcal = parseNum(_kcal.text) ?? 0, protein = parseNum(_protein.text) ?? 0;
            // Antes el botón no hacía nada sin decir por qué.
            if (label.isEmpty) {
              showSnack(context, 'Falta qué comiste');
              return;
            }
            if (kcal <= 0 && protein <= 0) {
              showSnack(context, 'Pon al menos las kcal o la proteína, aunque sea a ojo');
              return;
            }
            Navigator.pop(
              context,
              MealItemDraft(
                label: label,
                macros: Macros(
                  kcal: kcal,
                  protein: protein,
                  carbs: parseNum(_carbs.text) ?? 0,
                  fat: parseNum(_fat.text) ?? 0,
                ),
              ),
            );
          },
          child: Text(widget.initial == null ? 'Añadir' : 'Guardar'),
        ),
      ],
    );
  }
}

class _TemplateNameDialog extends StatefulWidget {
  const _TemplateNameDialog({required this.skipped});

  /// Entradas libres que no entran al combo.
  final int skipped;

  @override
  State<_TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<_TemplateNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Guardar como combo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Cena con pan',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Si ya existe un combo con ese nombre, se reemplaza.'),
            if (widget.skipped > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child:
                    Text('${widget.skipped} entrada(s) libre(s) no entran: un combo solo usa el catálogo.'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: const Text('Guardar')),
        ],
      );
}
