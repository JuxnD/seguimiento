import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/ai_gateway.dart';
import '../../data/repositories/ai_conversation_repository.dart';
import '../../data/weekly_ai.dart';
import '../../domain/ai_context.dart';
import '../../domain/dates.dart';
import '../ai/ai_conversation_screen.dart';
import '../ai/ai_history_screen.dart';
import '../ai/ai_budget.dart';
import '../ai/ai_activation_screen.dart';

class WeeklyAiScreen extends StatefulWidget {
  const WeeklyAiScreen(
      {super.key,
      required this.report,
      this.activation,
      this.clientFactory,
      this.repository,
      this.rangeStart,
      this.rangeEnd});
  final String report;
  final AiActivation? activation;
  final http.Client Function()? clientFactory;
  final AiConversationRepository? repository;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  @override
  State<WeeklyAiScreen> createState() => _WeeklyAiScreenState();
}

class _WeeklyAiScreenState extends State<WeeklyAiScreen> {
  final _license = TextEditingController();
  String? _hwid, _error, _status;
  AiQuota? _quota;
  bool _enabled = false;
  bool _consent = false, _busy = false;
  http.Client? _client;
  http.Client? _statusClient;
  List<AiNote>? _notes;
  int? _savedConversationId;
  int _generation = 0;
  int _statusGeneration = 0;
  AiActivation get _activation => widget.activation ?? AiActivation();

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copiado con su evidencia.')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo copiar. Puedes seleccionar el texto.')));
      }
    }
  }

  Future<void> _share() async {
    final text = aiReviewText(_notes!);
    final box = context.findRenderObject() as RenderBox?;
    try {
      await Share.share(text,
          subject: 'Comentarios de IA · Seguimiento',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo compartir. Usa Copiar respuesta.')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _statusGeneration++;
    _statusClient?.close();
    try {
      final (hwid, license) = await _activation.read();
      if (mounted) {
        setState(() {
          _hwid = hwid;
          _license.text = license;
          _enabled = false;
          _status = null;
          _quota = null;
        });
        if (license.isNotEmpty) unawaited(_refreshStatus(hwid, license));
      }
    } on Object {
      if (mounted) {
        setState(() =>
            _error = 'No se pudo abrir la activación segura del teléfono.');
      }
    }
  }

  Future<void> _refreshStatus(String hwid, String license) async {
    final generation = ++_statusGeneration;
    _statusClient?.close();
    final client = (widget.clientFactory ?? http.Client.new)();
    _statusClient = client;
    try {
      final status =
          await AiGatewayClient(client).status(hwid: hwid, license: license);
      if (mounted && generation == _statusGeneration) {
        setState(() {
          _status = status.message;
          _quota = status.quota;
          _enabled = status.enabled;
        });
      }
    } finally {
      client.close();
      if (identical(_statusClient, client)) _statusClient = null;
    }
  }

  Future<void> _openActivation() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AiActivationScreen(
          activation: _activation,
          clientFactory: widget.clientFactory,
        ),
      ),
    );
    if (mounted) await _load();
  }

  void _cancel() {
    _generation++;
    _statusGeneration++;
    _client?.close();
    _statusClient?.close();
    _client = null;
    setState(() {
      _busy = false;
      _error = 'Consulta cancelada. No se cambió ningún registro.';
    });
  }

  Future<void> _send() async {
    final license = _license.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$').hasMatch(license)) {
      setState(() => _error =
          'Escribe la licencia de este teléfono: cuatro grupos de cuatro caracteres.');
      return;
    }
    final generation = ++_generation;
    _statusGeneration++;
    _statusClient?.close();
    setState(() {
      _busy = true;
      _error = null;
      _consent = false;
      _notes = null;
      _savedConversationId = null;
    });
    final client = (widget.clientFactory ?? http.Client.new)();
    _client = client;
    try {
      await _activation.save(license);
      // El usuario puede cancelar mientras se cifra la licencia.
      if (!mounted || generation != _generation) return;
      final notes =
          await WeeklyAi(client).analyze(widget.report, _hwid!, license);
      if (mounted && generation == _generation) setState(() => _notes = notes);
      if (mounted && generation == _generation && _hwid != null) {
        unawaited(_refreshStatus(_hwid!, license));
      }
      final repository = widget.repository;
      if (repository != null && mounted && generation == _generation) {
        try {
          final snapshot = AiConversationSnapshot(
            kind: AiConversationKind.weeklyAnalysis,
            title: widget.rangeStart == null || widget.rangeEnd == null
                ? 'Análisis semanal'
                : 'Informe · ${dayKey(widget.rangeStart!)} – ${dayKey(widget.rangeEnd!)}',
            rangeStart: widget.rangeStart,
            rangeEnd: widget.rangeEnd,
            sources: [
              AiContextSource(
                  id: 'report',
                  title: 'Informe seleccionado',
                  text: widget.report)
            ],
            model: 'gpt-6-luna',
            contractVersion: 1,
          );
          final id = await repository.createValidatedConversation(
            snapshot: snapshot,
            question: 'Analizar el informe seleccionado',
            answer:
                notes.map((note) => '${note.title}: ${note.text}').join('\n'),
            citations: [
              for (final note in notes)
                AiCitation(sourceId: 'report', quote: note.quote)
            ],
            turnModel: 'gpt-6-luna',
            turnContractVersion: 1,
          );
          if (mounted && generation == _generation) {
            setState(() => _savedConversationId = id);
          }
        } on Object {
          if (mounted && generation == _generation) {
            setState(() => _error =
                'La respuesta quedó visible y se puede copiar, pero no se guardó en el historial local.');
          }
        }
      }
    } on Object catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            e is AiError ? e.message : 'No se pudo completar la consulta.');
        if (e is AiError && _hwid != null) {
          unawaited(_refreshStatus(_hwid!, license));
        }
      }
    } finally {
      client.close();
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _client = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _statusGeneration++;
    _client?.close();
    _statusClient?.close();
    _license.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Analizar mi semana'),
          actions: [
            if (widget.repository != null)
              IconButton(
                tooltip: 'Historial de IA',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AiHistoryScreen())),
              ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
              'GPT-6 Luna revisa el informe seleccionado. Sus comentarios son propuestas: contrástalos con tus registros. No cambia tu plan ni da diagnósticos.'),
          const SizedBox(height: 16),
          const Text('Activación en Control360i'),
          if (_hwid != null)
            SelectableText('Identificador del teléfono: $_hwid'),
          TextButton.icon(
              onPressed: _hwid == null
                  ? null
                  : () => Clipboard.setData(ClipboardData(text: _hwid!)),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar identificador para activar')),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openActivation,
            icon: const Icon(Icons.key_outlined),
            label: const Text('Revisar activación de IA'),
          ),
          ExpansionTile(
              title: const Text('Ver exactamente qué se enviará'),
              children: [
                SelectableText(widget.report,
                    style: const TextStyle(fontSize: 12))
              ]),
          const Text(
              'Se envía este texto a Control360i y OpenAI. No se envían fotos ni la base. Control360i no conserva el informe ni la respuesta. OpenAI conserva registros de seguridad normalmente hasta 30 días, con excepciones legales o de seguridad. La consulta requiere internet.'),
          TextButton(
              onPressed: () => launchUrl(
                  Uri.parse(
                      'https://developers.openai.com/api/docs/guides/your-data'),
                  mode: LaunchMode.externalApplication),
              child: const Text('Consultar política de datos de OpenAI')),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consent,
              onChanged:
                  _busy ? null : (v) => setState(() => _consent = v ?? false),
              title:
                  const Text('Acepto enviar este informe para esta consulta')),
          AiStatusPanel(status: _status, quota: _quota),
          FilledButton(
              onPressed: !_busy &&
                      _consent &&
                      _hwid != null &&
                      _enabled &&
                      (_quota?.remaining ?? 1) > 0
                  ? _send
                  : null,
              child: Text(_busy ? 'Analizando…' : 'Enviar y analizar')),
          if (_busy) ...[
            const LinearProgressIndicator(),
            TextButton(onPressed: _cancel, child: const Text('Cancelar'))
          ],
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!)),
          if (_notes != null) ...[
            const Text('Comentarios de IA · verifica la evidencia'),
            if (_savedConversationId != null && widget.repository != null)
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AiConversationScreen.forConversation(
                      repository: widget.repository!,
                      conversationId: _savedConversationId!,
                      activation: _activation,
                      clientFactory: widget.clientFactory,
                    ),
                  ),
                ),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Preguntar sobre estos comentarios'),
              ),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                  onPressed: () => _copy(aiReviewText(_notes!)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar respuesta')),
              TextButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Compartir respuesta')),
            ]),
            for (final note in _notes!)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(note.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall)),
                              IconButton(
                                  tooltip: 'Copiar comentario',
                                  icon: const Icon(Icons.copy_outlined),
                                  onPressed: () => _copy(note.copyText)),
                            ]),
                            SelectableText(note.text),
                            const SizedBox(height: 8),
                            SelectableText('Del informe: ${note.quote}'),
                          ]))),
          ],
        ]),
      );
}
