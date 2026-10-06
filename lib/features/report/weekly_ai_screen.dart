import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../data/weekly_ai.dart';

class WeeklyAiScreen extends StatefulWidget {
  const WeeklyAiScreen(
      {super.key, required this.report, this.activation, this.clientFactory});
  final String report;
  final AiActivation? activation;
  final http.Client Function()? clientFactory;
  @override
  State<WeeklyAiScreen> createState() => _WeeklyAiScreenState();
}

class _WeeklyAiScreenState extends State<WeeklyAiScreen> {
  final _license = TextEditingController();
  String? _hwid, _error;
  bool _consent = false, _busy = false;
  http.Client? _client;
  List<AiNote>? _notes;
  int _generation = 0;
  AiActivation get _activation => widget.activation ?? AiActivation();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (hwid, license) = await _activation.read();
      if (mounted) {
        setState(() {
          _hwid = hwid;
          _license.text = license;
        });
      }
    } on Object {
      if (mounted) {
        setState(() =>
            _error = 'No se pudo abrir la activación segura del teléfono.');
      }
    }
  }

  void _cancel() {
    _generation++;
    _client?.close();
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
    setState(() {
      _busy = true;
      _error = null;
      _notes = null;
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
    } on Object catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error =
            e is AiError ? e.message : 'No se pudo completar la consulta.');
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
    _client?.close();
    _license.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Analizar mi semana')),
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
          TextField(
              controller: _license,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                  labelText: 'Licencia de este teléfono')),
          TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        await _activation.save('');
                        if (mounted) setState(() => _license.clear());
                      } on Object {
                        if (mounted) {
                          setState(
                              () => _error = 'No se pudo quitar la licencia.');
                        }
                      }
                    },
              child: const Text('Olvidar licencia')),
          ExpansionTile(
              title: const Text('Ver exactamente qué se enviará'),
              children: [
                SelectableText(widget.report,
                    style: const TextStyle(fontSize: 12))
              ]),
          const Text(
              'Se envía este texto a Control360i y OpenAI. No se envían fotos ni la base. Control360i no conserva el informe ni la respuesta; OpenAI puede conservar registros de seguridad hasta 30 días. La consulta requiere internet.'),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consent,
              onChanged:
                  _busy ? null : (v) => setState(() => _consent = v ?? false),
              title:
                  const Text('Acepto enviar este informe para esta consulta')),
          FilledButton(
              onPressed: !_busy && _consent && _hwid != null ? _send : null,
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
            for (final note in _notes!)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                switch (note.kind) {
                                  'missing' => 'Dato faltante',
                                  'question' => 'Pregunta para revisar',
                                  _ => 'Observación'
                                },
                                style: Theme.of(context).textTheme.titleSmall),
                            Text(note.text),
                            const SizedBox(height: 8),
                            SelectableText('Del informe: ${note.quote}'),
                          ]))),
          ],
        ]),
      );
}
