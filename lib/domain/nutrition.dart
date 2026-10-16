import 'dart:math' as math;

import 'enums.dart';

/// Meta de kcal del día (§19.3): los días de fútbol (sábado y domingo)
/// tienen la suya; sin ella, la de entre semana.
int dailyKcalTarget({required DateTime day, required int weekdayTarget, int? footballTarget}) =>
    footballTarget != null && day.weekday >= DateTime.saturday ? footballTarget : weekdayTarget;

class Macros {
  const Macros({this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0});

  static const zero = Macros();

  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  Macros operator +(Macros o) =>
      Macros(kcal: kcal + o.kcal, protein: protein + o.protein, carbs: carbs + o.carbs, fat: fat + o.fat);

  Macros scale(double f) => Macros(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f);

  static Macros sum(Iterable<Macros> all) => all.fold(zero, (a, b) => a + b);
}

/// Same coherence gate for photo/text estimates. Not a nutrition accuracy test.
bool validEstimatedMacros(Macros m) =>
    [m.kcal, m.protein, m.carbs, m.fat].every((v) => v.isFinite && v >= 0) &&
    m.kcal > 0 &&
    m.kcal <= 2000 &&
    m.protein <= 200 &&
    m.carbs <= 400 &&
    m.fat <= 200 &&
    (m.kcal - (4 * m.protein + 4 * m.carbs + 9 * m.fat)).abs() <=
        math.max(100, m.kcal * .35);

/// Macros de una cantidad de un alimento del catálogo.
/// `unit`: cantidad en unidades. `per100`: cantidad en g/ml.
Macros macrosFor({required FoodBasis basis, required Macros perBasis, required double quantity}) =>
    perBasis.scale(basis == FoodBasis.unit ? quantity : quantity / 100);

/// Dos cifras de un mismo plato son la misma si no difieren en más de medio
/// gramo o media kcal: lo que se reescribe a mano no sale idéntico.
bool sameMacros(Macros a, Macros b) =>
    (a.kcal - b.kcal).abs() <= 0.5 &&
    (a.protein - b.protein).abs() <= 0.5 &&
    (a.carbs - b.carbs).abs() <= 0.5 &&
    (a.fat - b.fat).abs() <= 0.5;

/// Multiplicadores de porción de un toque: "comí muchas pastas" es ×1,5, no un
/// alimento nuevo.
const portionMultipliers = [0.5, 1.0, 1.5, 2.0];

/// Pulgadas → cm. Todo se guarda en cm; solo la vista convierte.
const cmPerInch = 2.54;

double toCm(double value, LengthUnit unit) => unit == LengthUnit.cm ? value : value * cmPerInch;

double fromCm(double cm, LengthUnit unit) => unit == LengthUnit.cm ? cm : cm / cmPerInch;

/// Comidas principales: con las tres registradas el día se da por cerrado.
const mainMealSlots = {MealSlot.desayuno, MealSlot.almuerzo, MealSlot.cena};

/// Regla alternativa de cierre (§16.6.3): con tantas comidas, o tantas kcal,
/// el día cuenta aunque falte un tipo (el almuerzo guardado como merienda).
const closeByMealCount = 3;
const closeByKcal = 1800;

/// Un día cuenta para promedios y alertas si tiene desayuno, almuerzo y cena,
/// si tiene 3 comidas o 1.800 kcal registradas, o si el usuario lo cerró a
/// mano (no desayunó, comió dos veces…).
bool isDayClosed(Set<MealSlot> slots, {bool manuallyClosed = false, int mealCount = 0, double kcal = 0}) =>
    manuallyClosed || mainMealSlots.every(slots.contains) || mealCount >= closeByMealCount || kcal >= closeByKcal;

/// Comidas principales que faltan en un día.
List<MealSlot> missingMainMeals(Set<MealSlot> slots) => [
      for (final s in mainMealSlots)
        if (!slots.contains(s)) s
    ];


/// Meta de grasa (§16.30.4, decidida por el usuario el 16 oct): 60–75 g al
/// día en todos los tipos de día. Por encima de [fatAlertG], se avisa.
const fatGoalMinG = 60, fatGoalMaxG = 75, fatAlertG = 90;

/// «Grasa 82 g · meta 60–75 g».
String fatGoalLine(double fat) =>
    'Grasa ${fat.round()} g · meta $fatGoalMinG–$fatGoalMaxG g';

/// Aviso con la comida que más grasa aportó, o null si no pasa de 90 g.
String? fatAlert(double fat, {String? topMeal, double? topFat}) {
  if (fat <= fatAlertG) return null;
  final top = topMeal == null || topFat == null
      ? ''
      : ' Lo que más aportó: $topMeal (${topFat.round()} g).';
  return 'Grasa por encima de $fatAlertG g.$top';
}
