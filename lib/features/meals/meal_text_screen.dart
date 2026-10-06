import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/database.dart';
import '../../data/meal_assistant.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../data/weekly_ai.dart';
import '../../domain/format.dart';
import '../../domain/nutrition.dart';
import '../../ui/widgets.dart';
import '../ai/ai_activation_screen.dart';
import '../ai/ai_budget.dart';

/// Turns a phrase into a reviewed list of local catalog foods. It never saves.
class MealTextScreen extends StatefulWidget {
  const MealTextScreen({
    super.key,
    required this.foods,
    this.activation,
    this.clientFactory,
  });

  final List<FoodRow> foods;
  final AiActivation? activation;
  final http.Client Function()? clientFactory;

  @override
  State<MealTextScreen> createState() => _MealTextScreenState();
}

class _MealTextScreenState extends State<MealTextScreen> {
  final _text = TextEditingController();
  String? _consentedText;
  String? _analysisText, _proposalText;
  String? _hwid, _license, _error;
  AiQuota? _quota;
  bool _busy = false, _enabled = false;
  int _generation = 0, _activationGeneration = 0, _statusGeneration = 0;
  http.Client? _client, _statusClient;
  MealTextProposal? _proposal;
  final _choices = <FoodRow?>[];
  final _quantities = <TextEditingController>[];
  final _useProposed = <bool>[];
  final _useUsual = <bool>[];
  final _removed = <bool>[];

  AiActivation get _activation => widget.activation ?? AiActivation();

  @override
  void initState() {
    super.initState();
    _text.addListener(_inputChanged);
    _loadActivation();
  }

  void _inputChanged() {
    if (!mounted) return;
    final changed = _text.text != (_analysisText ?? _proposalText);
    setState(() {
      if (_consentedText != null && _text.text != _consentedText) {
        _consentedText = null;
      }
      if (_busy && changed) {
        _generation++;
        _client?.close();
        _client = null;
        _busy = false;
        _error = 'La descripción cambió; la consulta anterior se descartó.';
        _clearProposal();
      } else if (_proposal != null && _text.text != _proposalText) {
        _clearProposal();
      }
    });
  }

  void _clearProposal() {
    _proposal = null;
    _proposalText = null;
    _choices.clear();
    _useProposed.clear();
    _useUsual.clear();
    _removed.clear();
    for (final controller in _quantities) {
      controller.dispose();
    }
    _quantities.clear();
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
      // Status is informational; the user can still open activation or retry.
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

  Future<void> _analyze() async {
    final hwid = _hwid;
    final license = _license;
    final text = _text.text.trim();
    if (hwid == null || license == null || license.isEmpty || text.isEmpty)
      return;
    if (_consentedText != _text.text) {
      setState(() =>
          _error = 'Confirma el envío de esta descripción antes de continuar.');
      return;
    }
    final generation = ++_generation;
    _analysisText = text;
    final client = (widget.clientFactory ?? http.Client.new)();
    _client = client;
    setState(() {
      _busy = true;
      _error = null;
      _clearProposal();
    });
    try {
      final assistant = MealAssistant(client);
      final proposal = await assistant.describeMeal(
          text: text, catalog: widget.foods, hwid: hwid, license: license);
      if (!mounted || generation != _generation) return;
      setState(() {
        _proposal = proposal;
        _proposalText = text;
        _quota = assistant.lastQuota;
        for (final item in proposal.items) {
          final chosen =
              widget.foods.where((f) => f.id == item.foodId).firstOrNull;
          _choices.add(chosen);
          final compatible =
              chosen != null && _compatible(item.unit, chosen.unitLabel);
          _quantities.add(TextEditingController(
              text: compatible && item.quantity != null
                  ? fmtDec(item.quantity!)
                  : ''));
          _useProposed.add(false);
          _useUsual.add(false);
          _removed.add(false);
        }
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
            'No se pudo analizar. Puedes seguir con el registro manual.');
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

  bool _compatible(String? proposed, String catalogUnit) =>
      proposed != null &&
      proposed.trim().toLowerCase() == catalogUnit.trim().toLowerCase();

  List<MealItemDraft> _drafts() {
    if (_proposal == null) return [];
    final drafts = <MealItemDraft>[];
    for (var i = 0; i < _proposal!.items.length; i++) {
      if (_removed[i]) continue;
      final food = _choices[i];
      if (food == null) continue;
      final parsed = _useUsual[i]
          ? food.defaultQuantity
          : _useProposed[i]
              ? _proposal!.items[i].quantity
              : parseNum(_quantities[i].text);
      if (parsed == null || !parsed.isFinite || parsed <= 0 || parsed > 5000)
        continue;
      drafts.add(MealItemDraft.fromFood(food, parsed));
    }
    return drafts;
  }

  bool get _allItemsResolved {
    if (_proposal == null || _proposal!.items.isEmpty) return false;
    for (var i = 0; i < _proposal!.items.length; i++) {
      if (_removed[i]) continue;
      final food = _choices[i];
      if (food == null) return false;
      final quantity = _useUsual[i]
          ? food.defaultQuantity
          : _useProposed[i]
              ? _proposal!.items[i].quantity
              : parseNum(_quantities[i].text);
      if (quantity == null ||
          !quantity.isFinite ||
          quantity <= 0 ||
          quantity > 5000) {
        return false;
      }
    }
    return _drafts().isNotEmpty;
  }

  void _accept() {
    final drafts = _drafts();
    if (!_allItemsResolved || drafts.isEmpty) {
      setState(() => _error =
          'Resuelve o quita explícitamente cada propuesta antes de añadir.');
      return;
    }
    Navigator.pop(context, drafts);
  }

  @override
  void dispose() {
    _generation++;
    _activationGeneration++;
    _statusGeneration++;
    _client?.close();
    _statusClient?.close();
    _text.dispose();
    for (final controller in _quantities) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _enabled &&
        _hwid != null &&
        RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$').hasMatch(_license ?? '');
    final proposed = _proposal?.items ?? const <MealTextItem>[];
    final drafts = _drafts();
    final total = Macros.sum(drafts.map((d) => d.macros));
    return Scaffold(
      appBar: AppBar(title: const Text('Describir comida · IA')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'Escribe lo que comiste. Puedes usar el dictado de tu teclado. '
            'Solo se envía la frase y una lista reducida del catálogo; no se envían macros ni registros.'),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(
              labelText: 'Describe la comida', border: OutlineInputBorder()),
        ),
        if (!active)
          TextButton.icon(
              onPressed: _openActivation,
              icon: const Icon(Icons.lock_open),
              label: const Text('Activar IA en este teléfono')),
        if (active) ...[
          AiBudget(quota: _quota),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consentedText == _text.text,
            onChanged: _busy || _text.text.trim().isEmpty
                ? null
                : (v) => setState(
                    () => _consentedText = v == true ? _text.text : null),
            title: const Text(
                'Acepto enviar esta descripción para preparar el borrador'),
          ),
          FilledButton.icon(
            onPressed: !_busy &&
                    _consentedText == _text.text &&
                    _text.text.trim().isNotEmpty
                ? _analyze
                : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Preparar borrador'),
          ),
        ],
        if (_busy) ...[
          const LinearProgressIndicator(),
          TextButton(
              onPressed: _cancel, child: const Text('Cancelar consulta')),
        ],
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!)),
        if (_proposal != null) ...[
          const SizedBox(height: 16),
          Text('Revisa alimento y cantidad',
              style: Theme.of(context).textTheme.titleLarge),
          if (proposed.isEmpty)
            const Text('No se identificaron alimentos. Añádelos manualmente.'),
          for (var i = 0; i < proposed.length; i++)
            _proposalCard(i, proposed[i]),
          for (final doubt in _proposal!.uncertainties)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Por revisar: $doubt')),
          const Divider(),
          Text('Total calculado localmente: ${fmtInt(total.kcal)} kcal · '
              'P ${fmtInt(total.protein)} g · C ${fmtInt(total.carbs)} g · G ${fmtInt(total.fat)} g'),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _allItemsResolved ? _accept : null,
              child: const Text('Añadir al borrador')),
          const Text(
              'Volverás a la comida. Nada se registra hasta tocar Guardar.'),
        ],
      ]),
    );
  }

  Widget _proposalCard(int index, MealTextItem item) {
    if (_removed[index]) {
      return Card(
          child: ListTile(
        title: Text(item.label),
        subtitle: const Text('Propuesta excluida explícitamente.'),
        trailing: TextButton(
          onPressed: () => setState(() => _removed[index] = false),
          child: const Text('Restaurar'),
        ),
      ));
    }
    final food = _choices[index];
    final compatible = food != null && _compatible(item.unit, food.unitLabel);
    final controller = _quantities[index];
    final quantity = _useUsual[index]
        ? food?.defaultQuantity
        : _useProposed[index]
            ? item.quantity
            : parseNum(controller.text);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.label, style: Theme.of(context).textTheme.titleMedium),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _removed[index] = true;
                _useProposed[index] = false;
                _useUsual[index] = false;
              }),
              icon: const Icon(Icons.remove_circle_outline),
              label: const Text('Quitar esta propuesta'),
            ),
          ),
          DropdownButtonFormField<FoodRow>(
            value: food,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Alimento del catálogo'),
            items: [
              for (final candidate in widget.foods)
                DropdownMenuItem(
                    value: candidate,
                    child:
                        Text(candidate.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (selected) => setState(() {
              _choices[index] = selected;
              _useProposed[index] = false;
              _useUsual[index] = false;
              controller.clear();
            }),
          ),
          if (food == null)
            const Text(
                'Elige un alimento local; no se asignan macros por parecido de nombre.'),
          if (food != null) ...[
            if (item.quantity != null && item.unit != null && !compatible)
              Text(
                  'La cantidad propuesta está en ${item.unit}; el catálogo usa ${food.unitLabel}. '
                  'Escribe la cantidad en ${food.unitLabel}.'),
            if (item.quantity != null &&
                item.unit == null &&
                !_useProposed[index])
              TextButton(
                  onPressed: () => setState(() => _useProposed[index] = true),
                  child: Text(
                      'Confirmar ${fmtDec(item.quantity!)} ${food.unitLabel}')),
            if (item.quantity == null)
              TextButton(
                  onPressed: () => setState(() {
                        _useUsual[index] = true;
                        _useProposed[index] = false;
                      }),
                  child: Text(
                      'Usar porción habitual: ${fmtDec(food.defaultQuantity)} ${food.unitLabel}')),
            TextField(
              controller: controller,
              enabled: !_useUsual[index] && !_useProposed[index],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Cantidad en ${food.unitLabel}',
                  helperText: 'Válida entre 0 y 5.000'),
              onChanged: (_) => setState(() {}),
            ),
            if (_useProposed[index])
              TextButton(
                  onPressed: () => setState(() => _useProposed[index] = false),
                  child: const Text('Cambiar cantidad')),
            if (_useUsual[index])
              TextButton(
                  onPressed: () => setState(() => _useUsual[index] = false),
                  child: const Text('Ingresar otra cantidad')),
            if (quantity != null && quantity > 0 && quantity <= 5000)
              Text(_macroSummary(food, quantity)),
          ],
        ]),
      ),
    );
  }

  void _cancel() {
    _generation++;
    _client?.close();
    _client = null;
    setState(() {
      _busy = false;
      _error = 'Consulta cancelada. No se añadió ninguna comida.';
    });
  }

  String _macroSummary(FoodRow food, double quantity) {
    final macros =
        macrosFor(basis: food.basis, perBasis: food.macros, quantity: quantity);
    return '${fmtInt(macros.kcal)} kcal · P ${fmtDec(macros.protein)} g';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
