import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/meals/meal_text_screen.dart';

import '../support/test_fonts.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
}

class _ChangingActivation extends AiActivation {
  int reads = 0;

  @override
  Future<(String, String)> read() async {
    reads++;
    return (
      'SEG-FICTICIO',
      reads == 1 ? 'AAAA-BBBB-CCCC-DDDD' : 'EEEE-FFFF-GGGG-HHHH'
    );
  }
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
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const food = FoodRow(
    id: 1,
    name: 'Huevo',
    basis: FoodBasis.unit,
    unitLabel: 'unidad',
    kcal: 70,
    protein: 6,
    carbs: 1,
    fat: 5,
    defaultQuantity: 1,
    source: MacroSource.referencia,
    origin: FoodOrigin.semilla,
    favorite: false,
  );
  const id = 1;

  testWidgets(
      'consentimiento ligado a frase y macro local llega solo al borrador',
      (tester) async {
    await loadTestFonts(tester);
    var calls = 0;
    List<MealItemDraft>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<List<MealItemDraft>>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => MealTextScreen(
                                foods: const [food],
                                activation: _Activation(),
                                clientFactory: () =>
                                    MockClient((request) async {
                                  calls++;
                                  final body = jsonDecode(request.body) as Map;
                                  if (body['task'] == 'status') {
                                    return _reply('status', {'enabled': true});
                                  }
                                  expect(body['task'], 'meal_text');
                                  return _reply('meal_text', {
                                    'items': [
                                      {
                                        'label': 'dos huevos',
                                        'food_id': id,
                                        'quantity': 2,
                                        'unit': 'unidad'
                                      }
                                    ],
                                    'uncertainties': [],
                                  });
                                }),
                              )));
                },
                child: const Text('Abrir'),
              ))),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(calls, 1); // status, no request to the model
    expect(find.textContaining('Consultas disponibles: 3/4'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'dos huevos');
    final send = find.text('Preparar borrador');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(calls, 1);
    final consent = find.byType(CheckboxListTile).first;
    tester.widget<CheckboxListTile>(consent).onChanged!(true);
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isTrue);
    await tester.enterText(find.byType(TextField).first, 'tres huevos');
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isFalse);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(calls, 1);
    tester.widget<CheckboxListTile>(consent).onChanged!(true);
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isTrue);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(result, isNull);
    expect(find.text('140 kcal · P 12 g'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir al borrador'));
    await tester.pumpAndSettle();
    expect(result!.single.macros.kcal, 140);
    expect(result!.single.macros.protein, 12);
    expect(result!.single.foodId, id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'no pierde propuesta ambigua ni acepta parcialmente; quitar y resolver son explícitos',
      (tester) async {
    await loadTestFonts(tester);
    await tester.pumpWidget(MaterialApp(
        home: MealTextScreen(
      foods: const [food],
      activation: _Activation(),
      clientFactory: () => MockClient((request) async {
        final task = (jsonDecode(request.body) as Map)['task'];
        return task == 'status'
            ? _reply('status', {'enabled': true})
            : _reply('meal_text', {
                'items': [
                  {
                    'label': 'huevo pesado',
                    'food_id': id,
                    'quantity': 2,
                    'unit': 'g'
                  },
                  {
                    'label': 'huevo',
                    'food_id': null,
                    'quantity': null,
                    'unit': null
                  },
                ],
                'uncertainties': [],
              });
      }),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Activar IA en este teléfono'), findsNothing);
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .length,
        1);
    await tester.enterText(find.byType(TextField).first, 'huevo');
    await tester.pump();
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
        .onChanged!(true);
    await tester.pump();
    final prepare = find.text('Preparar borrador');
    await tester.ensureVisible(prepare);
    await tester.tap(prepare);
    await tester.pumpAndSettle();
    expect(find.text('huevo pesado'), findsOneWidget);
    expect(find.textContaining('catálogo usa unidad.'), findsOneWidget);
    final quantityInputs =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(quantityInputs[1].controller!.text, isEmpty,
        reason: 'la propuesta en g no se copia a la unidad de catálogo');
    final add = find.text('Añadir al borrador');
    await tester.scrollUntilVisible(add, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final addButton = find.widgetWithText(FilledButton, 'Añadir al borrador');
    expect(tester.widget<FilledButton>(addButton).onPressed, isNull);
    await tester.tap(find.text('Quitar esta propuesta').first);
    await tester.pump();
    final dropdowns = find.byType(DropdownButtonFormField<FoodRow>);
    await tester.tap(dropdowns.last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Huevo').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar porción habitual: 1 unidad'));
    await tester.pump();
    await tester.scrollUntilVisible(add, 160,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(addButton).onPressed, isNotNull);
    expect(
        find.text(
            'Total calculado localmente: 70 kcal · P 6 g · C 1 g · G 5 g'),
        findsOneWidget);
    expect(find.byType(MealTextScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reanálisis descarta confirmaciones de cantidad de la propuesta anterior',
      (tester) async {
    await loadTestFonts(tester);
    var modelCalls = 0;
    await tester.pumpWidget(MaterialApp(
        home: MealTextScreen(
      foods: const [food],
      activation: _Activation(),
      clientFactory: () => MockClient((request) async {
        final task = (jsonDecode(request.body) as Map)['task'];
        if (task == 'status') return _reply('status', {'enabled': true});
        modelCalls++;
        return _reply('meal_text', {
          'items': [
            {'label': 'huevo', 'food_id': id, 'quantity': null, 'unit': null}
          ],
          'uncertainties': [],
        });
      }),
    )));
    await tester.pumpAndSettle();
    final description = find.byType(TextField).first;
    await tester.enterText(description, 'un huevo');
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
        .onChanged!(true);
    await tester.pump();
    final prepare = find.text('Preparar borrador');
    await tester.ensureVisible(prepare);
    await tester.tap(prepare);
    await tester.pumpAndSettle();
    final usual = find.text('Usar porción habitual: 1 unidad');
    await tester.scrollUntilVisible(usual, 130,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(usual);
    await tester.pump();
    expect(find.text('70 kcal · P 6 g'), findsOneWidget);

    await tester.enterText(description, 'otro huevo');
    await tester.pump();
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isFalse);
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
        .onChanged!(true);
    await tester.pump();
    await tester.ensureVisible(prepare);
    await tester.tap(prepare);
    await tester.pumpAndSettle();
    expect(modelCalls, 2);
    await tester.scrollUntilVisible(usual, 130,
        scrollable: find.byType(Scrollable).first);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[1].controller!.text, isEmpty);
    expect(find.text('Usar porción habitual: 1 unidad'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Añadir al borrador'), 140,
        scrollable: find.byType(Scrollable).first);
    final add = find.widgetWithText(FilledButton, 'Añadir al borrador');
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editar frase descarta resultado viejo y exige consentimiento nuevo',
      (tester) async {
    await loadTestFonts(tester);
    await tester.pumpWidget(MaterialApp(
        home: MealTextScreen(
      foods: const [food],
      activation: _Activation(),
      clientFactory: () => MockClient((request) async {
        final task = (jsonDecode(request.body) as Map)['task'];
        return task == 'status'
            ? _reply('status', {'enabled': true})
            : _reply('meal_text', {
                'items': [
                  {
                    'label': 'huevo',
                    'food_id': id,
                    'quantity': 1,
                    'unit': 'unidad'
                  }
                ],
                'uncertainties': [],
              });
      }),
    )));
    await tester.pumpAndSettle();
    final phrase = find.byType(TextField).first;
    await tester.enterText(phrase, 'un huevo');
    tester
        .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
        .onChanged!(true);
    await tester.pump();
    final prepare = find.text('Preparar borrador');
    await tester.ensureVisible(prepare);
    await tester.tap(prepare);
    await tester.pumpAndSettle();
    final review = find.text('Revisa alimento y cantidad');
    await tester.scrollUntilVisible(review, 130,
        scrollable: find.byType(Scrollable).first);
    expect(review, findsOneWidget);

    await tester.enterText(phrase, 'dos huevos');
    await tester.pump();
    expect(find.text('Revisa alimento y cantidad'), findsNothing);
    expect(find.text('Añadir al borrador'), findsNothing);
    expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .value,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'respuesta tardía de status de licencia anterior no habilita ni reemplaza cuota',
      (tester) async {
    await loadTestFonts(tester);
    final activation = _ChangingActivation();
    final oldStatus = Completer<http.Response>();
    var statusCalls = 0;
    await tester.pumpWidget(MaterialApp(
        home: MealTextScreen(
      foods: const [],
      activation: activation,
      clientFactory: () => MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['task'], 'status');
        statusCalls++;
        if (statusCalls == 1) return oldStatus.future;
        final enabled = statusCalls == 2;
        return _reply('status', {'enabled': enabled});
      }),
    )));
    await tester.pumpAndSettle();
    expect(statusCalls, 1);
    await tester.tap(find.text('Activar IA en este teléfono'));
    await tester.pumpAndSettle();
    expect(find.text('IA habilitada para este teléfono.'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(statusCalls, 3);
    expect(find.text('Preparar borrador'), findsNothing);
    oldStatus.complete(_reply('status', {'enabled': true}));
    await tester.pumpAndSettle();
    expect(find.text('Preparar borrador'), findsNothing);
    expect(find.text('Consultas disponibles: 3/4'), findsNothing);
    expect(statusCalls, 3);
    expect(tester.takeException(), isNull);
  });
}
