import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart' show formatDuration;
import '../../domain/fitness_test.dart';
import '../../ui/widgets.dart';

/// Modo test (§19.11): lista guiada, un resultado por prueba (por lado si
/// toca), calidad limpia / con dudas y cronómetro de 3 min entre pruebas.
class TestModeScreen extends ConsumerStatefulWidget {
  const TestModeScreen({super.key, required this.date, required this.round, required this.part});

  final DateTime date;
  final int round;
  final TestPart part;

  @override
  ConsumerState<TestModeScreen> createState() => _TestModeScreenState();
}

class _TestModeScreenState extends ConsumerState<TestModeScreen> {
  late final _items = widget.part == TestPart.torso ? torsoTests : legTests;
  bool _loaded = false;
  bool _changed = false;
  final _errors = <String, String>{};

  /// Campo por prueba y lado ('' sin lado).
  final _fields = <String, TextEditingController>{};
  final _doubtful = <String>{};

  DateTime? _restEndsAt;
  Timer? _ticker;
  bool _saving = false;

  String _key(TestItem t, String side) => '${t.id}|$side';
  List<String> _sides(TestItem t) => t.perSide ? const ['I', 'D'] : const [''];

  TextEditingController _field(TestItem t, String side) => _fields.putIfAbsent(
      _key(t, side),
      () => TextEditingController()
        ..addListener(() => setState(() {
              _changed = true;
            })));

  double? _value(TestItem t, String side) => double.tryParse(_field(t, side).text.trim().replaceAll(',', '.'));

  bool get _hasAny => _fields.values.any((c) => c.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(fitnessTestRepositoryProvider).all();
    if (!mounted) return;
    for (final t in _items) {
      for (final side in _sides(t)) {
        final r = rows.where((r) => r.round == widget.round && r.item == t.id && (r.side ?? '') == side).firstOrNull;
        final c = _field(t, side);
        if (r != null) {
          c.text = r.value.toString();
          if (!r.clean) _doubtful.add(_key(t, side));
        }
      }
    }
    setState(() {
      _loaded = true;
      _changed = false;
    });
  }

  void _startRest() {
    _ticker?.cancel();
    setState(() => _restEndsAt = clock.now().add(const Duration(seconds: testRestSec)));
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
            date: widget.date,
            round: widget.round,
            part: widget.part,
            results: results,
            totalSec: 0,
          ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    ref.invalidate(fitnessTestsProvider);
    ref.invalidate(dashboardProvider);
    showSnack(context, 'Test ${widget.round} guardado: ${results.length} resultados.');
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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final previous = ref.watch(fitnessTestsProvider).valueOrNull ?? const <TestResult>[];
    final rest = _restEndsAt?.difference(clock.now());
    final torso = widget.part == TestPart.torso;
    return PopScope(
      canPop: !_changed,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Test ${widget.round} · ${torso ? 'torso y core' : 'piernas'}')),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  AppCard(
                    children: [
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
                  for (final (i, t) in _items.indexed) _itemCard(context, i + 1, t, previous),
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
                          label: Text('Descanso ${formatDuration(rest.inSeconds + 1)}'),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loaded && _hasAny && !_saving ? _save : null,
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

  Widget _itemCard(BuildContext context, int n, TestItem t, List<TestResult> previous) {
    final text = Theme.of(context).textTheme;
    final before = [
      for (var r = 1; r < widget.round; r++)
        if (testValue(previous, r, t.id) case final v?) 'Test $r: ${formatTestValue(t, v)}',
    ];
    return AppCard(
      title: '$n. ${t.name}',
      children: [
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
                  controller: _field(t, side),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText:
                        side.isEmpty ? t.unit.short : '${side == 'I' ? 'Izquierda' : 'Derecha'} (${t.unit.short})',
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
