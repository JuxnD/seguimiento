import 'nutrition.dart';

enum MealEstimateKind { known, estimated, unresolved }

class MealEstimateItem {
  const MealEstimateItem(
      {required this.kind,
      required this.label,
      required this.foodId,
      required this.quantity,
      required this.unit,
      required this.portion,
      required this.macros,
      required this.question,
      required this.assumptions});
  final MealEstimateKind kind;
  final String label;
  final int? foodId;
  final double? quantity;
  final String? unit, portion, question;

  /// Macros for the entire proposed quantity, never per100 implicitly.
  final Macros? macros;
  final List<String> assumptions;
}

class MealCoverage {
  const MealCoverage(this.text, this.itemIndex);
  final String text;
  final int itemIndex;
}

class MealEstimate {
  const MealEstimate(this.items, this.coverage, this.uncertainties);
  final List<MealEstimateItem> items;
  final List<MealCoverage> coverage;
  final List<String> uncertainties;
}
