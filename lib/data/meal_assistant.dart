import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_gateway.dart';
import 'database.dart';
import 'catalog_candidates.dart';
import '../domain/meal_estimate.dart';
import '../domain/nutrition.dart';
import '../domain/search.dart';

/// A reduced local catalog row sent with a meal description. It contains no
/// nutrition values: all macro calculations stay on this device.
class MealCatalogOption {
  const MealCatalogOption(this.food);

  final FoodRow food;

  Map<String, Object?> toJson() => {
        'id': food.id,
        'name': food.name,
        'basis': food.basis.name,
        'unit': food.unitLabel,
        'default_quantity': food.defaultQuantity,
      };
}

class MealTextProposal {
  const MealTextProposal({required this.items, required this.uncertainties});

  final List<MealTextItem> items;
  final List<String> uncertainties;
}

class MealTextItem {
  const MealTextItem({
    required this.label,
    required this.foodId,
    required this.quantity,
    required this.unit,
  });

  final String label;
  final int? foodId;
  final double? quantity;
  final String? unit;
}

/// Values read from a package. They are intentionally nullable and are not
/// converted until the person reviews the package and chooses a basis.
class FoodLabelProposal {
  const FoodLabelProposal({
    required this.name,
    required this.basis,
    required this.unit,
    required this.servingQuantity,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.uncertainties,
  });

  final String? name;
  final String? basis;
  final String? unit;
  final double? servingQuantity;
  final double? kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
  final List<String> uncertainties;
}

/// Typed callers for contract-v2 meal tasks. No retries are performed; the
/// caller owns and closes [client], including when it cancels a screen.
class MealAssistant {
  MealAssistant(this.client, {this.timeout = const Duration(seconds: 50)})
      : gateway = AiGatewayClient(client, timeout: timeout);

  final http.Client client;
  final Duration timeout;
  final AiGatewayClient gateway;

  AiQuota? get lastQuota => gateway.lastQuota;

  Future<MealTextProposal> describeMeal({
    required String text,
    required List<FoodRow> catalog,
    required String hwid,
    required String license,
  }) async {
    if (text.runes.isEmpty || text.runes.length > 2000) {
      throw const AiError('La descripción supera los límites permitidos.');
    }
    final ids = catalog.map((food) => food.id).toSet();
    if (ids.length != catalog.length) {
      throw const AiError('El catálogo local no pasó la verificación.');
    }
    final candidates = catalogCandidates(text, catalog);
    final result = await gateway.assist(
      task: 'meal_text',
      input: {
        'text': text,
        'catalog': [
          for (final food in candidates) MealCatalogOption(food).toJson()
        ],
      },
      hwid: hwid,
      license: license,
    );
    return _parseMealText(result, candidates.map((f) => f.id).toSet());
  }

  Future<MealEstimate> estimateMeal(
      {required String text,
      required List<FoodRow> catalog,
      required String hwid,
      required String license}) async {
    if (text.trim().isEmpty ||
        text.runes.length > 2000 ||
        catalog.map((f) => f.id).toSet().length != catalog.length) {
      throw const AiError('Revisa la descripción o el catálogo local.');
    }
    final candidates = catalogCandidates(text, catalog);
    final result = await gateway.assist(
        task: 'meal_estimate',
        input: {
          'text': text,
          'catalog': [
            for (final food in candidates) MealCatalogOption(food).toJson()
          ],
        },
        hwid: hwid,
        license: license);
    return parseMealEstimate(result, text, candidates);
  }

  Future<FoodLabelProposal> readFoodLabel({
    required Uint8List photo,
    required String hwid,
    required String license,
  }) async {
    if (photo.isEmpty || photo.length > 2 * 1024 * 1024) {
      throw const AiError('La foto supera el tamaño permitido. Elige otra.');
    }
    final result = await gateway.assist(
      task: 'food_label',
      input: {'mime': 'image/png', 'photo_base64': base64Encode(photo)},
      hwid: hwid,
      license: license,
    );
    return _parseFoodLabel(result);
  }
}

/// Strict new task; old meal_text response stays unchanged. Concatenated source
/// segments must reproduce the whole original phrase, not merely returned rows.
MealEstimate parseMealEstimate(
    Map<String, dynamic> result, String text, List<FoodRow> candidates) {
  void exact(Map<dynamic, dynamic> map, Set<String> fields) {
    if (map.length != fields.length || !map.keys.every(fields.contains)) {
      _invalidProposal();
    }
  }

  exact(result, {'items', 'coverage', 'uncertainties'});
  final raw = result['items'], coverage = result['coverage'];
  if (raw is! List ||
      raw.isEmpty ||
      raw.length > 8 ||
      coverage is! List ||
      coverage.isEmpty ||
      coverage.length > 24) _invalidProposal();
  final foods = {for (final food in candidates) food.id: food};
  final items = <MealEstimateItem>[];
  for (final row in raw) {
    if (row is! Map) _invalidProposal();
    exact(row, {
      'kind',
      'label',
      'food_id',
      'quantity',
      'unit',
      'portion',
      'kcal',
      'protein',
      'carbs',
      'fat',
      'question',
      'assumptions'
    });
    final kind =
        MealEstimateKind.values.where((v) => v.name == row['kind']).firstOrNull;
    final label = _optionalText(row['label'], 80);
    if (kind == null || label == null) _invalidProposal();
    final id = row['food_id'];
    final quantity = _optionalQuantity(row['quantity']);
    final unit = _optionalText(row['unit'], 30);
    final portion = _optionalText(row['portion'], 180);
    final question = _optionalText(row['question'], 300);
    final assumptions = _uncertainties(row['assumptions'], 6);
    if ((row['unit'] != null && unit == null) ||
        (row['portion'] != null && portion == null) ||
        (row['question'] != null && question == null)) _invalidProposal();
    Macros? macros;
    if (kind == MealEstimateKind.known) {
      final food = id is int ? foods[id] : null;
      if (food == null ||
          quantity == null ||
          unit != food.unitLabel ||
          row['portion'] != null ||
          row['question'] != null) _invalidProposal();
    } else if (kind == MealEstimateKind.estimated) {
      if (id != null ||
          quantity == null ||
          unit == null ||
          portion == null ||
          question != null ||
          assumptions.isEmpty) _invalidProposal();
      final values = [
        for (final field in ['kcal', 'protein', 'carbs', 'fat'])
          _optionalNumber(row[field])
      ];
      if (values.any((v) => v == null)) _invalidProposal();
      macros = Macros(
          kcal: values[0]!,
          protein: values[1]!,
          carbs: values[2]!,
          fat: values[3]!);
      if (!validEstimatedMacros(macros)) _invalidProposal();
    } else if (id != null ||
        row['quantity'] != null ||
        row['unit'] != null ||
        row['portion'] != null ||
        question == null) {
      _invalidProposal();
    }
    if (kind != MealEstimateKind.estimated &&
        ['kcal', 'protein', 'carbs', 'fat'].any((f) => row[f] != null)) {
      _invalidProposal();
    }
    items.add(MealEstimateItem(
        kind: kind,
        label: label,
        foodId: id as int?,
        quantity: quantity,
        unit: unit,
        portion: portion,
        macros: macros,
        question: question,
        assumptions: assumptions));
  }
  final segments = <MealCoverage>[];
  for (final segment in coverage) {
    if (segment is! Map) _invalidProposal();
    exact(segment, {'text', 'item_index'});
    final value = segment['text'], index = segment['item_index'];
    if (value is! String ||
        value.isEmpty ||
        value.runes.length > 2000 ||
        index is! int ||
        index < 0 ||
        index >= items.length) _invalidProposal();
    segments.add(MealCoverage(value, index));
  }
  if (segments.map((s) => s.text).join() != text ||
      segments.map((s) => s.itemIndex).toSet().length != items.length ||
      Macros.sum(items.where((i) => i.macros != null).map((i) => i.macros!))
              .kcal >
          5000) {
    _invalidProposal();
  }
  // Preserve explicitly supplied g/ml instead of replacing it with "usual".
  for (var i = 0; i < items.length; i++) {
    final source =
        segments.where((s) => s.itemIndex == i).map((s) => s.text).join();
    final amounts =
        RegExp(r'(\d+(?:[.,]\d+)?)\s*(ml|g)\b', caseSensitive: false)
            .allMatches(source)
            .toList();
    if (amounts.length == 1 &&
        items[i].kind != MealEstimateKind.unresolved &&
        (items[i].unit != amounts.single.group(2)!.toLowerCase() ||
            items[i].quantity !=
                double.parse(amounts.single.group(1)!.replaceAll(',', '.')))) {
      _invalidProposal();
    }
    // Named common recipes/additions must not be swallowed by a similar
    // known food (e.g. milk with Milo -> milk alone). This finite vocabulary
    // complements human coverage review; it is not general language proof.
    for (final name
        in recipeCandidates.where((n) => foldText(source).contains(n))) {
      final item = items[i];
      final identity = item.kind == MealEstimateKind.known
          ? foods[item.foodId]!.name
          : item.label;
      if (!foldText(identity).contains(name)) _invalidProposal();
    }
  }
  return MealEstimate(
      items, segments, _uncertainties(result['uncertainties'], 8));
}

extension _EstimateFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

MealTextProposal _parseMealText(
    Map<String, dynamic> result, Set<int> catalogIds) {
  final rawItems = result['items'];
  final rawUncertainties = result['uncertainties'];
  if (rawItems is! List ||
      rawItems.length > 8 ||
      rawUncertainties is! List ||
      rawUncertainties.length > 8) {
    throw const AiError(
        'La propuesta no pasó la validación. No se añadió comida.');
  }
  final items = <MealTextItem>[];
  for (final raw in rawItems) {
    if (raw is! Map) _invalidProposal();
    final label = _optionalText(raw['label'], 80);
    final rawId = raw['food_id'];
    final id = rawId == null
        ? null
        : rawId is int
            ? rawId
            : -1;
    final quantity = _optionalQuantity(raw['quantity']);
    final unit = _optionalText(raw['unit'], 32);
    if (label == null ||
        id == -1 ||
        (id != null && !catalogIds.contains(id)) ||
        (raw['quantity'] != null && quantity == null) ||
        (raw['unit'] != null && unit == null)) {
      _invalidProposal();
    }
    items.add(
        MealTextItem(label: label, foodId: id, quantity: quantity, unit: unit));
  }
  return MealTextProposal(
    items: items,
    uncertainties: _uncertainties(rawUncertainties, 8),
  );
}

FoodLabelProposal _parseFoodLabel(Map<String, dynamic> result) {
  final rawBasis = result['basis'];
  final basis = rawBasis == null
      ? null
      : rawBasis == 'per100' || rawBasis == 'portion'
          ? rawBasis as String
          : '';
  final rawUnit = result['unit'];
  final unit = rawUnit == null
      ? null
      : rawUnit == 'g' || rawUnit == 'ml'
          ? rawUnit as String
          : '';
  final name = _optionalText(result['name'], 80);
  final serving = _optionalNumber(result['serving_quantity']);
  if ((result['name'] != null && name == null) ||
      basis == '' ||
      unit == '' ||
      (result['serving_quantity'] != null && serving == null)) {
    _invalidProposal();
  }
  return FoodLabelProposal(
    name: name,
    basis: basis,
    unit: unit,
    servingQuantity: serving,
    kcal: _macro(result, 'kcal'),
    protein: _macro(result, 'protein'),
    carbs: _macro(result, 'carbs'),
    fat: _macro(result, 'fat'),
    uncertainties: _uncertainties(result['uncertainties'], 8),
  );
}

double? _macro(Map<dynamic, dynamic> map, String key) {
  final value = _optionalNumber(map[key]);
  if (map[key] != null && value == null) _invalidProposal();
  return value;
}

double? _optionalQuantity(dynamic value) {
  if (value == null) return null;
  final number = _optionalNumber(value);
  return number != null && number > 0 && number <= 5000 ? number : null;
}

double? _optionalNumber(dynamic value) =>
    value is num && value.isFinite && value >= 0 && value <= 100000
        ? value.toDouble()
        : null;

String? _optionalText(dynamic value, int maxLength) {
  if (value == null) return null;
  if (value is! String ||
      value.trim().isEmpty ||
      value.runes.length > maxLength) {
    return null;
  }
  return value.trim();
}

List<String> _uncertainties(dynamic value, int maxItems) {
  if (value is! List || value.length > maxItems) _invalidProposal();
  final parsed = <String>[];
  for (final item in value) {
    final text = _optionalText(item, 300);
    if (text == null) _invalidProposal();
    parsed.add(text);
  }
  return parsed;
}

Never _invalidProposal() => throw const AiError(
    'La propuesta no pasó la validación. No se guardó ningún dato.');
