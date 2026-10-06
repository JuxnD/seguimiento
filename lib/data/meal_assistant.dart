import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_gateway.dart';
import 'database.dart';

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
    if (text.runes.isEmpty ||
        text.runes.length > 2000 ||
        catalog.length > 200) {
      throw const AiError('La descripción supera los límites permitidos.');
    }
    final ids = catalog.map((food) => food.id).toSet();
    if (ids.length != catalog.length) {
      throw const AiError('El catálogo local no pasó la verificación.');
    }
    final result = await gateway.assist(
      task: 'meal_text',
      input: {
        'text': text,
        'catalog': [
          for (final food in catalog) MealCatalogOption(food).toJson()
        ],
      },
      hwid: hwid,
      license: license,
    );
    return _parseMealText(result, ids);
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
