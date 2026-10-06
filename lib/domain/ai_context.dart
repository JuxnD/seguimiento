import 'dart:convert';

import 'package:crypto/crypto.dart';

const aiQuestionModel = 'gpt-6-luna';
const aiQuestionContractVersion = 2;
const aiMaxQuestionBytes = 48000;
const aiMaxHistoryCharacters = 4000;

enum AiConversationKind { weeklyAnalysis, reportQuestion, exerciseQuestion }

enum AiMessageRole { user, assistant }

class AiContextSource {
  const AiContextSource(
      {required this.id, required this.title, required this.text});

  final String id;
  final String title;
  final String text;

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'text': text};

  factory AiContextSource.fromJson(Map<String, dynamic> json) =>
      AiContextSource(
        id: json['id'] as String,
        title: json['title'] as String,
        text: json['text'] as String,
      );
}

class AiCitation {
  const AiCitation({required this.sourceId, required this.quote});

  final String sourceId;
  final String quote;

  Map<String, Object?> toJson() => {'source_id': sourceId, 'quote': quote};

  factory AiCitation.fromJson(Map<String, dynamic> json) => AiCitation(
        sourceId: json['source_id'] as String,
        quote: json['quote'] as String,
      );
}

/// Datos de origen de una conversación, congelados antes de salir del dispositivo.
/// El hash cubre el JSON exacto de las fuentes, con orden de campos estable.
class AiConversationSnapshot {
  AiConversationSnapshot({
    required this.kind,
    required this.title,
    required List<AiContextSource> sources,
    required this.model,
    required this.contractVersion,
    this.rangeStart,
    this.rangeEnd,
  })  : sources = List.unmodifiable(sources),
        sourceJson =
            jsonEncode([for (final source in sources) source.toJson()]),
        sourceHash = sha256
            .convert(utf8.encode(
                jsonEncode([for (final source in sources) source.toJson()])))
            .toString() {
    _validateMetadata(
        title: title,
        model: model,
        contractVersion: contractVersion,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd);
    validateAiSources(sources);
  }

  AiConversationSnapshot._({
    required this.kind,
    required this.title,
    required List<AiContextSource> sources,
    required this.model,
    required this.contractVersion,
    required this.sourceJson,
    required this.sourceHash,
    this.rangeStart,
    this.rangeEnd,
  }) : sources = List.unmodifiable(sources) {
    _validateMetadata(
        title: title,
        model: model,
        contractVersion: contractVersion,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd);
    validateAiSources(sources);
  }

  final AiConversationKind kind;
  final String title;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final List<AiContextSource> sources;
  final String model;
  final int contractVersion;
  final String sourceJson;
  final String sourceHash;

  static AiConversationSnapshot restore({
    required String kind,
    required String title,
    required String? rangeStart,
    required String? rangeEnd,
    required String model,
    required int contractVersion,
    required String sourceJson,
    required String sourceHash,
  }) {
    if (sha256.convert(utf8.encode(sourceJson)).toString() != sourceHash) {
      throw const FormatException(
          'El contexto guardado cambió y no puede verificarse.');
    }
    final raw = jsonDecode(sourceJson);
    if (raw is! List || raw.any((e) => e is! Map<String, dynamic>)) {
      throw const FormatException(
          'El contexto guardado no tiene un formato válido.');
    }
    for (final item in raw.cast<Map<String, dynamic>>()) {
      if (item.keys.length != 3 ||
          item.keys.toSet().difference({'id', 'title', 'text'}).isNotEmpty) {
        throw const FormatException(
            'El contexto guardado contiene campos desconocidos.');
      }
    }
    AiConversationKind? parsedKind;
    for (final value in AiConversationKind.values) {
      if (value.name == kind) parsedKind = value;
    }
    if (parsedKind == null) {
      throw const FormatException('El tipo de conversación no es válido.');
    }
    final start = _parseDate(rangeStart), end = _parseDate(rangeEnd);
    if ((rangeStart != null && start == null) ||
        (rangeEnd != null && end == null) ||
        (start != null && end != null && end.isBefore(start))) {
      throw const FormatException('El rango guardado no es válido.');
    }
    return AiConversationSnapshot._(
      kind: parsedKind,
      title: title,
      rangeStart: start,
      rangeEnd: end,
      sources: [
        for (final item in raw.cast<Map<String, dynamic>>())
          AiContextSource.fromJson(item)
      ],
      model: model,
      contractVersion: contractVersion,
      sourceJson: sourceJson,
      sourceHash: sourceHash,
    );
  }
}

void _validateMetadata({
  required String title,
  required String model,
  required int contractVersion,
  required DateTime? rangeStart,
  required DateTime? rangeEnd,
}) {
  if (title.trim().isEmpty || title.length > 120) {
    throw const FormatException('El título del contexto no es válido.');
  }
  if (model.trim().isEmpty || contractVersion < 1) {
    throw const FormatException('La versión del contexto no es válida.');
  }
  if (rangeStart != null && rangeEnd != null && rangeEnd.isBefore(rangeStart)) {
    throw const FormatException('El rango del contexto no es válido.');
  }
}

void validateAiSources(List<AiContextSource> sources) {
  if (sources.isEmpty || sources.length > 2) {
    throw const FormatException('Elige una o dos fuentes para consultar.');
  }
  final ids = <String>{};
  for (final source in sources) {
    if (source.id.trim().isEmpty ||
        !ids.add(source.id) ||
        source.title.trim().isEmpty ||
        source.text.trim().isEmpty) {
      throw const FormatException(
          'Una fuente está vacía o tiene un identificador repetido.');
    }
  }
  final bytes = utf8
      .encode(jsonEncode([for (final source in sources) source.toJson()]))
      .length;
  if (bytes > aiMaxQuestionBytes) {
    throw const FormatException(
        'El contexto supera el límite. Elige un rango más corto.');
  }
}

/// Rechaza citas inventadas incluso si el envelope remoto era válido.
void validateAiAnswer({
  required AiConversationSnapshot snapshot,
  required String answer,
  required List<AiCitation> citations,
  required int contractVersion,
}) {
  final limit = contractVersion == aiQuestionContractVersion ? 1500 : 2500;
  if (answer.trim().isEmpty ||
      answer.runes.length > limit ||
      citations.isEmpty ||
      citations.length > 6) {
    throw const FormatException('La respuesta no pasó la verificación local.');
  }
  if (contractVersion == aiQuestionContractVersion &&
      RegExp(r'\d').hasMatch(answer)) {
    throw const FormatException(
        'La respuesta incluye cifras fuera de las citas.');
  }
  final sources = {for (final source in snapshot.sources) source.id: source};
  for (final citation in citations) {
    final source = sources[citation.sourceId];
    if (source == null ||
        citation.quote.trim().isEmpty ||
        citation.quote.runes.length > 500 ||
        !source.text.contains(citation.quote)) {
      throw const FormatException(
          'Una cita no coincide con la fuente guardada.');
    }
  }
}

/// Historial de cuatro pares, recortado solo entre pares y sin superar el
/// límite de puntos Unicode del gateway.
List<Map<String, String>> aiHistoryForRequest(List<AiStoredTurn> turns) {
  final pairs = <(String, String)>[];
  String? question;
  for (final turn in turns) {
    if (turn.role == AiMessageRole.user) {
      question = turn.text;
    } else if (question != null) {
      pairs.add((question, turn.text));
      question = null;
    }
  }
  final selected = pairs.skip(pairs.length > 4 ? pairs.length - 4 : 0).toList();
  while (selected.isNotEmpty &&
      selected.fold<int>(
              0,
              (sum, pair) =>
                  sum + pair.$1.runes.length + pair.$2.runes.length) >
          aiMaxHistoryCharacters) {
    selected.removeAt(0);
  }
  return [
    for (final (q, a) in selected) {'question': q, 'answer': a}
  ];
}

DateTime? _parseDate(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

class AiStoredTurn {
  const AiStoredTurn(
      {required this.role, required this.text, required this.citations});

  final AiMessageRole role;
  final String text;
  final List<AiCitation> citations;
}
