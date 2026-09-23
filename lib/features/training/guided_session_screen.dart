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
import '../../domain/session_script.dart';
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
          ),
      ],
    );

enum _Phase { calentamiento, trabajo, enfriamiento }

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

  int get _totalSec => DateTime.now().difference(_startedAt).inSeconds;
  int get _warmupSec => (_workStartedAt ?? DateTime.now()).difference(_startedAt).inSeconds;
  int get _netSec => _workStartedAt == null
      ? 0
      : (_workEndedAt ?? DateTime.now()).difference(_workStartedAt!).inSeconds;
  int get _cooldownSec => _workEndedAt == null ? 0 : DateTime.now().difference(_workEndedAt!).inSeconds;

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
      unawaited(notifications.scheduleRestEnd(
        inSeconds: Duration(seconds: step.seconds),
        nextLabel: step.nextLabel,
      ));
    }
  }

  void _completeWork() {
    final step = _current as WorkStep;
    _done.add(_Done(step.exercise, _reps ?? step.targetReps ?? 0, step.isRound));

    // Al cerrar la última parada de una ronda, queda la marca de la vuelta.
    if (step.isRound && _done.where((d) => d.isRound).length % _exercisesPerRound == 0) {
      _roundMarks.add(DateTime.now().difference(_workStartedAt!).inSeconds);
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
    final rounds = isCircuit
        ? completedRounds(_steps, _index, exercisesPerRound: _exercisesPerRound)
        : null;
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
    final finished = _phase == _Phase.enfriamiento;
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
            if (_phase == _Phase.trabajo)
              TextButton(onPressed: _finishEarly, child: const Text('Terminar')),
          ],
        ),
        body: Column(
          children: [
            _timesBar(),
            Expanded(child: Padding(padding: const EdgeInsets.all(12), child: _body(finished))),
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
      return _BigPanel(
        title: 'Calentando',
        subtitle: formatDuration(_warmupSec),
        detail: 'El plan pide mínimo 6 min antes de empezar',
        action: 'Empezar ${widget.day.type.label.toLowerCase()}',
        icon: Icons.play_arrow,
        onAction: _startWork,
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
    return Column(
      children: [
        Text(step.counterLabel, style: Theme.of(context).textTheme.titleMedium),
        if (step.blockName != null)
          Text('Bloque ${step.blockName}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text(
          step.exercise,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800),
        ),
        Text('Objetivo: ${step.targetLabel}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (step.targetReps != null) _repsStepper(),
        const Spacer(),
        SizedBox(
          height: 120,
          child: _BigButton(label: 'Hecho', icon: Icons.check, onTap: _completeWork),
        ),
        const SizedBox(height: 8),
        Text('Paso ${_index + 1} de ${_steps.length}',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _repsStepper() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            iconSize: 32,
            onPressed: (_reps ?? 0) > 0 ? () => setState(() => _reps = _reps! - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('${_reps ?? 0}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
          ),
          IconButton.filledTonal(
            iconSize: 32,
            onPressed: () => setState(() => _reps = (_reps ?? 0) + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      );

  Widget _rest(RestStep step) {
    final remaining = _restRemaining.clamp(0, step.seconds);
    final progress = step.seconds == 0 ? 1.0 : 1 - remaining / step.seconds;
    return Column(
      children: [
        Text('Descanso', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          width: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(value: progress, strokeWidth: 10),
              ),
              Text(formatDuration(remaining),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Plan: ${step.label}', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(step.nextLabel, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _skipRest,
          icon: const Icon(Icons.skip_next),
          label: const Text('Saltar descanso'),
        ),
      ],
    );
  }

  Widget _summary() {
    final draft = _buildDraft();
    final laps = _roundMarks.isEmpty ? <int>[] : lapDurationsOf(_roundMarks);
    return ListView(
      children: [
        Text('Sesión terminada', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        AppCard(
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
            if (laps.isNotEmpty)
              _SummaryRow('Tiempo por ronda', laps.map(formatDuration).join(' · ')),
            if (draft.incomplete) const _SummaryRow('Cierre', 'Incompleta'),
          ],
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

class _BigPanel extends StatelessWidget {
  const _BigPanel({
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.action,
    required this.icon,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String detail;
  final String action;
  final IconData icon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(subtitle,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          SizedBox(height: 120, child: _BigButton(label: action, icon: icon, onTap: onAction)),
        ],
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
