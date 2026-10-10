import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/coach_repository.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/adaptive_coach.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/domain/report/period_summary.dart';

import '../support/sqlite_host.dart';

/// Plan 009 sobre la base: lectura de Hoy, avisos e informe con la misma
/// evidencia.
void main() {
  late AppDatabase db;
  late CoachRepository coach;
  late StepsRepository steps;

  DateTime d(int month, int day) => DateTime(2026, month, day);
  final today = d(11, 2);

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    coach = CoachRepository(db);
    steps = StepsRepository(db);
    // Meta conocida de 5.000 desde mucho antes de la ventana.
    await db.delete(db.goalVersions).go();
    await db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
        metric: GoalMetric.pasos.name,
        value: const Value(5000),
        effectiveFrom: const Value('2026-09-01'),
        acceptedAt: '2026-09-01',
        origin: GoalOrigin.inicio));
  });

  tearDown(() => db.close());

  Future<void> fill(int Function(int i) value, {bool rested = true}) async {
    final w = coachWindow(today);
    for (var i = 0; i < w.length; i++) {
      await steps.setSteps(w[i], value(i));
    }
    // Una señal conocida de recuperación favorable (ayer, al despertar).
    if (rested) await RecoveryRepository(db).setFeeling(addDays(today, -1), 2);
  }

  test('pasos holgados: propone; aceptar desde Hoy rige mañana y Hoy cambia a "en prueba"', () async {
    await fill((i) => 6400 + i * 20);
    final r = await coach.stepsReading(today);
    expect(r.state, CoachState.propuesta);
    await GoalRepository(db).decideSteps(r.proposal!, ProposalStatus.aceptada, today: today);
    expect((await ProfileRepository(db).get()).stepsTarget, 5000);
    final same = await coach.stepsReading(today);
    expect((same.state, same.proposal), (CoachState.aceptada, null),
        reason: 'hoy todavía rige 5.000, pero la propuesta ya se decidió: no se repite');
    final tomorrow = await coach.stepsReading(addDays(today, 1));
    expect((tomorrow.state, tomorrow.nextReview), (CoachState.aceptada, addDays(today, 15)));
  });

  test('"cansado" al despertar o RPE 9: recuperación primero en Hoy y sin aviso de pasos', () async {
    await fill((i) => 6400 + i * 20);
    await RecoveryRepository(db).setFeeling(today, 3);
    expect((await coach.stepsReading(today)).state, CoachState.recuperacion);
    await RecoveryRepository(db).setFeeling(today, null);
    expect((await coach.stepsReading(today)).state, CoachState.propuesta, reason: 'sin respuesta no es fatiga');

    final training = TrainingRepository(db, ExerciseRepository(db));
    await training.save(SessionDraft(date: addDays(today, -1), type: SessionType.progresion, roundsDone: 10, rpe: 9));
    final r = await coach.stepsReading(today);
    expect(r.recoveryFirst, isTrue);

    final planned = planReminders(ReminderContext(
      now: DateTime(2026, 11, 2, 8),
      days: [ReminderDay(date: today, type: DayType.descanso)],
      settings: {ReminderKind.pasos: const ReminderSetting(kind: ReminderKind.pasos, enabled: true, hour: 18, threshold: 4000)},
      stepsRecoveryFirst: r.recoveryFirst,
    ));
    expect(planned.where((n) => n.kind == ReminderKind.pasos), isEmpty, reason: 'el aviso lee la misma decisión que Hoy');
  });

  test('el pulso del registro de la mañana no borra cómo amaneció, y al revés', () async {
    final rec = RecoveryRepository(db);
    await rec.setFeeling(today, 2);
    await rec.setRestingHr(today, 58);
    await rec.setRestingHr(today, null);
    expect(await rec.feelingOn(today), 2);
    await rec.setFeeling(today, null);
    expect(await db.select(db.morningChecks).get(), isEmpty);
  });

  test('Hoy trae la lectura del acompañamiento', () async {
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    final dash = await DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db)).today(now: today);
    expect(dash.coach, isNotNull);
    expect(dash.coach!.state, CoachState.faltanDatos, reason: 'sin pasos registrados');
  });

  test('informe: cada día con su meta; lo anterior a toda vigencia no se clasifica', () async {
    await db.delete(db.goalVersions).go();
    await seedGoalVersions(db, effectiveFrom: null, origin: GoalOrigin.legado, now: d(10, 13));
    await GoalRepository(db).updateProfile(const ProfilesCompanion(stepsTarget: Value(6000)),
        origin: GoalOrigin.perfil, now: d(10, 14));
    await steps.setSteps(d(10, 12), 5500); // lunes, antes de la migración: sin meta registrada
    await steps.setSteps(d(10, 14), 6100); // miércoles, con 6.000: cumple
    await steps.setSteps(d(10, 15), 5500); // jueves, con 6.000: no cumple
    final input = await ReportRepository(db, NutritionRepository(db)).load(d(10, 12), d(10, 18), today: d(10, 20));
    final s = summarizePeriod(input);
    expect((s.weekdaysAtGoal, s.weekdaysGoalUnknown, s.weekdaysWithSteps), (1, 1, 3));
  });

  test('borrar los pasos que sostenían la propuesta la retira con su razón', () async {
    await fill((i) => 6400 + i * 20);
    expect((await coach.stepsReading(today)).state, CoachState.propuesta);
    final w = coachWindow(today);
    for (final day in w.take(3)) {
      await steps.clear(day);
    }
    final r = await coach.stepsReading(today);
    expect((r.state, r.proposal), (CoachState.faltanDatos, null));
    expect(r.reason, contains('7 de 10'));
  });
}

