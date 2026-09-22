import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/nutrition.dart';
import '../database.dart';

class MealItemDraft {
  MealItemDraft({this.foodId, required this.label, this.quantity, this.quantityUnit, required this.macros});

  /// Desde el catálogo: los macros se calculan y se congelan al guardar.
  factory MealItemDraft.fromFood(FoodRow food, double quantity) => MealItemDraft(
        foodId: food.id,
        label: food.name,
        quantity: quantity,
        quantityUnit: food.unitLabel,
        macros: macrosFor(basis: food.basis, perBasis: food.macros, quantity: quantity),
      );

  int? foodId;
  String label;
  double? quantity;
  String? quantityUnit;
  Macros macros;

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
  Future<void> deleteFood(int id) => (db.delete(db.foods)..where((t) => t.id.equals(id))).go();

  // ---------- Comidas ----------

  Stream<List<MealWithItems>> watchDay(DateTime day) => watchRange(day, day);

  Stream<List<MealWithItems>> watchRange(DateTime from, DateTime to) {
    final q = db.select(db.meals).join([
      leftOuterJoin(db.mealItems, db.mealItems.mealId.equalsExp(db.meals.id)),
    ])
      ..where(db.meals.date.isBetweenValues(dayKey(from), dayKey(to)))
      ..orderBy([
        OrderingTerm(expression: db.meals.date),
        OrderingTerm(expression: db.meals.time),
        OrderingTerm(expression: db.mealItems.id),
      ]);
    return q.watch().map(_group);
  }

  Future<List<MealWithItems>> range(DateTime from, DateTime to) => watchRange(from, to).first;

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
