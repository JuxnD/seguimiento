import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:seguimiento/features/meals/meal_form_screen.dart';
import 'package:seguimiento/features/meals/meal_photo_screen.dart';
import 'package:seguimiento/features/report/weekly_ai_screen.dart';
import '../test/support/meal_photo_fixture.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
  @override
  Future<void> save(String value) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android relee portapapeles real con comentario y evidencia',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: WeeklyAiScreen(
      report: 'Peso: sin registro',
      activation: _Activation(),
      clientFactory: () => MockClient((_) async => http.Response(
          jsonEncode({
            'model': 'gpt-6-luna',
            'notes': [
              {
                'kind': 'missing',
                'text': 'Falta el registro.',
                'quote': 'Peso: sin registro'
              }
            ]
          }),
          200)),
    )));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Enviar y analizar'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Enviar y analizar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Copiar respuesta'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Copiar respuesta'));
    await tester.pumpAndSettle();
    expect((await Clipboard.getData('text/plain'))!.text,
        'Comentarios de IA · Seguimiento\nVerifica la evidencia antes de actuar.\n\nDato faltante\nFalta el registro.\nDel informe: Peso: sin registro');
  });
  testWidgets(
      'Android foto → formulario real → Guardar → relectura SQLite; sin red real',
      (tester) async {
    final db = openInMemoryDatabase();
    final repo = NutritionRepository(db);
    final date = DateTime(2026, 10, 6);
    var modelCalls = 0, statusCalls = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('Nueva comida'),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => MealFormScreen(
                                    draft: MealDraft(
                                        date: date, slot: MealSlot.almuerzo),
                                    photoScreenBuilder: () => MealPhotoScreen(
                                        activation: _Activation(),
                                        pickPhoto: (_) async =>
                                            fictionalPhoto(),
                                        clientFactory: () =>
                                            MockClient((request) async {
                                              final body =
                                                  jsonDecode(request.body)
                                                      as Map;
                                              if (body['task'] == 'status') {
                                                statusCalls++;
                                                return http.Response(
                                                    jsonEncode({
                                                      'status': 'success',
                                                      'contract': 2,
                                                      'task': 'status',
                                                      'model': 'gpt-6-luna',
                                                      'result': {
                                                        'enabled': true
                                                      },
                                                      'quota': {
                                                        'remaining': 3,
                                                        'limit': 4,
                                                        'reset_at':
                                                            '2026-10-07T00:00:00Z'
                                                      },
                                                    }),
                                                    200);
                                              }
                                              modelCalls++;
                                              return http.Response(
                                                  jsonEncode(fictionalMeal()),
                                                  200);
                                            })),
                                  )))))),
        )));
    await tester.tap(find.text('Nueva comida'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Registrar con foto · IA'), 130,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Registrar con foto · IA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir foto'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Analizar foto'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analizar foto'));
    await tester.pumpAndSettle();
    expect(await db.select(db.meals).get(), isEmpty);
    await tester.scrollUntilVisible(find.text('Añadir al borrador'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Añadir al borrador'));
    await tester.pumpAndSettle();
    expect(await db.select(db.meals).get(), isEmpty);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Guardar'));
    await tester.pumpAndSettle();
    final meals = await repo.range(date, date);
    expect(modelCalls, 1);
    expect(statusCalls, 2);
    expect(meals.length, 1);
    expect(meals.single.items.length, 2);
    expect(meals.single.macros.kcal, 460);
    expect(meals.single.macros.protein, 50);
    expect(
        meals.single.items
            .every((i) => i.sourceVerified == null && i.foodId == null),
        isTrue);
    expect(meals.single.meal.notes, contains('No se puede medir el aceite'));
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
