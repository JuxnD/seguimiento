import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'catalog_updates.dart';
import 'database.dart';

/// Catálogo inicial y combos frecuentes.
///
/// Los alimentos que se miden en gramos o mililitros se guardan **por 100**
/// (la cantidad se escribe en g/ml); el resto, **por unidad** (huevo, lata,
/// papeleta…). `source` distingue lo verificado contra la etiqueta de lo que
/// viene de una tabla de referencia.
class SeedFood {
  const SeedFood(
    this.name,
    this.unit,
    this.servingGrams,
    this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.source,
  );

  final String name;

  /// Unidad tal como se mide: 'g', 'ml', 'unidad', 'lata', 'papeleta'…
  final String unit;

  /// Gramos (o ml) de la porción a la que corresponden los macros. null en
  /// platos enteros, donde el peso no se conoce.
  final double? servingGrams;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final MacroSource source;

  bool get isBulk => unit == 'g' || unit == 'ml';

  /// Para g/ml se escala a 100; para el resto, los macros son de una unidad.
  FoodsCompanion toCompanion() {
    final factor = isBulk ? 100 / servingGrams! : 1.0;
    return FoodsCompanion.insert(
      name: name,
      basis: isBulk ? FoodBasis.per100 : FoodBasis.unit,
      unitLabel: Value(unit),
      kcal: kcal * factor,
      protein: protein * factor,
      carbs: Value(carbs * factor),
      fat: Value(fat * factor),
      defaultQuantity: Value(isBulk ? servingGrams! : 1),
      servingGrams: Value(servingGrams),
      source: Value(source),
    );
  }
}

const _etiqueta = MacroSource.etiqueta;
const _referencia = MacroSource.referencia;

/// Catálogo inicial, en el orden en que se siembra.
const initialFoods = <SeedFood>[
  SeedFood('Huevo (unidad)', 'unidad', 55, 70, 6.0, 0.4, 5.0, _referencia),
  SeedFood('Atún en lata (escurrido)', 'lata', 120, 120, 25.0, 0, 1.5, _referencia),
  SeedFood('Leche Klim en polvo', 'papeleta', 25, 125, 6.5, 9.5, 6.5, _referencia),
  SeedFood('Nestum', 'papeleta', 25, 95, 5.5, 17.0, 1.0, _referencia),
  SeedFood('Leche entera Colanta (bolsa)', 'bolsa', 200, 122, 6.5, 9.6, 6.4, _etiqueta),
  SeedFood('Leche entera', 'ml', 100, 61, 3.2, 4.8, 3.2, _etiqueta),
  SeedFood('Banano', 'unidad', 120, 105, 1.3, 27.0, 0.4, _referencia),
  SeedFood('Arroz blanco cocido', 'g', 100, 130, 2.7, 28.0, 0.3, _referencia),
  SeedFood('Frijoles cocidos', 'g', 100, 127, 8.7, 22.8, 0.5, _referencia),
  SeedFood('Lentejas cocidas', 'g', 100, 116, 9.0, 20.0, 0.4, _referencia),
  SeedFood('Carne de res (magra, cocida)', 'g', 100, 220, 26.0, 0, 12.0, _referencia),
  SeedFood('Pechuga de pollo (cocida)', 'g', 100, 165, 31.0, 0, 3.6, _referencia),
  SeedFood('Chicharrón', 'g', 100, 540, 25.0, 0, 48.0, _referencia),
  SeedFood('Chorizo', 'unidad', 70, 250, 12.0, 1.0, 22.0, _referencia),
  SeedFood('Pan tajado', 'rebanada', 28, 75, 2.6, 14.0, 1.0, _referencia),
  SeedFood('Pan (unidad)', 'unidad', 50, 140, 4.5, 26.0, 1.8, _referencia),
  SeedFood('Bollo de maíz', 'unidad', 120, 170, 3.5, 36.0, 1.5, _referencia),
  SeedFood('Patacón / tajada de plátano frito', 'unidad', 40, 110, 0.7, 16.0, 5.0, _referencia),
  SeedFood('Yuca frita', 'g', 100, 280, 1.5, 38.0, 13.0, _referencia),
  SeedFood('Papa frita', 'g', 100, 290, 3.4, 37.0, 14.0, _referencia),
  SeedFood('Aguacate', 'g', 100, 160, 2.0, 8.5, 15.0, _referencia),
  SeedFood('Queso costeño', 'g', 50, 160, 11.0, 1.0, 12.5, _referencia),
  SeedFood('Sardinas en lata', 'lata', 120, 200, 20.0, 0, 13.0, _referencia),
  SeedFood('Avena en hojuelas (seca)', 'g', 40, 150, 5.0, 27.0, 3.0, _referencia),
  SeedFood('Jugo de fruta', 'ml', 250, 120, 0.5, 29.0, 0.2, _referencia),
  SeedFood('Manzana', 'unidad', 180, 95, 0.5, 25.0, 0.3, _referencia),
  SeedFood('Crema de maní', 'cucharada', 16, 95, 4.0, 3.5, 8.0, _referencia),
  // En 'porción' no se podría pedir "100 g de ensalada": va por gramos.
  SeedFood('Ensalada (tomate, cebolla, lechuga)', 'g', 100, 25, 1.0, 5.0, 0.2, _referencia),
  SeedFood('Avena Alpina original (vaso)', 'vaso', 250, 173, 5.0, 28.0, 4.8, _etiqueta),
  // Añadidos en el esquema 8 (ver catalog_updates.dart). El almuerzo es el
  // plato entero estimado, no sus partes: así se registra de un toque.
  SeedFood('Almuerzo corriente (arroz + grano + carne + jugo)', 'plato', null, 880, 38.0, 100.0, 34.0, _referencia),
  SeedFood('Peto sin maíz (vaso)', 'vaso', 250, 190, 7.0, 30.0, 5.0, _referencia),
  SeedFood('Salchichón de pollo', 'g', 100, 200, 13.0, 3.0, 15.0, _referencia),
  SeedFood('Yogur Colanta arequipe', 'vaso', 150, 139, 4.2, 21.0, 4.7, _etiqueta),
];

/// Combos frecuentes: nombre → (alimento, cantidad). Las cantidades van en la
/// unidad del alimento (g/ml para los de granel, unidades para el resto).
const initialTemplates = <(String, MealSlot?, List<(String, double)>)>[
  (
    'Batido estándar',
    null,
    [
      ('Leche entera', 400),
      ('Leche Klim en polvo', 1),
      ('Nestum', 1),
      ('Banano', 1),
    ]
  ),
  (
    'Cena base (3 huevos + atún)',
    MealSlot.cena,
    [
      ('Huevo (unidad)', 3),
      ('Atún en lata (escurrido)', 1),
    ]
  ),
  (
    // El batido va expandido: un combo no anida a otro.
    'Cena completa (4 huevos + atún + batido)',
    MealSlot.cena,
    [
      ('Huevo (unidad)', 4),
      ('Atún en lata (escurrido)', 1),
      ('Leche entera', 400),
      ('Leche Klim en polvo', 1),
      ('Nestum', 1),
      ('Banano', 1),
    ]
  ),
  (
    'Almuerzo típico',
    MealSlot.almuerzo,
    [
      ('Arroz blanco cocido', 150),
      ('Frijoles cocidos', 100),
      ('Carne de res (magra, cocida)', 150),
      ('Ensalada (tomate, cebolla, lechuga)', 100),
    ]
  ),
  (
    'Almuerzo corriente',
    MealSlot.almuerzo,
    [
      ('Almuerzo corriente (arroz + grano + carne + jugo)', 1),
    ]
  ),
];

/// Siembra catálogo y combos la primera vez. Idempotente: si ya hay
/// alimentos, no toca nada.
Future<bool> seedFoodsIfEmpty(AppDatabase db) async {
  final existing = await db.select(db.foods).get();
  if (existing.isNotEmpty) return false;

  final idsByName = <String, int>{};
  for (final food in initialFoods) {
    idsByName[food.name] = await db.into(db.foods).insert(food.toCompanion());
  }

  var position = 0;
  for (final (name, slot, items) in initialTemplates) {
    await insertTemplate(db, name, slot, items, idsByName, position: position++);
  }
  return true;
}
