import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/adaptive_coach.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/goal_history.dart';

import '../support/sqlite_host.dart';

/// Plan 009: metas versionadas y propuestas sobre SQLite.
void main() {
  late AppDatabase db;
  late GoalRepository goals;

  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);

  setUp(() {
    db = openInMemoryDatabase();
    goals = GoalRepository(db);
  });

  tearDown(() => db.close());

  test('instalación nueva: base de 5.000 conocida desde hoy', () async {
    final h = await goals.history();
    final steps = h.current(GoalMetric.pasos, DateTime.now())!;
    expect((steps.value, steps.origin, steps.legacy), (5000.0, GoalOrigin.inicio, false));
    expect(h.on(GoalMetric.pasos, dateOnly(DateTime.now()))!.known, isTrue);
  });

  test('guardar el perfil crea una vigencia sólo para lo que cambió', () async {
    final before = (await goals.history()).versions.length;
    await goals.updateProfile(const ProfilesCompanion(stepsTarget: Value(6000), heightCm: Value(175)),
        origin: GoalOrigin.perfil, now: d(10, 20));
    final h = await goals.history();
    expect(h.versions.length, before + 1, reason: 'la estatura no es una meta');
    expect(h.on(GoalMetric.pasos, d(10, 19))!.value, 5000, reason: 'el día anterior se mide con la de antes');
    expect(h.on(GoalMetric.pasos, d(10, 20))!.value, 6000);
    await goals.updateProfile(const ProfilesCompanion(stepsTarget: Value(6000)), origin: GoalOrigin.perfil, now: d(10, 21));
    expect((await goals.history()).versions.length, before + 1, reason: 'guardar sin cambios no crea vigencias');
  });

  test('ProfileRepository.save pasa por la historia', () async {
    await ProfileRepository(db).save(const ProfilesCompanion(proteinMin: Value(140)));
    final h = await goals.history();
    expect(h.current(GoalMetric.proteinaMin, DateTime.now())!.value, 140);
    expect(h.current(GoalMetric.proteinaMin, DateTime.now())!.origin, GoalOrigin.perfil);
  });

  test('activar el v3.1 deja sus metas con vigencia de plan', () async {
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, d(10, 12));
    final kcal = (await goals.history()).current(GoalMetric.kcal, DateTime.now())!;
    expect((kcal.value, kcal.origin), (v31KcalWeekday.toDouble(), GoalOrigin.plan));
  });

  test('aceptar una propuesta rige desde mañana, una sola vez aunque se acepte dos veces', () async {
    const p = StepsProposal(from: 5000, to: 6000, average: 6490, daysAtGoal: 10);
    await goals.decideSteps(p, ProposalStatus.aceptada, today: d(11, 2), acceptedValue: 5800);
    await goals.decideSteps(p, ProposalStatus.aceptada, today: d(11, 2), acceptedValue: 5800);
    final h = await goals.history();
    expect(h.on(GoalMetric.pasos, d(11, 2))!.value, 5000, reason: 'hoy se mide con la de antes');
    final next = h.on(GoalMetric.pasos, d(11, 3))!;
    expect((next.value, next.since), (5800, d(11, 3)), reason: 'la cifra editada por la persona');
    expect(h.of(GoalMetric.pasos).where((v) => v.origin == GoalOrigin.propuesta), hasLength(1));
    final record = (await goals.proposal(p.id))!;
    expect(record.status, ProposalStatus.aceptada);
    final profile = await ProfileRepository(db).get();
    expect(profile.stepsTarget, 5800);
  });

  test('posponer guarda la fecha de revisión; rechazar persiste', () async {
    const p = StepsProposal(from: 5000, to: 6000, average: 6490, daysAtGoal: 10);
    await goals.decideSteps(p, ProposalStatus.pospuesta, today: d(11, 2));
    expect((await goals.lastProposal('pasos'))!.reviewAfter, d(11, 9));
    await goals.decideSteps(p, ProposalStatus.rechazada, today: d(11, 9));
    final r = (await goals.lastProposal('pasos'))!;
    expect((r.status, r.reviewAfter), (ProposalStatus.rechazada, null));
    expect((await ProfileRepository(db).get()).stepsTarget, 5000, reason: 'rechazar no toca la meta');
  });
}
