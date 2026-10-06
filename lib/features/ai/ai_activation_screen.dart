import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../data/ai_gateway.dart';
import '../../data/weekly_ai.dart';
import 'ai_budget.dart';

/// Administra la licencia guardada por Keystore sin reemplazar la ruta actual.
class AiActivationScreen extends StatefulWidget {
  const AiActivationScreen({
    super.key,
    this.activation,
    this.clientFactory,
  });

  final AiActivation? activation;
  final http.Client Function()? clientFactory;

  @override
  State<AiActivationScreen> createState() => _AiActivationScreenState();
}

class _AiActivationScreenState extends State<AiActivationScreen> {
  final _license = TextEditingController();
  AiActivation get _activation => widget.activation ?? AiActivation();
  String? _hwid, _error, _status;
  AiQuota? _quota;
  bool _busy = false;
  int _generation = 0;
  http.Client? _client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = _generation;
    try {
      final (hwid, license) = await _activation.read();
      if (!mounted || generation != _generation) return;
      setState(() {
        _hwid = hwid;
        _license.text = license;
      });
      if (license.isNotEmpty) await _refreshStatus(hwid, license);
    } on Object {
      if (mounted) {
        setState(() =>
            _error = 'No se pudo abrir la activación segura de este teléfono.');
      }
    }
  }

  Future<void> _refreshStatus(String hwid, String license) async {
    final generation = ++_generation;
    _client?.close();
    final client = (widget.clientFactory ?? http.Client.new)();
    _client = client;
    try {
      final gateway = AiGatewayClient(client);
      final status = await gateway.status(hwid: hwid, license: license);
      if (mounted && generation == _generation) {
        setState(() {
          _quota = status.quota;
          _status = status.message;
        });
      }
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
  }

  Future<void> _save() async {
    final license = _license.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$').hasMatch(license)) {
      setState(() => _error =
          'Escribe la licencia de este teléfono: cuatro grupos de cuatro caracteres.');
      return;
    }
    setState(() {
      _generation++;
      _client?.close();
      _client = null;
      _busy = true;
      _error = null;
    });
    try {
      await _activation.save(license);
      if (!mounted) return;
      setState(() => _error = null);
      final hwid = _hwid;
      if (hwid != null) await _refreshStatus(hwid, license);
    } on Object {
      if (mounted) setState(() => _error = 'No se pudo guardar la licencia.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    setState(() {
      _generation++;
      _client?.close();
      _client = null;
      _busy = true;
      _error = null;
    });
    try {
      await _activation.save('');
      if (mounted) {
        setState(() {
          _license.clear();
          _quota = null;
          _status = 'Licencia quitada de este teléfono.';
        });
      }
    } on Object {
      if (mounted) setState(() => _error = 'No se pudo quitar la licencia.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyId() async {
    final id = _hwid;
    if (id == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Identificador copiado.')));
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'No se pudo copiar el identificador.');
      }
    }
  }

  void _back() => Navigator.of(context).pop();

  @override
  void dispose() {
    _generation++;
    _client?.close();
    _license.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) _back();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Activación de IA'),
            leading: IconButton(
                onPressed: _back,
                tooltip: 'Volver',
                icon: const Icon(Icons.arrow_back)),
          ),
          body: ListView(padding: const EdgeInsets.all(20), children: [
            const Text(
                'La licencia queda cifrada en este teléfono y se puede revocar desde Control360i.'),
            const SizedBox(height: 16),
            if (_hwid != null)
              SelectableText('Identificador del teléfono: $_hwid'),
            TextButton.icon(
                onPressed: _busy || _hwid == null ? null : _copyId,
                icon: const Icon(Icons.copy),
                label: const Text('Copiar identificador')),
            TextField(
                controller: _license,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                    labelText: 'Licencia de este teléfono')),
            Wrap(spacing: 8, children: [
              FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Guardar licencia')),
              TextButton(
                  onPressed: _busy ? null : _forget,
                  child: const Text('Olvidar licencia')),
            ]),
            if (_busy) const LinearProgressIndicator(),
            if (_status != null) ...[
              const SizedBox(height: 12),
              AiStatusPanel(status: _status, quota: _quota),
            ],
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!)),
          ]),
        ),
      );
}
