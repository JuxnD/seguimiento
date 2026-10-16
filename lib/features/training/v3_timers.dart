import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/repositories/training_repository.dart';
import '../../domain/active_session.dart';
import '../../domain/timer_profile.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/cindy_protocol.dart';
import '../../ui/progress_ring.dart';
import '../../ui/widgets.dart';
import 'pre_attempt_card.dart';

export '../../domain/cindy_protocol.dart' show cindyRound, splitPartialRound;

// Cronómetros del Plan v3 (§18.2, §18.9, §18.10): Cindy (AMRAP 20 min),
// Tabata (4 bloques de 8 × 20/10) y el EMOM de burpees del viernes. Todo se
// mide con marcas de reloj: si la pantalla se apaga, al volver el tiempo
// sigue bien.

void _beep({bool strong = false}) {
  unawaited(SystemSound.play(SystemSoundType.alert));
  unawaited(strong ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact());
}

/// Fases comunes: calentamiento con meta, trabajo y enfriamiento.
enum _Phase { calentamiento, trabajo, enfriamiento }

mixin _Ticking<T extends StatefulWidget> on State<T> {
  Timer? _ticker;

  /// Se reemplaza al retomar una sesión que Android cerró.
  DateTime startedAt = clock.now();
  DateTime? workStartedAt;
  DateTime? workEndedAt;
  DateTime? endedAt;

  void onTick() {}

  void startTicking() {
    WakelockPlus.enable();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      onTick();
      if (mounted) setState(() {});
    });
  }

  void stopTicking() {
    _ticker?.cancel();
    WakelockPlus.disable();
  }

  int sec(DateTime from, [DateTime? to]) => (to ?? clock.now()).difference(from).inSeconds;
  int get warmupSec => sec(startedAt, workStartedAt);
  int get cooldownSec => workEndedAt == null ? 0 : sec(workEndedAt!, endedAt);
  int get totalSec => sec(startedAt, endedAt);
}

/// Pantalla de calentamiento o enfriamiento con su anillo.
class _PhasePanel extends StatelessWidget {
  const _PhasePanel({
    required this.title,
    required this.elapsed,
    required this.goal,
    required this.hint,
    required this.button,
    required this.onPressed,
  });

  final String title;
  final int elapsed;
  final int goal;
  final String hint;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.2)),
          const Spacer(),
          ProgressRing(
            progress: goal == 0 ? 1 : (elapsed / goal).clamp(0, 1).toDouble(),
            value: formatDuration(elapsed),
            label: 'meta ${formatDuration(goal)}',
            size: 220,
            stroke: 14,
          ),
          const SizedBox(height: 16),
          Text(hint, textAlign: TextAlign.center),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: FilledButton(onPressed: onPressed, child: Text(button)),
          ),
        ],
      );
}

// ---------------------------------------------------------------- Cindy --

/// Cindy: AMRAP de 20 min de la ronda del circuito. Métrica: rondas + reps.
class AmrapScreen extends StatefulWidget {
  const AmrapScreen({
    super.key,
    required this.date,
    this.minutes = 20,
    this.warmupGoalSec = 480,
    this.resume,
    this.onSnapshot,
    this.attempt = false,
  });

  final DateTime date;
  final int minutes;
  final int warmupGoalSec;

  /// Cindy de prueba (línea base, cada 4 semanas o el viernes de pruebas):
  /// calentamiento y checklist a la vista (§16.23).
  final bool attempt;

  /// Cindy a mitad que Android cerró: se retoma donde iba.
  final TimerSnapshot? resume;

  /// Foto del estado en cada cambio, para poder retomar.
  final ValueChanged<TimerSnapshot>? onSnapshot;

  @override
  State<AmrapScreen> createState() => _AmrapScreenState();
}

class _AmrapScreenState extends State<AmrapScreen> with _Ticking {
  _Phase _phase = _Phase.calentamiento;
  final _roundMarks = <int>[];
  late final int _capSec = widget.minutes * 60;
  int? _partial;

  int get _workElapsed => workStartedAt == null ? 0 : sec(workStartedAt!, workEndedAt);
  int get _left => (_capSec - _workElapsed).clamp(0, _capSec);

  @override
  void initState() {
    super.initState();
    if (widget.resume case final r?) {
      startedAt = r.startedAt;
      workStartedAt = r.workStartedAt;
      workEndedAt = r.workEndedAt;
      _phase = _Phase.values.byName(r.phase);
      _roundMarks.addAll(r.roundMarks);
      _partial = r.partial;
      // Terminó el tiempo con la app cerrada y nunca se anotó la ronda a medias.
      if (_phase == _Phase.trabajo && workEndedAt != null && _partial == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_askPartial()));
      }
    }
    startTicking();
  }

  void _snapshot() => widget.onSnapshot?.call(TimerSnapshot(
        date: dayKey(widget.date),
        startedAt: startedAt,
        mode: 'cindy',
        phase: _phase.name,
        workStartedAt: workStartedAt,
        workEndedAt: workEndedAt,
        roundMarks: List.of(_roundMarks),
        partial: _partial,
      ));

  @override
  void dispose() {
    stopTicking();
    super.dispose();
  }

  @override
  void onTick() {
    if (_phase == _Phase.trabajo && _left == 0 && workEndedAt == null) {
      workEndedAt = workStartedAt!.add(Duration(seconds: _capSec));
      _beep(strong: true);
      unawaited(_askPartial());
    }
  }

  void _start() {
    workStartedAt = clock.now();
    _phase = _Phase.trabajo;
    _beep();
    _snapshot();
  }

  void _round() {
    if (workEndedAt != null) return;
    _roundMarks.add(_workElapsed);
    unawaited(HapticFeedback.mediumImpact());
    _snapshot();
  }

  Future<void> _askPartial() async {
    final reps = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NumberDialog(
        title: 'Tiempo: ¿cuántas reps de la ronda a medias?',
        hint: 'Dominadas cuentan primero, luego flexiones y sentadillas (máximo 29).',
        max: 29,
      ),
    );
    if (!mounted) return;
    setState(() {
      _partial = reps ?? 0;
      _phase = _Phase.enfriamiento;
    });
    _snapshot();
  }

  Future<void> _finishEarly() async {
    // Auditoría 053, P1-8: «Terminar antes» estaba a un toque del botón
    // grande.
    if (!await confirmAction(context,
        title: '¿Terminar antes?',
        body: 'Se corta la Cindy aquí; no cuenta como marca de 20 min.',
        confirm: 'Terminar')) {
      return;
    }
    if (!mounted) return;
    workEndedAt = clock.now();
    await _askPartial();
  }

  /// Auditoría 053, P1-8: un «+1 ronda» de más se puede quitar.
  void _undoRound() {
    if (workEndedAt != null || _roundMarks.isEmpty) return;
    _roundMarks.removeLast();
    _snapshot();
  }

  SessionDraft _draft() {
    final rounds = _roundMarks.length;
    final roundsLabel = '$rounds ${rounds == 1 ? 'ronda' : 'rondas'}';
    final partial = _partial ?? 0;
    // Cortado antes de los 20 min: no es una marca comparable.
    final cut = _workElapsed < _capSec;
    return SessionDraft(
      date: widget.date,
      startTime: timeKey(startedAt.hour, startedAt.minute),
      type: SessionType.resistencia,
      mode: 'cindy',
      // Sumar fases ya truncadas conserva la ventana de trabajo medida:
      // truncar también el total por separado puede añadir un segundo.
      totalSec: warmupSec + _workElapsed + cooldownSec,
      warmupSec: warmupSec,
      cooldownSec: cooldownSec,
      roundsDone: rounds,
      extraReps: partial,
      incomplete: cut,
      roundMarksSec: List.of(_roundMarks),
      context: cut
          ? 'Cindy cortada: $roundsLabel + $partial reps en ${formatDuration(_workElapsed)} de ${widget.minutes} min'
          : 'Cindy: $roundsLabel + $partial reps en ${widget.minutes} min',
      sets: [
        for (var r = 0; r < rounds; r++)
          for (final (name, reps) in cindyRound) SetDraft(exercise: name, reps: reps),
        for (final (name, reps) in splitPartialRound(partial)) SetDraft(exercise: name, reps: reps),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Cindy · AMRAP')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        // Ancho completo: sin esto la columna se encoge a su hijo más ancho
        // y todo queda cargado a la izquierda.
        child: SizedBox(
          width: double.infinity,
          child: switch (_phase) {
            // Cindy de prueba: tarjeta fija y desplazable; el botón no se tapa.
            _Phase.calentamiento when widget.attempt => Column(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        const PreAttemptCard(torso: true),
                        const SizedBox(height: 8),
                        Text('Calentando ${formatDuration(warmupSec)} · meta ${formatDuration(widget.warmupGoalSec)}',
                            textAlign: TextAlign.center, style: text.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                            'Luego ${widget.minutes} min de 5 dominadas + 10 flexiones + 15 sentadillas, tantas rondas '
                            'como puedas. Toca "+1 ronda" al cerrar cada una.',
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton(onPressed: () => setState(_start), child: const Text('Empezar AMRAP')),
                  ),
                ],
              ),
            _Phase.calentamiento => _PhasePanel(
                title: 'Calentamiento',
                elapsed: warmupSec,
                goal: widget.warmupGoalSec,
                hint: 'Luego ${widget.minutes} min de 5 dominadas + 10 flexiones + 15 sentadillas, tantas rondas como '
                    'puedas. Toca "+1 ronda" al cerrar cada una.',
                button: 'Empezar AMRAP',
                onPressed: () => setState(_start),
              ),
            _Phase.trabajo => Column(
                children: [
                  Text('AMRAP ${widget.minutes} MIN', style: text.labelLarge?.copyWith(letterSpacing: 1.2)),
                  const Spacer(),
                  ProgressRing(
                    progress: _workElapsed / _capSec,
                    value: formatDuration(_left),
                    label: '${_roundMarks.length} ${_roundMarks.length == 1 ? 'ronda' : 'rondas'}',
                    size: 240,
                    stroke: 16,
                  ),
                  const SizedBox(height: 12),
                  Text('5 dominadas · 10 flexiones · 15 sentadillas', style: text.titleMedium),
                  if (_roundMarks.isNotEmpty)
                    Text(
                        'Última ronda: ${formatDuration(_roundMarks.last - (_roundMarks.length > 1 ? _roundMarks[_roundMarks.length - 2] : 0))}',
                        style: text.bodySmall),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 110,
                    child: FilledButton(
                      onPressed: () => setState(_round),
                      child: Text('+1 ronda', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    children: [
                      TextButton(
                          onPressed: _roundMarks.isEmpty
                              ? null
                              : () => setState(_undoRound),
                          child: const Text('Quitar la última ronda')),
                      TextButton(onPressed: _finishEarly, child: const Text('Terminar antes')),
                    ],
                  ),
                ],
              ),
            _Phase.enfriamiento => _PhasePanel(
                title: 'Enfriamiento',
                elapsed: cooldownSec,
                goal: 180,
                hint: 'Cindy: ${_roundMarks.length} rondas + ${_partial ?? 0} reps. Camina y respira; después, la '
                    'movilidad nocturna.',
                button: 'Terminar y guardar',
                onPressed: () {
                  endedAt = clock.now();
                  Navigator.pop(context, _draft());
                },
              ),
          },
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Tabata --

/// Tabata: 4 bloques de 8 × (20 s máximo / 10 s pausa), 1 min entre bloques.
/// Métrica: reps del peor intervalo de cada bloque.
class TabataScreen extends StatefulWidget {
  const TabataScreen({
    super.key,
    required this.date,
    required this.exercises,
    this.warmupGoalSec = 480,
    this.workSec = 20,
    this.restSec = 10,
    this.intervals = 8,
    this.betweenBlocksSec = 60,
    this.includeFinalRest = false,
    this.profile = TimerProfile.tabata,
    this.footballFreeConfirmed,
    this.resume,
    this.onSnapshot,
  });

  factory TabataScreen.running1515({
    Key? key,
    required DateTime date,
    required bool footballFreeConfirmed,
    TimerSnapshot? resume,
    ValueChanged<TimerSnapshot>? onSnapshot,
  }) {
    if (resume != null && resume.profile != TimerProfile.running1515) {
      throw ArgumentError('La sesión guardada no es carrera 15/15');
    }
    final confirmed = resume?.footballFreeConfirmed ?? footballFreeConfirmed;
    if (!confirmed) throw ArgumentError('Confirma primero que no hay fútbol entre semana');
    return TabataScreen(
      key: key,
      date: date,
      exercises: const ['Carrera 15/15', 'Carrera 15/15'],
      workSec: 15,
      restSec: 15,
      intervals: 16,
      betweenBlocksSec: 0,
      includeFinalRest: true,
      profile: TimerProfile.running1515,
      footballFreeConfirmed: confirmed,
      resume: resume,
      onSnapshot: onSnapshot,
    );
  }

  final DateTime date;
  final List<String> exercises;

  /// Tabata a mitad que Android cerró: se retoma donde iba.
  final TimerSnapshot? resume;

  /// Foto del estado en cada cambio, para poder retomar.
  final ValueChanged<TimerSnapshot>? onSnapshot;
  final int warmupGoalSec;
  final int workSec;
  final int restSec;
  final int intervals;
  final int betweenBlocksSec;
  final bool includeFinalRest;
  final TimerProfile profile;
  final bool? footballFreeConfirmed;

  @override
  State<TabataScreen> createState() => _TabataScreenState();
}

/// Un tramo del Tabata: trabajo, pausa o descanso entre bloques.
class TabataSegment {
  const TabataSegment(this.block, this.interval, this.kind, this.seconds);

  final int block;
  final int interval;

  /// 'trabajo', 'pausa' o 'bloque'.
  final String kind;
  final int seconds;
}

/// La línea de tiempo del Tabata, tramo a tramo.
List<TabataSegment> tabataTimeline(
    {int blocks = 4,
    int intervals = 8,
    int work = 20,
    int rest = 10,
    int between = 60,
    bool includeFinalRest = false}) {
  final out = <TabataSegment>[];
  for (var b = 0; b < blocks; b++) {
    for (var i = 0; i < intervals; i++) {
      out.add(TabataSegment(b, i, 'trabajo', work));
      // Historical Tabata omits the last rest. Running explicitly keeps it
      // so each 16 x (15/15) block lasts the full eight minutes.
      if (i < intervals - 1 || includeFinalRest) out.add(TabataSegment(b, i, 'pausa', rest));
    }
    if (b < blocks - 1 && between > 0) out.add(TabataSegment(b, intervals - 1, 'bloque', between));
  }
  return out;
}

/// Trabajo y pausas hechos hasta `elapsed` segundos del Tabata. Si se corta
/// antes, las pausas que no llegaron no cuentan como descanso (antes se
/// descontaba el Tabata entero y el neto quedaba en 0).
({int work, int rest}) tabataTimeSplit(List<TabataSegment> timeline, int elapsed) {
  var work = 0, rest = 0, t = 0;
  for (final s in timeline) {
    if (t >= elapsed) break;
    final done = (elapsed - t).clamp(0, s.seconds);
    if (s.kind == 'trabajo') {
      work += done;
    } else {
      rest += done;
    }
    t += s.seconds;
  }
  return (work: work, rest: rest);
}

class _TabataScreenState extends State<TabataScreen> with _Ticking {
  _Phase _phase = _Phase.calentamiento;
  late final _prescription = widget.resume?.prescription ??
      TimerPrescription(
          profile: widget.profile,
          workSec: widget.workSec,
          restSec: widget.restSec,
          intervals: widget.intervals,
          betweenBlocksSec: widget.betweenBlocksSec,
          includeFinalRest: widget.includeFinalRest,
          footballFreeConfirmed: widget.footballFreeConfirmed);
  late final _exercises = List<String>.unmodifiable(
      widget.resume?.exercises.isNotEmpty == true ? widget.resume!.exercises : widget.exercises);
  bool get _running => _prescription.profile == TimerProfile.running1515;
  String get _title => _running ? 'Carrera · intervalos 15/15' : 'Tabata';
  DateTime get _date => widget.resume == null ? widget.date : parseDay(widget.resume!.date);
  late final _timeline = tabataTimeline(
    blocks: _exercises.length,
    intervals: _prescription.intervals,
    work: _prescription.workSec,
    rest: _prescription.restSec,
    between: _prescription.betweenBlocksSec,
    includeFinalRest: _prescription.includeFinalRest,
  );
  late final int _totalWorkSec = _timeline.fold(0, (a, s) => a + s.seconds);
  int _lastSegment = -1;
  final _worst = <int, int>{};
  bool _asking = false;

  int get _elapsed => workStartedAt == null ? 0 : sec(workStartedAt!, workEndedAt);

  /// Tramo en curso y cuánto le queda.
  (int, int) get _position {
    var t = _elapsed;
    for (var i = 0; i < _timeline.length; i++) {
      if (t < _timeline[i].seconds) return (i, _timeline[i].seconds - t);
      t -= _timeline[i].seconds;
    }
    return (_timeline.length, 0);
  }

  @override
  void initState() {
    super.initState();
    _prescription.validate(blocks: _exercises.length);
    if (widget.resume case final r?) {
      startedAt = r.startedAt;
      workStartedAt = r.workStartedAt;
      workEndedAt = r.workEndedAt;
      _phase = _Phase.values.byName(r.phase);
      _worst.addAll(r.worst);
      // Sigue desde el tramo en que va: sin pitar ni preguntar por los que
      // pasaron con la app cerrada.
      if (workStartedAt != null) _lastSegment = _position.$1;
      if (_running && _phase == _Phase.trabajo && _elapsed >= _totalWorkSec) {
        workEndedAt = workStartedAt!.add(Duration(seconds: _totalWorkSec));
        _phase = _Phase.enfriamiento;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _snapshot();
        });
      }
    }
    startTicking();
  }

  void _snapshot() => widget.onSnapshot?.call(TimerSnapshot(
        date: dayKey(_date),
        startedAt: startedAt,
        mode: _prescription.profile.name,
        phase: _phase.name,
        workStartedAt: workStartedAt,
        workEndedAt: workEndedAt,
        worst: Map.of(_worst),
        exercises: _exercises,
        prescription: _prescription,
      ));

  @override
  void dispose() {
    stopTicking();
    super.dispose();
  }

  @override
  void onTick() {
    if (_phase != _Phase.trabajo || workEndedAt != null) return;
    final (index, _) = _position;
    if (index != _lastSegment) {
      // Al cambiar de tramo: pitido fuerte al empezar a trabajar, suave al
      // descansar. Al cerrar un bloque se pide el peor intervalo.
      // El bloque se cierra al entrar al minuto entre bloques (o al final):
      // ahí, descansando, se anota el peor intervalo.
      final finishedBlock = _lastSegment >= 0 && (index >= _timeline.length || _timeline[index].kind == 'bloque');
      if (finishedBlock && !_running) unawaited(_askWorst(_timeline[_lastSegment].block));
      _lastSegment = index;
      if (index >= _timeline.length) {
        workEndedAt = workStartedAt!.add(Duration(seconds: _totalWorkSec));
        if (_running) _phase = _Phase.enfriamiento;
        _beep(strong: true);
        _snapshot();
      } else {
        _beep(strong: _timeline[index].kind == 'trabajo');
      }
    }
  }

  Future<void> _askWorst(int block) async {
    if (_asking) return;
    _asking = true;
    final reps = await showDialog<int>(
      context: context,
      builder: (_) => _NumberDialog(
        title: '${_exercises[block]}: reps del peor intervalo',
        hint: 'El intervalo de ${_prescription.workSec} s en que menos hiciste. Es la métrica del Tabata.',
        max: 60,
      ),
    );
    _asking = false;
    if (reps != null) _worst[block] = reps;
    if (mounted && workEndedAt != null) setState(() => _phase = _Phase.enfriamiento);
    _snapshot();
  }

  SessionDraft _draft() {
    final done = _elapsed.clamp(0, _totalWorkSec);
    final split = tabataTimeSplit(_timeline, done);
    final cut = done < _totalWorkSec;
    return SessionDraft(
      date: _date,
      startTime: timeKey(startedAt.hour, startedAt.minute),
      type: SessionType.resistencia,
      mode: _prescription.profile.name,
      totalSec: totalSec,
      warmupSec: warmupSec,
      cooldownSec: cooldownSec,
      restSec: split.rest,
      incomplete: cut,
      context: _running
          ? 'Carrera 15/15 · 2 bloques de 8 min · ${cut ? 'interrumpida' : 'completa'}'
              ' · ${split.work} s trabajo / ${split.rest} s pausa'
          : '${cut ? 'Tabata cortado a los ${formatDuration(done)} de ${formatDuration(_totalWorkSec)}' : 'Tabata'}'
              ' · peor intervalo: '
              '${[for (var b = 0; b < _exercises.length; b++) '${_exercises[b]} ${_worst[b] ?? '—'}'].join(' · ')}',
      sets: [
        if (!_running)
          for (var b = 0; b < _exercises.length; b++)
            if (_worst[b] != null) SetDraft(exercise: _exercises[b], reps: _worst[b]!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (index, left) = _position;
    final seg = index < _timeline.length ? _timeline[index] : null;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        // Ancho completo: sin esto la columna se encoge a su hijo más ancho
        // y todo queda cargado a la izquierda.
        child: SizedBox(
          width: double.infinity,
          child: switch (_phase) {
            _Phase.calentamiento => _PhasePanel(
                title: 'Calentamiento',
                elapsed: warmupSec,
                goal: widget.warmupGoalSec,
                hint: _running
                    ? '2 bloques de 8 min: 16 × (15 s de carrera / 15 s de pausa), incluida la última pausa. '
                        'Sin descanso extra entre bloques. Suena al cambiar de tramo.'
                    : '${_exercises.length} bloques de ${_prescription.intervals} × '
                        '(${_prescription.workSec} s a tope / ${_prescription.restSec} s pausa), '
                        '${_prescription.betweenBlocksSec ~/ 60} min entre bloques: '
                        '${_exercises.join(' · ')}. Suena al cambiar de tramo.',
                button: _running ? 'Empezar intervalos' : 'Empezar Tabata',
                onPressed: () {
                  setState(() {
                    workStartedAt = clock.now();
                    _phase = _Phase.trabajo;
                  });
                  _snapshot();
                },
              ),
            _Phase.trabajo => seg == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Text(
                          'BLOQUE ${seg.block + 1}/${_exercises.length} · '
                          'INTERVALO ${seg.interval + 1}/${_prescription.intervals}',
                          style: text.labelLarge?.copyWith(letterSpacing: 1.2)),
                      const Spacer(),
                      Text(
                        switch (seg.kind) {
                          'trabajo' => _running ? 'Carrera' : '¡A TOPE!',
                          'pausa' => 'Pausa',
                          _ => 'Descanso entre bloques',
                        },
                        style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ProgressRing(
                        progress: 1 - left / seg.seconds,
                        value: '$left',
                        label: seg.kind == 'bloque' ? 'Siguiente: ${_exercises[seg.block + 1]}' : _exercises[seg.block],
                        size: 240,
                        stroke: 16,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          workEndedAt = clock.now();
                          setState(() => _phase = _Phase.enfriamiento);
                          _snapshot();
                        },
                        child: const Text('Terminar antes'),
                      ),
                    ],
                  ),
            _Phase.enfriamiento => _PhasePanel(
                title: 'Enfriamiento',
                elapsed: cooldownSec,
                goal: 180,
                hint: _running
                    ? 'Intervalos terminados. Después, la movilidad nocturna.'
                    : 'Peor intervalo: ${[
                        for (var b = 0; b < _exercises.length; b++) '${_worst[b] ?? '—'}'
                      ].join(' · ')}. '
                        'Después, la movilidad nocturna.',
                button: 'Terminar y guardar',
                onPressed: () {
                  endedAt = clock.now();
                  Navigator.pop(context, _draft());
                },
              ),
          },
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- EMOM --

/// Resultado del EMOM: burpees hechos en cada minuto.
class EmomResult {
  const EmomResult({required this.target, required this.perMinute});

  final int target;
  final List<int> perMinute;

  /// Minutos con todos los burpees de la meta.
  int get completeMinutes => perMinute.where((r) => r >= target).length;
}

/// Burpees que quedan como meta si un minuto no se completa: los del escalón
/// anterior de la progresión (10 → 8 → 6), y de 6 baja a 5 (§18.10).
int emomFallback(int target) => switch (target) {
      >= 10 => 8,
      >= 8 => 6,
      _ => target > 1 ? target - 1 : 1,
    };

/// EMOM: al empezar cada minuto, N burpees; lo que sobra del minuto es
/// descanso. Si un minuto no sale, el resto sigue con la meta anterior.
class EmomScreen extends StatefulWidget {
  const EmomScreen({super.key, required this.minutes, required this.reps, this.exercise = 'Burpees'});

  final int minutes;
  final int reps;
  final String exercise;

  @override
  State<EmomScreen> createState() => _EmomScreenState();
}

class _EmomScreenState extends State<EmomScreen> with _Ticking {
  final _done = <int>[];
  late int _target = widget.reps;
  int _lastMinute = -1;

  int get _elapsed => workStartedAt == null ? 0 : sec(workStartedAt!, workEndedAt);
  int get _minute => _elapsed ~/ 60;
  int get _left => 60 - _elapsed % 60;
  bool get _over => _minute >= widget.minutes;

  @override
  void initState() {
    super.initState();
    startTicking();
  }

  @override
  void dispose() {
    stopTicking();
    super.dispose();
  }

  @override
  void onTick() {
    if (workStartedAt == null || workEndedAt != null) return;
    if (_minute != _lastMinute) {
      // Un minuto que pasó sin marcar se cuenta como no completado.
      while (_done.length < _minute && _done.length < widget.minutes) {
        _done.add(0);
        _target = emomFallback(_target);
      }
      _lastMinute = _minute;
      if (_over) {
        workEndedAt = workStartedAt!.add(Duration(minutes: widget.minutes));
        _beep(strong: true);
      } else {
        _beep(strong: true);
      }
    }
  }

  void _mark(int reps) {
    if (_done.length > _minute || _over) return;
    _done.add(reps);
    if (reps < _target) _target = emomFallback(_target);
    unawaited(HapticFeedback.mediumImpact());
  }

  Future<void> _partial() async {
    final reps = await showDialog<int>(
      context: context,
      builder: (_) => _NumberDialog(title: '¿Cuántos burpees en este minuto?', hint: 'Meta: $_target', max: _target),
    );
    if (reps != null && mounted) setState(() => _mark(reps));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final markedThisMinute = _done.length > _minute;
    return Scaffold(
      appBar: AppBar(title: Text('EMOM ${widget.minutes} min · ${widget.exercise.toLowerCase()}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              workStartedAt == null
                  ? '${widget.reps} ${widget.exercise.toLowerCase()} al empezar cada minuto'
                  : (_over ? 'TERMINADO' : 'MINUTO ${_minute + 1}/${widget.minutes}'),
              style: text.labelLarge?.copyWith(letterSpacing: 1.2),
            ),
            const Spacer(),
            ProgressRing(
              progress: workStartedAt == null ? 0 : (_over ? 1 : 1 - _left / 60),
              value: workStartedAt == null ? '${widget.minutes}:00' : (_over ? '✓' : '$_left'),
              label: _over ? '${_done.where((r) => r >= widget.reps).length} min completos' : 'meta $_target',
              size: 240,
              stroke: 16,
            ),
            const SizedBox(height: 12),
            Text(
              'Pecho al suelo, extensión completa de cadera al saltar, aterrizaje suave. '
              'Si un minuto no sale, el resto va con ${emomFallback(widget.reps)}.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const Spacer(),
            if (workStartedAt == null)
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  onPressed: () => setState(() => workStartedAt = clock.now()),
                  child: const Text('Empezar EMOM'),
                ),
              )
            else if (_over)
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  onPressed: () {
                    endedAt = clock.now();
                    Navigator.pop(context, EmomResult(target: widget.reps, perMinute: List.of(_done)));
                  },
                  child: const Text('Guardar'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 96,
                      child: FilledButton(
                        onPressed: markedThisMinute ? null : () => setState(() => _mark(_target)),
                        child: Text(markedThisMinute ? 'Hecho ✓' : '$_target hechos'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 96,
                    child: OutlinedButton(
                      onPressed: markedThisMinute ? null : _partial,
                      child: const Text('No llegué'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Pide un número con teclado numérico.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.hint, required this.max});

  final String title;
  final String hint;
  final int max;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  int? get _value {
    final v = int.tryParse(_field.text.trim());
    return v == null || v < 0 || v > widget.max ? null : v;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.hint),
            const SizedBox(height: 8),
            NumberField(controller: _field, label: 'Reps', onChanged: (_) => setState(() {})),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: _value == null ? null : () => Navigator.pop(context, _value), child: const Text('Listo')),
        ],
      );
}


/// Auditoría 053, P0: Cindy, Tabata y EMOM se cerraban con «atrás» y se
/// perdía lo hecho. Ahora pregunta antes de salir.
class TimerExitGuard extends StatelessWidget {
  const TimerExitGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          final leave = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('¿Salir del cronómetro?'),
              content: const Text(
                  'Si sales ahora, lo de esta sesión no se guarda. Para guardarlo, termina o usa «Terminar».'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Salir sin guardar')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Seguir')),
              ],
            ),
          );
          if (leave == true) navigator.pop();
        },
        child: child,
      );
}
