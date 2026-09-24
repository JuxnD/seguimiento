import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/nutrition.dart';
import '../database.dart';

class MealItemDraft {
  MealItemDraft({
    this.foodId,
    required this.label,
    this.quantity,
    this.quantityUnit,
    required this.macros,
    this.sourceVerified,
  });

  /// Desde el catálogo: los macros se calculan y se congelan al guardar.
  factory MealItemDraft.fromFood(FoodRow food, double quantity) => MealItemDraft(
        foodId: food.id,
        label: food.name,
        quantity: quantity,
        quantityUnit: food.unitLabel,
        macros: macrosFor(basis: food.basis, perBasis: food.macros, quantity: quantity),
        sourceVerified: food.source.isVerified,
      );

  int? foodId;
  String label;
  double? quantity;
  String? quantityUnit;
  Macros macros;

  /// null en entradas libres: ahí la cifra es una estimación a ojo.
  bool? sourceVerified;

  bool get isFree => foodId == null;

  String? get quantityLabel {
    if (quantity == null) return null;
    final q = fmtDec(quantity!);
    final u = quantityUnit ?? '';
    return (u == 'g' || u == 'ml') ? '$q $u' : '×$q${u.isEmpty || u == 'unidad' ? '' : ' $u'}';
  }
}

class MealDraft {
  MealDraft({this.id, required this.date, this.time, required this.slot, this.notes, List<MealItemDraft>? items})
      : items = items ?? [];

  int? id;
  DateTime date;
  String? time;
  MealSlot slot;
  String? notes;
  final List<MealItemDraft> items;

  Macros get macros => Macros.sum(items.map((i) => i.macros));
}

class MealWithItems {
  MealWithItems(this.meal, this.items);

  final MealRow meal;
  final List<MealItemRow> items;

  Macros get macros => Macros.sum(items.map((i) => i.macros));
}

extension FoodRowMacros on FoodRow {
  Macros get macros => Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat);

  String get basisLabel => basis == FoodBasis.unit ? 'por $unitLabel' : 'por 100 $unitLabel';
}

extension MealItemRowMacros on MealItemRow {
  Macros get macros => Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat);
}


/// Combo con sus alimentos ya resueltos.
class MealTemplate {
  MealTemplate(this.row, this.items);

  final MealTemplateRow row;

  /// (alimento, cantidad en la unidad del alimento).
  final List<(FoodRow, double)> items;

  String get name => row.name;

  List<MealItemDraft> toDrafts() =>
      [for (final (food, quantity) in items) MealItemDraft.fromFood(food, quantity)];

  Macros get macros => Macros.sum(toDrafts().map((i) => i.macros));
}

class NutritionRepository {
  NutritionRepository(this.db);

  final AppDatabase db;

  // ---------- Catálogo ----------

  Stream<List<FoodRow>> watchFoods() =>
      (db.select(db.foods)..orderBy([(t) => OrderingTerm(expression: t.name.collate(Collate.noCase))])).watch();

  /// Alimentos más usados en los últimos 30 días primero: acelera el registro.
  Future<List<FoodRow>> foodsByRecentUse() async {
    final since = dayKey(addDays(DateTime.now(), -30));
    final uses = db.mealItems.id.count();
    final rows = await (db.select(db.foods).join([
      leftOuterJoin(
        db.mealItems,
        db.mealItems.foodId.equalsExp(db.foods.id) &
            db.mealItems.mealId.isInQuery(
              db.selectOnly(db.meals)
                ..addColumns([db.meals.id])
                ..where(db.meals.date.isBiggerOrEqualValue(since)),
            ),
      ),
    ])
          ..addColumns([uses])
          ..groupBy([db.foods.id])
          ..orderBy([
            OrderingTerm(expression: uses, mode: OrderingMode.desc),
            OrderingTerm(expression: db.foods.name.collate(Collate.noCase)),
          ]))
        .get();
    return rows.map((r) => r.readTable(db.foods)).toList();
  }

  Future<int> saveFood(FoodsCompanion data) async {
    if (data.id.present) {
      await (db.update(db.foods)..where((t) => t.id.equals(data.id.value))).write(data);
      return data.id.value;
    }
    return db.into(db.foods).insert(data);
  }

  /// Seguro: los items históricos conservan sus macros (foodId → null).
  /// Los combos que lo usan sí lo pierden: ver [templatesUsingFood].
  Future<void> deleteFood(int id) => (db.delete(db.foods)..where((t) => t.id.equals(id))).go();

  /// Nombres de los combos que llevan este alimento: borrarlo los cambia.
  Future<List<String>> templatesUsingFood(int foodId) async {
    final rows = await (db.select(db.mealTemplates).join([
      innerJoin(db.mealTemplateItems, db.mealTemplateItems.templateId.equalsExp(db.mealTemplates.id)),
    ])
          ..where(db.mealTemplateItems.foodId.equals(foodId))
          ..orderBy([OrderingTerm(expression: db.mealTemplates.position)]))
        .get();
    return {for (final r in rows) r.readTable(db.mealTemplates).name}.toList();
  }

  // ---------- Combos ----------

  /// Combos frecuentes, con sus alimentos actuales del catálogo.
  Future<List<MealTemplate>> templates() async {
    final rows = await (db.select(db.mealTemplates)
          ..orderBy([(t) => OrderingTerm(expression: t.position), (t) => OrderingTerm(expression: t.id)]))
        .get();
    final out = <MealTemplate>[];
    for (final row in rows) {
      final items = await (db.select(db.mealTemplateItems).join([
        innerJoin(db.foods, db.foods.id.equalsExp(db.mealTemplateItems.foodId)),
      ])
            ..where(db.mealTemplateItems.templateId.equals(row.id))
            ..orderBy([OrderingTerm(expression: db.mealTemplateItems.position)]))
          .get();
      out.add(MealTemplate(
        row,
        [
          for (final r in items)
            (r.readTable(db.foods), r.readTable(db.mealTemplateItems).quantity),
        ],
      ));
    }
    return out;
  }

  /// Guarda un combo desde la app. Si ya existe uno con ese nombre, se
  /// reemplazan sus alimentos (renombrar = guardar con el nombre nuevo).
  /// Solo entran alimentos del catálogo: una entrada libre no tiene receta.
  Future<int> saveTemplate(String name, MealSlot? slot, List<(int, double)> items) =>
      db.transaction(() async {
        final clean = name.trim();
        final existing = await (db.select(db.mealTemplates)..where((t) => t.name.equals(clean)))
            .getSingleOrNull();
        final int id;
        if (existing == null) {
          final count = (await db.select(db.mealTemplates).get()).length;
          id = await db.into(db.mealTemplates).insert(MealTemplatesCompanion.insert(
                name: clean,
                slot: Value(slot),
                position: Value(count),
              ));
        } else {
          id = existing.id;
          await (db.update(db.mealTemplates)..where((t) => t.id.equals(id)))
              .write(MealTemplatesCompanion(slot: Value(slot)));
          await (db.delete(db.mealTemplateItems)..where((t) => t.templateId.equals(id))).go();
        }
        var position = 0;
        for (final (foodId, quantity) in items) {
          await db.into(db.mealTemplateItems).insert(MealTemplateItemsCompanion.insert(
                templateId: id,
                foodId: foodId,
                quantity: quantity,
                position: Value(position++),
              ));
        }
        return id;
      });

  Future<void> deleteTemplate(int id) => (db.delete(db.mealTemplates)..where((t) => t.id.equals(id))).go();

  Future<FoodRow?> foodById(int id) =>
      (db.select(db.foods)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<MealTemplate>> watchTemplates() =>
      db.select(db.mealTemplates).watch().asyncMap((_) => templates());

  /// Registra el combo como una comida del día. Devuelve el id de la comida.
  Future<int> logTemplate(MealTemplate template, DateTime date, {MealSlot? slot, String? time}) {
    final draft = MealDraft(
      date: date,
      time: time,
      slot: slot ?? template.row.slot ?? MealSlot.otro,
      items: template.toDrafts(),
    );
    return saveMeal(draft);
  }

  // ---------- Comidas ----------

  Stream<List<MealWithItems>> watchDay(DateTime day) => watchRange(day, day);

  JoinedSelectStatement<HasResultSet, dynamic> _rangeQuery(DateTime from, DateTime to) => db.select(db.meals).join([
        leftOuterJoin(db.mealItems, db.mealItems.mealId.equalsExp(db.meals.id)),
      ])
        ..where(db.meals.date.isBetweenValues(dayKey(from), dayKey(to)))
        ..orderBy([
          OrderingTerm(expression: db.meals.date),
          OrderingTerm(expression: db.meals.time),
          OrderingTerm(expression: db.mealItems.id),
        ]);

  Stream<List<MealWithItems>> watchRange(DateTime from, DateTime to) => _rangeQuery(from, to).watch().map(_group);

  /// Consulta de una vez (no abre un stream para quedarse con el primer valor).
  Future<List<MealWithItems>> range(DateTime from, DateTime to) async => _group(await _rangeQuery(from, to).get());

  List<MealWithItems> _group(List<TypedResult> rows) {
    final byId = <int, MealWithItems>{};
    for (final r in rows) {
      final meal = r.readTable(db.meals);
      final entry = byId.putIfAbsent(meal.id, () => MealWithItems(meal, []));
      final item = r.readTableOrNull(db.mealItems);
      if (item != null) entry.items.add(item);
    }
    final list = byId.values.toList()
      ..sort((a, b) => '${a.meal.date} ${a.meal.slot.index} ${a.meal.time ?? ''}'
          .compareTo('${b.meal.date} ${b.meal.slot.index} ${b.meal.time ?? ''}'));
    return list;
  }

  Future<int> saveMeal(MealDraft d) => db.transaction(() async {
        final data = MealsCompanion(
          date: Value(dayKey(d.date)),
          time: Value(d.time),
          slot: Value(d.slot),
          notes: Value((d.notes == null || d.notes!.trim().isEmpty) ? null : d.notes!.trim()),
        );
        final int id;
        if (d.id == null) {
          id = await db.into(db.meals).insert(data);
        } else {
          id = d.id!;
          await (db.update(db.meals)..where((t) => t.id.equals(id))).write(data);
          await (db.delete(db.mealItems)..where((t) => t.mealId.equals(id))).go();
        }
        for (final it in d.items) {
          await db.into(db.mealItems).insert(MealItemsCompanion.insert(
                mealId: id,
                foodId: Value(it.foodId),
                label: it.label.trim(),
                quantity: Value(it.quantity),
                quantityUnit: Value(it.quantityUnit),
                kcal: it.macros.kcal,
                protein: it.macros.protein,
                carbs: Value(it.macros.carbs),
                fat: Value(it.macros.fat),
                sourceVerified: Value(it.sourceVerified),
              ));
        }
        d.id = id;
        return id;
      });

  Future<MealDraft> loadMeal(int id) async {
    final m = await (db.select(db.meals)..where((t) => t.id.equals(id))).getSingle();
    final items = await (db.select(db.mealItems)
          ..where((t) => t.mealId.equals(id))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    return MealDraft(
      id: m.id,
      date: parseDay(m.date),
      time: m.time,
      slot: m.slot,
      notes: m.notes,
      items: [
        for (final i in items)
          MealItemDraft(
            foodId: i.foodId,
            label: i.label,
            quantity: i.quantity,
            quantityUnit: i.quantityUnit,
            macros: i.macros,
            sourceVerified: i.sourceVerified,
          ),
      ],
    );
  }

  /// Copia una comida a otra fecha (tus desayunos se repiten).
  Future<int> copyMeal(int id, DateTime toDate, {String? time}) async {
    final d = await loadMeal(id);
    d
      ..id = null
      ..date = toDate
      ..time = time ?? d.time;
    return saveMeal(d);
  }

  Future<void> deleteMeal(int id) => (db.delete(db.meals)..where((t) => t.id.equals(id))).go();
}
