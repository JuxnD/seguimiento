import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/meal_assistant.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/meal_estimate.dart';
import 'package:seguimiento/data/ai_gateway.dart';
import '../support/meal_estimate_fixture.dart';

FoodRow catalogFood(int id, String name) => FoodRow(
    id: id,
    name: name,
    basis: FoodBasis.unit,
    unitLabel: 'unidad',
    kcal: 70,
    protein: 6,
    carbs: 1,
    fat: 5,
    defaultQuantity: 1,
    source: MacroSource.referencia,
    origin: FoodOrigin.usuario,
    favorite: false);

void main() {
  test('cliente status real sin cambio desdea0521c8 acepta tarea nueva',
      () async {
    final gateway = AiGatewayClient(MockClient((_) async => http.Response(
        jsonEncode({
          'status': 'success',
          'contract': 2,
          'task': 'status',
          'model': 'gpt-6-luna',
          'result': {
            'enabled': true,
            'tasks': [
              'meal_text',
              'food_label',
              'report_question',
              'exercise_question',
              'meal_estimate'
            ]
          }
        }),
        200)));
    final status = await gateway.status(
        hwid: 'SEG-FICTICIO', license: 'AAAA-BBBB-CCCC-DDDD');
    expect(status.enabled, isTrue);
    expect(status.message, 'IA habilitada para este teléfono.');
  });
  test('desconocido requiere porción o deja pendiente explícito', () {
    final pending = parseMealEstimate(
        estimateResult([estimateItem('Arroz chino', kind: 'unresolved')],
            [('comí arroz chino', 0)]),
        'comí arroz chino',
        []);
    expect(pending.items.single.kind, MealEstimateKind.unresolved);
    final result = parseMealEstimate(
        estimateResult(
            [estimateItem('Arroz chino')], [('250 g de arroz chino', 0)]),
        '250 g de arroz chino',
        []);
    expect(result.items.single.quantity, 250);
    expect(result.items.single.macros!.kcal, 500);
    expect(result.items.single.assumptions, isNotEmpty);
  });
  test('4 huevos pan leche350ml Milo preservan componentes sin doble contar',
      () {
    const text = '4 huevos con un pan y un vaso de350 ml de leche con milo';
    final foods = [
      catalogFood(1, 'Huevo'),
      catalogFood(2, 'Pan'),
      catalogFood(3, 'Leche').copyWith(unitLabel: 'ml', basis: FoodBasis.per100)
    ];
    final result = parseMealEstimate(
        estimateResult([
          estimateItem('Huevos',
              kind: 'known', id: 1, quantity: 4, unit: 'unidad'),
          estimateItem('Pan',
              kind: 'known', id: 2, quantity: 1, unit: 'unidad'),
          estimateItem('Leche',
              kind: 'known', id: 3, quantity: 350, unit: 'ml'),
          estimateItem('Milo',
              kind: 'unresolved', question: '¿Cuántos gramos de Milo añadiste?')
        ], [
          ('4 huevos', 0),
          (' con un pan', 1),
          (' y un vaso de350 ml de leche', 2),
          (' con milo', 3)
        ]),
        text,
        foods);
    expect(result.items[2].quantity, 350);
    expect(result.items[3].question, contains('Milo'));
    expect(result.items[3].macros, isNull);
  });
  test(
      'rechaza parcial, ID ajeno, unidad incorrecta, cantidad perdida y macros imposibles',
      () {
    final food = catalogFood(1, 'Huevo');
    final bad = [
      estimateResult([
        estimateItem('Huevo', kind: 'known', id: 1, quantity: 1, unit: 'unidad')
      ], [
        ('huevo', 0)
      ]),
      estimateResult([
        estimateItem('Arroz chino',
            kind: 'known', id: 999, quantity: 1, unit: 'unidad')
      ], [
        ('huevo y arroz chino', 0)
      ]),
      estimateResult([
        estimateItem('Arroz chino',
            kind: 'known', id: 1, quantity: 1, unit: 'g')
      ], [
        ('huevo y arroz chino', 0)
      ]),
      estimateResult([estimateItem('Arroz chino')..['kcal'] = 1],
          [('huevo y arroz chino', 0)]),
    ];
    for (final result in bad) {
      expect(() => parseMealEstimate(result, 'huevo y arroz chino', [food]),
          throwsA(isA<AiError>()));
    }
    expect(
        () => parseMealEstimate(
            estimateResult(
                [estimateItem('Leche', quantity: 1, unit: 'porción')],
                [('350 ml de leche', 0)]),
            '350 ml de leche',
            []),
        throwsA(isA<AiError>()));
  });
  test('catálogo 1000 conserva alimento nombrado fuera de primeros200',
      () async {
    final catalog = [
      for (var i = 1; i <= 1000; i++)
        catalogFood(i, i == 1000 ? 'Alimento raro' : 'Ficha $i')
    ];
    var calls = 0;
    final assistant = MealAssistant(MockClient((request) async {
      calls++;
      final encoded =
          request.headers['content-type']?.startsWith('multipart/') == true
              ? request.body.split('\r\n\r\n')[1].split('\r\n--')[0]
              : request.body;
      final body = jsonDecode(encoded) as Map;
      final rows = (body['input'] as Map)['catalog'] as List;
      expect(rows.length, lessThanOrEqualTo(200));
      expect(rows.where((r) => (r as Map)['id'] == 1000), hasLength(1));
      return http.Response(
          jsonEncode({
            'status': 'success',
            'contract': 2,
            'task': 'meal_text',
            'model': 'gpt-6-luna',
            'result': {
              'items': [
                {
                  'label': 'Alimento raro',
                  'food_id': 1000,
                  'quantity': 1,
                  'unit': 'unidad'
                }
              ],
              'uncertainties': []
            }
          }),
          200);
    }));
    final result = await assistant.describeMeal(
        text: 'Alimento raro',
        catalog: catalog,
        hwid: 'SEG-FICTICIO',
        license: 'AAAA-BBBB-CCCC-DDDD');
    expect(calls, 1);
    expect(result.items.single.foodId, 1000);
  });
  test('texto largo no llama; JSON truncado no crea propuesta', () async {
    var calls = 0;
    final assistant = MealAssistant(MockClient((_) async {
      calls++;
      return http.Response('{', 200);
    }));
    await expectLater(
        assistant.estimateMeal(
            text: List.filled(2001, '😀').join(),
            catalog: [],
            hwid: 'SEG-FICTICIO',
            license: 'AAAA-BBBB-CCCC-DDDD'),
        throwsA(isA<AiError>()));
    expect(calls, 0);
    await expectLater(
        assistant.estimateMeal(
            text: '250 g de arroz chino',
            catalog: [],
            hwid: 'SEG-FICTICIO',
            license: 'AAAA-BBBB-CCCC-DDDD'),
        throwsA(isA<AiError>()));
    expect(calls, 1);
  });
  test('cobertura de caracteres no permite arroz chino bajo huevo conocido',
      () {
    final food = catalogFood(1, 'Huevo');
    expect(
        () => parseMealEstimate(
            estimateResult([
              estimateItem('Huevo',
                  kind: 'known', id: 1, quantity: 1, unit: 'unidad')
            ], [
              ('huevo y arroz chino', 0)
            ]),
            'huevo y arroz chino',
            [food]),
        throwsA(isA<AiError>()));
  });
}
