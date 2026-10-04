import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../domain/dates.dart';
import '../../ui/progress_ring.dart';
import '../../ui/theme.dart';

/// Pasos que da una caminata de 10 min en casa o en el pasillo (§18.10).
const stepsPerWalk = 1100;

/// Caminatas de 10 min que faltan para la meta; 0 si ya se llegó.
int walksLeft(int steps, int goal) => steps >= goal ? 0 : ((goal - steps) / stepsPerWalk).ceil();

/// Caminata de 10 min con cuenta regresiva (§18.10: el barrio no deja
/// caminar cómodo, así que se camina en casa después de cada comida). Los
/// pasos los cuenta el reloj; aquí solo se mide el tiempo.
class WalkScreen extends StatefulWidget {
  const WalkScreen({super.key, this.minutes = 10});

  final int minutes;

  @override
  State<WalkScreen> createState() => _WalkScreenState();
}

class _WalkScreenState extends State<WalkScreen> {
  late final int _totalSec = widget.minutes * 60;

  /// Segundos ya caminados en tramos anteriores (pausas incluidas fuera).
  int _doneSec = 0;
  DateTime? _runningSince;
  Timer? _ticker;
  bool _finished = false;

  int get _elapsed => _doneSec + (_runningSince == null ? 0 : clock.now().difference(_runningSince!).inSeconds);
  int get _left => (_totalSec - _elapsed).clamp(0, _totalSec);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  void _tick() {
    if (_runningSince != null && _left == 0 && !_finished) {
      _finished = true;
      _doneSec = _totalSec;
      _runningSince = null;
      unawaited(HapticFeedback.heavyImpact());
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    if (mounted) setState(() {});
  }

  void _toggle() => setState(() {
        if (_runningSince == null) {
          _runningSince = clock.now();
        } else {
          _doneSec = _elapsed;
          _runningSince = null;
        }
      });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final running = _runningSince != null;
    return Scaffold(
      appBar: AppBar(title: Text('Caminata de ${widget.minutes} min')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Spacer(),
            ProgressRing(
              progress: _elapsed / _totalSec,
              value: formatDuration(_left),
              label: _finished ? '¡Hecha!' : (running ? 'caminando' : 'en pausa'),
              sublabel: '≈ $stepsPerWalk pasos',
              color: AppColors.steps,
              size: 240,
              stroke: 16,
            ),
            const SizedBox(height: 24),
            Text(
              _finished
                  ? 'Listo: el reloj suma los pasos solo. Desliza Hoy hacia abajo para traerlos.'
                  : 'En casa o en el pasillo, a ritmo de conversación. Sirve también durante una llamada.',
              textAlign: TextAlign.center,
              style: text.bodyLarge,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: _finished
                  ? FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check),
                      label: const Text('Terminar'),
                    )
                  : FilledButton.icon(
                      onPressed: _toggle,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.steps),
                      icon: Icon(running ? Icons.pause : Icons.play_arrow),
                      label: Text(running ? 'Pausar' : (_elapsed == 0 ? 'Empezar' : 'Seguir')),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
