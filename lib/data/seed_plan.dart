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

/// Tabata de bajo impacto del viernes del v3.1 (§19.1): víspera de partido,
/// sin saltos ni burpees.
const tabataLowImpact = ['Flexiones', 'Escaladores', 'Sentadillas', 'Hollow rocks'];

/// Plan v3.1 (§19.1, 5 oct), desde el lunes `start`. Reemplaza la semana del
/// v3: tirón y hombro, empuje y brazos, piernas y potencia el miércoles (a
/// ~72 h de los partidos), torso B y el viernes de referencia. Lo que cambia
/// por semana (descarga, Cindy o Tabata) lo decide `plan_v3.dart`.
PlanDraft planV31(DateTime start) {
  final draft = PlanDraft.empty(start)
    ..scheme = v31Scheme
    ..notes = 'v3.1: fuerza a RIR 0–3 con doble progresión, piernas el miércoles y una sola sesión '
        'metabólica (viernes). 9 semanas: pruebas el ${formatLong(v31TestDate(start))}. '
        'Calentamiento general de 8 min.';

  PlanExerciseDraft ex(String name, int sets,
          {int? reps,
          int? repsMax,
          int? holdMin,
          int? holdMax,
          int? rest,
          int? restMax,
          int? rir,
          int? rirMax,
          bool perSide = false,
          String? grip,
          String? block,
          String? variant,
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
        restSecMax: restMax,
        rirMin: rir,
        rirMax: rirMax ?? rir,
        perSide: perSide,
        grip: grip,
        block: block,
        variant: variant,
        supersetGroup: superset,
        notes: notes,
      );

  // Práctica de pino al empezar, sin fatiga (bloque previo al trabajo).
  PlanExerciseDraft pino({int max = 300}) => ex('Pino pecho a la pared', 1,
      holdMin: 300, holdMax: max, block: 'pino', notes: 'Práctica libre: varios intentos cortos, sin fatiga.');

  draft.days[0] // lunes: tirón + hombro
    ..type = DayType.trenSuperior
    ..notes = 'Tirón + hombro. Después: caminata suave de 15–20 min.'
    ..exercises.addAll([
      pino(),
      ex('Dominadas', 4, reps: 5, repsMax: 8, rir: 1, rirMax: 2, rest: 120, restMax: 180, grip: 'prona',
          notes: 'Con mochila: +2–5 kg al completar 4 × 8 con RIR 1–2.'),
      ex('Remo invertido (mesa)', 3, reps: 8, repsMax: 12, rir: 1, rirMax: 2, rest: 90, superset: 'remo',
          notes: 'Pies elevados.'),
      ex('Elevaciones laterales con banda', 4, reps: 15, repsMax: 25, rir: 0, rirMax: 1, rest: 90, superset: 'remo'),
      ex('Pike push-up', 3, reps: 6, repsMax: 10, rir: 1, rirMax: 2, rest: 120),
      ex('Face pull con banda', 2, reps: 15, repsMax: 20, rir: 1, rest: 60),
      ex('Elevación de piernas colgado', 3, reps: 6, repsMax: 12, rir: 1, rirMax: 2, rest: 90,
          notes: 'Toes-to-bar cuando salgan con las piernas rectas.'),
      ex('Rollout con toalla', 2, reps: 6, repsMax: 10, rir: 2, rest: 90),
    ]);

  draft.days[1] // martes: empuje + brazos
    ..type = DayType.trenSuperior
    ..notes = 'Empuje + brazos.'
    ..exercises.addAll([
      pino(),
      ex('Fondos en barra', 4, reps: 6, repsMax: 10, rir: 1, rirMax: 2, rest: 120, restMax: 180,
          notes: 'Con mochila cuando salgan 4 × 10.'),
      ex('Flexión arquero', 3, reps: 4, repsMax: 6, rir: 2, rest: 120, perSide: true,
          notes: 'Cuando el arquero sea fácil, flexión a una mano con la mano elevada.'),
      ex('Flexiones con pies elevados', 3, reps: 10, repsMax: 20, rir: 0, rirMax: 2, rest: 90),
      ex('Extensión de tríceps sobre la cabeza con banda', 3, reps: 12, repsMax: 20, rir: 0, rirMax: 1, rest: 60,
          superset: 'brazos'),
      ex('Curl con banda', 3, reps: 12, repsMax: 20, rir: 0, rirMax: 1, rest: 60, superset: 'brazos'),
      ex('Colgarse de la barra', 3, holdMin: 30, holdMax: 60, rest: 60, notes: '2–3 min acumulados.'),
    ]);

  draft.days[2] // miércoles: piernas + potencia
    ..type = DayType.piernas
    ..notes = 'Piernas + potencia, a ~72 h de los partidos. Calentamiento tipo FIFA 11+.'
    ..exercises.addAll([
      ex('Calentamiento tipo FIFA 11+', 1, holdMin: 600, block: 'calentamiento'),
      ex('Salto vertical', 3, reps: 8, rest: 60, restMax: 90, notes: '60–100 contactos entre los tres saltos.'),
      ex('Salto largo', 3, reps: 6, rest: 60, restMax: 90),
      ex('Salto de patinador', 3, reps: 6, rest: 60, restMax: 90, perSide: true),
      ex('Aceleración 10–20 m', 6, reps: 1, rest: 60, restMax: 120,
          notes: 'Solo con un espacio seguro; si no, van en el calentamiento del partido.'),
      ex('Sentadilla búlgara', 4, reps: 8, repsMax: 12, rir: 1, rirMax: 2, rest: 120, perSide: true),
      ex('Peso muerto a una pierna con mochila', 3, reps: 8, repsMax: 12, rir: 2, rest: 90, perSide: true),
      ex('Nórdico (isquios)', 3, reps: 3, repsMax: 6, rir: 2, rest: 120,
          notes: 'Bajada lenta (3–5 s). Las primeras 2 semanas, 2 series.'),
      ex('Gemelos a una pierna en escalón', 3, reps: 12, repsMax: 20, rir: 1, rest: 60, perSide: true),
      ex('Carga de maleta con mochila', 3, reps: 30, repsMax: 40, rest: 60, perSide: true,
          notes: 'Metros por lado. Alterna con la carga abrazada al pecho.'),
      ex('Pallof press con banda', 3, reps: 10, rest: 45, perSide: true, block: 'core'),
      ex('Plancha lateral', 2, holdMin: 30, holdMax: 45, rest: 45, perSide: true, block: 'core'),
    ]);

  draft.days[3] // jueves: torso B
    ..type = DayType.trenSuperior
    ..notes = 'Torso B: segunda frecuencia. Si las piernas llegan pesadas al sábado, el circuito del '
        'viernes pasa a hoy, después del torso.'
    ..exercises.addAll([
      ex('Dominadas', 3, reps: 6, repsMax: 10, rir: 1, rest: 120, grip: 'supina'),
      ex('Flexiones con pies elevados', 3, reps: 8, repsMax: 15, rir: 1, rirMax: 2, rest: 90, notes: 'O fondos.'),
      ex('Remo invertido (mesa)', 2, reps: 10, repsMax: 15, rir: 1, rirMax: 2, rest: 90),
      ex('Elevaciones laterales con banda', 4, reps: 15, repsMax: 25, rir: 0, rirMax: 1, rest: 60),
      ex('Curl con banda', 2, reps: 12, repsMax: 20, rir: 0, rirMax: 1, rest: 60, superset: 'brazos'),
      ex('Extensión de tríceps sobre la cabeza con banda', 2, reps: 12, repsMax: 20, rir: 0, rirMax: 1, rest: 60,
          superset: 'brazos'),
      // Compresión (A) o L-sit (B): se alternan por semana.
      ex('Elevaciones en pike sentado', 3, reps: 8, repsMax: 10, rest: 60, restMax: 90, block: 'compresión', variant: 'A'),
      ex('Elevaciones en straddle', 3, reps: 8, rest: 60, restMax: 90, block: 'compresión', variant: 'A'),
      ex('Barca / V-sit', 3, holdMin: 20, holdMax: 30, rest: 60, block: 'compresión', variant: 'A'),
      ex('Plancha inversa con patada', 2, reps: 10, rest: 60, perSide: true, block: 'compresión', variant: 'A'),
      ex('L-sit', 4, holdMin: 10, holdMax: 20, rest: 60, restMax: 90, block: 'compresión', variant: 'B'),
      ex('Progresión de pistol', 2, reps: 5, rir: 3, rest: 90, perSide: true, block: 'opcional',
          notes: 'Lejos del fallo. Si no hay tiempo, se salta.'),
    ]);

  draft.days[4] // viernes: circuito de referencia + habilidades
    ..type = DayType.progresion
    ..targetRounds = 10
    ..restBetweenRoundsSec = 30
    ..notes = 'Circuito 5/10/15 hasta cerrar 10 rondas limpias; después, semanas alternas de Cindy y Tabata de '
        'bajo impacto. Movilidad 10 min al final. Sin saltos ni burpees: víspera de partido.'
    ..exercises.addAll([
      pino(max: 600),
      PlanExerciseDraft(name: 'Dominadas', repsMin: 5, grip: 'prona', restSec: 0),
      PlanExerciseDraft(name: 'Flexiones', repsMin: 10, restSec: 0),
      PlanExerciseDraft(name: 'Sentadillas', repsMin: 15, restSec: 0),
      ex('L-sit', 2, holdMin: 10, holdMax: 20, rest: 60, block: 'habilidades', notes: 'Ligero, lejos del fallo.'),
      ex('Toes-to-bar', 2, reps: 5, repsMax: 8, rir: 3, rest: 60, block: 'habilidades', notes: 'Ligero, lejos del fallo.'),
      for (final name in tabataLowImpact) PlanExerciseDraft(name: name, sets: 8, holdSecMin: 20, block: 'tabata'),
    ]);

  draft.days[5]
    ..type = DayType.futbol
    ..notes = 'Calentamiento tipo FIFA 11+ con 4–6 aceleraciones antes de jugar. 400–560 ml de agua unas 4 h antes.';
  draft.days[6]
    ..type = DayType.futbol
    ..notes = 'Si el partido fue de RPE ≥ 8, el lunes va en versión ligera. Agua fría solo después del domingo.';
  return draft;
}

/// Bloque de planche (§19.7): martes, jueves y viernes, al inicio, ~10 min.
/// Muñecas, inclinación y, el martes, flexiones pseudo-planche; el tuck entra
/// cuando la inclinación llega a 3 × 30 s. En descarga, solo inclinaciones.
const plancheDays = {DateTime.tuesday, DateTime.thursday, DateTime.friday};

List<PlanExerciseDraft> plancheBlock({required int weekday, required bool deload, required bool tuckReady}) {
  if (!plancheDays.contains(weekday)) return const [];
  PlanExerciseDraft p(String name, int sets,
          {int? reps, int? repsMax, int? hold, int? holdMax, int? rest, int? rir, String? notes}) =>
      PlanExerciseDraft(
        name: name,
        sets: sets,
        repsMin: reps,
        repsMax: repsMax ?? reps,
        holdSecMin: hold,
        holdSecMax: holdMax ?? hold,
        restSec: rest,
        rirMin: rir,
        rirMax: rir,
        block: 'planche',
        notes: notes,
      );
  return [
    if (!deload) p('Muñecas (planche)', 1, hold: 120, notes: 'Círculos, balanceo en cuatro apoyos y palmas al revés.'),
    p('Inclinación de planche', 3, hold: 15, holdMax: 30, rest: 60,
        notes: 'Hombros por delante de las manos. Meta: 3 × 30 s.'),
    if (!deload && weekday == DateTime.tuesday)
      p('Flexión pseudo-planche', 3, reps: 5, repsMax: 8, rir: 2, rest: 90),
    if (!deload && tuckReady)
      p('Tuck planche', 6, hold: 5, holdMax: 10, rest: 60, notes: 'Meta: 10 s. Sin dolor de muñeca o codo.'),
  ];
}

/// Metas del v3.1 (§19.3): 2.100 kcal entre semana y 2.400 en días de
/// fútbol (los rangos son 2.100–2.200 y 2.400–2.500), proteína 160–170 g
/// todos los días. Son el punto de partida: la báscula decide cada 2 semanas.
const v31KcalWeekday = 2100;
const v31KcalFootball = 2400;
const v31ProteinMin = 160;
const v31ProteinMax = 170;

/// Activa el Plan v3.1 desde el lunes `start`: crea la versión (si había un
/// v3 desde ese mismo lunes, el v3.1 lo reemplaza: a igual fecha gana la
/// versión más nueva), completa las guías de los ejercicios nuevos, pone las
/// metas de §19.3 y fija la próxima medición (sábado 17 oct, abdomen en
/// ayunas). Devuelve el id de la versión.
Future<int> activatePlanV31(AppDatabase db, PlanRepository plan, DateTime start) async {
  final id = await plan.saveAsNewVersion(planV31(start));
  await applyExerciseGuides(db);
  await (db.update(db.profiles)..where((t) => t.id.equals(1))).write(ProfilesCompanion(
    nextMeasurementDate: Value(dayKey(v31MeasurementDates(start).first)),
    kcalTarget: const Value(v31KcalWeekday),
    kcalTargetFootball: const Value(v31KcalFootball),
    proteinMin: const Value(v31ProteinMin),
    proteinMax: const Value(v31ProteinMax),
    // El abdomen va cada 2 semanas: el aviso de "medición antes de tiempo" y
    // la alerta del informe usan este mínimo.
    measureIntervalDays: const Value(14),
    measureIntervalMaxDays: const Value(21),
  ));
  return id;
}

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

/// Lunes de inicio del v3.1, o null si no se activó.
Future<DateTime?> v31Start(AppDatabase db) async {
  final rows = await (db.select(db.planVersions)
        ..where((t) => t.scheme.equals(v31Scheme))
        ..orderBy([(t) => OrderingTerm(expression: t.validFrom)])
        ..limit(1))
      .get();
  return rows.isEmpty ? null : parseDay(rows.first.validFrom);
}

/// Tras medir con el v3.1 activo, la próxima medición acordada pasa a la
/// siguiente fecha del calendario (abdomen cada 2 semanas, §19.4). Sin v3.1
/// no toca nada.
Future<void> advanceV31Measurement(AppDatabase db, DateTime measured) async {
  final start = await v31Start(db);
  if (start == null) return;
  final next = v31NextMeasurement(start, addDays(measured, 1));
  if (next == null) return;
  await (db.update(db.profiles)..where((t) => t.id.equals(1)))
      .write(ProfilesCompanion(nextMeasurementDate: Value(dayKey(next))));
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

