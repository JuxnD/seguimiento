import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/domain/ai_context.dart';

import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);

  late AppDatabase db;
  late AiConversationRepository repository;
  final snapshot = AiConversationSnapshot(
    kind: AiConversationKind.reportQuestion,
    title: 'Informe · 28 sep–4 oct',
    rangeStart: DateTime(2026, 9, 28),
    rangeEnd: DateTime(2026, 10, 4),
    sources: const [
      AiContextSource(
          id: 'report',
          title: 'Resumen del informe',
          text: 'Sesiones y comida del rango.')
    ],
    model: aiQuestionModel,
    contractVersion: aiQuestionContractVersion,
  );

  setUp(() async {
    db = openInMemoryDatabase();
    await db.customStatement('select 1');
    repository = AiConversationRepository(db);
  });

  tearDown(() => db.close());

  test('crea al validar, relee snapshot/hash/cita y borra mensajes en cascada',
      () async {
    final id = await repository.createValidatedConversation(
      snapshot: snapshot,
      question: '¿Qué resume este rango?',
      answer: 'El informe reúne sesiones y comidas del periodo.',
      citations: const [
        AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
      ],
      turnModel: aiQuestionModel,
      turnContractVersion: aiQuestionContractVersion,
    );
    final record = await repository.read(id);
    expect(record, isNotNull);
    expect(record!.snapshot.sourceJson, snapshot.sourceJson);
    expect(record.snapshot.sourceHash, snapshot.sourceHash);
    expect(record.turns.map((turn) => turn.role),
        [AiMessageRole.user, AiMessageRole.assistant]);
    expect(record.turns.last.citations.single.quote,
        'Sesiones y comida del rango.');
    expect(record.turns.last.model, aiQuestionModel);
    expect(record.turns.last.contractVersion, aiQuestionContractVersion);
    expect(await repository.count(), 1);

    await repository.delete(id);
    expect(await repository.read(id), isNull);
    expect(await db.select(db.aiMessages).get(), isEmpty);
  });

  test(
      'rechaza citas ajenas o inventadas sin persistir ni crear conversación vacía',
      () async {
    await expectLater(
      repository.createValidatedConversation(
        snapshot: snapshot,
        question: '¿Qué resume este rango?',
        answer: 'El informe reúne sesiones y comidas del periodo.',
        citations: const [
          AiCitation(
              sourceId: 'inexistente', quote: 'Sesiones y comida del rango.')
        ],
        turnModel: aiQuestionModel,
        turnContractVersion: aiQuestionContractVersion,
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.createValidatedConversation(
        snapshot: snapshot,
        question: '¿Qué resume este rango?',
        answer: 'El informe reúne sesiones y comidas del periodo.',
        citations: const [
          AiCitation(sourceId: 'report', quote: 'frase inventada')
        ],
        turnModel: aiQuestionModel,
        turnContractVersion: aiQuestionContractVersion,
      ),
      throwsFormatException,
    );
    expect(await repository.count(), 0);
  });

  test(
      'append vuelve a validar contra fuentes guardadas y no cambia el snapshot',
      () async {
    final id = await repository.createValidatedConversation(
      snapshot: snapshot,
      question: 'Pregunta inicial',
      answer: 'El informe reúne sesiones.',
      citations: const [
        AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
      ],
      turnModel: aiQuestionModel,
      turnContractVersion: aiQuestionContractVersion,
    );
    await expectLater(
      repository.appendValidatedTurn(
        conversationId: id,
        question: 'Seguimiento',
        answer: 'Los datos muestran una tendencia.',
        citations: const [
          AiCitation(sourceId: 'report', quote: 'tendencia inventada')
        ],
      ),
      throwsFormatException,
    );
    expect((await repository.read(id))!.turns, hasLength(2));

    await repository.appendValidatedTurn(
      conversationId: id,
      question: 'Seguimiento',
      answer: 'El resumen conserva la fuente original.',
      citations: const [
        AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
      ],
    );
    final record = (await repository.read(id))!;
    expect(record.turns, hasLength(4));
    expect(record.snapshot.sourceJson, snapshot.sourceJson);
    expect(
        aiHistoryForRequest([
          for (final turn in record.turns)
            AiStoredTurn(
                role: turn.role, text: turn.text, citations: turn.citations),
        ]),
        hasLength(2));
  });

  test('el límite de veinte turnos se anuncia y nunca borra los anteriores',
      () async {
    final id = await repository.createValidatedConversation(
      snapshot: snapshot,
      question: 'Pregunta inicial',
      answer: 'La respuesta se apoya en la fuente.',
      citations: const [
        AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
      ],
      turnModel: aiQuestionModel,
      turnContractVersion: aiQuestionContractVersion,
    );
    for (var i = 0; i < 19; i++) {
      await repository.appendValidatedTurn(
        conversationId: id,
        question: 'Pregunta de seguimiento',
        answer: 'La respuesta se apoya en la fuente.',
        citations: const [
          AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
        ],
      );
    }
    await expectLater(
      repository.appendValidatedTurn(
        conversationId: id,
        question: 'Pregunta que excede el límite',
        answer: 'La respuesta se apoya en la fuente.',
        citations: const [
          AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
        ],
      ),
      throwsA(isA<AiConversationLimitException>()),
    );
    expect((await repository.read(id))!.turns, hasLength(40));
  });

  test('el límite persistente de cien no oculta ni borra conversaciones',
      () async {
    for (var i = 0; i < AiConversationRepository.maxConversations; i++) {
      await repository.createValidatedConversation(
        snapshot: snapshot,
        question: 'Pregunta $i',
        answer: 'La respuesta se apoya en la fuente.',
        citations: const [
          AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
        ],
        turnModel: aiQuestionModel,
        turnContractVersion: aiQuestionContractVersion,
        createdAt: DateTime.utc(2026, 1, 1, 0, 0, i),
      );
    }

    await expectLater(
      repository.createValidatedConversation(
        snapshot: snapshot,
        question: 'Pregunta que excede el límite',
        answer: 'La respuesta se apoya en la fuente.',
        citations: const [
          AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
        ],
        turnModel: aiQuestionModel,
        turnContractVersion: aiQuestionContractVersion,
      ),
      throwsA(isA<AiHistoryLimitException>()),
    );
    expect(await repository.count(), 100);
    expect(await repository.watchRecent(limit: 100).first, hasLength(100));
  });

  test('respuesta v2 con dígitos y snapshot alterado fallan cerrados',
      () async {
    expect(
      () => validateAiAnswer(
        snapshot: snapshot,
        answer: 'El cambio fue de 2 sesiones.',
        citations: const [
          AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
        ],
        contractVersion: aiQuestionContractVersion,
      ),
      throwsFormatException,
    );
    await repository.createValidatedConversation(
      snapshot: snapshot,
      question: 'Pregunta inicial',
      answer: 'La respuesta se apoya en la fuente.',
      citations: const [
        AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
      ],
      turnModel: aiQuestionModel,
      turnContractVersion: aiQuestionContractVersion,
    );
    final row = (await db.select(db.aiConversations).getSingle());
    await (db.update(db.aiConversations)
          ..where((item) => item.id.equals(row.id)))
        .write(const AiConversationsCompanion(sourcesJson: Value('[]')));
    await expectLater(repository.read(row.id), throwsFormatException);
  });

  test('read rechaza citas guardadas que no pertenecen al snapshot', () async {
    final id = await repository.createValidatedConversation(
      snapshot: snapshot,
      question: 'Pregunta inicial',
      answer: 'La respuesta se apoya en la fuente.',
      citations: const [
        AiCitation(sourceId: 'report', quote: 'Sesiones y comida del rango.')
      ],
      turnModel: aiQuestionModel,
      turnContractVersion: aiQuestionContractVersion,
    );
    final assistant = await (db.select(db.aiMessages)
          ..where((message) => message.conversationId.equals(id))
          ..where(
              (message) => message.role.equals(AiMessageRole.assistant.name)))
        .getSingle();
    await (db.update(db.aiMessages)
          ..where((message) => message.id.equals(assistant.id)))
        .write(const AiMessagesCompanion(
            citationsJson:
                Value('[{"source_id":"report","quote":"inventada"}]')));

    await expectLater(repository.read(id), throwsFormatException);
  });

  test('el snapshot copia la lista de fuentes y congela el hash', () {
    final mutableSources = <AiContextSource>[
      const AiContextSource(
        id: 'report',
        title: 'Resumen',
        text: 'Sesiones y comida del rango.',
      ),
    ];
    final frozen = AiConversationSnapshot(
      kind: AiConversationKind.reportQuestion,
      title: 'Informe',
      sources: mutableSources,
      model: aiQuestionModel,
      contractVersion: aiQuestionContractVersion,
    );
    final hash = frozen.sourceHash;
    mutableSources.clear();

    expect(frozen.sources, hasLength(1));
    expect(frozen.sourceHash, hash);
    expect(() => frozen.sources.clear(), throwsUnsupportedError);
  });
}
