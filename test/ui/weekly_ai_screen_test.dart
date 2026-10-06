import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/features/report/weekly_ai_screen.dart';
import '../support/test_fonts.dart';
import '../support/sqlite_host.dart';

class FakeActivation extends AiActivation {
  String license = 'AAAA-BBBB-CCCC-DDDD';
  @override
  Future<(String, String)> read() async => ('SEG-ficticio', license);
  @override
  Future<void> save(String value) async {
    license = value;
  }
}

http.Response statusResponse() => http.Response(
      jsonEncode({
        'status': 'success',
        'contract': 2,
        'task': 'status',
        'model': 'gpt-6-luna',
        'result': {'enabled': true},
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(useHostSqlite);
  testWidgets(
      'la respuesta permite seleccionar, copiar y compartir con evidencia',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadTestFonts(tester);
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel,
        (call) async {
      platformCalls.add(call);
      return 'dismissed';
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null);
    });
    await tester.pumpWidget(MaterialApp(
        home: WeeklyAiScreen(
            report: 'Peso: sin registro',
            activation: FakeActivation(),
            clientFactory: () => MockClient((request) async =>
                request.url.path.endsWith('/asistir')
                    ? statusResponse()
                    : http.Response(
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
                        200,
                        headers: {
                            'content-type': 'application/json; charset=utf-8'
                          })))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar y analizar'));
    await tester.pumpAndSettle();
    final copy = find.text('Copiar respuesta');
    await tester.scrollUntilVisible(copy, 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    const expected =
        'Comentarios de IA · Seguimiento\nVerifica la evidencia antes de actuar.\n\nDato faltante\nFalta el registro.\nDel informe: Peso: sin registro';
    final copied =
        platformCalls.where((c) => c.method == 'Clipboard.setData').last;
    expect(copied.arguments, {'text': expected});
    await tester.tap(find.text('Compartir respuesta'));
    await tester.pumpAndSettle();
    expect(
        (platformCalls.where((c) => c.method == 'share').last.arguments
            as Map<Object?, Object?>)['text'],
        expected);
    await tester.scrollUntilVisible(find.text('Falta el registro.'), 140,
        scrollable: find.byType(Scrollable).first);
    expect(find.widgetWithText(SelectableText, 'Falta el registro.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Copiar comentario'));
    await tester.pumpAndSettle();
    expect(
        platformCalls
            .where((c) => c.method == 'Clipboard.setData')
            .last
            .arguments,
        {
          'text':
              'Dato faltante\nFalta el registro.\nDel informe: Peso: sin registro'
        });
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'sin consentimiento no envía; preview coincide y cancelar descarta respuesta tardía',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadTestFonts(tester);
    var calls = 0;
    final reply = Completer<http.Response>();
    await tester.pumpWidget(MaterialApp(
        home: WeeklyAiScreen(
            report: 'Peso: sin registro',
            activation: FakeActivation(),
            clientFactory: () => MockClient((request) {
                  if (request.url.path.endsWith('/asistir')) {
                    return Future.value(statusResponse());
                  }
                  calls++;
                  return reply.future;
                }))));
    await tester.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, 'Enviar y analizar');
    await tester.scrollUntilVisible(send, 160,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    expect(calls, 0);
    await tester.scrollUntilVisible(
        find.text('Ver exactamente qué se enviará'), -160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Ver exactamente qué se enviará'));
    await tester.pumpAndSettle();
    expect(find.text('Peso: sin registro'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.scrollUntilVisible(send, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(send);
    await tester.pump();
    expect(calls, 1);
    await tester.scrollUntilVisible(find.text('Cancelar'), 100,
        scrollable: find.byType(Scrollable).first);
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

  testWidgets('un segundo análisis fallido no enlaza la conversación anterior',
      (tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    final repository = AiConversationRepository(db);
    var analyses = 0;
    await tester.pumpWidget(MaterialApp(
        home: WeeklyAiScreen(
      report: 'Peso: sin registro',
      activation: FakeActivation(),
      repository: repository,
      clientFactory: () => MockClient((request) async {
        if (request.url.path.endsWith('/asistir')) return statusResponse();
        analyses++;
        if (analyses == 1) {
          return http.Response(
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
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('fallo sintético', 503);
      }),
    )));
    await tester.pumpAndSettle();

    Future<void> consentAndSend() async {
      final checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(checkbox, 180,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(checkbox);
      await tester.pump();
      final send = find.widgetWithText(FilledButton, 'Enviar y analizar');
      await tester.scrollUntilVisible(send, 180,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(send);
      await tester.pumpAndSettle();
    }

    await consentAndSend();
    expect(find.text('Preguntar sobre estos comentarios'), findsOneWidget);
    expect(await repository.count(), 1);
    await consentAndSend();
    expect(analyses, 2);
    expect(find.text('Preguntar sobre estos comentarios'), findsNothing);
    expect(await repository.count(), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
  });
}
