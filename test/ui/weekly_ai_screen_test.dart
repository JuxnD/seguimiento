import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/features/report/weekly_ai_screen.dart';

class FakeActivation extends AiActivation {
  String license = 'AAAA-BBBB-CCCC-DDDD';
  @override
  Future<(String, String)> read() async => ('SEG-ficticio', license);
  @override
  Future<void> save(String value) async {
    license = value;
  }
}

void main() {
  testWidgets(
      'sin consentimiento no envía; preview coincide y cancelar descarta respuesta tardía',
      (tester) async {
    var calls = 0;
    final reply = Completer<http.Response>();
    await tester.pumpWidget(MaterialApp(
        home: WeeklyAiScreen(
            report: 'Peso: sin registro',
            activation: FakeActivation(),
            clientFactory: () => MockClient((_) {
                  calls++;
                  return reply.future;
                }))));
    await tester.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, 'Enviar y analizar');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    expect(calls, 0);
    await tester.tap(find.text('Ver exactamente qué se enviará'));
    await tester.pumpAndSettle();
    expect(find.text('Peso: sin registro'), findsOneWidget);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pump();
    expect(calls, 1);
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    reply.complete(http.Response(
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
        200));
    await tester.pumpAndSettle();
    expect(find.text('Falta el registro.'), findsNothing);
    expect(find.text('Consulta cancelada. No se cambió ningún registro.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
