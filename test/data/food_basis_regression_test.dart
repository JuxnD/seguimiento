import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  test(
      'optional remembered250g retains per100 and homonym/combo/snapshot unchanged',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final repo = NutritionRepository(db);
    await seedFoodsIfEmpty(db);
    final rice = (await repo.foodNamed('Arroz blanco cocido'))!;
    final before = (await repo.templates())
        .firstWhere((t) => t.name == 'Almuerzo típico')
        .macros
        .kcal;
    final meal = MealDraft(
        date: DateTime(2026, 10, 9),
        slot: MealSlot.otro,
        items: [MealItemDraft.fromFood(rice, 150)]);
    await repo.saveMeal(meal);
    final snapshots = await db.select(db.mealItems).get();
    final estimate = MealItemDraft(
        label: rice.name,
        quantity: 250,
        quantityUnit: 'g',
        macros: const Macros(kcal: 500, protein: 20, carbs: 70, fat: 16));
    final id = await repo.rememberReviewedEstimate(estimate);
    final learned = (await repo.foodById(id))!;
    expect(learned.id, isNot(rice.id));
    expect(learned.name, '${rice.name} (2)');
    expect(learned.basis, FoodBasis.per100);
    expect(learned.unitLabel, 'g');
    expect(learned.kcal, 200);
    expect(learned.defaultQuantity, 250);
    expect(learned.source, MacroSource.estimado);
    expect(MealItemDraft.fromFood(learned, 250).macros.kcal, 500);
    expect(MealItemDraft.fromFood(learned, 250).sourceVerified, isNull);
    expect(
        (await repo.templates())
            .firstWhere((t) => t.name == 'Almuerzo típico')
            .macros
            .kcal,
        before);
    expect(await db.select(db.mealItems).get(), snapshots);
  });
}
