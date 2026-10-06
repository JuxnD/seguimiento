import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/domain/ai_context.dart';
import 'package:seguimiento/features/ai/ai_conversation_screen.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

class _Activation extends AiActivation {
  @override
  Future<(String, String)> read() async =>
      ('HWID-FICTICIO', 'AAAA-BBBB-CCCC-DDDD');

  @override
  Future<void> save(String license) async {}
}

class _RecordingRepository extends AiConversationRepository {
  _RecordingRepository(super.db);

  int creates = 0;
  String? question;
  String? answer;
  List<AiCitation> citations = const [];

  @override
  Future<int> createValidatedConversation({
    required AiConversationSnapshot snapshot,
    required String question,
    required String answer,
    required List<AiCitation> citations,
    required String turnModel,
    required int turnContractVersion,
    DateTime? createdAt,
  }) async {
    creates++;
    this.question = question;
    this.answer = answer;
    this.citations = citations;
    return 1;
  }

  @override
  Future<AiConversationRecord?> read(int id) async => null;
}

void main() {
  setUpAll(useHostSqlite);

  late AppDatabase db;
  late _RecordingRepository repository;
  final snapshot = AiConversationSnapshot(
    kind: AiConversationKind.reportQuestion,
    title: 'Informe sintético',
    rangeStart: DateTime(2026, 10, 5),
    rangeEnd: DateTime(2026, 10, 11),
    sources: const [
      AiContextSource(
        id: 'report',
        title: 'Resumen local',
        text: 'Sesiones y comidas del rango.',
      ),
    ],
    model: aiQuestionModel,
    contractVersion: aiQuestionContractVersion,
  );

  setUp(() {
    db = openInMemoryDatabase();
    repository = _RecordingRepository(db);
  });

  tearDown(() => db.close());

  Future<void> ask(WidgetTester tester, MockClient client) async {
    await loadTestFonts(tester);
    await tester.pumpWidget(MaterialApp(
      home: AiConversationScreen.forQuestion(
        repository: repository,
        snapshot: snapshot,
        activation: _Activation(),
        clientFactory: () => client,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '¿Qué resume este rango?');
    await tester.pump();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('Enviar pregunta'));
    await tester.tap(find.text('Enviar pregunta'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
      'consentimiento y respuesta válida llegan a persistencia sin secretos',
      (tester) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      final responseBody = jsonEncode({
        'status': 'success',
        'contract': 2,
        'task': 'report_question',
        'model': 'gpt-6-luna',
        'result': {
          'answer': 'El rango reúne sesiones y comidas.',
          'citations': [
            {'source_id': 'report', 'quote': 'Sesiones y comidas del rango.'}
          ],
        },
      });
      return http.Response(responseBody, 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await ask(tester, client);

    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['task'], 'report_question');
    final input = body['input'] as Map<String, dynamic>;
    final sources = input['sources'] as List<dynamic>;
    final firstSource = sources.single as Map<String, dynamic>;
    expect(firstSource['text'], 'Sesiones y comidas del rango.');
    expect(body['hwid'], 'HWID-FICTICIO');
    expect(repository.creates, 1);
    expect(repository.answer, 'El rango reúne sesiones y comidas.');
    expect(repository.question, '¿Qué resume este rango?');
    expect(repository.citations.single.quote, 'Sesiones y comidas del rango.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cita inventada queda visible como error y no crea historial',
      (tester) async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'status': 'success',
            'contract': 2,
            'task': 'report_question',
            'model': 'gpt-6-luna',
            'result': {
              'answer': 'El informe se ve consistente.',
              'citations': [
                {'source_id': 'report', 'quote': 'frase inventada'}
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));
    await ask(tester, client);

    expect(repository.creates, 0);
    expect(find.text('Una cita no coincide con la fuente guardada.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
