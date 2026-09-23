/// Guion de una sesión: la lista de pasos que el cronómetro va a recorrer.
///
/// Se arma desde el plan del día, así que el cronómetro nunca tiene que
/// adivinar si está contando rondas de circuito o series de un bloque. Es
/// lógica pura: no sabe de pantallas ni de base de datos.
library;

import 'enums.dart';

sealed class ScriptStep {
  const ScriptStep();
}

/// Un trabajo efectivo: una parada del circuito o una serie de un ejercicio.
class WorkStep extends ScriptStep {
  const WorkStep({
    required this.exercise,
    required this.targetLabel,
    this.targetReps,
    this.holdSec,
    required this.position,
    required this.total,
    required this.isRound,
    this.blockName,
  });

  final String exercise;

  /// Lo que pide el plan: "14–16", "8", "20–40 s".
  final String targetLabel;

  /// Repeticiones objetivo para prellenar el registro (el mínimo del rango).
  final int? targetReps;
  final int? holdSec;

  /// Ronda o serie actual, 1-based.
  final int position;

  /// Rondas o series totales.
  final int total;

  /// true = es una ronda de circuito; false = una serie de un bloque.
  final bool isRound;

  /// Bloque extra al que pertenece ('core', 'hombro'), si aplica.
  final String? blockName;

  String get counterLabel => isRound ? 'Ronda $position/$total' : 'Serie $position/$total';
}

/// Descanso con duración del plan. `maxSec` cuando el plan da un rango.
class RestStep extends ScriptStep {
  const RestStep({required this.seconds, this.maxSec, required this.nextLabel});

  final int seconds;
  final int? maxSec;

  /// Qué viene después, para mostrarlo durante la cuenta regresiva.
  final String nextLabel;

  String get label => maxSec == null || maxSec == seconds ? '$seconds s' : '$seconds–$maxSec s';
}

/// Datos mínimos de un ejercicio del plan que el guion necesita.
class ScriptExercise {
  const ScriptExercise({
    required this.name,
    this.sets,
    this.repsMin,
    this.repsMax,
    this.restSec,
    this.restSecMax,
    this.holdSecMin,
    this.holdSecMax,
    this.perSide = false,
    this.blockName,
    this.variant,
  });

  final String name;
  final int? sets;
  final int? repsMin;
  final int? repsMax;
  final int? restSec;
  final int? restSecMax;
  final int? holdSecMin;
  final int? holdSecMax;
  final bool perSide;
  final String? blockName;
  final String? variant;

  String get targetLabel {
    final reps = repsMin == null
        ? null
        : (repsMax == null || repsMax == repsMin)
            ? '$repsMin'
            : '$repsMin–$repsMax';
    final hold = holdSecMin == null
        ? null
        : (holdSecMax == null || holdSecMax == holdSecMin)
            ? '$holdSecMin s'
            : '$holdSecMin–$holdSecMax s';
    return [
      if (reps != null) reps else if (hold != null) hold else '—',
      if (perSide) 'por lado',
    ].join(' · ');
  }
}

/// El día tal como lo entiende el cronómetro.
class ScriptDay {
  const ScriptDay({
    required this.type,
    required this.exercises,
    this.targetRounds,
    this.restBetweenRoundsSec,
  });

  final DayType type;
  final List<ScriptExercise> exercises;
  final int? targetRounds;
  final int? restBetweenRoundsSec;

  List<ScriptExercise> get main => exercises.where((e) => e.blockName == null).toList();
  List<ScriptExercise> get blockExercises => exercises.where((e) => e.blockName != null).toList();
}

/// Arma el guion. `rounds` permite pasar un objetivo distinto al del plan
/// (por ejemplo, bajar a 5 rondas tras un domingo intenso).
///
/// Circuito: N rondas de todos los ejercicios seguidos, sin descanso dentro de
/// la ronda y con el descanso del plan al cerrarla.
/// Bloques: se agota un ejercicio antes de pasar al siguiente, con su descanso
/// entre series.
/// En un día de circuito, los bloques extra van después, con su propio formato.
List<ScriptStep> buildScript(ScriptDay day, {int? rounds, String? coreVariant}) {
  final steps = <ScriptStep>[];
  final main = day.main;

  if (day.type.isCircuit && main.isNotEmpty) {
    final total = rounds ?? day.targetRounds ?? 1;
    final rest = day.restBetweenRoundsSec ?? 0;
    for (var round = 1; round <= total; round++) {
      for (final e in main) {
        steps.add(_work(e, position: round, total: total, isRound: true));
      }
      final isLastRound = round == total;
      if (!isLastRound && rest > 0) {
        steps.add(RestStep(seconds: rest, nextLabel: 'Ronda ${round + 1}: ${main.first.name}'));
      }
    }
  } else {
    steps.addAll(_blockSteps(main));
  }

  // Bloques extra (core, cuádriceps, hombro), filtrando la variante elegida.
  final extras = day.blockExercises
      .where((e) => e.variant == null || coreVariant == null || e.variant == coreVariant)
      .toList();
  for (final blockName in extras.map((e) => e.blockName!).toSet()) {
    steps.addAll(_blockSteps(extras.where((e) => e.blockName == blockName).toList()));
  }
  return steps;
}

List<ScriptStep> _blockSteps(List<ScriptExercise> exercises) {
  final steps = <ScriptStep>[];
  for (var i = 0; i < exercises.length; i++) {
    final e = exercises[i];
    final sets = e.sets ?? 1;
    for (var set = 1; set <= sets; set++) {
      steps.add(_work(e, position: set, total: sets, isRound: false));
      final isLastSetOfLastExercise = set == sets && i == exercises.length - 1;
      if (!isLastSetOfLastExercise && (e.restSec ?? 0) > 0) {
        final next = set == sets ? exercises[i + 1].name : e.name;
        steps.add(RestStep(
          seconds: e.restSec!,
          maxSec: e.restSecMax,
          nextLabel: set == sets ? 'Siguiente: $next' : '$next, serie ${set + 1}/$sets',
        ));
      }
    }
  }
  return steps;
}

WorkStep _work(ScriptExercise e, {required int position, required int total, required bool isRound}) =>
    WorkStep(
      exercise: e.name,
      targetLabel: e.targetLabel,
      targetReps: e.repsMin,
      holdSec: e.holdSecMin,
      position: position,
      total: total,
      isRound: isRound,
      blockName: e.blockName,
    );

/// Cuántas rondas o series de trabajo tiene el guion (sin contar descansos).
int workStepCount(List<ScriptStep> steps) => steps.whereType<WorkStep>().length;

/// Rondas completas a partir de los pasos ya hechos, para registrar una
/// sesión que se cerró antes de tiempo.
int completedRounds(List<ScriptStep> steps, int doneSteps, {required int exercisesPerRound}) {
  if (exercisesPerRound <= 0) return 0;
  final doneWork = steps.take(doneSteps).whereType<WorkStep>().where((s) => s.isRound).length;
  return doneWork ~/ exercisesPerRound;
}
