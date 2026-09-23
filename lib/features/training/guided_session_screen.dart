import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../data/repositories/plan_repository.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/progress.dart';
import '../../domain/session_math.dart' show meanSec;
import '../../domain/session_script.dart';
import '../../ui/progress_ring.dart';
import '../../ui/session_style.dart';
import '../../ui/widgets.dart';

/// Convierte el día del plan en algo que el guion entiende.
ScriptDay scriptDayFrom(PlanDayDraft day) => ScriptDay(
      type: day.type,
      targetRounds: day.targetRounds,
      restBetweenRoundsSec: day.restBetweenRoundsSec,
      exercises: [
        for (final e in day.exercises)
          ScriptExercise(
            name: e.name,
            sets: e.sets,
            repsMin: e.repsMin,
            repsMax: e.repsMax,
            restSec: e.restSec,
            restSecMax: e.restSecMax,
            holdSecMin: e.holdSecMin,
            holdSecMax: e.holdSecMax,
            perSide: e.perSide,
            blockName: e.block,
            variant: e.variant,
            grip: e.grip,
          ),
      ],
    );

/// Calentamiento y enfriamiento son fases iguales: pantalla propia, reloj
/// visible y botón para cerrarlas. El enfriamiento no se salta por accidente.
enum _Phase { calentamiento, trabajo, enfriamiento, terminado }

class _Done {
  _Done(this.exercise, this.reps, this.isRound);

  final String exercise;
  final int reps;
  final bool isRound;
}

/// Cronómetro que sabe qué toca: recorre el guion del día paso a paso, lleva
/// los descansos solo y separa calentamiento, trabajo neto y enfriamiento.
class GuidedSessionScreen extends ConsumerStatefulWidget {
  const GuidedSessionScreen({
    super.key,
    required this.day,
    required this.date,
    this.planDayId,
    this.sessionType,
    this.coreVariant,
    this.roundsOverride,
  });

  final PlanDayDraft day;
  final DateTime date;
  final int? planDayId;
  final SessionType? sessionType;
  final String? coreVariant;
  final int? roundsOverride;

  @override
  ConsumerState<GuidedSessionScreen> createState() => _GuidedSessionScreenState();
}

class _GuidedSessionScreenState extends ConsumerState<GuidedSessionScreen> {
  late final List<ScriptStep> _steps =
      buildScript(scriptDayFrom(widget.day), rounds: widget.roundsOverride, coreVariant: widget.coreVariant);
  late final int _exercisesPerRound = widget.day.main.isEmpty ? 1 : widget.day.main.length;

  final _startedAt = DateTime.now();
  DateTime? _workStartedAt;
  DateTime? _workEndedAt;
  DateTime? _endedAt;
  DateTime? _restStartedAt;

  final _done = <_Done>[];

  /// Segundos desde el inicio del trabajo al cerrar cada ronda.
  final _roundMarks = <int>[];

  int _index = 0;
  int? _reps;
  _Phase _phase = _Phase.calentamiento;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WakelockPlus.disable();
    unawaited(ref.read(notificationServiceProvider).cancelRestEnd());
    super.dispose();
  }

  ScriptStep? get _current => _index < _steps.length ? _steps[_index] : null;

  DateTime get _clock => _endedAt ?? DateTime.now();
  int get _totalSec => _clock.difference(_startedAt).inSeconds;
  int get _warmupSec => (_workStartedAt ?? DateTime.now()).difference(_startedAt).inSeconds;
  /// Con el trabajo cerrado, neto = total − calentamiento − enfriamiento: la
  /// misma cuenta del formulario, para que ambos muestren el mismo número.
  int get _netSec {
    if (_workStartedAt == null) return 0;
    if (_workEndedAt == null) return DateTime.now().difference(_workStartedAt!).inSeconds;
    final net = _totalSec - _warmupSec - _cooldownSec;
    return net < 0 ? 0 : net;
  }
  int get _cooldownSec => _workEndedAt == null ? 0 : _clock.difference(_workEndedAt!).inSeconds;

  /// Metas del plan: 6 min antes y 3 min después; menos de 1 min no es enfriar.
  static const _warmupGoalSec = 360;
  static const _cooldownGoalSec = 180;
  static const _cooldownMinSec = 60;

  int get _restRemaining {
    final step = _current;
    if (step is! RestStep || _restStartedAt == null) return 0;
    final elapsed = DateTime.now().difference(_restStartedAt!).inSeconds;
    return step.seconds - elapsed;
  }

  void _tick() {
    final step = _current;
    if (step is RestStep && _restStartedAt != null && _restRemaining <= 0) {
      _alertRestOver();
      _advance();
      return;
    }
    setState(() {});
  }

  /// Sonido + vibración al cerrar el descanso. Con la app en segundo plano
  /// esto no suena: eso llega con las notificaciones locales.
  void _alertRestOver() {
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(HapticFeedback.heavyImpact());
  }

  void _startWork() => setState(() {
        _workStartedAt = DateTime.now();
        _phase = _Phase.trabajo;
        _prepareStep();
      });

  void _prepareStep() {
    final step = _current;
    final notifications = ref.read(notificationServiceProvider);
    if (step is WorkStep) {
      _reps = step.targetReps;
      _restStartedAt = null;
      unawaited(notifications.cancelRestEnd());
    } else if (step is RestStep) {
      _restStartedAt = DateTime.now();
      // Con la app en segundo plano el sonido no llega: la notificación sí.
      unawaited(notifications
          .scheduleRestEnd(inSeconds: Duration(seconds: step.seconds), nextLabel: step.nextLabel)
          .then(_warnIfInexact));
    }
  }

  bool _warnedInexact = false;

  /// Una sola vez por sesión: sin alarma exacta, el aviso con la pantalla
  /// apagada puede llegar tarde. Aquí se dice dónde arreglarlo.
  void _warnIfInexact(bool exact) {
    if (exact || _warnedInexact || !mounted) return;
    _warnedInexact = true;
    showSnack(context, 'Con la pantalla apagada el fin del descanso puede avisar tarde. '
        'Permite alarmas exactas en Ajustes › Recordatorios.');
  }

  void _completeWork() {
    final step = _current as WorkStep;
    _done.add(_Done(step.exercise, _reps ?? step.targetReps ?? 0, step.isRound));

    // Al cerrar la última parada de una ronda, queda la marca de la vuelta.
    if (step.isRound && _done.where((d) => d.isRound).length % _exercisesPerRound == 0) {
      _roundMarks.add(DateTime.now().difference(_workStartedAt!).inSeconds);
      unawaited(HapticFeedback.mediumImpact());
    }
    _advance();
  }

  void _advance() {
    setState(() {
      _index++;
      if (_current == null) {
        _endWork();
      } else {
        _prepareStep();
      }
    });
  }

  void _endWork() {
    _workEndedAt ??= DateTime.now();
    _phase = _Phase.enfriamiento;
    unawaited(ref.read(notificationServiceProvider).cancelRestEnd());
    unawaited(HapticFeedback.mediumImpact());
  }

  /// Cierra el enfriamiento. Por debajo del mínimo pide confirmación: guardar
  /// una sesión con 12 s de enfriamiento casi siempre es un descuido.
  Future<void> _finishCooldown() async {
    if (_cooldownSec < _cooldownMinSec) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Enfriamiento muy corto'),
          content: Text('Llevas ${formatDuration(_cooldownSec)}. El plan pide al menos 1 min '
              '(la meta son 3).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Terminar')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _endedAt = DateTime.now();
      _phase = _Phase.terminado;
    });
    unawaited(HapticFeedback.heavyImpact());
  }

  void _skipRest() {
    _restStartedAt = null;
    unawaited(ref.read(notificationServiceProvider).cancelRestEnd());
    _advance();
  }

  Future<void> _finishEarly() async {
    final pending = _steps.length - _index;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Terminar antes?'),
        content: Text('Quedan $pending pasos del plan. La sesión se guarda como incompleta, '
            'con lo que alcanzaste a hacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Terminar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _index = _steps.length;
      _endWork();
    });
  }

  SessionDraft _buildDraft() {
    final isCircuit = widget.day.type.isCircuit;
    final rounds = isCircuit ? completedRounds(_steps, _index, exercisesPerRound: _exercisesPerRound) : null;
    return SessionDraft(
      date: widget.date,
      startTime: timeKey(_startedAt.hour, _startedAt.minute),
      type: widget.sessionType ?? _typeFor(widget.day.type),
      planDayId: widget.planDayId,
      totalSec: _totalSec,
      warmupSec: _warmupSec,
      cooldownSec: _cooldownSec,
      roundsDone: rounds,
      plannedRounds: isCircuit ? (widget.roundsOverride ?? widget.day.targetRounds) : workStepCount(_steps),
      incomplete: _index < _steps.length,
      roundMarksSec: List.of(_roundMarks),
      sets: [for (final d in _done) SetDraft(exercise: d.exercise, reps: d.reps)],
    );
  }

  static SessionType _typeFor(DayType type) => switch (type) {
        DayType.circuito => SessionType.circuito,
        DayType.circuitoLigero => SessionType.circuitoLigero,
        DayType.progresion => SessionType.progresion,
        DayType.bloques => SessionType.bloques,
        _ => SessionType.otro,
      };

  @override
  Widget build(BuildContext context) {
    final finished = _phase == _Phase.terminado;
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (_done.isEmpty || await _confirmExit()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.day.type.label),
          actions: [
            if (_phase == _Phase.trabajo) TextButton(onPressed: _finishEarly, child: const Text('Terminar')),
          ],
        ),
        body: Column(
          children: [
            _timesBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                // Cada paso entra deslizándose: el cambio de ejercicio se siente.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: [...previous, if (current != null) current],
                  ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.12, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(key: ValueKey('${_phase.name}-$_index'), child: _body(finished)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timesBar() => AppCard(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat('Total', formatDuration(_totalSec)),
              _Stat('Calent.', formatDuration(_warmupSec)),
              _Stat('Neto', formatDuration(_netSec)),
              _Stat('Enfr.', formatDuration(_cooldownSec)),
            ],
          ),
        ],
      );

  Widget _body(bool finished) {
    if (_phase == _Phase.calentamiento) {
      return _PhasePanel(
        title: 'Calentando',
        seconds: _warmupSec,
        goalSec: _warmupGoalSec,
        detail: _warmupSec < _warmupGoalSec
            ? 'Faltan ${formatDuration(_warmupGoalSec - _warmupSec)} para los 6 min del plan'
            : 'Calentamiento cumplido',
        action: 'Empezar ${widget.day.type.label.toLowerCase()}',
        icon: Icons.play_arrow,
        onAction: _startWork,
        footer: _planPreview(),
      );
    }
    if (_phase == _Phase.enfriamiento) {
      return _PhasePanel(
        title: 'Enfriando',
        seconds: _cooldownSec,
        goalSec: _cooldownGoalSec,
        detail: _cooldownSec < _cooldownGoalSec
            ? 'Estira y respira. Faltan ${formatDuration(_cooldownGoalSec - _cooldownSec)} para los 3 min'
            : 'Enfriamiento cumplido',
        action: 'Terminar enfriamiento',
        icon: Icons.check,
        onAction: _finishCooldown,
        footer: _doneSoFar(),
      );
    }
    if (finished) return _summary();

    final step = _current;
    if (step is RestStep) return _rest(step);
    if (step is WorkStep) return _work(step);
    return const SizedBox.shrink();
  }

  Widget _work(WorkStep step) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final target = step.targetReps;
    final next = _nextWorkLabel();
    return Column(
      children: [
        Text(step.counterLabel.toUpperCase(), style: text.titleMedium?.copyWith(letterSpacing: 2)),
        if (step.blockName != null) Text('Bloque ${step.blockName}', style: text.bodySmall),
        const SizedBox(height: 8),
        Text(
          step.exercise,
          textAlign: TextAlign.center,
          style: text.headlineMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
        ),
        if (step.grip != null) Text('Agarre ${step.grip}', style: text.titleMedium),
        const Spacer(),
        // El anillo se llena al llegar al objetivo: ajustar reps se ve.
        if (target != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: (_reps ?? 0) > 0 ? () => setState(() => _reps = _reps! - 1) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ProgressRing(
                  progress: target == 0 ? 1 : (_reps ?? 0) / target,
                  value: '${_reps ?? 0}',
                  sublabel: 'de $target reps',
                  label: '',
                  size: 200,
                  stroke: 14,
                  color: (_reps ?? 0) >= target ? scheme.primary : scheme.primary.withOpacity(0.6),
                ),
              ),
              IconButton.filledTonal(
                iconSize: 32,
                onPressed: () => setState(() => _reps = (_reps ?? 0) + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          )
        else
          Text(step.targetLabel,
              textAlign: TextAlign.center,
              style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const Spacer(),
        if (next != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('Después: $next', textAlign: TextAlign.center, style: text.bodyLarge),
          ),
        _sessionProgress(),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: _BigButton(label: 'Hecho', icon: Icons.check, onTap: _completeWork),
        ),
      ],
    );
  }

  Widget _rest(RestStep step) {
    final remaining = _restRemaining.clamp(0, step.seconds);
    // El anillo se vacía con el tiempo que queda: se lee de un vistazo.
    final left = step.seconds == 0 ? 0.0 : remaining / step.seconds;
    // Si este descanso viene de cerrar una ronda, se celebra la vuelta.
    final prev = _index > 0 ? _steps[_index - 1] : null;
    final roundsClosed = _done.where((d) => d.isRound).length;
    final closedRound =
        prev is WorkStep && prev.isRound && roundsClosed > 0 && roundsClosed % _exercisesPerRound == 0
            ? prev.position
            : null;
    final laps = _roundMarks.isEmpty ? const <int>[] : lapDurationsOf(_roundMarks);
    return Column(
      children: [
        if (closedRound != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RoundBadge(round: closedRound, lapSec: laps.isEmpty ? null : laps.last),
          ),
        Text('DESCANSO', style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 2)),
        const SizedBox(height: 16),
        ProgressRing(
          progress: left,
          value: formatDuration(remaining),
          sublabel: 'plan ${step.label}',
          label: '',
          size: 200,
          stroke: 14,
          color: const Color(0xFF4EA8FF),
        ),
        const SizedBox(height: 12),
        Text('A continuación', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(step.nextLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        _sessionProgress(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: _skipRest,
            icon: const Icon(Icons.skip_next),
            label: const Text('Saltar descanso'),
          ),
        ),
      ],
    );
  }

  /// Barra de avance de la sesión: cuánto va de lo que pide el plan.
  Widget _sessionProgress() {
    final total = workStepCount(_steps);
    final done = _done.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 8,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 6),
        Text(
            widget.day.type.isCircuit ? '$done de $total ejercicios hechos' : '$done de $total series hechas',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  /// Mientras calienta, el circuito a la vista: llega sabiendo qué sigue.
  Widget _planPreview() {
    final seen = <String>{};
    final lines = [
      for (final s in _steps)
        if (s is WorkStep && seen.add(s.exercise))
          [s.exercise, s.targetLabel, if (s.grip != null) s.grip!].join(' · '),
    ];
    final isCircuit = widget.day.type.isCircuit;
    final rounds = widget.roundsOverride ?? widget.day.targetRounds;
    return AppCard(
      margin: EdgeInsets.zero,
      title: isCircuit && rounds != null ? 'Lo que viene · $rounds ${rounds == 1 ? 'ronda' : 'rondas'}' : 'Lo que viene',
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• $l', style: Theme.of(context).textTheme.bodyLarge),
          ),
      ],
    );
  }

  /// En el enfriamiento, lo logrado: motiva a cerrar bien en vez de cortar.
  Widget _doneSoFar() {
    final isCircuit = widget.day.type.isCircuit;
    final rounds = isCircuit ? completedRounds(_steps, _index, exercisesPerRound: _exercisesPerRound) : null;
    final reps = _done.fold<int>(0, (a, d) => a + d.reps);
    return AppCard(
      margin: EdgeInsets.zero,
      title: 'Ya hiciste',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (rounds != null) _Stat('Rondas', '$rounds'),
            if (rounds == null) _Stat('Series', '${_done.length}'),
            _Stat('Reps', '$reps'),
            _Stat('Neto', formatDuration(_netSec)),
          ],
        ),
      ],
    );
  }

  /// Lo que viene después del paso actual, para no tener que pensar.
  String? _nextWorkLabel() {
    for (var i = _index + 1; i < _steps.length; i++) {
      final s = _steps[i];
      if (s is WorkStep) return '${s.exercise} · ${s.targetLabel}';
    }
    return null;
  }

  Widget _summary() {
    final draft = _buildDraft();
    final laps = _roundMarks.isEmpty ? <int>[] : lapDurationsOf(_roundMarks);
    return ListView(
      children: [
        _CompletionHeader(draft: draft, lapsSec: laps, color: styleForDay(widget.day.type).color),
        const SizedBox(height: 12),
        // Sin el margen de AppCard: aquí ya hay padding y quedaba más angosta
        // que la cabecera.
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _SummaryRow('Calentamiento', formatDuration(draft.warmupSec)),
                _SummaryRow('Trabajo neto', formatDuration(_netSec)),
                _SummaryRow('Enfriamiento', formatDuration(draft.cooldownSec)),
                _SummaryRow('Total', formatDuration(draft.totalSec)),
                const Divider(),
                if (draft.roundsDone != null)
                  _SummaryRow('Rondas', '${draft.roundsDone} de ${draft.plannedRounds ?? '—'}')
                else
                  _SummaryRow('Series', '${_done.length} de ${draft.plannedRounds ?? '—'}'),
                if (laps.isNotEmpty) _SummaryRow('Tiempo por ronda', laps.map(formatDuration).join(' · ')),
                if (draft.incomplete) const _SummaryRow('Cierre', 'Incompleta'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, draft),
          icon: const Icon(Icons.save),
          label: const Text('Revisar y guardar'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Descartar'),
        ),
      ],
    );
  }

  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('Se pierde todo lo de esta sesión.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salir')),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// Marcas acumuladas → duración de cada vuelta.
List<int> lapDurationsOf(List<int> marks) {
  final out = <int>[];
  var prev = 0;
  for (final m in marks) {
    out.add(m - prev);
    prev = m;
  }
  return out;
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      );
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: scheme.onPrimary),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Insignia al cerrar una ronda: entra con rebote para que se note el logro.
class _RoundBadge extends StatelessWidget {
  const _RoundBadge({required this.round, this.lapSec});

  final int round;
  final int? lapSec;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF7ED957);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: green.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: green),
            const SizedBox(width: 8),
            Text(
              lapSec == null ? 'Ronda $round lista' : 'Ronda $round lista · ${formatDuration(lapSec!)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: green, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fase con reloj propio y meta visible: calentamiento y enfriamiento se ven y
/// se cierran igual.
class _PhasePanel extends StatelessWidget {
  const _PhasePanel({
    required this.title,
    required this.seconds,
    required this.goalSec,
    required this.detail,
    required this.action,
    required this.icon,
    required this.onAction,
    this.footer,
  });

  final String title;
  final Widget? footer;
  final int seconds;
  final int goalSec;
  final String detail;
  final String action;
  final IconData icon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final done = seconds >= goalSec;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(title.toUpperCase(), style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 2)),
        const SizedBox(height: 16),
        ProgressRing(
          progress: goalProgress(seconds, goalSec),
          value: formatDuration(seconds),
          sublabel: 'meta ${formatDuration(goalSec)}',
          label: '',
          size: 200,
          stroke: 14,
          color: done ? const Color(0xFF7ED957) : scheme.primary,
        ),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        const Spacer(),
        if (footer != null) ...[footer!, const SizedBox(height: 12)],
        SizedBox(height: 110, child: _BigButton(label: action, icon: icon, onTap: onAction)),
      ],
    );
  }
}

/// Cierre de sesión: medalla animada y un mensaje con el dato real de hoy
/// frente a la sesión anterior del mismo tipo.
class _CompletionHeader extends ConsumerStatefulWidget {
  const _CompletionHeader({required this.draft, required this.lapsSec, required this.color});

  final SessionDraft draft;
  final List<int> lapsSec;
  final Color color;

  @override
  ConsumerState<_CompletionHeader> createState() => _CompletionHeaderState();
}

class _CompletionHeaderState extends ConsumerState<_CompletionHeader> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  late final Future<SessionComparison> _comparison = _compare();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<SessionComparison> _compare() async {
    final d = widget.draft;
    final repo = ref.read(trainingRepositoryProvider);
    final previous = await repo.previousOfType(d.type, d.date);
    final best = d.type.isCircuit ? await repo.bestRounds() : null;
    // Misma regla que Hoy y el informe: cuentan las rondas hechas, aunque la
    // sesión se cerrara antes; no cuentan las estimadas.
    final record = d.type.isCircuit && d.roundsDone != null && !d.roundsEstimated && isRecord(d.roundsDone!, best);
    return SessionComparison(
      rounds: d.roundsDone,
      plannedRounds: d.plannedRounds,
      meanLapSec: meanSec(widget.lapsSec),
      previousRounds: previous?.$2,
      previousMeanLapSec: previous == null ? null : meanSec(lapDurationsOf(previous.$3)),
      previousDateLabel:
          previous == null ? null : 'el ${weekdayLong(previous.$1.weekday).toLowerCase()} ${previous.$1.day}',
      incomplete: d.incomplete,
      isRecord: record,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<SessionComparison>(
      future: _comparison,
      builder: (context, snap) {
        final c = snap.data;
        final (title, body) = c == null ? ('Sesión terminada', '') : sessionPraise(c);
        final record = c?.isRecord ?? false;
        final color = record ? const Color(0xFFFFC53D) : widget.color;
        return AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final t = Curves.easeOutBack.transform(_anim.value.clamp(0.0, 1.0));
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.30), Colors.transparent],
                ),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Transform.scale(
                    scale: 0.4 + 0.6 * t,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withOpacity(0.18),
                        boxShadow: [
                          BoxShadow(
                              color: color.withOpacity(0.45 * _anim.value), blurRadius: 32, spreadRadius: 4),
                        ],
                      ),
                      child: Icon(record ? Icons.emoji_events : Icons.military_tech, size: 56, color: color),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: _anim.value,
                    child: Column(
                      children: [
                        Text(title,
                            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: color)),
                        if (body.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(body, textAlign: TextAlign.center, style: text.titleMedium),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
