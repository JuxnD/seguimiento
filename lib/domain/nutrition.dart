import 'enums.dart';

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

/// Macros de una cantidad de un alimento del catálogo.
/// `unit`: cantidad en unidades. `per100`: cantidad en g/ml.
Macros macrosFor({required FoodBasis basis, required Macros perBasis, required double quantity}) =>
    perBasis.scale(basis == FoodBasis.unit ? quantity : quantity / 100);

/// Pulgadas → cm. Todo se guarda en cm; solo la vista convierte.
const cmPerInch = 2.54;

double toCm(double value, LengthUnit unit) => unit == LengthUnit.cm ? value : value * cmPerInch;

double fromCm(double cm, LengthUnit unit) => unit == LengthUnit.cm ? cm : cm / cmPerInch;
