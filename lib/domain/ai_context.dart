import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'search.dart';

const aiQuestionModel = 'gpt-6-luna';
const aiQuestionContractVersion = 2;
const aiMaxQuestionBytes = 48000;
const aiMaxHistoryCharacters = 4000;

enum AiConversationKind { weeklyAnalysis, reportQuestion, exerciseQuestion }

enum AiMessageRole { user, assistant }

/// Parámetros locales necesarios para reabrir exactamente la variante de guía.
/// Nunca se serializan en la solicitud al gateway.
class AiGuideContext {
  AiGuideContext({
    required this.exercise,
    required List<String> cues,
    this.progressionNote,
    this.anchor,
    this.grip,
    this.loaded,
  }) : cues = List.unmodifiable(cues) {
    _validate();
  }

  final String exercise;
  final List<String> cues;
  final String? progressionNote;
  final String? anchor;
  final String? grip;
  final bool? loaded;

  Map<String, Object?> toJson() => {
        'exercise': exercise,
        'cues': cues,
        'progressionNote': progressionNote,
        'anchor': anchor,
        'grip': grip,
        'loaded': loaded,
      };

  factory AiGuideContext.fromJson(Map<String, dynamic> json) {
    if (json.keys.toSet().difference({
          'exercise',
          'cues',
          'progressionNote',
          'anchor',
          'grip',
          'loaded'
        }).isNotEmpty ||
        json['exercise'] is! String ||
        json['cues'] is! List ||
        (json['progressionNote'] != null &&
            json['progressionNote'] is! String) ||
        (json['anchor'] != null && json['anchor'] is! String) ||
        (json['grip'] != null && json['grip'] is! String) ||
        (json['loaded'] != null && json['loaded'] is! bool) ||
        (json['cues'] as List).any((cue) => cue is! String)) {
      throw const FormatException(
          'El contexto de guía no tiene un formato válido.');
    }
    return AiGuideContext(
      exercise: json['exercise'] as String,
      cues: (json['cues'] as List).cast<String>(),
      progressionNote: json['progressionNote'] as String?,
      anchor: json['anchor'] as String?,
      grip: json['grip'] as String?,
      loaded: json['loaded'] as bool?,
    );
  }

  void _validate() {
    if (exercise.trim().isEmpty ||
        exercise.length > 120 ||
        cues.length > 30 ||
        cues.any((cue) => cue.trim().isEmpty || cue.length > 500) ||
        (progressionNote?.length ?? 0) > 1000 ||
        (anchor != null &&
            !{'alto', 'medio', 'bajo', 'manos'}.contains(anchor)) ||
        (grip != null && !{'prona', 'supina'}.contains(grip))) {
      throw const FormatException(
          'Los parámetros locales de guía no son válidos.');
    }
  }
}

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
    this.guideContext,
    this.rangeStart,
    this.rangeEnd,
  })  : sources = List.unmodifiable(sources),
        sourceJson =
            jsonEncode([for (final source in sources) source.toJson()]),
        sourceHash = sha256
            .convert(utf8.encode(
                jsonEncode([for (final source in sources) source.toJson()])))
            .toString() {
    guideContextJson =
        guideContext == null ? null : jsonEncode(guideContext!.toJson());
    guideContextHash = guideContextJson == null
        ? null
        : sha256.convert(utf8.encode(guideContextJson!)).toString();
    _validateMetadata(
        title: title,
        model: model,
        contractVersion: contractVersion,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd);
    validateAiSources(sources);
    _validateGuideBinding(kind, this.sources, guideContext);
  }

  AiConversationSnapshot._({
    required this.kind,
    required this.title,
    required List<AiContextSource> sources,
    required this.model,
    required this.contractVersion,
    required this.sourceJson,
    required this.sourceHash,
    required this.guideContext,
    required this.guideContextJson,
    required this.guideContextHash,
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
    _validateGuideBinding(kind, this.sources, guideContext);
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
  final AiGuideContext? guideContext;
  late final String? guideContextJson;
  late final String? guideContextHash;

  static AiConversationSnapshot restore({
    required String kind,
    required String title,
    required String? rangeStart,
    required String? rangeEnd,
    required String model,
    required int contractVersion,
    required String sourceJson,
    required String sourceHash,
    String? guideContextJson,
    String? guideContextHash,
  }) {
    if (sha256.convert(utf8.encode(sourceJson)).toString() != sourceHash) {
      throw const FormatException(
          'El contexto guardado cambió y no puede verificarse.');
    }
    final raw = jsonDecode(sourceJson);
    AiGuideContext? guideContext;
    if ((guideContextJson == null) != (guideContextHash == null)) {
      throw const FormatException('La metadata de guía está incompleta.');
    }
    if (guideContextJson != null) {
      if (sha256.convert(utf8.encode(guideContextJson)).toString() !=
          guideContextHash) {
        throw const FormatException('La variante de guía guardada cambió.');
      }
      final decodedGuide = jsonDecode(guideContextJson);
      if (decodedGuide is! Map<String, dynamic>) {
        throw const FormatException('La variante de guía no es válida.');
      }
      guideContext = AiGuideContext.fromJson(decodedGuide);
    }
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
      guideContext: guideContext,
      guideContextJson: guideContextJson,
      guideContextHash: guideContextHash,
    );
  }
}

void _validateGuideBinding(AiConversationKind kind,
    List<AiContextSource> sources, AiGuideContext? guideContext) {
  if (guideContext == null) return;
  if (kind != AiConversationKind.exerciseQuestion ||
      !sources.any((source) =>
          source.id == 'exercise_guide:${nameKey(guideContext.exercise)}')) {
    throw const FormatException('La guía guardada no coincide con su fuente.');
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
