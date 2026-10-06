import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/meals/food_label_screen.dart';
import 'package:seguimiento/features/meals/foods_screen.dart';
import 'package:seguimiento/features/meals/meal_form_screen.dart';
import 'package:seguimiento/features/meals/meal_text_screen.dart';

import '../test/support/meal_photo_fixture.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
}

http.Response _reply(String task, Object result) => http.Response(
      jsonEncode({
        'status': 'success',
        'contract': 2,
        'task': task,
        'model': 'gpt-6-luna',
        'result': result,
        'quota': {
          'remaining': 3,
          'limit': 4,
          'reset_at': '2026-10-07T00:00:00Z',
        }
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Android revisa frase y etiqueta; escribe solo tras Guardar y relee SQLite',
      (tester) async {
    final db = openInMemoryDatabase();
    final repo = NutritionRepository(db);
    final date = DateTime(2026, 10, 6);
    final eggId = await repo.saveFood(FoodsCompanion.insert(
        name: 'Huevo', basis: FoodBasis.unit, kcal: 70, protein: 6));
    final beforeLabel = await db.select(db.foods).get();
    var textModelCalls = 0, labelModelCalls = 0;

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: Column(children: [
                    TextButton(
                      onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MealFormScreen(
                              draft: MealDraft(
                                  date: date, slot: MealSlot.almuerzo),
                              textScreenBuilder: (foods) => MealTextScreen(
                                foods: foods,
                                activation: _Activation(),
                                clientFactory: () =>
                                    MockClient((request) async {
                                  final task =
                                      (jsonDecode(request.body) as Map)['task'];
                                  if (task == 'status')
                                    return _reply('status', {'enabled': true});
                                  textModelCalls++;
                                  return _reply('meal_text', {
                                    'items': [
                                      {
                                        'label': 'dos huevos',
                                        'food_id': eggId,
                                        'quantity': 2,
                                        'unit': 'unidad'
                                      }
                                    ],
                                    'uncertainties': [],
                                  });
                                }),
                              ),
                            ),
                          )),
                      child: const Text('Nueva comida'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FoodsScreen(
                              labelScreenBuilder: () => FoodLabelScreen(
                                activation: _Activation(),
                                pickPhoto: (_) async => fictionalPhoto(),
                                clientFactory: () =>
                                    MockClient((request) async {
                                  final task =
                                      (jsonDecode(request.body) as Map)['task'];
                                  if (task == 'status')
                                    return _reply('status', {'enabled': true});
                                  labelModelCalls++;
                                  return _reply('food_label', {
                                    'name': 'Yogur de prueba',
                                    'basis': 'portion',
                                    'unit': 'g',
                                    'serving_quantity': 30,
                                    'kcal': 150,
                                    'protein': 3,
                                    'carbs': 6,
                                    'fat': 2,
                                    'uncertainties': [],
                                  });
                                }),
                              ),
                            ),
                          )),
                      child: const Text('Abrir catálogo'),
                    ),
                  ]),
                )),
      ),
    ));

    await tester.tap(find.text('Nueva comida'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Describir comida · IA'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Describir comida · IA'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'dos huevos');
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Preparar borrador'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Preparar borrador'));
    await tester.pumpAndSettle();
    expect(textModelCalls, 1);
    expect(await db.select(db.meals).get(), isEmpty);
    expect(await db.select(db.foods).get(), hasLength(1));
    await tester.scrollUntilVisible(find.text('Añadir al borrador'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Añadir al borrador'));
    await tester.pumpAndSettle();
    expect(await db.select(db.meals).get(), isEmpty);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Guardar'));
    await tester.pumpAndSettle();
    final meals = await repo.range(date, date);
    expect(meals, hasLength(1));
    expect(meals.single.macros.kcal, 140);
    expect(meals.single.macros.protein, 12);
    expect(meals.single.items.single.foodId, eggId);
    expect(meals.single.items.single.quantity, 2);

    await tester.tap(find.text('Abrir catálogo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leer etiqueta · IA'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Elegir foto'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 130,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Leer etiqueta'), 130,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Leer etiqueta'));
    await tester.pumpAndSettle();
    expect(labelModelCalls, 1);
    await tester.scrollUntilVisible(
        find.text('Revisar y completar alimento'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Revisar y completar alimento'));
    await tester.pumpAndSettle();
    expect((await db.select(db.foods).get()).length, beforeLabel.length);
    await tester
        .ensureVisible(find.text('Comprobé valores y porción con el empaque'));
    await tester.tap(find.text('Comprobé valores y porción con el empaque'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar'));
    await tester.tap(find.text('Guardar').last);
    await tester.pumpAndSettle();
    final foods = await db.select(db.foods).get();
    final yogurt = foods.singleWhere((f) => f.name == 'Yogur de prueba');
    expect(yogurt.basis, FoodBasis.unit);
    expect(yogurt.unitLabel, 'porción (30 g)');
    expect(yogurt.kcal, 150);
    expect(yogurt.source, MacroSource.etiqueta);
    expect(foods, hasLength(beforeLabel.length + 1));

    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
