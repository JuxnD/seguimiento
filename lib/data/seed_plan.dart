import 'package:drift/drift.dart';

import '../domain/dates.dart';
import '../domain/enums.dart';
import '../domain/plan_v3.dart';
import 'catalog_updates.dart';
import 'database.dart';
import 'repositories/plan_repository.dart';

/// Plan real del usuario, sembrado en la primera apertura.
///
/// v1 rige desde el 26 ago 2026; v2 desde el 28 sep 2026 y añade bloques de
/// ~10 min después de la sesión principal. Las versiones son inmutables: si
/// el plan cambia, se crea la v3 desde la app.
const programStartDate = '2026-08-26';

/// Los tres ejercicios de cada ronda del circuito, sin descanso entre ellos.
List<PlanExerciseDraft> _circuitRound() => [
      PlanExerciseDraft(name: 'Dominadas', repsMin: 5, grip: 'prona', restSec: 0),
      PlanExerciseDraft(name: 'Flexiones', repsMin: 10, restSec: 0),
      PlanExerciseDraft(name: 'Sentadillas', repsMin: 15, restSec: 0),
    ];

PlanDraft planV1() {
  final draft = PlanDraft.empty(DateTime(2026, 8, 26))..notes = 'Plan base. Circuito + bloques.';

  draft.days[0] // lunes
    ..type = DayType.circuito
    ..targetRounds = 6
    ..restBetweenRoundsSec = 30
    ..exercises.addAll(_circuitRound());

  draft.days[1] // martes
    ..type = DayType.bloques
    ..exercises.addAll([
      PlanExerciseDraft(
          name: 'Dominadas', sets: 4, repsMin: 6, repsMax: 8, restSec: 90, restSecMax: 120, grip: 'prona'),
      PlanExerciseDraft(name: 'Flexiones', sets: 4, repsMin: 14, repsMax: 16, restSec: 90, restSecMax: 120),
      PlanExerciseDraft(name: 'Sentadillas', sets: 3, repsMin: 25, repsMax: 25, restSec: 60),
    ]);

  draft.days[2] // miércoles
    ..type = DayType.circuitoLigero
    ..targetRounds = 5
    ..restBetweenRoundsSec = 30
    ..exercises.addAll(_circuitRound());

  draft.days[3] // jueves
    ..type = DayType.bloques
    ..exercises.addAll([
      PlanExerciseDraft(name: 'Dominadas', sets: 3, repsMin: 8, restSec: 90, restSecMax: 120, grip: 'supina'),
      PlanExerciseDraft(name: 'Flexiones', sets: 5, repsMin: 13, restSec: 60, restSecMax: 75),
      PlanExerciseDraft(name: 'Sentadillas', sets: 3, repsMin: 20, repsMax: 25, restSec: 60),
    ]);

  draft.days[4] // viernes
    ..type = DayType.progresion
    ..targetRounds = 8
    ..restBetweenRoundsSec = 30
    ..exercises.addAll(_circuitRound());

  draft.days[5].type = DayType.futbol; // sábado
  draft.days[6].type = DayType.futbol; // domingo
  return draft;
}

/// v2 = v1 + bloques extra de ~10 min. Jueves y viernes quedan protegidos.
PlanDraft planV2() {
  final draft = planV1()
    ..validFrom = DateTime(2026, 9, 28)
    ..notes = 'Suma core, cuádriceps con carga y hombro. Jueves y viernes protegidos.';

  draft.days[0].exercises.addAll([
    PlanExerciseDraft(
      name: 'Elevación de piernas colgado',
      sets: 3,
      repsMin: 8,
      repsMax: 12,
      block: 'core',
      variant: 'A',
      notes: 'Bloque de ~10 min después del circuito. Alterna con la variante B.',
    ),
    PlanExerciseDraft(
      name: 'Hollow body hold',
      sets: 2,
      holdSecMin: 20,
      holdSecMax: 40,
      block: 'core',
      variant: 'A',
    ),
    PlanExerciseDraft(
      name: 'Elevación de piernas colgado',
      sets: 3,
      repsMin: 8,
      repsMax: 12,
      block: 'core',
      variant: 'B',
    ),
    PlanExerciseDraft(
      name: 'Plancha lateral',
      sets: 2,
      holdSecMin: 30,
      holdSecMax: 45,
      perSide: true,
      block: 'core',
      variant: 'B',
    ),
  ]);

  draft.days[1].exercises.add(PlanExerciseDraft(
    name: 'Sentadilla búlgara',
    sets: 3,
    repsMin: 8,
    repsMax: 12,
    perSide: true,
    rirMin: 1,
    rirMax: 2,
    block: 'cuádriceps',
    notes: 'Al llegar a 12, añadir carga (mochila o garrafas). No subir repeticiones.',
  ));

  draft.days[2].exercises.add(PlanExerciseDraft(
    name: 'Pike push-up',
    sets: 3,
    repsMin: 6,
    repsMax: 8,
    rirMin: 2,
    rirMax: 3,
    block: 'hombro',
    notes: 'Progresión: pike → pies elevados → HSPU asistido → HSPU. '
        'Si el viernes empeoran las flexiones, bajar a 2 series.',
  ));

  draft.days[3].notes = 'Protegido: nada extra.';
  draft.days[4].notes = 'Protegido: nada extra.';
  return draft;
}

/// Plan v3 "Cierre de año" (§18.2), desde el lunes `start`. La semana tipo
/// es fija; lo que cambia por semana (descargas, Cindy o Tabata, burpees) lo
/// decide `plan_v3.dart` según la semana del bloque.
PlanDraft planV3(DateTime start) {
  final draft = PlanDraft.empty(start)
    ..scheme = v3Scheme
    ..notes = 'Cierre de año: físico proporcionado (espalda en V, hombro, brazos, abdomen) manteniendo la '
        'resistencia. 10 semanas hasta el test del ${formatLong(v3TestDate(start))}. Calentamiento de 8 min.';

  PlanExerciseDraft ex(String name, int sets,
          {int? reps,
          int? repsMax,
          int? holdMin,
          int? holdMax,
          int? rest,
          int? rir,
          int? rirMax,
          bool perSide = false,
          String? grip,
          String? block,
          String? superset,
          String? notes}) =>
      PlanExerciseDraft(
        name: name,
        sets: sets,
        repsMin: reps,
        repsMax: repsMax ?? reps,
        holdSecMin: holdMin,
        holdSecMax: holdMax,
        restSec: rest,
        rirMin: rir,
        rirMax: rirMax ?? rir,
        perSide: perSide,
        grip: grip,
        block: block,
        supersetGroup: superset,
        notes: notes,
      );

  draft.days[0] // lunes: tren superior A (tirón y hombro)
    ..type = DayType.trenSuperior
    ..notes = 'Tren superior A: tirón y hombro.'
    ..exercises.addAll([
      ex('Separaciones con banda', 2, reps: 15, rest: 30, notes: 'Parte del calentamiento.'),
      ex('Dominadas', 4, reps: 5, repsMax: 8, rir: 1, rirMax: 2, rest: 120, grip: 'prona'),
      ex('Fondos en barra', 3, reps: 6, repsMax: 10, rir: 2, rest: 90),
      ex('Remo invertido (mesa)', 3, reps: 8, repsMax: 15, rir: 1, rirMax: 2, rest: 90),
      ex('Pike push-up', 3, reps: 6, repsMax: 10, rir: 2, rest: 90),
      ex('Elevaciones laterales con banda', 3, reps: 15, repsMax: 20, rir: 1, rest: 60),
      ex('Elevación de piernas colgado', 3, reps: 8, repsMax: 12, rir: 2, rest: 60, block: 'core'),
      ex('Hollow body hold', 2, holdMin: 30, holdMax: 40, rest: 60, block: 'core'),
    ]);

  draft.days[1] // martes: piernas y core funcional
    ..type = DayType.piernas
    ..notes = 'Piernas y core funcional. La búlgara y el peso muerto progresan con la mochila.'
    ..exercises.addAll([
      ex('Sentadilla búlgara', 3, reps: 8, repsMax: 12, rir: 1, rirMax: 2, rest: 90, perSide: true),
      ex('Peso muerto a una pierna con mochila', 3, reps: 8, repsMax: 10, rir: 2, rest: 90, perSide: true),
      ex('Puente de glúteo a una pierna', 3, reps: 12, repsMax: 15, rir: 1, rirMax: 2, rest: 60, perSide: true),
      ex('Gemelos a una pierna en escalón', 3, reps: 15, repsMax: 20, rir: 1, rest: 45, perSide: true),
      ex('Pallof press con banda', 3, reps: 10, rir: 2, rest: 45, perSide: true),
      ex('Plancha lateral', 2, holdMin: 35, holdMax: 45, rest: 45, perSide: true),
    ]);

  draft.days[2] // miércoles: resistencia (Cindy, Tabata o por tiempo según la semana)
    ..type = DayType.resistencia
    ..notes = 'Semanas impares Cindy (AMRAP 20 min), pares Tabata. Después, movilidad nocturna completa.'
    ..exercises.addAll([
      // La ronda de Cindy y de las 10 rondas por tiempo.
      PlanExerciseDraft(name: 'Dominadas', repsMin: 5, grip: 'prona', restSec: 0),
      PlanExerciseDraft(name: 'Flexiones', repsMin: 10, restSec: 0),
      PlanExerciseDraft(name: 'Sentadillas', repsMin: 15, restSec: 0),
      // Los cuatro bloques del Tabata, en orden.
      for (final name in tabataExercises) PlanExerciseDraft(name: name, sets: 8, holdSecMin: 20, block: 'tabata'),
    ]);

  draft.days[3] // jueves: tren superior B (empuje y brazos)
    ..type = DayType.trenSuperior
    ..notes = 'Tren superior B: empuje y brazos.'
    ..exercises.addAll([
      ex('Dominadas', 4, reps: 6, repsMax: 10, rir: 1, rirMax: 2, rest: 120, grip: 'supina'),
      ex('Flexión arquero', 4, reps: 3, repsMax: 6, rir: 2, rest: 90, perSide: true,
          notes: 'Progresión: arquero → una mano con mano elevada → una mano pies abiertos → una mano estricta.'),
      ex('Remo con banda', 3, reps: 12, repsMax: 15, rir: 1, rest: 60),
      ex('Flexiones diamante', 3, reps: 10, repsMax: 15, rir: 1, rirMax: 2, rest: 60),
      ex('Curl con banda', 3, reps: 12, repsMax: 15, rir: 1, rest: 60, superset: 'brazos'),
      ex('Extensión de tríceps sobre la cabeza con banda', 3, reps: 12, repsMax: 15, rir: 1, rest: 60,
          superset: 'brazos'),
      ex('Face pull con banda', 3, reps: 15, repsMax: 20, rir: 1, rest: 45),
      ex('Elevaciones laterales con banda', 2, reps: 15, repsMax: 20, rir: 1, rest: 45),
    ]);

  draft.days[4] // viernes: densidad y core avanzado (+ burpees EMOM)
    ..type = DayType.densidad
    ..targetRounds = 6
    ..restBetweenRoundsSec = 30
    ..notes = 'Circuito ligero con técnica perfecta y respiración nasal todo lo posible. '
        'Después L-sit, toes-to-bar y el EMOM de burpees.'
    ..exercises.addAll([
      PlanExerciseDraft(name: 'Dominadas', repsMin: 5, grip: 'prona', restSec: 0),
      PlanExerciseDraft(name: 'Flexiones', repsMin: 10, restSec: 0),
      PlanExerciseDraft(name: 'Sentadillas', repsMin: 15, restSec: 0),
      ex('L-sit', 5, holdMin: 10, holdMax: 20, rest: 60, block: 'core avanzado'),
      ex('Toes-to-bar', 3, reps: 5, repsMax: 8, rest: 60, block: 'core avanzado'),
    ]);

  draft.days[5].type = DayType.futbol;
  draft.days[6]
    ..type = DayType.futbol
    ..notes = 'Si fue de intensidad ≥ 8, el lunes va en versión ligera.';
  return draft;
}

/// Los cuatro ejercicios del Tabata, en orden (§18.2).
const tabataExercises = ['Burpees', 'Escaladores', 'Sentadilla con salto', 'Rodillas arriba'];

/// Activa el Plan v3 desde el lunes `start`: crea la versión, completa las
/// guías de los ejercicios nuevos y fija la próxima medición (viernes de la
/// semana 4). Devuelve el id de la versión.
Future<int> activatePlanV3(AppDatabase db, PlanRepository plan, DateTime start) async {
  final id = await plan.saveAsNewVersion(planV3(start));
  await applyExerciseGuides(db);
  await (db.update(db.profiles)..where((t) => t.id.equals(1)))
      .write(ProfilesCompanion(nextMeasurementDate: Value(dayKey(v3MeasurementDates(start).first))));
  return id;
}

/// Siembra plan y metas la primera vez. Idempotente: si ya hay una versión de
/// plan, no toca nada (las versiones posteriores son del usuario).
Future<bool> seedIfEmpty(AppDatabase db, PlanRepository plan) async {
  final existing = await plan.versions();
  if (existing.isNotEmpty) return false;

  await plan.saveAsNewVersion(planV1());
  await plan.saveAsNewVersion(planV2());
  await applyExerciseGuides(db);
  await (db.update(db.profiles)..where((t) => t.id.equals(1))).write(const ProfilesCompanion(
    startDate: Value(programStartDate),
    proteinMin: Value(130),
    proteinMax: Value(160),
    kcalTarget: Value(2400),
    kcalFloor: Value(2000),
    minWarmupSec: Value(360),
    cooldownTargetSec: Value(180),
    measureIntervalDays: Value(21),
    measureIntervalMaxDays: Value(28),
    nextMeasurementDate: Value('2026-10-02'),
    neverToFailure: Value(true),
  ));
  return true;
}

