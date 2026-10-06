import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/ai_context.dart';
import '../database.dart';

class AiConversationRepository {
  static const maxConversations = 100;

  AiConversationRepository(this.db);

  final AppDatabase db;

  Stream<List<AiConversationRow>> watchRecent(
          {int limit = 100, int offset = 0}) =>
      (db.select(db.aiConversations)
            ..orderBy([
              (row) => OrderingTerm(
                  expression: row.createdAt, mode: OrderingMode.desc)
            ])
            ..limit(limit, offset: offset))
          .watch();

  Future<int> count() async =>
      (await db.select(db.aiConversations).get()).length;

  Stream<int> watchCount() {
    final count = db.aiConversations.id.count();
    return (db.selectOnly(db.aiConversations)..addColumns([count]))
        .watchSingle()
        .map((row) => row.read(count) ?? 0);
  }

  Future<AiConversationRecord?> read(int id) async {
    final conversation = await (db.select(db.aiConversations)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (conversation == null) return null;
    final snapshot = _snapshot(conversation);
    final messages = await (db.select(db.aiMessages)
          ..where((row) => row.conversationId.equals(id))
          ..orderBy([(row) => OrderingTerm(expression: row.id)]))
        .get();
    final turns = [
      for (final message in messages)
        AiConversationTurn(
          id: message.id,
          role: AiMessageRole.values
              .firstWhere((role) => role.name == message.role),
          text: message.messageText,
          citations: _decodeCitations(message.citationsJson),
          model: message.model,
          contractVersion: message.contractVersion,
          createdAt: DateTime.fromMillisecondsSinceEpoch(message.createdAt,
              isUtc: true),
        ),
    ];
    for (final turn
        in turns.where((turn) => turn.role == AiMessageRole.assistant)) {
      if (turn.model.trim().isEmpty || turn.contractVersion < 1) {
        throw const FormatException(
            'Un turno guardado no tiene contrato válido.');
      }
      validateAiAnswer(
        snapshot: snapshot,
        answer: turn.text,
        citations: turn.citations,
        contractVersion: turn.contractVersion,
      );
    }
    return AiConversationRecord(
      row: conversation,
      snapshot: snapshot,
      turns: turns,
    );
  }

  /// Crea el registro solo después de que la respuesta completa pase la
  /// verificación. Cancelar o recibir un error antes no deja conversaciones vacías.
  Future<int> createValidatedConversation({
    required AiConversationSnapshot snapshot,
    required String question,
    required String answer,
    required List<AiCitation> citations,
    required String turnModel,
    required int turnContractVersion,
    DateTime? createdAt,
  }) async {
    _validateQuestion(question);
    validateAiAnswer(
      snapshot: snapshot,
      answer: answer,
      citations: citations,
      contractVersion: turnContractVersion,
    );
    final time = (createdAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    return db.transaction(() async {
      final total = db.aiConversations.id.count();
      final count = await (db.selectOnly(db.aiConversations)
            ..addColumns([total]))
          .map((row) => row.read(total) ?? 0)
          .getSingle();
      if (count >= maxConversations) {
        throw const AiHistoryLimitException(
            'El historial llegó a cien conversaciones. Borra alguna desde Historial para guardar otra.');
      }
      final id = await db
          .into(db.aiConversations)
          .insert(AiConversationsCompanion.insert(
            kind: snapshot.kind.name,
            title: snapshot.title,
            rangeStart: Value(snapshot.rangeStart == null
                ? null
                : _dayKey(snapshot.rangeStart!)),
            rangeEnd: Value(
                snapshot.rangeEnd == null ? null : _dayKey(snapshot.rangeEnd!)),
            model: snapshot.model,
            contractVersion: snapshot.contractVersion,
            sourcesJson: snapshot.sourceJson,
            sourcesHash: snapshot.sourceHash,
            guideContextJson: Value(snapshot.guideContextJson),
            guideContextHash: Value(snapshot.guideContextHash),
            createdAt: time,
          ));
      await _insertTurn(
        id: id,
        question: question,
        answer: answer,
        citations: citations,
        model: turnModel,
        contractVersion: turnContractVersion,
        createdAt: time,
      );
      return id;
    });
  }

  /// Lee y comprueba el snapshot de SQLite en la misma transacción antes de
  /// aceptar citas; el caller nunca puede sustituir las fuentes guardadas.
  Future<void> appendValidatedTurn({
    required int conversationId,
    required String question,
    required String answer,
    required List<AiCitation> citations,
    String model = aiQuestionModel,
    int contractVersion = aiQuestionContractVersion,
    DateTime? createdAt,
  }) async {
    _validateQuestion(question);
    await db.transaction(() async {
      final row = await (db.select(db.aiConversations)
            ..where((item) => item.id.equals(conversationId)))
          .getSingle();
      final snapshot = _snapshot(row);
      validateAiAnswer(
          snapshot: snapshot,
          answer: answer,
          citations: citations,
          contractVersion: contractVersion);
      final previous = await (db.select(db.aiMessages)
            ..where((item) => item.conversationId.equals(conversationId)))
          .get();
      final turns =
          previous.where((item) => item.role == AiMessageRole.user.name).length;
      if (turns >= 20) {
        throw const AiConversationLimitException(
            'Esta conversación alcanzó veinte preguntas.');
      }
      final time = (createdAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
      await _insertTurn(
        id: conversationId,
        question: question,
        answer: answer,
        citations: citations,
        model: model,
        contractVersion: contractVersion,
        createdAt: time,
      );
    });
  }

  Future<void> _insertTurn({
    required int id,
    required String question,
    required String answer,
    required List<AiCitation> citations,
    required String model,
    required int contractVersion,
    required int createdAt,
  }) async {
    await db.into(db.aiMessages).insert(AiMessagesCompanion.insert(
          conversationId: id,
          role: AiMessageRole.user.name,
          messageText: question,
          citationsJson: '[]',
          model: model,
          contractVersion: contractVersion,
          createdAt: createdAt,
        ));
    await db.into(db.aiMessages).insert(AiMessagesCompanion.insert(
          conversationId: id,
          role: AiMessageRole.assistant.name,
          messageText: answer,
          citationsJson:
              jsonEncode([for (final citation in citations) citation.toJson()]),
          model: model,
          contractVersion: contractVersion,
          createdAt: createdAt,
        ));
  }

  Future<void> delete(int id) =>
      (db.delete(db.aiConversations)..where((row) => row.id.equals(id))).go();

  Future<void> clear() => db.delete(db.aiConversations).go();

  AiConversationSnapshot _snapshot(AiConversationRow row) =>
      AiConversationSnapshot.restore(
        kind: row.kind,
        title: row.title,
        rangeStart: row.rangeStart,
        rangeEnd: row.rangeEnd,
        model: row.model,
        contractVersion: row.contractVersion,
        sourceJson: row.sourcesJson,
        sourceHash: row.sourcesHash,
        guideContextJson: row.guideContextJson,
        guideContextHash: row.guideContextHash,
      );

  List<AiCitation> _decodeCitations(String json) {
    final raw = jsonDecode(json);
    if (raw is! List || raw.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException(
          'Las citas guardadas no tienen un formato válido.');
    }
    return [
      for (final item in raw.cast<Map<String, dynamic>>())
        AiCitation.fromJson(item)
    ];
  }

  void _validateQuestion(String question) {
    if (question.trim().isEmpty || question.runes.length > 1000) {
      throw const FormatException(
          'La pregunta debe tener entre uno y mil caracteres.');
    }
  }

  String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class AiConversationRecord {
  const AiConversationRecord(
      {required this.row, required this.snapshot, required this.turns});

  final AiConversationRow row;
  final AiConversationSnapshot snapshot;
  final List<AiConversationTurn> turns;
}

class AiConversationTurn {
  const AiConversationTurn({
    required this.id,
    required this.role,
    required this.text,
    required this.citations,
    required this.model,
    required this.contractVersion,
    required this.createdAt,
  });

  final int id;
  final AiMessageRole role;
  final String text;
  final List<AiCitation> citations;
  final String model;
  final int contractVersion;
  final DateTime createdAt;
}

class AiConversationLimitException implements Exception {
  const AiConversationLimitException(this.message);
  final String message;
}

class AiHistoryLimitException implements Exception {
  const AiHistoryLimitException(this.message);
  final String message;
}
