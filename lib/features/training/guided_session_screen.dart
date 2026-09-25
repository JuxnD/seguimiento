import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../data/database.dart' show ExerciseRow;
import '../../data/notification_service.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/plan_repository.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/active_session.dart';
import '../../domain/dates.dart';
import '../../domain/energy.dart';
import '../../domain/format.dart';
import '../../domain/enums.dart';
import '../../domain/progress.dart';
import '../../domain/report/report_input.dart' show Targets;
import '../../domain/session_math.dart' show lapDurations, meanSec, roundWork;
import '../../domain/session_script.dart';
import '../../ui/progress_ring.dart';
import '../../ui/session_style.dart';
import '../../ui/widgets.dart';
import '../../ui/theme.dart';

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

// Calentamiento y enfriamiento son fases iguales (GuidedPhase): pantalla
// propia, reloj visible y botón para cerrarlas. El enfriamiento no se salta
// por accidente.

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
    this.resume,
  });

  final PlanDayDraft day;
  final DateTime date;
  final int? planDayId;
  final SessionType? sessionType;
  final String? coreVariant;
  final int? roundsOverride;

  /// Sesión que Android cerró a mitad: se retoma donde iba.
  final GuidedSnapshot? resume;

  @override
  ConsumerState<GuidedSessionScreen> createState() => _GuidedSessionScreenState();
}

class _GuidedSessionScreenState extends ConsumerState<GuidedSessionScreen> {
  late final List<ScriptStep> _steps =
      buildScript(scriptDayFrom(widget.day), rounds: widget.roundsOverride, coreVariant: widget.coreVariant);
  late final int _exercisesPerRound = widget.day.main.isEmpty ? 1 : widget.day.main.length;

  late final DateTime _startedAt = widget.resume?.startedAt ?? clock.now();
  late DateTime? _workStartedAt = widget.resume?.workStartedAt;
  late DateTime? _workEndedAt = widget.resume?.workEndedAt;
  late DateTime? _endedAt = widget.resume?.endedAt;
  late DateTime? _restStartedAt = widget.resume?.restStartedAt;

  /// Descansos ya cerrados, en segundos. El trabajo neto los descuenta.
  late int _restAccumSec = widget.resume?.restAccumSec ?? 0;

  late final _done = <DoneStep>[...?widget.resume?.done];

  /// Segundos desde el inicio del trabajo al cerrar cada ronda.
  late final _roundMarks = <int>[...?widget.resume?.roundMarks];

  /// Descanso después de cada ronda, en paralelo a `_roundMarks`. Así cada
  /// vuelta se separa en trabajo y descanso (una vuelta sola los mezcla).
  late final _roundRests = <int>[...?widget.resume?.roundRests];

  /// Guías de técnica de los ejercicios del día, por nombre.
  Map<String, ExerciseRow> _guides = const {};

  /// Carga externa (kg) por ejercicio: arranca en la última usada.
  final _loads = <String, double>{};

  late int _index = widget.resume?.index ?? 0;
  late int? _reps = widget.resume?.reps;
  late GuidedPhase _phase = widget.resume?.phase ?? GuidedPhase.calentamiento;
  Timer? _ticker;

  /// Se toma al iniciar: en `dispose` Riverpod ya no deja usar `ref`, y ahí
  /// hay que cancelar el aviso de fin de descanso.
  late final NotificationService _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = ref.read(notificationServiceProvider);
    unawaited(_loadGuides());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WakelockPlus.enable();
    // Una sesión retomada en mitad de un descanso vuelve a programar su aviso.
    if (widget.resume != null && _current is RestStep && _restStartedAt != null) {
      final left = (_current as RestStep).seconds - clock.now().difference(_restStartedAt!).inSeconds;
      if (left > 0) {
        unawaited(ref
            .read(notificationServiceProvider)
            .scheduleRestEnd(inSeconds: Duration(seconds: left), nextLabel: (_current as RestStep).nextLabel));
      }
    }
    _persist();
  }

  /// Foto del estado en disco: si Android mata la app, se retoma desde aquí.
  void _persist() => unawaited(ref.read(activeSessionStoreProvider).save(GuidedSnapshot(
        date: dayKey(widget.date),
        startedAt: _startedAt,
        planDayId: widget.planDayId ?? -1,
        sessionType: widget.sessionType,
        coreVariant: widget.coreVariant,
        roundsOverride: widget.roundsOverride,
        phase: _phase,
        index: _index,
        workStartedAt: _workStartedAt,
        workEndedAt: _workEndedAt,
        endedAt: _endedAt,
        restStartedAt: _restStartedAt,
        restAccumSec: _restAccumSec,
        reps: _reps,
        done: List.of(_done),
        roundMarks: List.of(_roundMarks),
        roundRests: List.of(_roundRests),
      )));

  /// Claves de técnica y última carga usada de cada ejercicio del guion.
  Future<void> _loadGuides() async {
    final names = {for (final st in _steps) if (st is WorkStep) st.exercise};
    try {
      final guides = await ref.read(exerciseRepositoryProvider).byNames(names);
      final training = ref.read(trainingRepositoryProvider);
      final loads = <String, double>{};
      for (final g in guides.values.where((g) => g.tracksLoad)) {
        loads[g.name] = await training.lastLoad(g.name) ?? 0;
      }
      if (!mounted) return;
      setState(() {
        _guides = guides;
        for (final e in loads.entries) {
          _loads.putIfAbsent(e.key, () => e.value);
        }
      });
    } on Object {
      // Sin guías el cronómetro funciona igual.
    }
  }

  /// Trabajo de cada ronda (sin descansos), o las vueltas completas si los
  /// descansos no se midieron (sesión retomada de una versión anterior).
  List<int> get _roundWork {
    if (_roundMarks.isEmpty) return const [];
    return roundWork(_roundMarks, _roundRests) ?? lapDurations(_roundMarks);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WakelockPlus.disable();
    unawaited(_notifications.cancelRestEnd());
    super.dispose();
  }

  ScriptStep? get _current => _index < _steps.length ? _steps[_index] : null;

  DateTime get _clock => _endedAt ?? clock.now();
  int get _totalSec => _clock.difference(_startedAt).inSeconds;
  int get _warmupSec => (_workStartedAt ?? clock.now()).difference(_startedAt).inSeconds;
  /// Descanso en curso: lo que va de la cuenta regresiva actual.
  int get _restNowSec {
    if (_current is! RestStep || _restStartedAt == null) return 0;
    return _restCap(clock.now().difference(_restStartedAt!).inSeconds);
  }

  /// Descansos de la sesión (cerrados + el que corre).
  int get _restSec => _restAccumSec + _restNowSec;

  /// Trabajo neto: desde que empieza el trabajo hasta que termina, sin los
  /// descansos. Es la misma cuenta del formulario (total − calentamiento −
  /// enfriamiento − descanso), para que ambos muestren el mismo número.
  int get _netSec {
    if (_workStartedAt == null) return 0;
    final span = (_workEndedAt ?? clock.now()).difference(_workStartedAt!).inSeconds;
    final net = span - _restSec;
    return net < 0 ? 0 : net;
  }

  /// Un descanso cuenta como mucho lo que pide el plan: si la app estuvo en
  /// segundo plano y el aviso ya sonó, el tiempo de más casi siempre fue
  /// trabajo, no descanso.
  int _restCap(int elapsed) {
    final step = _current;
    if (step is! RestStep) return elapsed;
    final max = step.maxSec ?? step.seconds;
    return elapsed.clamp(0, max);
  }

  /// Suma el descanso que corre al acumulado. Se llama al salir de un paso de
  /// descanso por cualquier camino: se acabó, se saltó o se terminó antes.
  void _closeRest() {
    if (_current is RestStep && _restStartedAt != null) {
      final rest = _restNowSec;
      _restAccumSec += rest;
      // En circuito el descanso va entre rondas: es de la ronda que acaba de cerrar.
      if (_roundMarks.isNotEmpty && _roundRests.length == _roundMarks.length) {
        _roundRests[_roundRests.length - 1] += rest;
      }
    }
    _restStartedAt = null;
  }

  /// Peso más reciente para estimar las kcal; null si no hay pesajes.
  double? get _weightKg => ref.read(latestWeightProvider);

  SessionType get _sessionType => widget.sessionType ?? widget.day.type.asSessionType;

  /// kcal aproximadas hasta ahora (MET por fase × peso × tiempo).
  double? get _kcal => sessionKcal(
        type: _sessionType,
        weightKg: _weightKg,
        warmupSec: _warmupSec,
        workSec: _netSec,
        restSec: _restSec,
        cooldownSec: _cooldownSec,
      );

  /// Repeticiones ya hechas de un ejercicio en esta sesión.
  int _repsSoFar(String exercise) =>
      _done.where((d) => d.exercise == exercise).fold(0, (sum, d) => sum + d.reps);
  int get _cooldownSec => _workEndedAt == null ? 0 : _clock.difference(_workEndedAt!).inSeconds;

  /// Metas del perfil (6 min antes y 3 min después por defecto). Menos de
  /// 1 min no es enfriar: esa es una definición, no una meta.
  late final int _warmupGoalSec = ref.read(profileProvider).value?.minWarmupSec ?? 360;
  late final int _cooldownGoalSec = ref.read(profileProvider).value?.cooldownTargetSec ?? 180;
  static const _cooldownMinSec = Targets.minCooldownSecDefault;

  int get _restRemaining {
    final step = _current;
    if (step is! RestStep || _restStartedAt == null) return 0;
    final elapsed = clock.now().difference(_restStartedAt!).inSeconds;
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

  /// Empezar antes de la meta de calentamiento se puede, pero se avisa: con
  /// 4–5 min se rinde peor.
  Future<void> _tryStartWork() async {
    if (_warmupSec < _warmupGoalSec) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Calentamiento corto'),
          content: Text('Llevas ${formatDuration(_warmupSec)} de ${formatDuration(_warmupGoalSec)}. '
              'Con menos de la meta sueles rendir peor.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Empezar igual')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir calentando')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _startWork();
  }

  void _startWork() {
    setState(() {
      _workStartedAt = clock.now();
      _phase = GuidedPhase.trabajo;
      _prepareStep();
    });
    _persist();
  }

  void _prepareStep() {
    final step = _current;
    final notifications = _notifications;
    if (step is WorkStep) {
      _reps = step.targetReps;
      _restStartedAt = null;
      unawaited(notifications.cancelRestEnd());
    } else if (step is RestStep) {
      _restStartedAt = clock.now();
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

  void _setReps(int value) {
    setState(() => _reps = value);
    _persist();
  }

  void _completeWork() {
    final step = _current as WorkStep;
    _done.add(DoneStep(step.exercise, _reps ?? step.targetReps ?? 0, step.isRound, loadKg: _loadFor(step.exercise)));

    // Al cerrar la última parada de una ronda, queda la marca de la vuelta.
    if (step.isRound && _done.where((d) => d.isRound).length % _exercisesPerRound == 0) {
      if (_roundRests.length == _roundMarks.length) _roundRests.add(0);
      _roundMarks.add(clock.now().difference(_workStartedAt!).inSeconds);
      unawaited(HapticFeedback.mediumImpact());
    }
    _advance();
  }

  void _advance() {
    setState(() {
      _closeRest();
      _index++;
      if (_current == null) {
        _endWork();
      } else {
        _prepareStep();
      }
    });
    _persist();
  }

  void _endWork() {
    _closeRest();
    _workEndedAt ??= clock.now();
    _phase = GuidedPhase.enfriamiento;
    unawaited(_notifications.cancelRestEnd());
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
          content: Text('Llevas ${formatDuration(_cooldownSec)}. Menos de 1 min no cuenta como enfriar '
              '(la meta es ${formatDuration(_cooldownGoalSec)}).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Terminar')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _endedAt = clock.now();
      _phase = GuidedPhase.terminado;
    });
    _persist();
    unawaited(HapticFeedback.heavyImpact());
  }

  void _skipRest() {
    unawaited(_notifications.cancelRestEnd());
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
      // El índice queda donde iba: de él salen "incompleta" y las rondas
      // completas. Antes se ponía al final y una sesión cortada se guardaba
      // como completa, con todas las rondas del plan.
      _closeRest();
      _endWork();
    });
    _persist();
  }

  SessionDraft _buildDraft() {
    final isCircuit = widget.day.type.isCircuit;
    final rounds = isCircuit ? completedRounds(_steps, _index, exercisesPerRound: _exercisesPerRound) : null;
    return SessionDraft(
      date: widget.date,
      startTime: timeKey(_startedAt.hour, _startedAt.minute),
      type: _sessionType,
      planDayId: widget.planDayId,
      totalSec: _totalSec,
      warmupSec: _warmupSec,
      cooldownSec: _cooldownSec,
      restSec: _restSec,
      roundsDone: rounds,
      plannedRounds: isCircuit ? (widget.roundsOverride ?? widget.day.targetRounds) : workStepCount(_steps),
      incomplete: _index < _steps.length,
      roundMarksSec: List.of(_roundMarks),
      roundRestSec: _roundRests.length == _roundMarks.length ? List.of(_roundRests) : null,
      sets: [for (final d in _done) SetDraft(exercise: d.exercise, reps: d.reps, loadKg: d.loadKg)],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Para que las kcal aparezcan en cuanto se conozca el peso.
    ref.watch(latestWeightProvider);
    final finished = _phase == GuidedPhase.terminado;
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
            if (_phase == GuidedPhase.trabajo) TextButton(onPressed: _finishEarly, child: const Text('Terminar')),
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
              _Stat('Desc.', formatDuration(_restSec)),
              _Stat('Enfr.', formatDuration(_cooldownSec)),
            ],
          ),
          const SizedBox(height: 6),
          _KcalLine(kcal: _kcal),
        ],
      );

  Widget _body(bool finished) {
    if (_phase == GuidedPhase.calentamiento) {
      return _PhasePanel(
        title: 'Calentando',
        seconds: _warmupSec,
        goalSec: _warmupGoalSec,
        detail: _warmupSec < _warmupGoalSec
            ? 'Faltan ${formatDuration(_warmupGoalSec - _warmupSec)} para la meta de ${formatDuration(_warmupGoalSec)}'
            : 'Calentamiento cumplido',
        action: 'Empezar ${widget.day.type.label.toLowerCase()}',
        icon: Icons.play_arrow,
        onAction: _tryStartWork,
        footer: _planPreview(),
      );
    }
    if (_phase == GuidedPhase.enfriamiento) {
      return _PhasePanel(
        title: 'Enfriando',
        seconds: _cooldownSec,
        goalSec: _cooldownGoalSec,
        detail: _cooldownSec < _cooldownGoalSec
            ? 'Estira y respira. Faltan ${formatDuration(_cooldownGoalSec - _cooldownSec)} para la meta de ${formatDuration(_cooldownGoalSec)}'
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
        _RepsSoFar(exercise: step.exercise, reps: _repsSoFar(step.exercise)),
        if (_guides[step.exercise]?.hasGuide ?? false)
          TextButton.icon(
            onPressed: () => _showGuide(_guides[step.exercise]!),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Técnica'),
          ),
        if (_guides[step.exercise]?.tracksLoad ?? false) _loadRow(step.exercise),
        const Spacer(),
        // El anillo se llena al llegar al objetivo: ajustar reps se ve.
        if (target != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(tooltip: 'Una menos', 
                iconSize: 32,
                onPressed: (_reps ?? 0) > 0 ? () => _setReps(_reps! - 1) : null,
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
              IconButton.filledTonal(tooltip: 'Una más', 
                iconSize: 32,
                onPressed: () => _setReps((_reps ?? 0) + 1),
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

  double? _loadFor(String exercise) {
    final kg = _loads[exercise];
    return kg == null || kg == 0 ? null : kg;
  }

  /// Carga externa del ejercicio: la búlgara progresa con peso, no con reps.
  Widget _loadRow(String exercise) {
    final kg = _loads[exercise] ?? 0;
    void set(double v) {
      setState(() => _loads[exercise] = v < 0 ? 0 : v);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Menos carga',
          onPressed: kg > 0 ? () => set(kg - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(kg == 0 ? 'Sin carga' : 'Carga ${fmtDec(kg)} kg', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          tooltip: 'Más carga',
          onPressed: () => set(kg + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  /// Claves de técnica en el momento de hacerlo, con el enlace al video.
  Future<void> _showGuide(ExerciseRow guide) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => _GuideSheet(guide: guide),
      );

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
    final laps = _roundWork;
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
          color: AppColors.protein,
        ),
        const SizedBox(height: 12),
        Text('A continuación', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(step.nextLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (_nextGuide case final guide?)
          TextButton.icon(
            onPressed: () => _showGuide(guide),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text('Técnica: ${guide.name}'),
          ),
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
            _Stat('Desc.', formatDuration(_restSec)),
          ],
        ),
      ],
    );
  }

  /// Repeticiones por ejercicio, en el orden en que aparecieron.
  Map<String, int> _exerciseTotals() {
    final out = <String, int>{};
    for (final d in _done) {
      out[d.exercise] = (out[d.exercise] ?? 0) + d.reps;
    }
    return out;
  }

  /// Guía del próximo ejercicio: el descanso es el momento de repasarla.
  ExerciseRow? get _nextGuide {
    for (var i = _index + 1; i < _steps.length; i++) {
      final st = _steps[i];
      if (st is WorkStep) {
        final g = _guides[st.exercise];
        return g != null && g.hasGuide ? g : null;
      }
    }
    return null;
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
    final laps = _roundWork;
    final measuredRests = _roundRests.length == _roundMarks.length && _roundMarks.isNotEmpty;
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
                _SummaryRow('Descanso', formatDuration(draft.restSec)),
                _SummaryRow('Enfriamiento', formatDuration(draft.cooldownSec)),
                _SummaryRow('Total', formatDuration(draft.totalSec)),
                if (_kcal != null) _SummaryRow('Gasto aproximado', '≈ ${fmtInt(_kcal!)} kcal'),
                const Divider(),
                if (draft.roundsDone != null)
                  _SummaryRow('Rondas', '${draft.roundsDone} de ${draft.plannedRounds ?? '—'}')
                else
                  _SummaryRow('Series', '${_done.length} de ${draft.plannedRounds ?? '—'}'),
                if (laps.isNotEmpty)
                  _SummaryRow(measuredRests ? 'Trabajo por ronda' : 'Tiempo por ronda',
                      laps.map(formatDuration).join(' · ')),
                if (measuredRests && _roundRests.length > 1)
                  _SummaryRow('Descanso por ronda',
                      _roundRests.take(_roundRests.length - 1).map(formatDuration).join(' · ')),
                const Divider(),
                for (final e in _exerciseTotals().entries) _SummaryRow(e.key, '${e.value} reps'),
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

/// Claves de técnica, progresión y enlace a la referencia visual.
class _GuideSheet extends StatelessWidget {
  const _GuideSheet({required this.guide});

  final ExerciseRow guide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final url = guide.mediaUrl == null ? null : Uri.tryParse(guide.mediaUrl!);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(guide.name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final (i, cue) in guide.cues.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 24, child: Text('${i + 1}.', style: text.titleMedium)),
                    Expanded(child: Text(cue, style: text.bodyLarge)),
                  ],
                ),
              ),
            if (guide.progressionNote != null) ...[
              const SizedBox(height: 4),
              Text('Progresión', style: text.labelLarge),
              Text(guide.progressionNote!, style: text.bodyMedium),
            ],
            if (url != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => launchUrl(url, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Ver cómo se hace'),
              ),
            ],
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

/// "Llevas 36 reps de Flexiones": el acumulado del ejercicio en pantalla,
/// sin contar la serie que se está haciendo.
class _RepsSoFar extends StatelessWidget {
  const _RepsSoFar({required this.exercise, required this.reps});

  final String exercise;
  final int reps;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          reps == 0 ? 'Primera vez hoy con este ejercicio' : 'Llevas $reps reps de $exercise',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

/// Gasto aproximado en vivo. Sin peso registrado no inventa un número: dice
/// qué falta.
class _KcalLine extends StatelessWidget {
  const _KcalLine({required this.kcal});

  final double? kcal;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.local_fire_department, size: 16, color: AppColors.kcal),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            kcal == null ? 'Registra tu peso para estimar las kcal' : '≈ ${fmtInt(kcal!)} kcal (aprox.)',
            style: text.labelLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
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
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
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
    const green = AppColors.body;
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
          color: done ? AppColors.body : scheme.primary,
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
      previousMeanLapSec: previous == null ? null : meanSec(lapDurations(previous.$3)),
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
        final color = record ? AppColors.record : widget.color;
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
