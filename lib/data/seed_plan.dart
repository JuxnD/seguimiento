import 'package:drift/drift.dart';

import '../domain/enums.dart';
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

/// Siembra plan y metas la primera vez. Idempotente: si ya hay una versión de
/// plan, no toca nada (las versiones posteriores son del usuario).
Future<bool> seedIfEmpty(AppDatabase db, PlanRepository plan) async {
  final existing = await plan.versions();
  if (existing.isNotEmpty) return false;

  await plan.saveAsNewVersion(planV1());
  await plan.saveAsNewVersion(planV2());
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

