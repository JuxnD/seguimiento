import 'dates.dart';

// Escaleras de core del v3.1 (§19.10): V-up el jueves y dragon flag el lunes,
// desde el peldaño 1. Se propone subir cuando el criterio sale en 2 sesiones
// seguidas y lleva al menos 2 semanas en el peldaño; una molestia lumbar
// baja un peldaño.

/// Bloque del plan donde va el peldaño del día.
const ladderBlock = 'escalera';

/// Días mínimos en un peldaño antes de proponer subir ("nunca antes de 2–3
/// semanas").
const ladderMinDays = 14;

/// Sesiones seguidas que deben cumplir el criterio.
const ladderCleanSessions = 2;

/// Lo que pide el criterio de un ejercicio: `sets` series de al menos
/// `value` (reps, o segundos si es aguante). Por lado: `sets` por cada lado.
class LadderGoal {
  const LadderGoal(this.exercise, this.sets, this.value, {this.hold = false, this.perSide = false});

  final String exercise;
  final int sets;
  final int value;
  final bool hold;
  final bool perSide;

  /// ¿Las series de una sesión lo cumplen? Por lado se guardan de dos en dos.
  bool metBy(List<int> values) => values.where((v) => v >= value).length >= sets * (perSide ? 2 : 1);

  String get label => '$sets × $value${hold ? ' s' : ''}${perSide ? ' por lado' : ''}';
}

class LadderStep {
  const LadderStep({
    required this.step,
    required this.exercise,
    required this.prescription,
    this.sets = 3,
    this.repsMin,
    this.repsMax,
    this.holdMin,
    this.holdMax,
    this.perSide = false,
    this.rest = 60,
    this.restMax,
    this.rir,
    this.notes,
    this.goals = const [],
    this.hollowSec,
  });

  final int step;
  final String exercise;

  /// "3 × 8–12, bajada en 3 s".
  final String prescription;
  final int sets;
  final int? repsMin;
  final int? repsMax;
  final int? holdMin;
  final int? holdMax;
  final bool perSide;
  final int rest;
  final int? restMax;
  final int? rir;
  final String? notes;

  /// Criterio para subir. Vacío = último peldaño.
  final List<LadderGoal> goals;

  /// Peldaño 1: hollow de acompañamiento (3 × N s), parte del criterio.
  final int? hollowSec;

  String get criterion => goals.isEmpty ? 'Último peldaño' : goals.map((g) => '${g.exercise} ${g.label}').join(' + ');
}

class CoreLadder {
  const CoreLadder({required this.id, required this.name, required this.weekday, required this.steps});

  final String id;
  final String name;

  /// Día del v3.1 en que va (lunes el dragon flag, jueves el V-up).
  final int weekday;
  final List<LadderStep> steps;

  LadderStep stepAt(int n) => steps[(n.clamp(1, steps.length)) - 1];
  int get top => steps.length;

  /// ¿Este ejercicio es de la escalera? (incluye el hollow del peldaño 1).
  bool owns(String exercise) => steps.any((s) => s.exercise == exercise);
}

const hollowHold = 'Hollow body hold';

const dragonFlagLadder = CoreLadder(id: 'dragon_flag', name: 'Dragon flag', weekday: DateTime.monday, steps: [
  LadderStep(
    step: 1,
    exercise: 'Encogimiento inverso',
    prescription: '3 × 8–12, bajada en 3 s + hollow 3 × 30–40 s',
    repsMin: 8,
    repsMax: 12,
    rir: 2,
    rest: 60,
    restMax: 90,
    notes: 'Bajada en 3 s; la lumbar no se arquea.',
    hollowSec: 40,
    goals: [LadderGoal('Encogimiento inverso', 3, 12), LadderGoal(hollowHold, 3, 40, hold: true)],
  ),
  LadderStep(
    step: 2,
    exercise: 'Vela',
    prescription: '3 × 10–20 s',
    holdMin: 10,
    holdMax: 20,
    rest: 90,
    notes: 'Hombros en el suelo; cadera y piernas en vertical.',
    goals: [LadderGoal('Vela', 3, 20, hold: true)],
  ),
  LadderStep(
    step: 3,
    exercise: 'Negativo de dragon flag recogido',
    prescription: '3 × 3–5, bajada de 4 s',
    repsMin: 3,
    repsMax: 5,
    rest: 120,
    notes: 'Rodillas recogidas, bajada de 4 s, sin arquear la lumbar.',
    goals: [LadderGoal('Negativo de dragon flag recogido', 3, 5)],
  ),
  LadderStep(
    step: 4,
    exercise: 'Negativo de dragon flag a una pierna',
    prescription: '3 × 3–5',
    repsMin: 3,
    repsMax: 5,
    rest: 120,
    notes: 'Una pierna estirada, la otra recogida.',
    goals: [LadderGoal('Negativo de dragon flag a una pierna', 3, 5)],
  ),
  LadderStep(
    step: 5,
    exercise: 'Negativo de dragon flag',
    prescription: '3 × 3–5, bajada de 5 s',
    repsMin: 3,
    repsMax: 5,
    rest: 120,
    notes: 'Cuerpo recto, bajada de 5 s.',
    goals: [LadderGoal('Negativo de dragon flag', 3, 5)],
  ),
  LadderStep(
    step: 6,
    exercise: 'Dragon flag',
    prescription: '3 × 3–5',
    repsMin: 3,
    repsMax: 5,
    rest: 120,
  ),
]);

const vUpLadder = CoreLadder(id: 'v_up', name: 'V-up', weekday: DateTime.thursday, steps: [
  LadderStep(
    step: 1,
    exercise: 'Tuck-up',
    prescription: '3 × 8–12 + hollow 3 × 30 s',
    repsMin: 8,
    repsMax: 12,
    rir: 2,
    rest: 60,
    hollowSec: 30,
    goals: [LadderGoal('Tuck-up', 3, 12), LadderGoal(hollowHold, 3, 30, hold: true)],
  ),
  LadderStep(
    step: 2,
    exercise: 'V-up a una pierna',
    prescription: '3 × 6–8 por lado',
    repsMin: 6,
    repsMax: 8,
    perSide: true,
    rest: 60,
    goals: [LadderGoal('V-up a una pierna', 3, 8, perSide: true)],
  ),
  LadderStep(
    step: 3,
    exercise: 'V-up',
    prescription: '3 × 5–8 → 3 × 12',
    repsMin: 5,
    repsMax: 12,
    rest: 60,
    notes: 'Meta para subir: 3 × 12.',
    goals: [LadderGoal('V-up', 3, 12)],
  ),
  LadderStep(
    step: 4,
    exercise: 'V-up con bajada lenta',
    prescription: '3 × 8, bajada de 3 s',
    repsMin: 8,
    rest: 60,
  ),
]);

const coreLadders = [dragonFlagLadder, vUpLadder];

CoreLadder? ladderById(String id) => coreLadders.where((l) => l.id == id).firstOrNull;

/// La escalera que trae este ejercicio (el hollow no: va en las dos).
CoreLadder? ladderOf(String exercise) =>
    exercise == hollowHold ? null : coreLadders.where((l) => l.owns(exercise)).firstOrNull;

/// Una sesión con series de la escalera: valores por ejercicio (reps o s).
class LadderSession {
  const LadderSession({required this.date, required this.sets});

  final DateTime date;
  final Map<String, List<int>> sets;
}

class LadderAdvice {
  const LadderAdvice({required this.step, required this.daysOnStep, required this.cleanInARow, required this.canStepUp});

  final LadderStep step;
  final int daysOnStep;

  /// Sesiones seguidas (las últimas) que cumplen el criterio.
  final int cleanInARow;
  final bool canStepUp;

  String get status {
    if (step.goals.isEmpty) return 'Último peldaño.';
    if (canStepUp) return 'Criterio cumplido $cleanInARow sesiones seguidas: toca subir.';
    final days = daysOnStep < ladderMinDays ? ' · ${ladderMinDays - daysOnStep} días para poder subir' : '';
    return '$cleanInARow de $ladderCleanSessions sesiones seguidas con el criterio$days';
  }
}

/// ¿Toca subir? `sessions`: las del peldaño actual (desde `since`, sin las de
/// días con molestia lumbar), en cualquier orden.
LadderAdvice ladderAdvice(CoreLadder ladder, int step, DateTime since, List<LadderSession> sessions, DateTime today) {
  final s = ladder.stepAt(step);
  final sorted = [...sessions]..sort((a, b) => b.date.compareTo(a.date));
  var inARow = 0;
  for (final x in sorted) {
    if (s.goals.isEmpty || !s.goals.every((g) => g.metBy(x.sets[g.exercise] ?? const []))) break;
    inARow++;
  }
  final days = daysBetween(dateOnly(since), dateOnly(today));
  return LadderAdvice(
    step: s,
    daysOnStep: days,
    cleanInARow: inARow,
    canStepUp: s.goals.isNotEmpty && step < ladder.top && inARow >= ladderCleanSessions && days >= ladderMinDays,
  );
}
