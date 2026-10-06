import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../ui/widgets.dart';
import 'food_label_screen.dart';

enum _FoodFilter { todos, favoritos, personalizados }

/// Catálogo de alimentos: lo sembrado desde las etiquetas y lo que el usuario
/// fue creando (a mano o desde una entrada libre). Aquí se editan, renombran,
/// borran, marcan como favoritos y se convierten en combo.
class FoodsScreen extends ConsumerStatefulWidget {
  const FoodsScreen({super.key, this.labelScreenBuilder});

  final FoodLabelScreen Function()? labelScreenBuilder;

  @override
  ConsumerState<FoodsScreen> createState() => _FoodsScreenState();
}

class _FoodsScreenState extends ConsumerState<FoodsScreen> {
  _FoodFilter _filter = _FoodFilter.todos;

  bool _passes(FoodRow f) => switch (_filter) {
        _FoodFilter.todos => true,
        _FoodFilter.favoritos => f.favorite,
        _FoodFilter.personalizados => f.isCustom,
      };

  @override
  Widget build(BuildContext context) {
    final foods = ref.watch(foodsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de alimentos')),
      body: foods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final list = [...all.where(_passes)]..sort((a, b) {
              if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
              return 0;
            });
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: OutlinedButton.icon(
                    onPressed: () => _importLabel(context, ref),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Leer etiqueta · IA')),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final f in _FoodFilter.values)
                      ChoiceChip(
                        label: Text(switch (f) {
                          _FoodFilter.todos => 'Todos',
                          _FoodFilter.favoritos => 'Favoritos',
                          _FoodFilter.personalizados => 'Personalizados',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? const EmptyHint(
                        'Vacío. Añade huevo, atún, Klim, leche, arroz…')
                    : list.isEmpty
                        ? EmptyHint(_filter == _FoodFilter.favoritos
                            ? 'Sin favoritos. Toca la estrella de un alimento para que salga primero.'
                            : 'Las entradas libres se guardan aquí solas al registrar una comida.')
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) => _FoodTile(
                              food: list[i],
                              onEdit: () => _edit(context, ref, list[i]),
                              onDelete: () => _delete(context, ref, list[i]),
                              onCombo: () => _asCombo(context, ref, list[i]),
                            ),
                          ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Alimento'),
      ),
    );
  }

  /// Un plato que se repite entero (almuerzo corriente) queda a un toque.
  Future<void> _asCombo(
      BuildContext context, WidgetRef ref, FoodRow food) async {
    final repo = ref.read(nutritionRepositoryProvider);
    final taken =
        (await repo.templates()).any((t) => t.name == food.name.trim());
    if (!context.mounted) return;
    if (taken) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Ya hay un combo "${food.name}"'),
          content: const Text(
              'Se reemplaza por este alimento con su porción habitual.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Reemplazar')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    await guarded(context, () => repo.templateFromFood(food),
        ok: 'Combo "${food.name}" listo en Comidas');
  }

  /// Borrar un alimento no toca el historial (los macros están copiados),
  /// pero sí vacía los combos que lo usan: se dice cuáles antes de borrar.
  Future<void> _delete(
      BuildContext context, WidgetRef ref, FoodRow food) async {
    final repo = ref.read(nutritionRepositoryProvider);
    final combos = await repo.templatesUsingFood(food.id);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Borrar ${food.name}?'),
        content: Text(combos.isEmpty
            ? 'Las comidas ya registradas no cambian.'
            : 'Las comidas ya registradas no cambian, pero sale de '
                '${combos.length == 1 ? 'este combo' : 'estos combos'}: ${combos.join(', ')}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await guarded(context, () => repo.deleteFood(food.id));
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, FoodRow? food) async {
    final data = await showDialog<FoodsCompanion>(
        context: context, builder: (_) => FoodDialog(food: food));
    if (data != null && context.mounted) {
      await guarded(
          context, () => ref.read(nutritionRepositoryProvider).saveFood(data));
    }
  }

  Future<void> _importLabel(BuildContext context, WidgetRef ref) async {
    final draft = await Navigator.push<FoodLabelDraft>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                widget.labelScreenBuilder?.call() ?? const FoodLabelScreen()));
    if (draft == null || !context.mounted) return;
    final data = await showDialog<FoodsCompanion>(
        context: context, builder: (_) => FoodDialog(labelDraft: draft));
    if (data != null && context.mounted) {
      await guarded(
          context, () => ref.read(nutritionRepositoryProvider).saveFood(data));
    }
  }
}

class _FoodTile extends ConsumerWidget {
  const _FoodTile(
      {required this.food,
      required this.onEdit,
      required this.onDelete,
      required this.onCombo});

  final FoodRow food;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCombo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = food;
    return ListTile(
      leading: IconButton(
        tooltip: f.favorite ? 'Quitar de favoritos' : 'Marcar como favorito',
        icon: Icon(f.favorite ? Icons.star : Icons.star_border,
            color: f.favorite ? Theme.of(context).colorScheme.primary : null),
        onPressed: () => guarded(
            context,
            () => ref
                .read(nutritionRepositoryProvider)
                .setFavorite(f.id, !f.favorite)),
      ),
      title: Row(
        children: [
          Flexible(child: Text(f.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          _SourceBadge(source: f.source),
        ],
      ),
      subtitle: Text(
          '${fmtInt(f.kcal)} kcal · P ${fmtDec(f.protein)} · C ${fmtDec(f.carbs)} · '
          'G ${fmtDec(f.fat)} ${f.basisLabel}'
          '${f.origin == FoodOrigin.entradaLibre ? ' · de una entrada libre' : ''}'),
      trailing: PopupMenuButton<String>(
        tooltip: 'Más',
        onSelected: (v) => switch (v) {
          'editar' => onEdit(),
          'combo' => onCombo(),
          _ => onDelete(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'editar', child: Text('Editar o renombrar')),
          PopupMenuItem(value: 'combo', child: Text('Usar como combo')),
          PopupMenuItem(value: 'borrar', child: Text('Borrar')),
        ],
      ),
      onTap: onEdit,
    );
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
        color: verified
            ? scheme.primary.withOpacity(0.18)
            : scheme.surfaceContainerHighest,
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
  const FoodDialog({super.key, this.food, this.initialName, this.labelDraft});

  final FoodRow? food;

  /// Nombre prellenado (lo que se estaba buscando).
  final String? initialName;
  final FoodLabelDraft? labelDraft;

  @override
  State<FoodDialog> createState() => _FoodDialogState();
}

class _FoodDialogState extends State<FoodDialog> {
  late final _name = TextEditingController(
      text: widget.food?.name ??
          widget.labelDraft?.name ??
          widget.initialName ??
          '');
  late final _unit = TextEditingController(
      text: widget.food?.unitLabel ??
          (widget.labelDraft == null
              ? 'unidad'
              : widget.labelDraft!.unitLabel));
  late final _kcal = TextEditingController(
      text: _macroText(widget.food?.kcal, widget.labelDraft?.kcal));
  late final _protein = TextEditingController(
      text: _macroText(widget.food?.protein, widget.labelDraft?.protein));
  late final _carbs = TextEditingController(
      text: _macroText(widget.food?.carbs, widget.labelDraft?.carbs));
  late final _fat = TextEditingController(
      text: _macroText(widget.food?.fat, widget.labelDraft?.fat));
  late final _qty = TextEditingController(
      text: widget.food != null
          ? fmtDec(widget.food!.defaultQuantity)
          : widget.labelDraft?.defaultQuantity == null
              ? (widget.labelDraft == null ? '1' : '')
              : fmtDec(widget.labelDraft!.defaultQuantity!));
  late final _eggs = TextEditingController(
      text: widget.food?.eggsPerUnit == null
          ? ''
          : fmtDec(widget.food!.eggsPerUnit!));
  late FoodBasis? _basis = widget.food?.basis ??
      widget.labelDraft?.basis ??
      (widget.labelDraft == null ? FoodBasis.unit : null);
  late MacroSource _source = widget.food?.source ?? MacroSource.referencia;
  bool _verifiedAgainstPackage = false;
  bool _confirmedUnweighedPortion = false;

  static String _macroText(double? saved, double? imported) {
    final value = saved ?? imported;
    return value == null ? '' : fmtDec(value);
  }

  Widget _labelSnapshot(FoodLabelDraft draft) {
    final source = draft.sourceSnapshot;
    String value(double? v, String unit) =>
        v == null ? 'no leído' : '${fmtDec(v)} $unit';
    final basis = switch (source.basis) {
      'per100' => 'Por 100 ${source.unit ?? '(unidad no identificada)'}',
      'portion' => 'Por porción',
      _ => 'No identificada',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'Lectura de etiqueta · ${_verifiedAgainstPackage ? 'verificada por ti' : 'sin verificar'}'),
        Text('Base leída: $basis'),
        Text('Unidad leída: ${source.unit ?? 'no identificada'}'),
        Text(
            'Porción: ${source.servingQuantity == null ? 'no identificada' : '${fmtDec(source.servingQuantity!)} ${source.unit ?? ''}'}'),
        Text(
            'Original: ${value(source.kcal, 'kcal')} · P ${value(source.protein, 'g')} · '
            'C ${value(source.carbs, 'g')} · G ${value(source.fat, 'g')}'),
        if (draft.convertedToPer100)
          Text(
              'Conversión local guardada por 100 ${source.unit}: valor × 100 ÷ ${fmtDec(source.servingQuantity!)}.'),
        for (final uncertainty in draft.uncertainties)
          Text('Por verificar: $uncertainty'),
      ]),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _unit,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _qty,
      _eggs
    ]) {
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
              decoration: const InputDecoration(
                  labelText: 'Nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            if (widget.labelDraft != null) ...[
              _labelSnapshot(widget.labelDraft!),
              const SizedBox(height: 8),
              if (widget.labelDraft!.portionNeedsConfirmation)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _confirmedUnweighedPortion,
                  onChanged: (value) => setState(
                      () => _confirmedUnweighedPortion = value ?? false),
                  title: const Text(
                      'Confirmo usar una unidad llamada “porción” sin conversión a g/ml'),
                  subtitle: const Text(
                      'El empaque no mostró el peso de esa porción; define también una cantidad por defecto.'),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _verifiedAgainstPackage,
                onChanged: (value) =>
                    setState(() => _verifiedAgainstPackage = value ?? false),
                title: const Text('Comprobé valores y porción con el empaque'),
                subtitle: const Text(
                    'Solo esta confirmación marca la fuente como etiqueta verificada.'),
              ),
              const SizedBox(height: 8),
            ],
            SegmentedButton<FoodBasis>(
              segments: const [
                ButtonSegment(value: FoodBasis.unit, label: Text('Por unidad')),
                ButtonSegment(
                    value: FoodBasis.per100, label: Text('Por 100 g/ml')),
              ],
              emptySelectionAllowed: true,
              selected: _basis == null ? <FoodBasis>{} : {_basis!},
              onSelectionChanged: (s) => setState(() {
                _basis = s.first;
                if (_basis == FoodBasis.per100) {
                  _qty.text = '100';
                }
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: InputDecoration(
                labelText: _basis == FoodBasis.unit
                    ? 'Unidad (huevo, lata, scoop)'
                    : _basis == FoodBasis.per100
                        ? 'g o ml'
                        : 'Elige primero una base',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _basis == FoodBasis.unit
                  ? 'Macros de 1 ${_unit.text.isEmpty ? 'unidad' : _unit.text}'
                  : _basis == FoodBasis.per100
                      ? 'Macros por 100 ${_unit.text.isEmpty ? 'g o ml' : _unit.text}'
                      : 'Indica si los valores son por unidad o por 100 g/ml',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: NumberField(
                        controller: _kcal, label: 'kcal', decimal: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: NumberField(
                        controller: _protein,
                        label: 'Proteína',
                        suffix: 'g',
                        decimal: true)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: NumberField(
                        controller: _carbs,
                        label: 'Carbos',
                        suffix: 'g',
                        decimal: true)),
                const SizedBox(width: 8),
                Expanded(
                    child: NumberField(
                        controller: _fat,
                        label: 'Grasa',
                        suffix: 'g',
                        decimal: true)),
              ],
            ),
            const SizedBox(height: 8),
            NumberField(
                controller: _qty, label: 'Cantidad por defecto', decimal: true),
            const SizedBox(height: 8),
            // Para el contador del día: un plato con huevos los cuenta aunque
            // no diga "huevo" en el nombre (§16.15).
            NumberField(
                controller: _eggs,
                label: 'Huevos enteros por porción (vacío = ninguno)',
                decimal: true),
            const SizedBox(height: 12),
            if (widget.labelDraft == null)
              SegmentedButton<MacroSource>(
                segments: const [
                  ButtonSegment(
                      value: MacroSource.etiqueta, label: Text('Etiqueta')),
                  ButtonSegment(
                      value: MacroSource.referencia, label: Text('Referencia')),
                  ButtonSegment(
                      value: MacroSource.estimado, label: Text('A ojo')),
                ],
                selected: {_source},
                onSelectionChanged: (s) => setState(() => _source = s.first),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                  '"Referencia" son promedios y "a ojo" estimaciones de un plato: el informe los '
                  'arrastra con esa incertidumbre.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final kcal = parseNum(_kcal.text);
            final protein = parseNum(_protein.text);
            final carbs = parseNum(_carbs.text);
            final fat = parseNum(_fat.text);
            final quantity = parseNum(_qty.text);
            final unit = _unit.text.trim();
            final importingLabel = widget.labelDraft != null;
            if (name.isEmpty ||
                kcal == null ||
                protein == null ||
                (importingLabel &&
                    (_basis == null ||
                        unit.isEmpty ||
                        carbs == null ||
                        fat == null ||
                        quantity == null ||
                        quantity <= 0 ||
                        kcal < 0 ||
                        protein < 0 ||
                        carbs < 0 ||
                        fat < 0 ||
                        (_basis == FoodBasis.per100 &&
                            !['g', 'ml'].contains(unit)) ||
                        (widget.labelDraft!.portionNeedsConfirmation &&
                            !_confirmedUnweighedPortion)))) {
              showSnack(context,
                  'Completa nombre, base, unidad y los cuatro valores con cantidades válidas');
              return;
            }
            Navigator.pop(
              context,
              FoodsCompanion(
                id: widget.food == null
                    ? const Value.absent()
                    : Value(widget.food!.id),
                name: Value(name),
                basis: Value(_basis!),
                unitLabel: Value(unit.isEmpty ? 'unidad' : unit),
                kcal: Value(kcal),
                protein: Value(protein),
                carbs: Value(carbs ?? 0),
                fat: Value(fat ?? 0),
                // 0 o vacío abriría el diálogo de cantidad con el botón apagado.
                defaultQuantity: Value(_positiveOr(quantity, 1)),
                eggsPerUnit: Value((parseNum(_eggs.text) ?? 0) > 0
                    ? parseNum(_eggs.text)
                    : null),
                source: Value(widget.labelDraft != null
                    ? (_verifiedAgainstPackage
                        ? MacroSource.etiqueta
                        : MacroSource.estimado)
                    : _source),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

double _positiveOr(double? value, double fallback) =>
    value == null || value <= 0 ? fallback : value;
