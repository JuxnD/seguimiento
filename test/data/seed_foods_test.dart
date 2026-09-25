import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);

  late AppDatabase db;
  late NutritionRepository nutrition;

  setUp(() async {
    db = openInMemoryDatabase();
    nutrition = NutritionRepository(db);
    await seedFoodsIfEmpty(db);
  });

  tearDown(() => db.close());

  Future<FoodRow> food(String name) async =>
      (await db.select(db.foods).get()).firstWhere((f) => f.name == name);

  test('siembra el catálogo completo una sola vez', () async {
    expect((await db.select(db.foods).get()).length, 33);
    expect(await seedFoodsIfEmpty(db), isFalse);
    expect((await db.select(db.foods).get()).length, 33);
  });

  test('lo que se mide en unidades guarda los macros de una unidad', () async {
    final huevo = await food('Huevo (unidad)');
    expect(huevo.basis, FoodBasis.unit);
    expect(huevo.kcal, 70);
    expect(huevo.protein, 6.0);
    expect(huevo.servingGrams, 55);
    expect(huevo.defaultQuantity, 1);

    final klim = await food('Leche Klim en polvo');
    expect(klim.unitLabel, 'papeleta');
    expect(klim.kcal, 125);
  });

  test('lo que se mide en g/ml se normaliza a 100 y prefija la porción', () async {
    // 150 kcal por 40 g → 375 por 100 g.
    final avena = await food('Avena en hojuelas (seca)');
    expect(avena.basis, FoodBasis.per100);
    expect(avena.kcal, closeTo(375, 0.01));
    expect(avena.protein, closeTo(12.5, 0.01));
    expect(avena.defaultQuantity, 40, reason: 'la porción habitual queda prellenada');

    // 120 kcal por 250 ml → 48 por 100 ml.
    final jugo = await food('Jugo de fruta');
    expect(jugo.kcal, closeTo(48, 0.01));
    expect(jugo.defaultQuantity, 250);

    // 160 kcal por 50 g → 320 por 100 g.
    final queso = await food('Queso costeño');
    expect(queso.kcal, closeTo(320, 0.01));
    expect(queso.protein, closeTo(22, 0.01));

    final arroz = await food('Arroz blanco cocido');
    expect(arroz.kcal, 130, reason: 'los que ya venían por 100 g no cambian');
  });

  test('marca qué viene de etiqueta y qué es referencia', () async {
    expect((await food('Leche entera Colanta (bolsa)')).source, MacroSource.etiqueta);
    expect((await food('Avena Alpina original (vaso)')).source, MacroSource.etiqueta);
    expect((await food('Yogur Colanta arequipe')).source, MacroSource.etiqueta);
    expect((await food('Leche entera')).source, MacroSource.etiqueta);
    expect((await food('Huevo (unidad)')).source, MacroSource.referencia);

    final verificados = (await db.select(db.foods).get()).where((f) => f.source.isVerified);
    expect(verificados.length, 4);
  });

  group('combos', () {
    test('el batido suma lo que suman sus alimentos', () async {
      final batido = (await nutrition.templates()).firstWhere((t) => t.name == 'Batido estándar');
      // 400 ml de leche (244) + Klim (125) + Nestum (95) + banano (105).
      expect(batido.macros.kcal, closeTo(569, 0.5));
      expect(batido.macros.protein, closeTo(26.1, 0.1));
    });

    test('la cena completa trae el batido expandido, sin anidar combos', () async {
      final cena =
          (await nutrition.templates()).firstWhere((t) => t.name.startsWith('Cena completa'));
      expect(cena.items.length, 6);
      expect(cena.macros.kcal, closeTo(969, 1));
      // 4 huevos (24) + atún (25) + batido (26,1): 75,1 g, no 93,1.
      expect(cena.macros.protein, closeTo(75.1, 0.1));
    });

    test('el almuerzo típico usa las cantidades en gramos', () async {
      final almuerzo = (await nutrition.templates()).firstWhere((t) => t.name == 'Almuerzo típico');
      expect(almuerzo.macros.kcal, closeTo(677, 1));
      expect(almuerzo.macros.protein, closeTo(52.75, 0.1));
    });

    test('registrar un combo crea la comida con sus alimentos', () async {
      final cena = (await nutrition.templates()).firstWhere((t) => t.name.startsWith('Cena base'));
      await nutrition.logTemplate(cena, DateTime(2026, 9, 22), time: '20:30');

      final meals = await nutrition.watchDay(DateTime(2026, 9, 22)).first;
      expect(meals.single.meal.slot, MealSlot.cena, reason: 'el combo trae su franja');
      expect(meals.single.items.map((i) => i.label), ['Huevo (unidad)', 'Atún en lata (escurrido)']);
      expect(meals.single.macros.kcal, closeTo(330, 0.5));
      expect(meals.single.macros.protein, closeTo(43, 0.1));
    });

    test('el ítem recuerda si sus macros venían de etiqueta', () async {
      final batido = (await nutrition.templates()).firstWhere((t) => t.name == 'Batido estándar');
      await nutrition.logTemplate(batido, DateTime(2026, 9, 22));
      final items = (await nutrition.watchDay(DateTime(2026, 9, 22)).first).single.items;
      final leche = items.firstWhere((i) => i.label == 'Leche entera');
      final klim = items.firstWhere((i) => i.label == 'Leche Klim en polvo');
      expect(leche.sourceVerified, isTrue, reason: 'la leche sí está verificada');
      expect(klim.sourceVerified, isFalse, reason: 'Klim sigue siendo referencia');
    });

    test('la comida guarda los macros del momento, no la receta', () async {
      final batido = (await nutrition.templates()).firstWhere((t) => t.name == 'Batido estándar');
      await nutrition.logTemplate(batido, DateTime(2026, 9, 22));

      // Cambiar el catálogo después no reescribe lo registrado.
      final klim = (await db.select(db.foods).get()).firstWhere((f) => f.name == 'Leche Klim en polvo');
      await nutrition.saveFood(FoodsCompanion(id: Value(klim.id), kcal: const Value(999)));

      final meals = await nutrition.watchDay(DateTime(2026, 9, 22)).first;
      expect(meals.single.macros.kcal, closeTo(569, 0.5));
    });
  });

  group('combos creados desde la app', () {
    Future<int> foodId(String name) async =>
        (await db.select(db.foods).get()).firstWhere((f) => f.name == name).id;

    test('guardar un combo nuevo y registrarlo en un toque', () async {
      await nutrition.saveTemplate('Cena con pan', MealSlot.cena, [
        (await foodId('Huevo (unidad)'), 4),
        (await foodId('Pan (unidad)'), 1),
        (await foodId('Atún en lata (escurrido)'), 1),
      ]);
      final combo = (await nutrition.templates()).firstWhere((t) => t.name == 'Cena con pan');
      // 4 huevos (280) + pan (140) + atún (120).
      expect(combo.macros.kcal, closeTo(540, 0.5));
      expect(combo.macros.protein, closeTo(24 + 4.5 + 25, 0.1));

      await nutrition.logTemplate(combo, DateTime(2026, 9, 24));
      final meal = (await nutrition.watchDay(DateTime(2026, 9, 24)).first).single;
      expect(meal.meal.slot, MealSlot.cena);
      expect(meal.items.length, 3);
    });

    test('guardar con el mismo nombre reemplaza, no duplica', () async {
      final huevo = await foodId('Huevo (unidad)');
      await nutrition.saveTemplate('Desayuno', MealSlot.desayuno, [(huevo, 2)]);
      await nutrition.saveTemplate('Desayuno', MealSlot.desayuno, [(huevo, 3)]);
      final combos = (await nutrition.templates()).where((t) => t.name == 'Desayuno').toList();
      expect(combos.length, 1);
      expect(combos.single.items.single.$2, 3);
    });

    test('borrar un combo no toca las comidas ya registradas', () async {
      final base = (await nutrition.templates()).firstWhere((t) => t.name.startsWith('Cena base'));
      await nutrition.logTemplate(base, DateTime(2026, 9, 24));
      await nutrition.deleteTemplate(base.row.id);

      expect((await nutrition.templates()).any((t) => t.name.startsWith('Cena base')), isFalse);
      final meal = (await nutrition.watchDay(DateTime(2026, 9, 24)).first).single;
      expect(meal.macros.kcal, closeTo(330, 0.5));
    });

    test('un alimento creado en el registro queda en el catálogo', () async {
      final id = await nutrition.saveFood(FoodsCompanion.insert(
        name: 'Arepa de huevo',
        basis: FoodBasis.unit,
        kcal: 350,
        protein: 12,
      ));
      final food = await nutrition.foodById(id);
      expect(food!.name, 'Arepa de huevo');
      expect(food.source, MacroSource.referencia, reason: 'lo nuevo empieza como referencia');
      expect((await nutrition.foodsByRecentUse()).any((f) => f.id == id), isTrue);
    });
  });
}
