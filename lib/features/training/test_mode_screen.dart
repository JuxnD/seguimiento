import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart' show formatDuration, dateOnly, dayKey;
import '../../domain/fitness_test.dart';
import '../../domain/test_protocol.dart';
import '../../domain/test_attempt_evidence.dart';
import '../../ui/widgets.dart';
import 'pre_attempt_card.dart';

/// Modo test (§19.11): lista guiada, un resultado por prueba (por lado si
/// toca), calidad limpia / con dudas y cronómetro de 3 min entre pruebas.
class TestModeScreen extends ConsumerStatefulWidget {
  const TestModeScreen(
      {super.key,
      required this.date,
      required this.round,
      required this.part,
      this.scheduleKey,
      this.attemptId,
      this.newAttempt = false});

  final DateTime date;
  final int round;
  final TestPart part;
  final TestScheduleKey? scheduleKey;
  final int? attemptId;
  final bool newAttempt;

  @override
  ConsumerState<TestModeScreen> createState() => _TestModeScreenState();
}

class _TestModeScreenState extends ConsumerState<TestModeScreen> {
  TestProtocolId get _protocol =>
      widget.scheduleKey?.protocolId ?? TestProtocolId.v31_12;
  late final _items = protocolItems(_protocol, widget.part);
  int? _attemptId;
  final _conditions = <String, Map<String, Object?>>{};
  bool _loaded = false;
  String? _jumpRestriction;
  bool _changed = false;
  final _errors = <String, String>{};

  /// Campo por prueba y lado ('' sin lado).
  final _fields = <String, TextEditingController>{};
  final _doubtful = <String>{};

  DateTime? _restEndsAt;
  Timer? _ticker;
  bool _saving = false;
  late DateTime _executionDate;
  bool _editing = false;
  bool _dateNeedsConfirmation = false;
  bool _dateWasConfirmed = false;
  String _dateIssue = '';

  String _key(TestItem t, String side) => '${t.id}|$side';
  List<String> _sides(TestItem t) => t.perSide ? const ['I', 'D'] : const [''];

  TextEditingController _field(TestItem t, String side) => _fields.putIfAbsent(
      _key(t, side),
      () => TextEditingController()
        ..addListener(() => setState(() {
              _changed = true;
            })));

  double? _value(TestItem t, String side) =>
      double.tryParse(_field(t, side).text.trim().replaceAll(',', '.'));

  bool get _hasAny => _fields.values.any((c) => c.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(fitnessTestRepositoryProvider);
    final rows = await repo.resultsFor(widget.round, widget.part,
        protocol: _protocol,
        key: widget.scheduleKey,
        attemptId: widget.attemptId);
    if (!mounted) return;
    final partRows = rows
        .where(
            (r) => r.round == widget.round && _items.any((t) => t.id == r.item))
        .toList();
    final today = dateOnly(clock.now());
    final dates = partRows
        .where((r) => r.date != null)
        .map((r) => dayKey(r.date!))
        .toSet();
    final invalid = partRows.any((r) => r.date == null);
    final mixed = dates.length > 1;
    final future =
        partRows.any((r) => r.date != null && dateOnly(r.date!).isAfter(today));
    _attemptId = widget.newAttempt ? null : partRows.firstOrNull?.attemptId;
    _editing = !widget.newAttempt && partRows.isNotEmpty;
    for (final r in partRows) {
      if (r.conditions != null) {
        try {
          final parsed =
              (jsonDecode(r.conditions!) as Map).cast<String, Object?>();
          canonicalTestConditions(r.item, parsed);
          _conditions[r.item] = parsed;
        } catch (_) {
          _dateIssue =
              'Hay condiciones sin validar; el registro original se conserva.';
        }
      }
    }
    _dateNeedsConfirmation = _editing && (invalid || mixed || future);
    _dateIssue = [
      if (invalid) 'Hay resultados sin fecha válida.',
      if (mixed) 'Hay resultados de fechas distintas.',
      if (future) 'Hay resultados con fecha futura.',
    ].join(' ');
    // Only a uniform valid non-future date belongs to the whole stored part.
    // A conflicting legacy date is not replaced until explicit confirmation.
    _executionDate = _editing && !_dateNeedsConfirmation
        ? dateOnly(partRows.first.date!)
        : today;
    for (final t in _items) {
      for (final side in _sides(t)) {
        final r = rows
            .where((r) =>
                r.round == widget.round &&
                r.item == t.id &&
                (r.side ?? '') == side)
            .firstOrNull;
        final c = _field(t, side);
        if (r != null && !widget.newAttempt) {
          c.text = r.value.toString();
          if (!r.clean) _doubtful.add(_key(t, side));
        }
      }
    }
    _jumpRestriction = await repo.jumpRestriction(_executionDate);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _changed = false;
    });
  }

  void _startRest() {
    _ticker?.cancel();
    setState(() =>
        _restEndsAt = clock.now().add(const Duration(seconds: testRestSec)));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _restEndsAt;
      if (end == null) return;
      if (!clock.now().isBefore(end)) {
        _ticker?.cancel();
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        setState(() => _restEndsAt = null);
        return;
      }
      setState(() {});
    });
  }

  void _stopRest() {
    _ticker?.cancel();
    setState(() => _restEndsAt = null);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    _errors.clear();
    for (final t in _items) {
      for (final side in _sides(t)) {
        if (_field(t, side).text.trim().isEmpty) continue;
        final error = testResultError(t, _value(t, side));
        if (error != null) _errors[_key(t, side)] = error;
      }
    }
    if (_errors.isNotEmpty) {
      setState(() {});
      return;
    }
    final results = <TestResult>[
      for (final t in _items)
        for (final side in _sides(t))
          if (!(t.id == 'broad_jump' && !_editing && _jumpRestriction != null))
            if (_value(t, side) case final v?)
              TestResult(
                round: widget.round,
                item: t.id,
                side: side.isEmpty ? null : side,
                value: v,
                clean: !_doubtful.contains(_key(t, side)),
              ),
    ];
    if (results.isEmpty) return;
    setState(() => _saving = true);
    final ok = await guarded(
      context,
      () => ref.read(fitnessTestRepositoryProvider).save(
            date: _executionDate,
            round: widget.round,
            part: widget.part,
            results: results,
            totalSec: 0,
            protocol: _protocol,
            scheme: widget.scheduleKey?.scheme ?? 'v3.1',
            blockStart: widget.scheduleKey?.blockStart,
            attemptId: _attemptId,
            conditions: _conditions,
          ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    ref.invalidate(fitnessTestsProvider);
    ref.invalidate(dashboardProvider);
    showSnack(context,
        'Test ${widget.round} guardado: ${results.length} resultados.');
    Navigator.pop(context, true);
  }

  Future<bool> _confirmLeave() async {
    if (!_changed) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('Los resultados anotados se pierden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Seguir')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Salir')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final previous =
        ref.watch(fitnessTestsProvider).valueOrNull ?? const <TestResult>[];
    final rest = _restEndsAt?.difference(clock.now());
    final torso = widget.part == TestPart.torso;
    return PopScope(
      canPop: !_changed,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
            title: Text(
                'Test ${widget.round} · ${torso ? 'torso y core' : 'piernas'}')),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  AppCard(
                    children: [
                      Text(_dateNeedsConfirmation
                          ? 'Fecha del intento sin confirmar: revisa la fecha de toda esta parte. $_dateIssue'
                          : 'Fecha del intento: ${dayKey(_executionDate)}${_dateWasConfirmed ? ' (confirmada para esta parte)' : _editing ? ' (conservada)' : ''}'),
                      if (!_editing ||
                          _dateNeedsConfirmation ||
                          _dateWasConfirmed)
                        TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _executionDate,
                                  firstDate: DateTime(2000),
                                  lastDate: dateOnly(clock.now()));
                              if (picked != null && mounted) {
                                final restriction = await ref
                                    .read(fitnessTestRepositoryProvider)
                                    .jumpRestriction(picked);
                                if (!mounted) return;
                                setState(() {
                                  _jumpRestriction = restriction;
                                  _executionDate = picked;
                                  _dateNeedsConfirmation = false;
                                  _dateWasConfirmed = true;
                                  _changed = true;
                                });
                              }
                            },
                            child: const Text('Confirmar o cambiar fecha')),
                      Text(
                        torso
                            ? (widget.date.weekday == DateTime.monday
                                ? 'Antes de empezar: calentamiento de 10 min. El test completo sustituye la sesión de tirón.'
                                : 'Test de torso y core. La Cindy del viernes sigue pendiente.')
                            : 'Después del FIFA 11+ y antes de la sesión de piernas.',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                          'Puedes guardar un test parcial y continuarlo después. 0 indica un intento sin repeticiones; vacío queda pendiente. El tiempo de esta pantalla no se registra como trabajo.'),
                      Text(
                        'Cada prueba es una sola serie máxima con técnica estricta: se corta en la primera repetición fea, '
                        'nunca al fallo total. 3 min de descanso entre pruebas.',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                  PreAttemptCard(torso: torso),
                  for (final (i, t) in _items.indexed)
                    _itemCard(context, i + 1, t, previous),
                ],
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: rest == null
                      ? OutlinedButton.icon(
                          onPressed: _startRest,
                          icon: const Icon(Icons.timer_outlined),
                          label: const Text('Descanso 3 min'),
                        )
                      : OutlinedButton.icon(
                          onPressed: _stopRest,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: Text(
                              'Descanso ${formatDuration(rest.inSeconds + 1)}'),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loaded &&
                            _hasAny &&
                            !_saving &&
                            !_dateNeedsConfirmation
                        ? _save
                        : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Guardar test'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(
      BuildContext context, int n, TestItem t, List<TestResult> previous) {
    final text = Theme.of(context).textTheme;
    final currentConditions = _conditions[t.id] == null
        ? null
        : canonicalTestConditions(t.id, _conditions[t.id]!);
    final before = [
      if (currentConditions != null)
        for (final evidence in eligibleAttempts(previous, t.id,
            asOf: clock.now(),
            protocol: _protocol.name,
            conditions: currentConditions))
          'Intento ${evidence.attemptId} comparable: ${formatTestValue(t, evidence.value)}',
    ];
    return AppCard(
      title: '$n. ${t.name}',
      children: [
        if (t.id == 'broad_jump' && !_editing && _jumpRestriction != null)
          Text(_jumpRestriction!, key: const ValueKey('jump-deferred')),
        TextButton(
            onPressed: () async {
              final previous = _conditions[t.id];
              final variant = TextEditingController(
                  text: previous?['variant'] as String? ?? '');
              final support = TextEditingController(
                  text: previous?['support'] as String? ?? '');
              final height = TextEditingController(
                  text: previous?['heightCm']?.toString() ?? '');
              String? grip = previous?['grip'] as String?;
              final gripRelevant =
                  ['pullup', 'dead_hang', 'hanging_leg_raise'].contains(t.id);
              final supportRelevant = [
                'dips',
                'one_arm_pushup',
                'pike_pushup',
                'pistol_box',
                'reverse_plank_forearm'
              ].contains(t.id);
              final raw = await showDialog<Map<String, Object?>>(
                  context: context,
                  builder: (c) => StatefulBuilder(
                      builder: (c, update) => AlertDialog(
                            title: Text('Condiciones · ${t.name}'),
                            content: SingleChildScrollView(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  const Text(
                                      'Repite estas condiciones en el retest. Vacío significa desconocido.'),
                                  TextField(
                                      controller: variant,
                                      decoration: const InputDecoration(
                                          labelText: 'Variante física')),
                                  if (gripRelevant)
                                    DropdownButtonFormField<String>(
                                        value: grip,
                                        decoration: const InputDecoration(
                                            labelText: 'Agarre'),
                                        items: [
                                          for (final name in [
                                            'prona',
                                            'supina',
                                            'neutro'
                                          ])
                                            DropdownMenuItem(
                                                value: name, child: Text(name))
                                        ],
                                        onChanged: (v) =>
                                            update(() => grip = v)),
                                  if (supportRelevant) ...[
                                    TextField(
                                        controller: support,
                                        decoration: const InputDecoration(
                                            labelText:
                                                'Apoyo (suelo, mesa, paralelas…)')),
                                    TextField(
                                        controller: height,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                            labelText:
                                                'Altura del apoyo (cm)')),
                                  ],
                                ])),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('Cancelar')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(c, <String, Object?>{
                                        if (variant.text.trim().isNotEmpty)
                                          'variant': variant.text.trim(),
                                        if (gripRelevant && grip != null)
                                          'grip': grip,
                                        if (supportRelevant &&
                                            support.text.trim().isNotEmpty)
                                          'support': support.text.trim(),
                                        if (supportRelevant &&
                                            height.text.trim().isNotEmpty)
                                          'heightCm': double.tryParse(
                                              height.text.replaceAll(',', '.')),
                                      }),
                                  child: const Text('Confirmar'))
                            ],
                          )));
              variant.dispose();
              support.dispose();
              height.dispose();
              if (raw == null || !context.mounted) return;
              try {
                final values = raw.isEmpty ? null : raw;
                if (values != null) canonicalTestConditions(t.id, values);
                if (widget.newAttempt &&
                    _conditions[t.id] != null &&
                    values != null &&
                    jsonEncode(_conditions[t.id]) != jsonEncode(values)) {
                  final accepted = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                              title: const Text('Nueva línea base'),
                              content: const Text(
                                  'Las condiciones cambiaron. Se conservarán ambos intentos sin compararlos.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancelar')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Crear línea base'))
                              ]));
                  if (accepted != true) return;
                }
                setState(() {
                  if (values == null) {
                    _conditions.remove(t.id);
                  } else {
                    _conditions[t.id] = values;
                  }
                  _changed = true;
                });
              } catch (_) {
                if (context.mounted) {
                  showSnack(context,
                      'Condiciones inválidas o no pertinentes para esta prueba');
                }
              }
            },
            child: Text(
                'Condiciones: ${_conditions[t.id] == null ? 'desconocidas' : _conditions[t.id]!.values.join(' · ')}')),
        if (before.isEmpty)
          const Text('Sin referencia comparable bajo estas condiciones.'),
        Text(
          [
            switch (t.unit) {
              TestUnit.reps => t.perSide ? 'Reps por lado' : 'Reps',
              TestUnit.seconds => 'Segundos',
              TestUnit.cm => 'Centímetros',
            },
            if (t.hint != null) t.hint!,
            ...before,
          ].join(' · '),
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final side in _sides(t)) ...[
              Expanded(
                child: TextField(
                  key: ValueKey('test-value-${t.id}-$side'),
                  enabled: !(t.id == 'broad_jump' &&
                      !_editing &&
                      _jumpRestriction != null),
                  controller: _field(t, side),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: side.isEmpty
                        ? t.unit.short
                        : '${side == 'I' ? 'Izquierda' : 'Derecha'} (${t.unit.short})',
                    errorText: _errors[_key(t, side)],
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (side != _sides(t).last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final side in _sides(t)) ...[
              ChoiceChip(
                label: Text('${side.isEmpty ? '' : '$side · '}Limpia'),
                selected: !_doubtful.contains(_key(t, side)),
                onSelected: (_) => setState(() {
                  _changed = true;
                  _doubtful.remove(_key(t, side));
                }),
              ),
              ChoiceChip(
                label: Text('${side.isEmpty ? '' : '$side · '}Con dudas'),
                selected: _doubtful.contains(_key(t, side)),
                onSelected: (_) => setState(() {
                  _changed = true;
                  _doubtful.add(_key(t, side));
                }),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
