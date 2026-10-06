import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/ai_gateway.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/meal_assistant.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);

  Map<String, Object?> envelope(String task, Object result) => {
        'status': 'success',
        'contract': 2,
        'task': task,
        'model': 'gpt-6-luna',
        'result': result,
        'quota': {
          'remaining': 3,
          'limit': 4,
          'reset_at': '2026-10-07T00:00:00Z',
        },
      };

  test('frase manda catálogo reducido y calcula con respuesta tipada',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final id = await db.into(db.foods).insert(FoodsCompanion.insert(
        name: 'Huevo', basis: FoodBasis.unit, kcal: 70, protein: 6));
    final food =
        await (db.select(db.foods)..where((f) => f.id.equals(id))).getSingle();
    final client = MockClient((request) async {
      expect(request.url.path, '/app/seguimiento/asistir');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['task'], 'meal_text');
      final input = body['input'] as Map<String, dynamic>;
      expect(input.keys.toSet(), {'text', 'catalog'});
      final row = (input['catalog'] as List).single as Map;
      expect(row, {
        'id': food.id,
        'name': food.name,
        'basis': food.basis.name,
        'unit': food.unitLabel,
        'default_quantity': food.defaultQuantity,
      });
      expect(row.containsKey('kcal'), isFalse);
      return http.Response(
          jsonEncode(envelope('meal_text', {
            'items': [
              {
                'label': 'huevo',
                'food_id': food.id,
                'quantity': 2,
                'unit': food.unitLabel
              }
            ],
            'uncertainties': ['Confirma si era frito.'],
          })),
          200);
    });
    final result = await MealAssistant(client).describeMeal(
        text: 'dos huevos 🥚',
        catalog: [food],
        hwid: 'SEG-FICTICIO',
        license: 'AAAA-BBBB-CCCC-DDDD');
    expect(result.items.single.foodId, food.id);
    expect(result.items.single.quantity, 2);
    expect(result.uncertainties, ['Confirma si era frito.']);
  });

  test(
      'cantidad ausente se conserva nula; id ajeno y cantidad inválida se rechazan',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final id = await db.into(db.foods).insert(FoodsCompanion.insert(
        name: 'Huevo', basis: FoodBasis.unit, kcal: 70, protein: 6));
    final food =
        await (db.select(db.foods)..where((f) => f.id.equals(id))).getSingle();
    MealAssistant clientFor(Object result) =>
        MealAssistant(MockClient((_) async =>
            http.Response(jsonEncode(envelope('meal_text', result)), 200)));

    final valid = await clientFor({
      'items': [
        {'label': 'huevo', 'food_id': food.id, 'quantity': null, 'unit': null}
      ],
      'uncertainties': [],
    }).describeMeal(
        text: 'huevo', catalog: [food], hwid: 'SEG-X', license: 'licencia');
    expect(valid.items.single.quantity, isNull);

    for (final bad in [
      {
        'items': [
          {'label': 'huevo', 'food_id': 999999, 'quantity': 2, 'unit': 'unidad'}
        ],
        'uncertainties': []
      },
      {
        'items': [
          {
            'label': 'huevo',
            'food_id': food.id,
            'quantity': -2,
            'unit': 'unidad'
          }
        ],
        'uncertainties': []
      },
      {
        'items': [
          {
            'label': 'huevo',
            'food_id': food.id,
            'quantity': 5001,
            'unit': 'unidad'
          }
        ],
        'uncertainties': []
      },
    ]) {
      await expectLater(
          clientFor(bad).describeMeal(
              text: 'huevo',
              catalog: [food],
              hwid: 'SEG-X',
              license: 'licencia'),
          throwsA(isA<AiError>()));
    }
  });

  test(
      'etiqueta envía solo foto y conserva base, porción, nulos e incertidumbres',
      () async {
    final photo = Uint8List.fromList([1, 2, 3]);
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['task'], 'food_label');
      expect(body['input'], {
        'mime': 'image/png',
        'photo_base64': base64Encode(photo),
      });
      return http.Response(
          jsonEncode(envelope('food_label', {
            'name': 'Yogur',
            'basis': 'portion',
            'unit': 'g',
            'serving_quantity': 30,
            'kcal': 150,
            'protein': 3,
            'carbs': null,
            'fat': null,
            'uncertainties': ['La grasa no es legible.'],
          })),
          200);
    });
    final result = await MealAssistant(client).readFoodLabel(
        photo: photo, hwid: 'SEG-FICTICIO', license: 'AAAA-BBBB-CCCC-DDDD');
    expect(result.basis, 'portion');
    expect(result.servingQuantity, 30);
    expect(result.kcal, 150);
    expect(result.carbs, isNull);
    expect(result.fat, isNull);
    expect(result.uncertainties.single, 'La grasa no es legible.');
  });

  test(
      'base/unidad sin leer y energía solo en kJ quedan nulas, nunca convertidas',
      () async {
    final client = MockClient((request) async {
      expect((jsonDecode(request.body) as Map)['task'], 'food_label');
      final response = envelope('food_label', {
        'name': 'Bebida',
        'basis': null,
        'unit': null,
        'serving_quantity': null,
        'kcal': null,
        'protein': null,
        'carbs': null,
        'fat': null,
        'uncertainties': [
          'La energía aparece en kJ; verifica kcal en el empaque.',
          'No se distingue si la base es por 100 ml o por porción.',
        ],
      });
      return http.Response(jsonEncode(response), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final result = await MealAssistant(client).readFoodLabel(
        photo: Uint8List.fromList([4, 5]),
        hwid: 'SEG-FICTICIO',
        license: 'AAAA-BBBB-CCCC-DDDD');
    expect(result.basis, isNull);
    expect(result.unit, isNull);
    expect(result.servingQuantity, isNull);
    expect(result.kcal, isNull);
    expect(result.protein, isNull);
    expect(result.carbs, isNull);
    expect(result.fat, isNull);
    expect(result.uncertainties, hasLength(2));
  });
}
