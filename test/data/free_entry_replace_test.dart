import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';

import '../support/sqlite_host.dart';

/// C01 (auditoría 9 oct): "Actualizar" una entrada libre homónima convertía
/// un alimento por 100 g en "porción", y los combos que lo usaban en gramos
/// pasaban a contar porciones (677 → 75.482 kcal).
void main() {
  late AppDatabase db;
  late NutritionRepository nutrition;

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    nutrition = NutritionRepository(db);
    await seedFoodsIfEmpty(db);
  });

  tearDown(() => db.close());

  Future<double> comboKcal(String name) async =>
      (await nutrition.templates()).firstWhere((t) => t.name == name).macros.kcal;

  test('un alimento por 100 g no se puede actualizar como porción: el combo no cambia', () async {
    final rice = (await nutrition.foodNamed('Arroz blanco cocido'))!;
    expect(rice.basis, FoodBasis.per100);
    expect(canUpdateAsPortion(rice), isFalse);
    final before = await comboKcal('Almuerzo típico');

    await expectLater(
      nutrition.saveFreeEntryFood(rice.name, const Macros(kcal: 500, protein: 20, carbs: 70, fat: 16),
          replacing: rice),
      throwsArgumentError,
    );

    expect(await comboKcal('Almuerzo típico'), before);
    final after = (await nutrition.foodById(rice.id))!;
    expect((after.basis, after.unitLabel, after.kcal, after.defaultQuantity),
        (rice.basis, rice.unitLabel, rice.kcal, rice.defaultQuantity));
  });

  test('un alimento por unidad tampoco: 1 huevo no pasa a ser 1 porción', () async {
    final egg = (await db.select(db.foods).get()).firstWhere((f) => f.basis == FoodBasis.unit && f.unitLabel != 'porción');
    expect(canUpdateAsPortion(egg), isFalse);
    await expectLater(
      nutrition.saveFreeEntryFood(egg.name, const Macros(kcal: 300, protein: 20), replacing: egg),
      throwsArgumentError,
    );
  });

  test('una entrada libre por porción sí se actualiza y sus combos siguen en porciones', () async {
    final id = await nutrition.saveFreeEntryFood('Arroz chino', const Macros(kcal: 400, protein: 12, carbs: 60, fat: 12));
    final saved = (await nutrition.foodById(id))!;
    expect(canUpdateAsPortion(saved), isTrue);
    await nutrition.saveTemplate('Arroz chino doble', null, [(id, 2)]);
    expect(await comboKcal('Arroz chino doble'), 800);

    await nutrition.saveFreeEntryFood('Arroz chino', const Macros(kcal: 450, protein: 14, carbs: 66, fat: 14),
        replacing: saved);

    expect(await comboKcal('Arroz chino doble'), 900);
  });

  test('un combo que ya quedó inflado se marca para revisar; uno normal no', () async {
    expect((await nutrition.templates()).every((t) => t.impossibleQuantity == null), isTrue,
        reason: 'la siembra no trae cantidades imposibles');
    final id = await nutrition.saveFreeEntryFood('Arroz chino', const Macros(kcal: 400, protein: 12));
    await nutrition.saveTemplate('Inflado', null, [(id, 150)]);
    await nutrition.saveTemplate('Normal', null, [(id, 2)]);
    final all = await nutrition.templates();
    expect(all.firstWhere((t) => t.name == 'Inflado').impossibleQuantity, '150 porciones de Arroz chino');
    expect(all.firstWhere((t) => t.name == 'Normal').impossibleQuantity, isNull);
  });
}
