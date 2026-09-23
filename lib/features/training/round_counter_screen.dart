import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../domain/active_session.dart';
import '../../domain/dates.dart';
import '../../ui/widgets.dart';

/// Resultado del contador: lo que la app ya no tiene que preguntarte.
class CounterResult {
  const CounterResult({
    required this.startTime,
    required this.totalSec,
    required this.warmupSec,
    required this.cooldownSec,
    required this.roundMarksSec,
  });

  final String startTime;
  final int totalSec;
  final int warmupSec;
  final int cooldownSec;

  /// Segundos desde el inicio del circuito al cerrar cada ronda.
  final List<int> roundMarksSec;

  int get rounds => roundMarksSec.length;
}

/// Cronómetro por fases con contador de rondas de toque grande.
/// Los tiempos se calculan con marcas de reloj, no acumulando ticks: si la
/// pantalla se apaga o la app pasa a segundo plano, no se pierde tiempo.
class RoundCounterScreen extends ConsumerStatefulWidget {
  const RoundCounterScreen({super.key, required this.date, this.outOfPlan = false, this.resume});

  /// Día de la sesión y si va fuera de plan: se guardan con la foto para que
  /// una sesión retomada se registre igual que la original.
  final DateTime date;
  final bool outOfPlan;

  /// Sesión que Android cerró a mitad: se retoma donde iba.
  final CounterSnapshot? resume;

  @override
  ConsumerState<RoundCounterScreen> createState() => _RoundCounterScreenState();
}

class _RoundCounterScreenState extends ConsumerState<RoundCounterScreen> {
  late final DateTime _startedAt = widget.resume?.startedAt ?? DateTime.now();
  late DateTime? _circuitStart = widget.resume?.circuitStart;
  late DateTime? _circuitEnd = widget.resume?.circuitEnd;
  late final _marks = <int>[...?widget.resume?.marks];
  late CounterPhase _phase = widget.resume?.phase ?? CounterPhase.warmup;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    WakelockPlus.enable();
    _persist();
  }

  /// Foto del estado en disco: si Android mata la app, se retoma desde aquí.
  void _persist() => unawaited(ref.read(activeSessionStoreProvider).save(CounterSnapshot(
        date: dayKey(widget.date),
        startedAt: _startedAt,
        phase: _phase,
        outOfPlan: widget.outOfPlan,
        circuitStart: _circuitStart,
        circuitEnd: _circuitEnd,
        marks: List.of(_marks),
      )));

  /// Cambia el estado y deja la foto al día.
  void _update(VoidCallback change) {
    setState(change);
    _persist();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  int get _totalSec => DateTime.now().difference(_startedAt).inSeconds;

  int get _warmupSec => (_circuitStart ?? DateTime.now()).difference(_startedAt).inSeconds;

  int get _circuitSec => _circuitStart == null
      ? 0
      : (_circuitEnd ?? DateTime.now()).difference(_circuitStart!).inSeconds;

  int get _cooldownSec => _circuitEnd == null ? 0 : DateTime.now().difference(_circuitEnd!).inSeconds;

  void _startCircuit() => _update(() {
        _circuitStart = DateTime.now();
        _phase = CounterPhase.circuit;
      });

  void _addRound() => _update(() => _marks.add(DateTime.now().difference(_circuitStart!).inSeconds));

  void _undoRound() => _update(() {
        if (_marks.isNotEmpty) _marks.removeLast();
      });

  void _endCircuit() => _update(() {
        _circuitEnd = DateTime.now();
        _phase = CounterPhase.cooldown;
      });

  void _finish() {
    _circuitStart ??= DateTime.now();
    _circuitEnd ??= DateTime.now();
    Navigator.pop(
      context,
      CounterResult(
        startTime: timeKey(_startedAt.hour, _startedAt.minute),
        totalSec: _totalSec,
        warmupSec: _warmupSec,
        cooldownSec: _cooldownSec,
        roundMarksSec: List.of(_marks),
      ),
    );
  }

  Future<bool> _confirmExit() async {
    if (_marks.isEmpty && _circuitStart == null) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('Se pierden el tiempo y las rondas de esta sesión.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final lastLap = _marks.length >= 2
        ? _marks.last - _marks[_marks.length - 2]
        : (_marks.length == 1 ? _marks.first : null);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmExit()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Circuito en curso')),
        body: Column(
          children: [
            AppCard(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Stat('Total', formatDuration(_totalSec)),
                    _Stat('Calent.', formatDuration(_warmupSec)),
                    _Stat('Circuito', formatDuration(_circuitSec)),
                    _Stat('Enfr.', formatDuration(_cooldownSec)),
                  ],
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _phase == CounterPhase.warmup
                    ? _BigButton(
                        label: 'Empezar circuito',
                        sub: 'Calentando ${formatDuration(_warmupSec)}',
                        icon: Icons.play_arrow,
                        onTap: _startCircuit,
                      )
                    : _phase == CounterPhase.circuit
                        ? _BigButton(
                            label: '${_marks.length}',
                            sub: lastLap == null
                                ? 'Toca al cerrar cada ronda'
                                : 'Última ronda: ${formatDuration(lastLap)}',
                            icon: Icons.add,
                            onTap: _addRound,
                          )
                        : _BigButton(
                            label: 'Finalizar',
                            sub: 'Enfriando ${formatDuration(_cooldownSec)}',
                            icon: Icons.check,
                            onTap: _finish,
                          ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Row(
                children: [
                  if (_phase == CounterPhase.circuit) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _marks.isEmpty ? null : _undoRound,
                        icon: const Icon(Icons.undo),
                        label: const Text('Deshacer'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _endCircuit,
                        icon: const Icon(Icons.stop),
                        label: const Text('Terminar circuito'),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _finish,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Guardar y continuar'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      );
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.sub, required this.icon, required this.onTap});

  final String label;
  final String sub;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: scheme.onPrimaryContainer),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .displayMedium
                    ?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(sub, style: TextStyle(color: scheme.onPrimaryContainer)),
            ],
          ),
        ),
      ),
    );
  }
}
