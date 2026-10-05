/// Guion de una sesión: la lista de pasos que el cronómetro va a recorrer.
///
/// Se arma desde el plan del día, así que el cronómetro nunca tiene que
/// adivinar si está contando rondas de circuito o series de un bloque. Es
/// lógica pura: no sabe de pantallas ni de base de datos.
library;

import 'enums.dart';
import 'format.dart';

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
    this.holdSecMax,
    required this.position,
    required this.total,
    required this.isRound,
    this.blockName,
    this.grip,
    this.side,
  });

  final String exercise;

  /// Agarre o ejecución que pide el plan ("prona"), para no olvidarlo.
  final String? grip;

  /// Lo que pide el plan: "14–16", "8", "20–40 s".
  final String targetLabel;

  /// Repeticiones objetivo para prellenar el registro (el mínimo del rango).
  final int? targetReps;

  /// Ejercicio por tiempo: mínimo y máximo del rango (20–40 s). El cronómetro
  /// avisa al llegar al mínimo y cierra solo en el máximo.
  final int? holdSec;
  final int? holdSecMax;

  /// 'derecho' o 'izquierdo' en los ejercicios por lado: cada lado es su
  /// propio paso, uno detrás del otro, y los dos forman una serie.
  final String? side;

  bool get isHold => targetReps == null && holdSec != null;

  /// Ronda o serie actual, 1-based.
  final int position;

  /// Rondas o series totales.
  final int total;

  /// true = es una ronda de circuito; false = una serie de un bloque.
  final bool isRound;

  /// Bloque extra al que pertenece ('core', 'hombro'), si aplica.
  final String? blockName;

  String get counterLabel =>
      isRound ? 'Ronda $position/$total' : 'Serie $position/$total${side == null ? '' : ' · lado $side'}';

  /// Objetivo de este paso: en un paso por lado ya no dice "por lado".
  String get stepTarget => side == null ? targetLabel : targetLabel.replaceAll(' · por lado', '');
}

/// Bloques del plan que no son pasos del cronómetro guiado: el calentamiento
/// del día (FIFA 11+ el miércoles del v3.1) se hace en la fase de
/// calentamiento, y el Tabata tiene su propio cronómetro.
const warmupBlock = 'calentamiento';
const tabataBlock = 'tabata';

/// Bloques que van antes del trabajo principal, sin fatiga: la práctica de
/// pino del v3.1 (§19.1).
const preBlocks = {'pino'};

/// Descanso entre series de un bloque cuando el plan no lo fija, y la
/// transición del circuito a los bloques extra. Sin ellos el cronómetro
/// pasaba de una serie a la siguiente sin respiro (uso real, 28 sep).
const defaultBlockRestSec = 60;
const blockTransitionRestSec = 90;

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
    this.grip,
    this.supersetGroup,
  });

  final String name;
  final String? grip;
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

  /// Superserie: se alterna serie a serie con el siguiente del mismo grupo.
  final String? supersetGroup;

  String get targetLabel {
    final reps = repsMin == null
        ? null
        : (repsMax == null || repsMax == repsMin)
            ? '$repsMin'
            : '$repsMin–$repsMax';
    final hold = holdLabel(holdSecMin, holdSecMax);
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

  /// Bloques extra que recorre el cronómetro (sin calentamiento ni Tabata).
  List<ScriptExercise> get blockExercises => exercises
      .where((e) => e.blockName != null && e.blockName != warmupBlock && e.blockName != tabataBlock)
      .toList();
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

  // La práctica de pino va primero, sin fatiga.
  final pre = day.blockExercises.where((e) => preBlocks.contains(e.blockName)).toList();
  if (pre.isNotEmpty) {
    steps.addAll(_blockSteps(pre));
    final first = main.isNotEmpty ? main.first.name : null;
    if (first != null) {
      steps.add(RestStep(seconds: defaultBlockRestSec, nextLabel: day.type.isCircuit ? 'Ronda 1: $first' : first));
    }
  }

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
      .where((e) => !preBlocks.contains(e.blockName))
      .where((e) => e.variant == null || coreVariant == null || e.variant == coreVariant)
      .toList();
  for (final blockName in extras.map((e) => e.blockName!).toSet()) {
    final block = extras.where((e) => e.blockName == blockName).toList();
    if (steps.isNotEmpty && steps.last is! RestStep) {
      steps.add(RestStep(seconds: blockTransitionRestSec, nextLabel: 'Bloque $blockName: ${block.first.name}'));
    }
    steps.addAll(_blockSteps(block));
  }
  return steps;
}

/// Ejercicios seguidos que van juntos: uno solo, o los de una superserie
/// (mismo `supersetGroup`, uno tras otro en el plan).
List<List<ScriptExercise>> _units(List<ScriptExercise> exercises) {
  final units = <List<ScriptExercise>>[];
  for (final e in exercises) {
    final last = units.isEmpty ? null : units.last;
    if (e.supersetGroup != null && last != null && last.last.supersetGroup == e.supersetGroup) {
      last.add(e);
    } else {
      units.add([e]);
    }
  }
  return units;
}

List<ScriptStep> _blockSteps(List<ScriptExercise> exercises) {
  final steps = <ScriptStep>[];
  final units = _units(exercises);
  for (var u = 0; u < units.length; u++) {
    final unit = units[u];
    final superset = unit.length > 1;
    // En superserie se alterna A1 → B1 → descanso → A2 → B2…: las series del
    // grupo son las del que más tenga.
    final sets = unit.map((e) => e.sets ?? 1).reduce((a, b) => a > b ? a : b);
    final last = unit.last;
    // Sin descanso en el plan, uno por defecto: nadie encadena series de core.
    final rest = last.restSec ?? defaultBlockRestSec;
    for (var set = 1; set <= sets; set++) {
      for (final e in unit) {
        if (set > (e.sets ?? 1)) continue;
        final total = e.sets ?? 1;
        if (e.perSide) {
          steps.add(_work(e, position: set, total: total, isRound: false, side: 'derecho'));
          steps.add(_work(e, position: set, total: total, isRound: false, side: 'izquierdo'));
        } else {
          steps.add(_work(e, position: set, total: total, isRound: false));
        }
      }
      final isLastOfAll = set == sets && u == units.length - 1;
      if (!isLastOfAll && rest > 0) {
        final nextUnit = set == sets ? units[u + 1] : unit;
        final next = nextUnit.map((e) => e.name).join(' + ');
        steps.add(RestStep(
          seconds: rest,
          maxSec: last.restSec == null ? null : last.restSecMax,
          nextLabel: set == sets
              ? 'Siguiente: $next'
              : '${superset ? 'Superserie ' : ''}$next, serie ${set + 1}/$sets',
        ));
      }
    }
  }
  return steps;
}

WorkStep _work(ScriptExercise e, {required int position, required int total, required bool isRound, String? side}) =>
    WorkStep(
      exercise: e.name,
      grip: e.grip,
      targetLabel: e.targetLabel,
      targetReps: e.repsMin,
      holdSec: e.holdSecMin,
      holdSecMax: e.holdSecMax ?? e.holdSecMin,
      position: position,
      total: total,
      isRound: isRound,
      blockName: e.blockName,
      side: side,
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
