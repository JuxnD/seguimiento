import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/features/meals/meal_photo_screen.dart';
import '../support/meal_photo_fixture.dart';
import '../support/test_fonts.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('SEG-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');
}

http.Response _status() => http.Response(
    jsonEncode({
      'status': 'success',
      'contract': 2,
      'task': 'status',
      'model': 'gpt-6-luna',
      'result': {'enabled': true},
      'quota': {
        'remaining': 3,
        'limit': 4,
        'reset_at': '2026-10-07T00:00:00Z',
      }
    }),
    200);

Future<void> _choosePhoto(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.text('Elegir foto'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'foto consentida → revisión de porción → borrador; ningún guardado automático',
      (tester) async {
    await loadTestFonts(tester);
    var calls = 0;
    PhotoMealSelection? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  child: const Text('Abrir'),
                  onPressed: () async {
                    result = await Navigator.push<PhotoMealSelection>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MealPhotoScreen(
                                  activation: _Activation(),
                                  pickPhoto: (_) async => fictionalPhoto(),
                                  clientFactory: () =>
                                      MockClient((request) async {
                                    calls++;
                                    if ((jsonDecode(request.body)
                                            as Map)['task'] ==
                                        'status') {
                                      return _status();
                                    }
                                    return http.Response(
                                        jsonEncode(fictionalMeal()), 200);
                                  }),
                                )));
                  },
                )))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await _choosePhoto(tester);
    expect(calls, 1);
    expect(result, isNull);
    final analyze = find.widgetWithText(FilledButton, 'Analizar foto');
    await tester.scrollUntilVisible(analyze, 180,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(analyze).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(analyze);
    await tester.pumpAndSettle();
    expect(calls, 3); // estado inicial, foto y refresco gratuito de cuota
    expect(result, isNull);
    await tester.scrollUntilVisible(find.text('Arroz cocido'), 150,
        scrollable: find.byType(Scrollable).first);
    final portion = find.byKey(const ValueKey('photo-portion-0-1.5'));
    await tester.scrollUntilVisible(portion, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(portion);
    await tester.pump();
    final add = find.text('Añadir al borrador');
    await tester.scrollUntilVisible(add, 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(result!.items.length, 2);
    expect(result!.items.first.macros.kcal, 315);
    expect(
        result!.items
            .every((i) => i.sourceVerified == null && i.foodId == null),
        isTrue);
    expect(result!.notes, contains('No se puede medir el aceite'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'cancelar descarta respuesta tardía; cambiar foto pide consentimiento nuevo',
      (tester) async {
    await loadTestFonts(tester);
    final reply = Completer<http.Response>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: MealPhotoScreen(
      activation: _Activation(),
      pickPhoto: (_) async => fictionalPhoto(),
      clientFactory: () => MockClient((request) {
        calls++;
        if ((jsonDecode(request.body) as Map)['task'] == 'status') {
          return Future.value(_status());
        }
        return reply.future;
      }),
    )));
    await tester.pumpAndSettle();
    await _choosePhoto(tester);
    final analyze = find.widgetWithText(FilledButton, 'Analizar foto');
    await tester.scrollUntilVisible(analyze, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(analyze);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Cancelar análisis'), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancelar análisis'));
    await tester.pump();
    reply.complete(http.Response(jsonEncode(fictionalMeal()), 200));
    await tester.pumpAndSettle();
    expect(find.text('Revisa la propuesta'), findsNothing);
    expect(calls, 2); // la cancelación no dispara otro estado
    await tester.scrollUntilVisible(find.text('Elegir foto'), -180,
        scrollable: find.byType(Scrollable).first);
    await _choosePhoto(tester);
    await tester.scrollUntilVisible(analyze, 160,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(analyze).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
