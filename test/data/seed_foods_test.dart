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
    expect((await db.select(db.foods).get()).length, 30);
    expect(await seedFoodsIfEmpty(db), isFalse);
    expect((await db.select(db.foods).get()).length, 30);
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
}
