import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../../data/ai_gateway.dart';
import '../../data/repositories/ai_conversation_repository.dart';
import '../../domain/ai_context.dart';
import '../../domain/dates.dart';
import '../../data/weekly_ai.dart' show AiActivation;
import '../../data/exercise_details.dart';
import '../../domain/search.dart';
import 'ai_activation_screen.dart';
import 'ai_budget.dart';
import '../training/technique_sheet.dart';

class AiConversationScreen extends StatefulWidget {
  const AiConversationScreen.forQuestion({
    super.key,
    required this.repository,
    required this.snapshot,
    this.activation,
    this.clientFactory,
  }) : conversationId = null;

  const AiConversationScreen.forConversation({
    super.key,
    required this.repository,
    required this.conversationId,
    this.activation,
    this.clientFactory,
  }) : snapshot = null;

  final AiConversationRepository repository;
  final AiConversationSnapshot? snapshot;
  final int? conversationId;
  final AiActivation? activation;
  final http.Client Function()? clientFactory;

  @override
  State<AiConversationScreen> createState() => _AiConversationScreenState();
}

class _AiConversationScreenState extends State<AiConversationScreen> {
  final _question = TextEditingController();
  AiConversationSnapshot? _snapshot;
  AiConversationRecord? _record;
  bool _loadingConversation = false;
  String? _hwid, _license, _error;
  AiQuota? _quota;
  bool _consent = false, _busy = false, _persisting = false;
  int _generation = 0;
  http.Client? _client;

  AiActivation get _activation => widget.activation ?? AiActivation();
  List<AiConversationTurn> get _turns => _record?.turns ?? const [];

  @override
  void initState() {
    super.initState();
    _snapshot = widget.snapshot;
    _loadingConversation = widget.conversationId != null;
    _loadConversation();
    _loadActivation();
  }

  Future<void> _loadConversation() async {
    final id = widget.conversationId;
    if (id == null) return;
    try {
      final record = await widget.repository.read(id);
      if (mounted) {
        setState(() {
          _record = record;
          _snapshot = record?.snapshot;
          if (record == null) {
            _error = 'La conversación ya no existe en este teléfono.';
          }
          _loadingConversation = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'El contexto guardado no pasó la verificación local.';
          _loadingConversation = false;
        });
      }
    }
  }

  Future<void> _loadActivation() async {
    try {
      final (hwid, license) = await _activation.read();
      if (!mounted) return;
      setState(() {
        _hwid = hwid;
        _license = license;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'No se pudo leer la activación segura.');
      }
    }
  }

  Future<void> _openActivation() async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => AiActivationScreen(activation: _activation)));
    if (mounted) await _loadActivation();
  }

  List<AiStoredTurn> _history() => [
        for (final turn in _turns)
          AiStoredTurn(
              role: turn.role, text: turn.text, citations: turn.citations),
      ];

  Map<String, Object?>? _requestInput() {
    final snapshot = _snapshot;
    final question = _question.text.trim();
    if (snapshot == null || question.isEmpty) return null;
    try {
      validateAiSources(snapshot.sources);
      final input = <String, Object?>{
        'question': question,
        'sources': [for (final source in snapshot.sources) source.toJson()],
        'history': aiHistoryForRequest(_history()),
      };
      if (utf8.encode(jsonEncode(input['sources'])).length >
          aiMaxQuestionBytes) {
        throw const FormatException(
            'El contexto supera el límite. Elige un rango más corto.');
      }
      return input;
    } on FormatException {
      return null;
    }
  }

  void _cancel() {
    _generation++;
    _client?.close();
    _client = null;
    setState(() {
      _busy = false;
      _persisting = false;
      _consent = false;
      _error = 'Consulta cancelada. No se guardó una conversación nueva.';
    });
  }

  Future<void> _send() async {
    final snapshot = _snapshot;
    final input = _requestInput();
    if (snapshot == null || input == null) {
      setState(() {});
      return;
    }
    final hwid = _hwid, license = _license;
    if (hwid == null || license == null || license.isEmpty) {
      setState(
          () => _error = 'Activa la IA en este teléfono antes de consultar.');
      return;
    }
    if (!RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$')
        .hasMatch(license.toUpperCase())) {
      setState(() => _error =
          'La licencia guardada no tiene un formato válido. Revisa la activación.');
      return;
    }
    final question = _question.text.trim();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _persisting = false;
      _error = null;
      _consent = false;
    });
    final client = (widget.clientFactory ?? http.Client.new)();
    _client = client;
    final gateway = AiGatewayClient(client);
    try {
      final result = await gateway.assist(
        task: snapshot.kind == AiConversationKind.exerciseQuestion
            ? 'exercise_question'
            : 'report_question',
        input: input,
        hwid: hwid,
        license: license.toUpperCase(),
      );
      final parsed = _parseResult(result);
      validateAiAnswer(
        snapshot: snapshot,
        answer: parsed.$1,
        citations: parsed.$2,
        contractVersion: aiQuestionContractVersion,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _quota = gateway.lastQuota;
        _persisting = true;
      });
      var id = _record?.row.id;
      if (id == null) {
        id = await widget.repository.createValidatedConversation(
          snapshot: snapshot,
          question: question,
          answer: parsed.$1,
          citations: parsed.$2,
          turnModel: aiQuestionModel,
          turnContractVersion: aiQuestionContractVersion,
        );
      } else {
        await widget.repository.appendValidatedTurn(
          conversationId: id,
          question: question,
          answer: parsed.$1,
          citations: parsed.$2,
        );
      }
      final record = await widget.repository.read(id);
      if (mounted && generation == _generation) {
        setState(() {
          _record = record;
          _snapshot = record?.snapshot ?? snapshot;
          _question.clear();
          _error = null;
        });
      }
    } on AiError catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _quota = e.quota ?? gateway.lastQuota;
          _error = e.message;
        });
      }
    } on FormatException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } on AiHistoryLimitException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _error = 'No se pudo guardar la respuesta verificada.');
      }
    } finally {
      client.close();
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _persisting = false;
          _client = null;
        });
      }
    }
  }

  (String, List<AiCitation>) _parseResult(Map<String, dynamic> result) {
    if (result.keys.toSet().difference({'answer', 'citations'}).isNotEmpty ||
        result['answer'] is! String ||
        result['citations'] is! List) {
      throw const FormatException(
          'La respuesta no tiene los campos esperados.');
    }
    final raw = result['citations'] as List;
    if (raw.isEmpty || raw.length > 6) {
      throw const FormatException('La respuesta no trajo citas verificables.');
    }
    final citations = <AiCitation>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic> ||
          item.keys.toSet().difference({'source_id', 'quote'}).isNotEmpty ||
          item['source_id'] is! String ||
          item['quote'] is! String) {
        throw const FormatException('Una cita no tiene el formato esperado.');
      }
      citations.add(AiCitation(
          sourceId: item['source_id'] as String,
          quote: item['quote'] as String));
    }
    return (result['answer'] as String, citations);
  }

  String _shareText() {
    final snapshot = _snapshot;
    if (snapshot == null) return '';
    final sourceTitles = {
      for (final source in snapshot.sources) source.id: source.title
    };
    return [
      snapshot.title,
      if (snapshot.rangeStart != null && snapshot.rangeEnd != null)
        '${formatShort(snapshot.rangeStart!)} – ${formatShort(snapshot.rangeEnd!)}',
      for (final turn in _turns)
        '${turn.role == AiMessageRole.user ? 'Pregunta' : 'Respuesta'}:\n${turn.text}'
            '${turn.role == AiMessageRole.assistant ? '\n${turn.citations.map((citation) => 'Del ${sourceTitles[citation.sourceId] ?? citation.sourceId}: “${citation.quote}”').join('\n')}' : ''}',
    ].join('\n\n');
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _shareText()));
    if (mounted) _snack('Conversación copiada con sus fuentes.');
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(_shareText(),
        subject: 'Consulta de IA · Seguimiento',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size);
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String? _exerciseForGuide(AiConversationSnapshot? snapshot) {
    if (snapshot?.kind != AiConversationKind.exerciseQuestion) return null;
    for (final source in snapshot!.sources) {
      const prefix = 'exercise_guide:';
      if (!source.id.startsWith(prefix)) continue;
      final key = source.id.substring(prefix.length);
      for (final name in exerciseDetails.keys) {
        if (nameKey(name) == key) return name;
      }
    }
    return null;
  }

  void _openGuide() {
    final exercise = _exerciseForGuide(_snapshot);
    if (exercise == null) return;
    if (widget.conversationId == null) {
      Navigator.pop(context);
    } else {
      showTechniqueSheet(context, exercise: exercise);
    }
  }

  @override
  void dispose() {
    _generation++;
    _client?.close();
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final ready = snapshot != null;
    final input = _requestInput();
    final exercise = _exerciseForGuide(snapshot);
    final contextTooLarge = snapshot != null &&
        utf8.encode(snapshot.sourceJson).length > aiMaxQuestionBytes;
    final canContinue =
        _turns.where((turn) => turn.role == AiMessageRole.user).length < 20;
    return Scaffold(
      appBar: AppBar(
        title: Text(snapshot?.kind == AiConversationKind.exerciseQuestion
            ? 'Preguntar sobre ejercicio'
            : 'Preguntar sobre informe'),
        actions: [
          IconButton(
              tooltip: 'Copiar conversación',
              onPressed: _turns.isEmpty ? null : _copy,
              icon: const Icon(Icons.copy_outlined)),
          IconButton(
              tooltip: 'Compartir conversación',
              onPressed: _turns.isEmpty ? null : _share,
              icon: const Icon(Icons.share_outlined)),
        ],
      ),
      body: !ready
          ? _loadingConversation
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error ?? 'No se pudo abrir esta conversación.'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Volver al historial'),
                        ),
                      ],
                    ),
                  ),
                )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Text(snapshot.title,
                    style: Theme.of(context).textTheme.titleLarge),
                if (snapshot.rangeStart != null && snapshot.rangeEnd != null)
                  Text(
                      '${formatShort(snapshot.rangeStart!)} – ${formatShort(snapshot.rangeEnd!)}'),
                const SizedBox(height: 8),
                const Text(
                    'La respuesta usa únicamente las fuentes visibles. No modifica registros ni hace diagnósticos.'),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Vista previa exacta de lo que se enviará'),
                  children: [
                    if (_question.text.trim().isNotEmpty) ...[
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Pregunta')),
                      SelectableText(_question.text.trim()),
                    ],
                    for (final source in snapshot.sources) ...[
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text(source.title,
                              style: Theme.of(context).textTheme.titleSmall)),
                      SelectableText(source.text),
                      const SizedBox(height: 10),
                    ],
                    if (_turns.isNotEmpty) ...[
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Historial que acompaña la pregunta')),
                      for (final pair in aiHistoryForRequest(_history()))
                        SelectableText(
                            'Pregunta: ${pair['question']}\nRespuesta: ${pair['answer']}'),
                    ],
                  ],
                ),
                for (final turn in _turns)
                  _TurnView(
                    turn: turn,
                    snapshot: snapshot,
                    onOpenGuide: exercise == null ? null : _openGuide,
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _question,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 5,
                  enabled: !_busy && canContinue,
                  onChanged: (_) => setState(() {
                    _consent = false;
                    _error = null;
                  }),
                  decoration: const InputDecoration(
                    labelText: 'Tu pregunta',
                    hintText:
                        'Pregunta por los datos que aparecen en las fuentes',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (contextTooLarge)
                  const Text(
                      'El contexto supera el límite. Selecciona un rango más corto antes de consultar.'),
                if (!canContinue)
                  const Text(
                      'Esta conversación llegó al límite de veinte preguntas. Puedes abrir otra desde el informe.'),
                if (snapshot.sources.length == 2 &&
                    utf8.encode(snapshot.sourceJson).length >
                        aiMaxQuestionBytes)
                  const Text(
                      'El contexto supera el límite. Selecciona un rango más corto antes de consultar.'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _consent,
                  onChanged: _busy || input == null
                      ? null
                      : (value) => setState(() => _consent = value ?? false),
                  title: const Text(
                      'Acepto enviar esta pregunta, las fuentes y el historial mostrado'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openActivation,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Revisar activación de IA'),
                ),
                AiBudget(quota: _quota),
                FilledButton.icon(
                  onPressed: !_busy &&
                          _consent &&
                          _hwid != null &&
                          (_license?.isNotEmpty ?? false) &&
                          (_quota?.remaining ?? 1) > 0 &&
                          canContinue
                      ? _send
                      : null,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(_busy
                      ? (_persisting
                          ? 'Guardando respuesta verificada…'
                          : 'Consultando…')
                      : 'Enviar pregunta'),
                ),
                if (_busy && !_persisting) ...[
                  const LinearProgressIndicator(),
                  TextButton(
                      onPressed: _cancel,
                      child: const Text('Cancelar consulta')),
                ],
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!)),
              ],
            ),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView(
      {required this.turn, required this.snapshot, this.onOpenGuide});

  final AiConversationTurn turn;
  final AiConversationSnapshot snapshot;
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final sourceTitles = {
      for (final source in snapshot.sources) source.id: source.title
    };
    final isUser = turn.role == AiMessageRole.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isUser ? 'Pregunta' : 'Respuesta de IA · revisa sus fuentes',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(turn.text),
          for (final citation in turn.citations) ...[
            const SizedBox(height: 6),
            Text(
                'De ${sourceTitles[citation.sourceId] ?? citation.sourceId}: “${citation.quote}”'),
            if (snapshot.kind == AiConversationKind.exerciseQuestion &&
                onOpenGuide != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenGuide,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Ver guía completa'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
