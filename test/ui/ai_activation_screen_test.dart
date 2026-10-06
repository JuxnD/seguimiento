import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/features/ai/ai_activation_screen.dart';

class _Activation extends AiActivation {
  _Activation(this.license);
  String license;
  final saved = <String>[];

  @override
  Future<(String, String)> read() async => ('SEG-FICTICIO', license);

  @override
  Future<void> save(String value) async {
    license = value;
    saved.add(value);
  }
}

http.Response _statusResponse() => http.Response(
      jsonEncode({
        'status': 'success',
        'contract': 2,
        'task': 'status',
        'model': 'gpt-6-luna',
        'result': {'enabled': true, 'tasks': []},
        'quota': {
          'remaining': 4,
          'limit': 20,
          'reset_at': '2026-10-07T00:00:00Z'
        },
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  testWidgets('guarda y olvida licencia por el bridge inyectado',
      (tester) async {
    final activation = _Activation('');
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: AiActivationScreen(
        activation: activation,
        clientFactory: () => MockClient((request) async {
          calls++;
          expect(request.url.toString(),
              'https://www.control360i.co/app/seguimiento/asistir');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['task'], 'status');
          return _statusResponse();
        }),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'AAAA-BBBB-CCCC-DDDD');
    await tester.tap(find.text('Guardar licencia'));
    await tester.pumpAndSettle();
    expect(activation.saved, ['AAAA-BBBB-CCCC-DDDD']);
    expect(calls, 1);
    expect(find.text('IA habilitada para este teléfono.'), findsOneWidget);
    expect(find.textContaining('4/20'), findsOneWidget);

    await tester.tap(find.text('Olvidar licencia'));
    await tester.pumpAndSettle();
    expect(activation.saved.last, '');
    expect(find.text('Licencia quitada de este teléfono.'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('descarta status tardío si se olvida otra licencia',
      (tester) async {
    final activation = _Activation('AAAA-BBBB-CCCC-DDDD');
    final pending = Completer<http.Response>();
    await tester.pumpWidget(MaterialApp(
      home: AiActivationScreen(
        activation: activation,
        clientFactory: () => MockClient((_) => pending.future),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Olvidar licencia'));
    await tester.pumpAndSettle();
    expect(find.text('Licencia quitada de este teléfono.'), findsOneWidget);

    pending.complete(_statusResponse());
    await tester.pumpAndSettle();
    expect(find.text('Licencia quitada de este teléfono.'), findsOneWidget);
    expect(find.text('IA habilitada para este teléfono.'), findsNothing);
  });
}
