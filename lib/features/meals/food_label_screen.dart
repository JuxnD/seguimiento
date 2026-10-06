import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../data/meal_assistant.dart';
import '../../data/meal_photo_ai.dart';
import '../../data/weekly_ai.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../ai/ai_activation_screen.dart';
import '../ai/ai_budget.dart';

/// A transient label proposal. It is not a FoodRow and has no persistence API.
class FoodLabelDraft {
  const FoodLabelDraft({
    required this.name,
    required this.basis,
    required this.unitLabel,
    required this.defaultQuantity,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.uncertainties,
    required this.sourceSnapshot,
    required this.convertedToPer100,
    required this.portionNeedsConfirmation,
  });

  final String? name;
  final FoodBasis? basis;
  final String unitLabel;
  final double? defaultQuantity;
  final double? kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
  final List<String> uncertainties;
  final FoodLabelProposal sourceSnapshot;
  final bool convertedToPer100;
  final bool portionNeedsConfirmation;
}

class FoodLabelScreen extends StatefulWidget {
  const FoodLabelScreen(
      {super.key, this.activation, this.clientFactory, this.pickPhoto});

  final AiActivation? activation;
  final http.Client Function()? clientFactory;
  final Future<Uint8List?> Function(ImageSource)? pickPhoto;

  @override
  State<FoodLabelScreen> createState() => _FoodLabelScreenState();
}

class _FoodLabelScreenState extends State<FoodLabelScreen> {
  Uint8List? _photo;
  bool _consent = false, _busy = false, _converted = false, _enabled = false;
  String? _hwid, _license, _error;
  AiQuota? _quota;
  int _generation = 0, _activationGeneration = 0, _statusGeneration = 0;
  http.Client? _client, _statusClient;
  FoodLabelProposal? _proposal;

  AiActivation get _activation => widget.activation ?? AiActivation();

  @override
  void initState() {
    super.initState();
    _loadActivation();
  }

  Future<void> _loadActivation() async {
    final generation = ++_activationGeneration;
    _statusGeneration++;
    _statusClient?.close();
    _statusClient = null;
    if (mounted) {
      setState(() {
        _enabled = false;
        _quota = null;
      });
    }
    try {
      final (hwid, license) = await _activation.read();
      if (!mounted || generation != _activationGeneration) return;
      setState(() {
        _hwid = hwid;
        _license = license;
      });
      if (license.isNotEmpty) {
        await _refreshStatus(hwid, license, activationGeneration: generation);
      }
    } on Object {
      if (mounted && generation == _activationGeneration) {
        setState(() => _error = 'No se pudo abrir la activación segura.');
      }
    }
  }

  Future<void> _refreshStatus(String hwid, String license,
      {required int activationGeneration}) async {
    final generation = ++_statusGeneration;
    _statusClient?.close();
    final client = (widget.clientFactory ?? http.Client.new)();
    _statusClient = client;
    try {
      final assistant = MealAssistant(client);
      final result = await assistant.gateway.assist(
          task: 'status', input: const {}, hwid: hwid, license: license);
      if (mounted &&
          generation == _statusGeneration &&
          activationGeneration == _activationGeneration) {
        setState(() {
          _quota = assistant.lastQuota;
          _enabled = result['enabled'] == true;
        });
      }
    } on AiError catch (e) {
      if (mounted &&
          generation == _statusGeneration &&
          activationGeneration == _activationGeneration) {
        setState(() {
          _quota = e.quota ?? _quota;
          _enabled = false;
        });
      }
    } on Object {
      // The status is informational; reading a label remains an explicit action.
    } finally {
      client.close();
      if (identical(_statusClient, client)) _statusClient = null;
    }
  }

  Future<void> _openActivation() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => AiActivationScreen(
            activation: widget.activation,
            clientFactory: widget.clientFactory)));
    if (mounted) await _loadActivation();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Uint8List? raw;
      if (widget.pickPhoto != null) {
        raw = await widget.pickPhoto!(source);
      } else {
        final file = await ImagePicker().pickImage(
            source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 80);
        if (file != null) {
          if (await file.length() > 8 * 1024 * 1024) {
            throw const AiError('Elige una foto de hasta 8 MB.');
          }
          raw = await file.readAsBytes();
        }
      }
      if (raw == null || !mounted) return;
      final photo = await prepareMealPhoto(raw);
      if (mounted) {
        setState(() {
          _photo = photo;
          _consent = false;
          _proposal = null;
          _converted = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e is AiError
            ? e.message
            : 'No se pudo abrir la cámara o galería. El catálogo sigue disponible.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze() async {
    final photo = _photo;
    final hwid = _hwid;
    final license = _license;
    if (photo == null ||
        hwid == null ||
        license == null ||
        license.isEmpty ||
        !_consent) return;
    final generation = ++_generation;
    final client = (widget.clientFactory ?? http.Client.new)();
    _client = client;
    setState(() {
      _busy = true;
      _error = null;
      _proposal = null;
    });
    try {
      final assistant = MealAssistant(client);
      final proposal = await assistant.readFoodLabel(
          photo: photo, hwid: hwid, license: license);
      if (!mounted || generation != _generation) return;
      setState(() {
        _proposal = proposal;
        _quota = assistant.lastQuota;
      });
    } on AiError catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e.message;
          _quota = e.quota ?? _quota;
        });
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _error =
            'No se pudo leer la etiqueta. Puedes completar el alimento a mano.');
      }
    } finally {
      client.close();
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          if (identical(_client, client)) _client = null;
        });
      }
    }
  }

  double? _per100(double? value) {
    final serving = _proposal?.servingQuantity;
    if (!_converted || value == null || serving == null || serving <= 0) {
      return value;
    }
    return value * 100 / serving;
  }

  String _basisLabel(String? basis, String? unit) => switch (basis) {
        'per100' => 'Por 100 ${unit ?? '(unidad no identificada)'}',
        'portion' => 'Por porción',
        _ => 'No identificada',
      };

  FoodLabelDraft _toDraft() {
    final p = _proposal!;
    final per100 = p.basis == 'per100' || _converted;
    final unit = p.unit;
    final serving = p.servingQuantity;
    final FoodBasis? basis = per100
        ? FoodBasis.per100
        : p.basis == 'portion'
            ? FoodBasis.unit
            : null;
    final unitLabel = per100
        ? (unit ?? '')
        : p.basis == 'portion' && serving != null
            ? 'porción (${fmtDec(serving)}${unit == null ? '' : ' $unit'})'
            : p.basis == 'portion'
                ? 'porción'
                : '';
    return FoodLabelDraft(
      name: p.name,
      basis: basis,
      unitLabel: unitLabel,
      defaultQuantity: per100 ? 100 : (serving == null ? null : 1),
      kcal: _per100(p.kcal),
      protein: _per100(p.protein),
      carbs: _per100(p.carbs),
      fat: _per100(p.fat),
      uncertainties: p.uncertainties,
      sourceSnapshot: p,
      convertedToPer100: _converted,
      portionNeedsConfirmation: p.basis == 'portion' && serving == null,
    );
  }

  void _accept() {
    final draft = _toDraft();
    Navigator.pop(context, draft);
  }

  void _cancel() {
    _generation++;
    _activationGeneration++;
    _statusGeneration++;
    _client?.close();
    _statusClient?.close();
    _client = null;
    setState(() {
      _busy = false;
      _error = 'Lectura cancelada. No se añadió ningún alimento.';
    });
  }

  @override
  void dispose() {
    _generation++;
    _activationGeneration++;
    _statusGeneration++;
    _client?.close();
    _statusClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _enabled &&
        _hwid != null &&
        RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$').hasMatch(_license ?? '');
    final proposal = _proposal;
    final canConvert = proposal?.basis == 'portion' &&
        proposal?.servingQuantity != null &&
        proposal!.servingQuantity! > 0 &&
        proposal.unit != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Leer etiqueta · IA')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Fotografía la tabla nutricional completa y legible. '
            'Los valores son una lectura para revisar, no se guardan hasta que confirmes.'),
        const SizedBox(height: 12),
        if (!active)
          TextButton.icon(
              onPressed: _openActivation,
              icon: const Icon(Icons.lock_open),
              label: const Text('Activar IA en este teléfono')),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Tomar foto')),
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Elegir foto')),
        ]),
        if (_photo != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_photo!, height: 240, fit: BoxFit.contain)),
          const SizedBox(height: 8),
          const Text(
              'Se enviará solo esta imagen, reducida y sin ubicación EXIF, a Control360i y OpenAI. '
              'No se guarda en el historial ni en el respaldo. Requiere internet y comparte el límite diario de IA.'),
          AiBudget(quota: _quota),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consent,
              onChanged:
                  _busy ? null : (v) => setState(() => _consent = v ?? false),
              title: const Text(
                  'Acepto enviar esta imagen para leer la etiqueta')),
          FilledButton.icon(
              onPressed: !_busy && active && _consent ? _analyze : null,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Leer etiqueta')),
        ],
        if (_busy) ...[
          const LinearProgressIndicator(),
          TextButton(onPressed: _cancel, child: const Text('Cancelar lectura')),
        ],
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!)),
        if (proposal != null) ...[
          const SizedBox(height: 16),
          Text('Revisa lo leído',
              style: Theme.of(context).textTheme.titleLarge),
          Text('Nombre: ${proposal.name ?? 'falta completar'}'),
          Text('Base leída: ${_basisLabel(proposal.basis, proposal.unit)}'),
          Text('Unidad: ${proposal.unit ?? 'falta confirmar g o ml'}'),
          Text(
              'Porción: ${proposal.servingQuantity == null ? 'no identificada' : '${fmtDec(proposal.servingQuantity!)} ${proposal.unit ?? ''}'}'),
          const SizedBox(height: 8),
          Text(
              'Valores de la etiqueta${_converted ? ' · conversión local por 100/${fmtDec(proposal.servingQuantity!)}' : ''}'),
          for (final (label, value) in <(String, double?)>[
            ('kcal', _per100(proposal.kcal)),
            ('Proteína (g)', _per100(proposal.protein)),
            ('Carbohidratos (g)', _per100(proposal.carbs)),
            ('Grasa (g)', _per100(proposal.fat)),
          ])
            Text(
                '$label: ${value == null ? 'falta completar' : fmtDec(value)}'),
          if (canConvert)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _converted,
              onChanged: (value) => setState(() => _converted = value),
              title: Text(_converted
                  ? 'Usar valores por 100 ${proposal.unit}'
                  : 'Convertir a valores por 100 ${proposal.unit}'),
              subtitle: Text(
                  'Cálculo local: valor leído × 100 ÷ ${fmtDec(proposal.servingQuantity!)}. Revisa el resultado contra el empaque.'),
            ),
          for (final doubt in proposal.uncertainties)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Por verificar: $doubt')),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _accept,
              child: const Text('Revisar y completar alimento')),
          const Text(
              'Se abrirá un borrador editable. No se crea en el catálogo en esta pantalla.'),
        ],
      ]),
    );
  }
}
