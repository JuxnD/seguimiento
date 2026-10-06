import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/domain/ai_context.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/features/ai/ai_conversation_screen.dart';
import 'package:seguimiento/features/report/weekly_ai_screen.dart';
import 'package:seguimiento/ui/widgets.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 10, 11);
}

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async => ('ID-SINTETICO', '');

  @override
  Future<void> save(String value) async {}
}

http.Response _status() => http.Response(
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
      'conversación histórica recalcula faltante, respeta fecha y solo guarda al confirmar',
      (tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    final repository = AiConversationRepository(db);
    const range = ('2026-10-05', '2026-10-11');
    await db.customStatement('select 1');
    final overrides = [
      databaseProvider.overrideWithValue(db),
      todayProvider.overrideWith(_FixedToday.new),
    ];
    final snapshot = AiConversationSnapshot(
      kind: AiConversationKind.weeklyAnalysis,
      title: 'Informe histórico · 5–11 oct',
      rangeStart: DateTime(2026, 10, 5),
      rangeEnd: DateTime(2026, 10, 11),
      sources: const [
        AiContextSource(
          id: 'report',
          title: 'Informe seleccionado',
          text: 'Peso: sin registro',
        ),
      ],
      model: aiQuestionModel,
      contractVersion: 1,
    );
    final id = await repository.createValidatedConversation(
      snapshot: snapshot,
      question: 'Analizar el informe seleccionado',
      answer: 'Falta el registro de peso.',
      citations: const [
        AiCitation(sourceId: 'report', quote: 'Peso: sin registro')
      ],
      turnModel: aiQuestionModel,
      turnContractVersion: 1,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: AiConversationScreen.forConversation(
          repository: repository,
          conversationId: id,
          activation: _Activation(),
          clientFactory: () => MockClient((_) async => _status()),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    final weighIn = find.text('Registrar pesaje · 11 oct 2026');
    for (var attempt = 0;
        attempt < 10 && weighIn.evaluate().isEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(weighIn, findsOneWidget);
    await tester.ensureVisible(weighIn);
    expect(weighIn, findsOneWidget);
    expect(
        find.textContaining(
            'Los comentarios y citas guardados conservan la fuente original.'),
        findsOneWidget);
    expect(find.text('Falta el registro de peso.'), findsOneWidget);

    await tester.tap(weighIn);
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(find.text('Registrar peso'), findsOneWidget);
    final dateTile = tester.widget<DateTile>(find.byType(DateTile));
    expect(dayKey(dateTile.date), range.$2);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(weighIn, findsOneWidget);

    await tester.ensureVisible(weighIn);
    await tester.tap(weighIn);
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tester.enterText(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == 'Peso'),
        '70');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    for (var attempt = 0;
        attempt < 20 && weighIn.evaluate().isNotEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Registrar pesaje · 11 oct 2026'), findsNothing);
    expect(find.text('Falta el registro de peso.'), findsOneWidget);
    expect(find.textContaining('Peso: sin registro'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets('respuesta Weekly muestra accesos del rango actual',
      (tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        todayProvider.overrideWith(_FixedToday.new),
      ],
      child: MaterialApp(
        home: WeeklyAiScreen(
          report: 'Peso: sin registro',
          activation: _ActivationForWeekly(),
          rangeStart: DateTime(2026, 10, 5),
          rangeEnd: DateTime(2026, 10, 11),
          clientFactory: () => MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['task'] == 'status') return _status();
            return http.Response(
              jsonEncode({
                'model': 'gpt-6-luna',
                'notes': [
                  {
                    'kind': 'missing',
                    'text': 'Falta el registro de peso.',
                    'quote': 'Peso: sin registro',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    await tester.scrollUntilVisible(find.byType(CheckboxListTile), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Enviar y analizar'), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar y analizar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    final weighIn = find.text('Registrar pesaje · 11 oct 2026');
    await tester.ensureVisible(weighIn);
    expect(weighIn, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}

class _ActivationForWeekly extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('ID-SINTETICO', 'AAAA-BBBB-CCCC-DDDD');

  @override
  Future<void> save(String value) async {}
}
