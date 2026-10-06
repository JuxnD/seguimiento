import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/meal_assistant.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/features/meals/food_label_screen.dart';
import 'package:seguimiento/features/meals/foods_screen.dart';

import '../support/meal_photo_fixture.dart';
import '../support/test_fonts.dart';

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
    headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _choosePhoto(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Elegir foto'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'porción 30 g se convierte localmente y el borrador mantiene lectura original',
      (tester) async {
    await loadTestFonts(tester);
    var calls = 0;
    FoodLabelDraft? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Abrir'),
                    onPressed: () async {
                      result = await Navigator.push<FoodLabelDraft>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => FoodLabelScreen(
                                    activation: _Activation(),
                                    pickPhoto: (_) async => fictionalPhoto(),
                                    clientFactory: () =>
                                        MockClient((request) async {
                                      calls++;
                                      final body =
                                          jsonDecode(request.body) as Map;
                                      if (body['task'] == 'status') {
                                        return _reply(
                                            'status', {'enabled': true});
                                      }
                                      expect(body['task'], 'food_label');
                                      return _reply('food_label', {
                                        'name': 'Yogur',
                                        'basis': 'portion',
                                        'unit': 'g',
                                        'serving_quantity': 30,
                                        'kcal': 150,
                                        'protein': 3,
                                        'carbs': 6,
                                        'fat': null,
                                        'uncertainties': [
                                          'La grasa no es legible.'
                                        ],
                                      });
                                    }),
                                  )));
                    },
                  ),
                ))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await _choosePhoto(tester);
    expect(calls, 1);
    final read = find.text('Leer etiqueta');
    await tester.ensureVisible(read);
    await tester.tap(read);
    await tester.pumpAndSettle();
    expect(calls, 1);
    final consent = find.byType(CheckboxListTile);
    tester.widget<CheckboxListTile>(consent).onChanged!(true);
    await tester.pump();
    await tester.tap(read);
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('kcal: 150'), findsOneWidget);
    final conversion = find.byType(SwitchListTile);
    await tester.ensureVisible(conversion);
    await tester.tap(conversion);
    await tester.pump();
    expect(find.text('kcal: 500'), findsOneWidget);
    expect(find.textContaining('valor leído × 100 ÷ 30'), findsOneWidget);
    final review = find.text('Revisar y completar alimento');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(result!.basis, FoodBasis.per100);
    expect(result!.unitLabel, 'g');
    expect(result!.defaultQuantity, 100);
    expect(result!.kcal, 500);
    expect(result!.protein, 10);
    expect(result!.fat, isNull);
    expect(result!.sourceSnapshot.kcal, 150);
    expect(result!.sourceSnapshot.servingQuantity, 30);
    expect(result!.uncertainties, ['La grasa no es legible.']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'FoodDialog deja incompletos vacíos y etiqueta requiere checkbox explícito',
      (tester) async {
    await loadTestFonts(tester);
    const snapshot = FoodLabelProposal(
      name: 'Yogur',
      basis: 'portion',
      unit: 'g',
      servingQuantity: 30,
      kcal: 150,
      protein: 3,
      carbs: 6,
      fat: null,
      uncertainties: ['Falta grasa.'],
    );
    const draft = FoodLabelDraft(
      name: 'Yogur',
      basis: FoodBasis.per100,
      unitLabel: 'g',
      defaultQuantity: 100,
      kcal: 500,
      protein: 10,
      carbs: 20,
      fat: null,
      uncertainties: ['Falta grasa.'],
      sourceSnapshot: snapshot,
      convertedToPer100: true,
      portionNeedsConfirmation: false,
    );
    FoodsCompanion? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Abrir'),
                    onPressed: () async {
                      result = await showDialog<FoodsCompanion>(
                          context: context,
                          builder: (_) => const FoodDialog(labelDraft: draft));
                    },
                  ),
                ))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Grasa: no leído'), findsNothing);
    expect(find.text('Por verificar: Falta grasa.'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(
        find.text(
            'Completa nombre, base, unidad y los cuatro valores con cantidades válidas'),
        findsOneWidget);
    final fatField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Grasa');
    await tester.enterText(fatField, '1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result!.source.value, MacroSource.estimado);
    expect(result!.basis.value, FoodBasis.per100);
    expect(result!.defaultQuantity.value, 100);
    await tester.pumpWidget(const SizedBox.shrink());
    result = null;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Abrir'),
                    onPressed: () async {
                      result = await showDialog<FoodsCompanion>(
                          context: context,
                          builder: (_) => const FoodDialog(labelDraft: draft));
                    },
                  ),
                ))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(fatField, '1');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result!.source.value, MacroSource.etiqueta);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'base y unidad no identificadas exigen elección explícita antes de guardar',
      (tester) async {
    await loadTestFonts(tester);
    const snapshot = FoodLabelProposal(
      name: 'Sopa',
      basis: null,
      unit: null,
      servingQuantity: null,
      kcal: 80,
      protein: 2,
      carbs: 10,
      fat: 3,
      uncertainties: ['La base y la unidad no se distinguen.'],
    );
    const draft = FoodLabelDraft(
      name: 'Sopa',
      basis: null,
      unitLabel: '',
      defaultQuantity: null,
      kcal: 80,
      protein: 2,
      carbs: 10,
      fat: 3,
      uncertainties: ['La base y la unidad no se distinguen.'],
      sourceSnapshot: snapshot,
      convertedToPer100: false,
      portionNeedsConfirmation: false,
    );
    FoodsCompanion? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Abrir'),
                    onPressed: () async {
                      result = await showDialog<FoodsCompanion>(
                          context: context,
                          builder: (_) => const FoodDialog(labelDraft: draft));
                    },
                  ),
                ))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('Por 100 g/ml'));
    await tester.pumpAndSettle();
    final unit = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'g o ml');
    await tester.enterText(unit, 'g');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(result!.basis.value, FoodBasis.per100);
    expect(result!.unitLabel.value, 'g');
    expect(result!.defaultQuantity.value, 100);
    expect(result!.source.value, MacroSource.estimado);
    expect(tester.takeException(), isNull);
  });
}
