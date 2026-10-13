import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/daily_routines.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/mobility.dart';
import '../../domain/recovery.dart' show sorenessZones;
import '../../ui/exercise_figure_3d_view.dart';
import '../../ui/progress_ring.dart';
import '../../ui/session_style.dart';
import '../../ui/widgets.dart';
import 'technique_sheet.dart';

/// Lo que devuelve el cronómetro de movilidad al cerrarse con "Guardar".
class MobilityResult {
  const MobilityResult({
    required this.startedAt,
    required this.totalSec,
    required this.stepsDone,
    required this.stepsTotal,
  });

  final DateTime startedAt;
  final int totalSec;
  final int stepsDone;
  final int stepsTotal;

  bool get complete => stepsDone >= stepsTotal;
}

/// Abre la rutina y, si se guarda, la registra como sesión de movilidad con
/// su id en `mode`: sin carga ni cadena intensa, fuera de adherencia y
/// récords. La recuperación activa (§19.17) pide el RPE y mantiene la racha;
/// con RPE > 5 ofrece guardarla como sesión normal.
Future<void> startMobility(BuildContext context, WidgetRef ref, {MobilityRoutine routine = mobilityNight}) async {
  final result = await Navigator.push<MobilityResult>(
    context,
    MaterialPageRoute(builder: (_) => MobilityScreen(routine: routine)),
  );
  if (result == null || !context.mounted) return;
  final start = result.startedAt;
  final recovery = routine.id == recoveryActiveId;
  int? rpe;
  var type = SessionType.movilidad;
  if (recovery) {
    rpe = await askRecoveryRpe(context);
    if (!context.mounted) return;
    if (rpe != null && rpe > recoveryMaxRpe) {
      final normal = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Esto ya no fue recuperación'),
          content: Text('Con RPE $rpe cuenta como carga. ¿La guardo como sesión normal?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Dejar como recuperación')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sesión normal')),
          ],
        ),
      );
      if (normal == null || !context.mounted) return;
      if (normal) type = SessionType.otro;
    }
  }
  final saved = await guarded(
    context,
    () => ref.read(trainingRepositoryProvider).save(SessionDraft(
          date: dateOnly(start),
          startTime: timeKey(start.hour, start.minute),
          type: type,
          totalSec: result.totalSec,
          incomplete: !result.complete,
          rpe: rpe,
          mode: type == SessionType.movilidad ? routine.id : null,
          notes: routine.name,
        )),
    ok: type == SessionType.movilidad
        ? 'Movilidad guardada · ${formatDuration(result.totalSec)}'
        : 'Sesión guardada · ${formatDuration(result.totalSec)}',
  );
  if (!saved || !context.mounted) return;
  // "¿Algo tirante o con molestia?" (§19.15): alimenta el aviso de molestias.
  final sore = await askTightness(context);
  if (sore == null || !context.mounted) return;
  await guarded(context, () => ref.read(recoveryRepositoryProvider).addSoreness(dateOnly(start), sore.$1, sore.$2),
      ok: 'Molestia anotada');
}

/// RPE al cerrar la recuperación activa. null = no lo puso.
Future<int?> askRecoveryRpe(BuildContext context) {
  var value = 3;
  return showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('¿Qué tan dura se sintió?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('RPE $value', style: Theme.of(c).textTheme.headlineSmall),
          Slider(value: value.toDouble(), min: 1, max: 10, divisions: 9, onChanged: (v) => set(() => value = v.round())),
          const Text('Recuperación es 3–4: cómodo, sin cansarte para mañana.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Omitir')),
          FilledButton(onPressed: () => Navigator.pop(c, value), child: const Text('Listo')),
        ],
      ),
    ),
  );
}

/// "¿Algo tirante o con molestia?": zona y 1–10. null = nada.
Future<(String, int)?> askTightness(BuildContext context) {
  String? zone;
  var level = 3;
  return showDialog<(String, int)>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('¿Algo tirante o con molestia?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final z in sorenessZones)
                ChoiceChip(label: Text(z), selected: zone == z, onSelected: (_) => set(() => zone = zone == z ? null : z)),
            ]),
            if (zone != null) ...[
              const SizedBox(height: 8),
              Text('$zone: $level/10'),
              Slider(value: level.toDouble(), min: 1, max: 10, divisions: 9, onChanged: (v) => set(() => level = v.round())),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Nada')),
          FilledButton(onPressed: zone == null ? null : () => Navigator.pop(c, (zone!, level)), child: const Text('Anotar')),
        ],
      ),
    ),
  );
}

class MobilityScreen extends StatefulWidget {
  const MobilityScreen({super.key, this.routine = mobilityNight});

  final MobilityRoutine routine;

  @override
  State<MobilityScreen> createState() => _MobilityScreenState();
}

class _MobilityScreenState extends State<MobilityScreen> {
  late final List<MobilityStep> _steps = buildMobilityScript(widget.routine);
  final DateTime _startedAt = clock.now();
  late DateTime _stepStartedAt = _startedAt;
  DateTime? _endedAt;
  int _index = 0;

  /// Pasos terminados (con "Hecho" o al acabar su tiempo), no los saltados a
  /// medias con "Terminar".
  int _done = 0;
  Timer? _ticker;

  MobilityStep get _step => _steps[_index];
  bool get _finished => _endedAt != null;
  int get _elapsedSec => (_endedAt ?? clock.now()).difference(_startedAt).inSeconds;
  int get _stepElapsedSec => clock.now().difference(_stepStartedAt).inSeconds;

  /// Segundos de preparación que faltan (0 si ya corre el ejercicio).
  int get _leadInLeft => _step.timed ? (mobilityLeadInSec - _stepElapsedSec).clamp(0, mobilityLeadInSec) : 0;

  /// Segundos que faltan del ejercicio por tiempo.
  int get _holdLeft => _step.exercise.durationSec! - (_stepElapsedSec - mobilityLeadInSec).clamp(0, 1 << 30);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  void _tick() {
    if (!mounted || _finished) return;
    if (_step.timed && _holdLeft <= 0) {
      unawaited(SystemSound.play(SystemSoundType.alert));
      unawaited(HapticFeedback.heavyImpact());
      _next();
      return;
    }
    setState(() {});
  }

  void _next() {
    setState(() {
      _done++;
      if (_index + 1 >= _steps.length) {
        _endedAt = clock.now();
        unawaited(HapticFeedback.heavyImpact());
      } else {
        _index++;
        _stepStartedAt = clock.now();
        unawaited(HapticFeedback.mediumImpact());
      }
    });
  }

  void _finishNow() => setState(() => _endedAt = clock.now());

  Future<bool> _confirmExit() async {
    if (_finished) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Salir de la movilidad?'),
        content: const Text('No se guarda nada. Si quieres registrar lo que hiciste, usa "Terminar".'),
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
    final style = styleForSession(SessionType.movilidad);
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _confirmExit() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.routine.name),
          actions: [
            if (!_finished) TextButton(onPressed: _finishNow, child: const Text('Terminar')),
          ],
        ),
        body: _finished ? _summary(context, style) : _running(context, style),
      ),
    );
  }

  Widget _running(BuildContext context, SessionStyle style) {
    final text = Theme.of(context).textTheme;
    final step = _step;
    final next = _index + 1 < _steps.length ? _steps[_index + 1] : null;
    final leadIn = _leadInLeft;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Text('Paso ${_index + 1}/${_steps.length}', style: text.labelLarge),
            const Spacer(),
            Text(formatDuration(_elapsedSec), style: text.labelLarge),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: _index / _steps.length, color: style.color),
        if (widget.routine.intensity != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Intensidad ${widget.routine.intensity}', style: text.bodySmall),
          ),
        const SizedBox(height: 20),
        Text(step.exercise.name, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (step.exercise.purpose != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(step.exercise.purpose!, style: text.bodyMedium),
          ),
        if (step.detail.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(step.detail, style: text.titleMedium?.copyWith(color: style.color)),
          ),
        const SizedBox(height: 20),
        Center(
          child: step.timed
              ? ProgressRing(
                  size: 200,
                  stroke: 14,
                  color: style.color,
                  progress: leadIn > 0 ? 1 - leadIn / mobilityLeadInSec : 1 - _holdLeft / step.exercise.durationSec!,
                  value: '${leadIn > 0 ? leadIn : _holdLeft}',
                  sublabel: leadIn > 0 ? 'prepárate' : 'segundos',
                  label: leadIn > 0 ? 'Colócate' : 'Aguanta',
                )
              : Column(
                  children: [
                    Text(step.target, style: text.displayMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: style.color, minimumSize: const Size(200, 56)),
                      onPressed: _next,
                      icon: const Icon(Icons.check),
                      label: const Text('Hecho'),
                    ),
                  ],
                ),
        ),
        if (step.timed)
          Center(
            child: TextButton(onPressed: _next, child: const Text('Saltar')),
          ),
        const SizedBox(height: 12),
        AppCard(
          title: 'Técnica',
          children: [
            ExerciseFigureView(exercise: step.exercise.name, side: step.side),
            const SizedBox(height: 14),
            for (final cue in step.exercise.formCues)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $cue', style: text.bodyMedium),
              ),
            const SizedBox(height: 8),
            ExerciseReferencePhoto(exercise: step.exercise.name),
          ],
        ),
        if (next != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Luego: ${next.exercise.name}${next.detail.isEmpty ? '' : ' · ${next.detail}'} (${next.target})',
              style: text.bodyMedium,
            ),
          ),
      ],
    );
  }

  Widget _summary(BuildContext context, SessionStyle style) {
    final text = Theme.of(context).textTheme;
    final done = _done;
    final complete = done >= _steps.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.self_improvement, size: 64, color: style.color),
        const SizedBox(height: 12),
        Text(complete ? 'Rutina completa' : 'Rutina a medias', textAlign: TextAlign.center, style: text.headlineSmall),
        const SizedBox(height: 8),
        Text('${formatDuration(_elapsedSec)} · $done de ${_steps.length} pasos',
            textAlign: TextAlign.center, style: text.titleMedium),
        const SizedBox(height: 8),
        Text(
            widget.routine.id == recoveryActiveId
                ? 'Cuenta como recuperación: mantiene la racha y no suma carga.'
                : 'Es opcional: no cuenta para adherencia, récords ni racha.',
            textAlign: TextAlign.center,
            style: text.bodySmall),
        if (widget.routine.closingNote != null) ...[
          const SizedBox(height: 12),
          Text(widget.routine.closingNote!, textAlign: TextAlign.center, style: text.bodyMedium),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: style.color),
          onPressed: () => Navigator.pop(
            context,
            MobilityResult(startedAt: _startedAt, totalSec: _elapsedSec, stepsDone: done, stepsTotal: _steps.length),
          ),
          icon: const Icon(Icons.save),
          label: const Text('Guardar'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Salir sin guardar')),
      ],
    );
  }
}
