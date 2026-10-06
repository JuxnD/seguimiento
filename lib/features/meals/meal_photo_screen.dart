import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../data/meal_photo_ai.dart';
import '../../data/meal_assistant.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../data/weekly_ai.dart';
import '../../domain/format.dart';
import '../../domain/nutrition.dart';
import '../ai/ai_activation_screen.dart';
import '../ai/ai_budget.dart';

class PhotoMealSelection {
  const PhotoMealSelection(this.items, this.notes);
  final List<MealItemDraft> items;
  final String notes;
}

/// Devuelve un borrador revisado. Esta pantalla no escribe comidas ni catálogo.
class MealPhotoScreen extends StatefulWidget {
  const MealPhotoScreen(
      {super.key, this.activation, this.clientFactory, this.pickPhoto});
  final AiActivation? activation;
  final http.Client Function()? clientFactory;
  final Future<Uint8List?> Function(ImageSource)? pickPhoto;
  @override
  State<MealPhotoScreen> createState() => _MealPhotoScreenState();
}

class _MealPhotoScreenState extends State<MealPhotoScreen> {
  Uint8List? _photo;
  String? _hwid, _license, _error;
  bool _consent = false, _busy = false, _enabled = false;
  AiQuota? _quota;
  int _generation = 0, _activationGeneration = 0, _statusGeneration = 0;
  http.Client? _client, _statusClient;
  PhotoMealEstimate? _estimate;
  List<bool> _selected = [];
  List<double> _multipliers = [];

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
      final (hwid, license) =
          await (widget.activation ?? AiActivation()).read();
      if (mounted && generation == _activationGeneration) {
        setState(() {
          _hwid = hwid;
          _license = license;
        });
      }
      if (license.isNotEmpty && generation == _activationGeneration) {
        await _refreshStatus(hwid, license, activationGeneration: generation);
      }
    } on Object {
      if (mounted && generation == _activationGeneration) {
        setState(() => _error =
            'No se pudo abrir la activación segura. Puedes registrar a mano.');
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
      // Status is informational and never changes the local draft.
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
          _estimate = null;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e is AiError
            ? e.message
            : 'No se pudo abrir la cámara o galería. Revisa los permisos o elige otra foto.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    _generation++;
    _client?.close();
    _client = null;
    setState(() {
      _busy = false;
      _error = 'Análisis cancelado. No se guardó ninguna comida.';
    });
  }

  Future<void> _analyze() async {
    final generation = ++_generation;
    final photo = _photo!;
    setState(() {
      _busy = true;
      _error = null;
      _estimate = null;
    });
    final client = (widget.clientFactory ?? http.Client.new)();
    _client = client;
    var responseReceived = false;
    try {
      final estimate = await MealPhotoAi(client).analyze(
          photo, _hwid!, _license!,
          onResponse: () => responseReceived = true);
      if (mounted && generation == _generation) {
        setState(() {
          _estimate = estimate;
          _selected = List.filled(estimate.items.length, true);
          _multipliers = List.filled(estimate.items.length, 1);
        });
      }
    } on Object catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e is AiError
            ? e.message
            : 'No se pudo analizar la foto. El registro manual sigue disponible.');
      }
    } finally {
      client.close();
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _client = null;
        });
        if (responseReceived && _hwid != null && _license != null) {
          await _refreshStatus(_hwid!, _license!,
              activationGeneration: _activationGeneration);
        }
      }
    }
  }

  List<MealItemDraft> get _drafts => [
        if (_estimate != null)
          for (var i = 0; i < _selected.length; i++)
            if (_selected[i]) _estimate!.items[i].toDraft(_multipliers[i]),
      ];

  void _accept() {
    final items = _drafts;
    if (items.isEmpty) return;
    final notes = StringBuffer(
        'Propuesta original por foto · estimación revisada antes de guardar. '
        'Este detalle no se actualiza si después corriges alimentos o cantidades; revisa el borrador de arriba.');
    for (var i = 0; i < _selected.length; i++) {
      if (_selected[i]) {
        notes.write(
            '\n${_estimate!.items[i].label}: ${_estimate!.items[i].portion} ×${fmtDec(_multipliers[i])}.');
      }
    }
    for (final doubt in _estimate!.uncertainties) {
      notes.write('\nPor verificar: $doubt');
    }
    Navigator.pop(context, PhotoMealSelection(items, notes.toString()));
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
    final total = Macros.sum(_drafts.map((d) => d.macros));
    return Scaffold(
      appBar: AppBar(title: const Text('Comida por foto')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'Fotografía el plato completo. La IA propone alimentos y cantidades aproximadas; puedes quitar alimentos, ajustar porciones y corregir las cifras antes de guardar.'),
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
          const SizedBox(height: 12),
          const Text(
              'Se enviará solo esta imagen, reducida y sin ubicación EXIF, a Control360i y OpenAI. Control360i no conserva la foto ni la propuesta. OpenAI puede conservar registros de seguridad hasta 30 días, con excepciones. La foto no se añade al respaldo. Requiere internet y comparte el límite diario del análisis semanal.'),
          AiBudget(quota: _quota),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consent,
              onChanged:
                  _busy ? null : (v) => setState(() => _consent = v ?? false),
              title:
                  const Text('Acepto enviar esta foto para estimar la comida')),
          FilledButton(
              onPressed: !_busy && active && _consent ? _analyze : null,
              child: const Text('Analizar foto')),
        ],
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          if (_client != null)
            TextButton(
                onPressed: _cancel, child: const Text('Cancelar análisis')),
        ],
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!)),
        if (_estimate != null) ...[
          const SizedBox(height: 20),
          Text('Revisa la propuesta',
              style: Theme.of(context).textTheme.titleLarge),
          const Text(
              'Todo es estimado: una foto no mide gramos ni revela aceites, salsas o ingredientes ocultos. Ajusta lo que corresponda.'),
          if (_estimate!.items.isEmpty)
            const Text(
                'No se pudo identificar una comida. Prueba otra foto o usa el registro manual.'),
          for (var i = 0; i < _estimate!.items.length; i++) ...[
            const Divider(),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected[i],
                onChanged: (v) => setState(() => _selected[i] = v ?? false),
                title: Text(_estimate!.items[i].label),
                subtitle: Text(_estimate!.items[i].portion)),
            Wrap(spacing: 6, children: [
              for (final multiplier in portionMultipliers)
                ChoiceChip(
                    key: ValueKey('photo-portion-$i-$multiplier'),
                    label: Text('×${fmtDec(multiplier)}'),
                    selected: _multipliers[i] == multiplier,
                    onSelected: _selected[i]
                        ? (_) => setState(() => _multipliers[i] = multiplier)
                        : null),
            ]),
            Text(
                '≈ ${fmtInt(_estimate!.items[i].macros.kcal * _multipliers[i])} kcal · P ${fmtInt(_estimate!.items[i].macros.protein * _multipliers[i])} g'),
          ],
          for (final doubt in _estimate!.uncertainties)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Por verificar: $doubt')),
          const Divider(),
          Text(
              'Total estimado: ${fmtInt(total.kcal)} kcal · P ${fmtInt(total.protein)} g · C ${fmtInt(total.carbs)} g · G ${fmtInt(total.fat)} g'),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _drafts.isEmpty ? null : _accept,
              child: const Text('Añadir al borrador')),
          const Text(
              'Volverás a la comida para corregir alimentos o cifras. Se registra únicamente al tocar Guardar.'),
        ],
      ]),
    );
  }
}
