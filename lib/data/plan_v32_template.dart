import '../domain/enums.dart';
import '../domain/goal_history.dart' show GoalMetric, GoalOrigin;
import 'database.dart';
import 'repositories/goal_repository.dart';
import 'exercise_details.dart';
import 'repositories/exercise_repository.dart';
import '../domain/plan_v32.dart';
import 'repositories/plan_repository.dart';
import 'seed_plan.dart';

Future<int> activatePlanV32(
        AppDatabase db, PlanRepository repository, DateTime start) =>
    db.transaction(() async {
      final exercises = ExerciseRepository(db);
      for (final name in [
        ...v32ExerciseNames.values,
        'Mesa invertida',
        'Plancha inversa sobre antebrazos',
        'Plancha inversa sobre las manos',
        'Plancha inversa a una pierna',
        'Plancha inversa con patada',
        'Plancha inversa con pies elevados'
      ]) {
        await exercises.getOrCreate(name);
        // The shared fixed guide is consulted by name; existing editable cues stay intact.
        if (exerciseDetail(name) == null) throw StateError('Falta guía: $name');
      }
      final id = await repository.saveAsNewVersion(planV32(start));
      // §16.30.4: el plan pide 7.000 pasos entre semana (§19.3); rige desde
      // el día en que empieza el v3.2 y el aviso de las 18:00 la usa.
      // Con vigencia desde `start` (puede ser el próximo lunes): el perfil
      // la toma cuando entra en vigor.
      await GoalRepository(db).scheduleGoal(
          GoalMetric.pasos, v32StepsWeekday.toDouble(),
          effectiveFrom: start,
          origin: GoalOrigin.plan,
          reason: 'Activación del v3.2: 7.000 pasos entre semana');
      return id;
    });

/// Pasos entre semana del plan (§19.3, §16.30.4).
const v32StepsWeekday = 7000;

/// The complete week from §19.13, retaining the shared immutable plan model.
PlanDraft planV32(DateTime start) {
  final draft = planV31(start)
    ..scheme = v32Scheme
    ..notes = 'v3.2: mantenimiento de 6 rondas; 10 por tiempo en las semanas 4 y 8; '
        'Cindy en las semanas 2, 6 y 9. Planche martes/viernes con paralelas. '
        'Tests de 13 pruebas; movilidad con cada test de piernas.';
  PlanExerciseDraft ex(String name, int sets,
          {int? min,
          int? max,
          int? hold,
          int? holdMax,
          bool side = false,
          int rest = 60,
          String? block,
          String? group,
          String? note}) =>
      PlanExerciseDraft(
          name: name,
          sets: sets,
          repsMin: min,
          repsMax: max ?? min,
          holdSecMin: hold,
          holdSecMax: holdMax ?? hold,
          perSide: side,
          restSec: rest,
          block: block,
          supersetGroup: group,
          notes: note);
  void remove(int day, List<String> names) =>
      draft.days[day].exercises.removeWhere((e) => names.contains(e.name));
  draft.days[0].exercises.addAll([
    ex('Scap pull-up', 2,
        min: 8,
        block: 'calentamiento',
        note: 'Sin barra: deslizamientos en la pared.'),
    ex('Rotación externa con banda', 2, min: 15, max: 20, group: 'manguito'),
    ex('Sentadilla isométrica en la pared', 4,
        hold: 30, holdMax: 45, group: 'rodilla', note: 'Esfuerzo 7/10.'),
    ex('Abducción de cadera de lado', 2,
        min: 15, max: 20, side: true, group: 'rodilla'),
    ex('Nórdico inverso', 2, min: 6, max: 10, note: 'Bajada de 3 s.'),
  ]);
  remove(0, ['Rollout con toalla']);
  draft.days[0].exercises
      .firstWhere((e) => e.name == 'Face pull con banda')
      .supersetGroup = 'manguito';
  draft.days[1].exercises.addAll([
    ex('Flexiones escapulares', 2, min: 10, block: 'calentamiento'),
    ex('Copenhague', 1,
        min: 3,
        max: 5,
        side: true,
        group: 'aductores',
        note: 'Sem1–2:3–5;3–4:7–10;5+:12–15. Rodilla corta.'),
    ex('Tibial en la pared', 2, min: 15, max: 25, group: 'aductores'),
  ]);
  final oneArm =
      draft.days[1].exercises.firstWhere((e) => e.name == 'Flexión a una mano');
  oneArm.repsMax = 5;
  final hang = draft.days[1].exercises
      .firstWhere((e) => e.name == 'Colgarse de la barra');
  hang.sets = 2;
  hang.notes = 'Máximo conocido menos 10 s; sin dato no inventar duración.';
  draft.days[1].notes =
      'Empuje + brazos. Desde semana5, intervalos15/15 sólo sin fútbol entre semana.';
  remove(2, ['Plancha lateral']);
  for (final e in draft.days[2].exercises) {
    if (e.name == 'Salto vertical' || e.name == 'Salto largo') {
      e.sets = 3;
      e.repsMin = 3;
      e.repsMax = 3;
    }
    if (e.name == 'Salto de patinador') {
      e.sets = 2;
      e.repsMin = 5;
      e.repsMax = 5;
    }
    if (e.name == 'Aceleración 10–20 m') {
      e.sets = 3;
    }
    if (e.name == 'Sentadilla búlgara') {
      e.sets = 3;
      e.repsMin = 6;
      e.repsMax = 10;
    }
    if (e.name == 'Peso muerto a una pierna con mochila') {
      e.repsMin = 8;
      e.repsMax = 8;
    }
    if (e.name == 'Pallof press con banda') e.sets = 2;
    if (e.name == 'Gemelos a una pierna en escalón') {
      e.repsMin = 10;
      e.repsMax = 15;
    }
  }
  draft.days[2].exercises.insert(
      1,
      ex('Aterrizaje clavado', 3,
          min: 5, note: 'Bilateral; unilateral desde semana3; estabiliza.'));
  draft.days[2].exercises.insert(
      2,
      ex('Sprint lanzado', 3,
          min: 1,
          rest: 120,
          note:
              '20 m progresivo +20 m; sem1–2 85–90%, luego95%. 3–4 reps; descanso2–3min. Pinchazo: parar.'));
  draft.days[2].exercises
      .add(ex('Sóleo sentado con mochila', 3, min: 12, max: 20));
  draft.days[2].exercises.add(ex('Carga abrazada al pecho', 3,
      min: 30, max: 40, note: 'Metros; alterna con carga de maleta.'));
  remove(3, [
    'Barca / V-sit',
    'Plancha inversa con patada',
    'Curl con banda',
    'Extensión de tríceps sobre la cabeza con banda'
  ]);
  for (final e in draft.days[3].exercises) {
    if (e.name == 'Elevaciones en pike sentado' ||
        e.name == 'Elevaciones en straddle' ||
        e.name == 'L-sit') e.variant = null;
    if (e.name == 'Elevaciones en straddle') e.repsMax = 10;
    if (e.name == 'Progresión de pistol') {
      e.sets = 3;
      e.block = null;
    }
    if (e.name == 'Flexiones con pies elevados') e.repsMax = 12;
    if (e.name == 'Remo invertido (mesa)') {
      e.sets = 3;
      e.repsMin = 10;
      e.repsMax = 10;
    }
    if (e.name == 'Elevaciones laterales con banda') e.sets = 3;
  }
  draft.days[3].notes =
      'Torso B + compresión. V-sit vuelve al lograr L-sit20s. Planche: sólo muñecas y support.';
  draft.days[3].exercises.addAll([
    ex('Scap pull-up', 2, min: 8, block: 'calentamiento'),
    ex('Rotación externa con banda', 2, min: 15),
    ex('Y-T prono', 2, min: 10, note: 'Pausa2s.'),
    ex('Copenhague', 1, min: 3, max: 5, side: true),
    ex('Bajada lateral del escalón', 2,
        min: 8, side: true, note: 'Bajada3s; rodilla sobrepie.'),
    ex('Sentadilla isométrica en la pared', 3,
        hold: 30, holdMax: 45, group: 'rodilla'),
    ex('Abducción de cadera de lado', 2,
        min: 15, max: 20, side: true, group: 'rodilla'),
  ]);
  remove(4, ['L-sit', 'Toes-to-bar', 'Escaladores', 'Hollow rocks']);
  draft.days[4].exercises.removeWhere((e) => e.block == 'tabata');
  draft.days[4].targetRounds = 6;
  draft.days[4].notes =
      'Mantenimiento6rondas; semana4 de cada bloque10. Sin saltos ni burpees.';
  draft.days[4].exercises.addAll([
    ex('Hollow rocks', 3, hold: 20, holdMax: 30, block: 'core'),
    ex('Sóleo sentado con mochila', 2, min: 15, group: 'tobillo'),
    ex('Tibial en la pared', 2, min: 20, group: 'tobillo'),
  ]);
  for (final index in [5, 6]) {
    draft.days[index].type = DayType.futbol;
    draft.days[index].notes =
        'FIFA abreviado10–15min antes: carrera/cambios/equilibrio/sentadilla/saltos. '
        'Pesoantes/después+agua; sRPE=RPE×minutos. NocheSuelta+módulopiernas.';
    draft.days[index].exercises.add(ex('Calentamiento tipo FIFA 11+', 1,
        hold: 600, holdMax: 900, block: 'calentamiento'));
  }
  for (final day in draft.days) {
    for (final e in day.exercises) {
      e.purpose ??= exercisePurpose(e.name);
      e.physicalVariantKey = switch (e.name) {
        'Copenhague' => 'copenhagen_short',
        'Sóleo sentado con mochila' => 'seated_soleus_bilateral',
        'Rotación externa con banda' => 'band_rotation_side',
        'Aterrizaje clavado' => landingBilateral,
        _ => null,
      };
    }
    orderV32Exercises(day);
  }
  return draft;
}

/// Canonical session sequence; adjacency keeps supersets executable together.
void orderV32Exercises(PlanDayDraft day) {
  const orders = <int, List<String>>{
    1: [
      'Scap pull-up',
      'Muñecas (planche)',
      'Pino pecho a la pared',
      'Dominadas',
      'Remo invertido (mesa)',
      'Elevaciones laterales con banda',
      'Pike push-up',
      'Face pull con banda',
      'Rotación externa con banda',
      'Elevación de piernas colgado',
      'Encogimiento inverso',
      'Vela',
      'Negativo de dragon flag recogido',
      'Negativo de dragon flag a una pierna',
      'Negativo de dragon flag',
      'Dragon flag',
      'Hollow body hold',
      'Sentadilla isométrica en la pared',
      'Abducción de cadera de lado',
      'Nórdico inverso'
    ],
    2: [
      'Flexiones escapulares',
      'Muñecas (planche)',
      'Pino pecho a la pared',
      'Inclinación de planche',
      'Flexión pseudo-planche',
      'Tuck planche',
      'Fondos en barra',
      'Flexión a una mano',
      'Flexiones diamante',
      'Support hold en paralelas',
      'Extensión de tríceps sobre la cabeza con banda',
      'Curl con banda',
      'Copenhague',
      'Tibial en la pared',
      'Colgarse de la barra',
      'Intervalos 15/15'
    ],
    3: [
      'Calentamiento tipo FIFA 11+',
      'Aterrizaje clavado',
      'Sprint lanzado',
      'Aceleración 10–20 m',
      'Salto vertical',
      'Salto largo',
      'Salto de patinador',
      'Sentadilla búlgara',
      'Peso muerto a una pierna con mochila',
      'Nórdico (isquios)',
      'Gemelos a una pierna en escalón',
      'Sóleo sentado con mochila',
      'Carga de maleta con mochila',
      'Carga abrazada al pecho',
      'Pallof press con banda'
    ],
    4: [
      'Scap pull-up',
      'Muñecas (planche)',
      'Elevaciones en pike sentado',
      'Elevaciones en straddle',
      'L-sit',
      'Tuck-up',
      'V-up a una pierna',
      'V-up',
      'V-up con bajada lenta',
      'Hollow body hold',
      'Mesa invertida',
      'Plancha inversa sobre antebrazos',
      'Plancha inversa sobre las manos',
      'Plancha inversa a una pierna',
      'Plancha inversa con patada',
      'Plancha inversa con pies elevados',
      'Progresión de pistol',
      'Dominadas',
      'Flexiones con pies elevados',
      'Remo invertido (mesa)',
      'Elevaciones laterales con banda',
      'Rotación externa con banda',
      'Y-T prono',
      'Copenhague',
      'Support hold en paralelas',
      'Bajada lateral del escalón',
      'Sentadilla isométrica en la pared',
      'Abducción de cadera de lado'
    ],
    5: [
      'Muñecas (planche)',
      'Pino pecho a la pared',
      'Inclinación de planche',
      'Flexión pseudo-planche',
      'Tuck planche',
      'Dominadas',
      'Flexiones',
      'Sentadillas',
      'Hollow rocks',
      'Mesa invertida',
      'Plancha inversa sobre antebrazos',
      'Plancha inversa sobre las manos',
      'Plancha inversa a una pierna',
      'Plancha inversa con patada',
      'Plancha inversa con pies elevados',
      'Sóleo sentado con mochila',
      'Tibial en la pared'
    ],
  };
  final order = orders[day.weekday];
  if (order == null) return;
  final original = {...day.exercises.asMap().map((i, e) => MapEntry(e, i))};
  int rank(PlanExerciseDraft e) {
    final at = order.indexOf(e.name);
    return at < 0 ? order.length : at;
  }

  day.exercises.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank == 0 ? original[a]!.compareTo(original[b]!) : byRank;
  });
}
