import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/reminder_scheduler.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

class _Sink implements NotificationSink {
  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async {}
}

/// Plan 053: «rodar la programación un día» (pedido del owner el 15 oct,
/// tras una semana en la que hizo el torso el martes y la app no sabía que
/// todo iba un día corrido).
void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12), tue = DateTime(2026, 10, 13);
  final wed = DateTime(2026, 10, 14), thu = DateTime(2026, 10, 15);
  final fri = DateTime(2026, 10, 16), sat = DateTime(2026, 10, 17);
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late DashboardRepository dashboard;

  setUp(() async {
    db = openInMemoryDatabase();
    await asExistingUser(db, since: mon);
    plan = PlanRepository(db, ExerciseRepository(db));
    training = TrainingRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, mon);
    dashboard = DashboardRepository(
        db, plan, NutritionRepository(db), ProfileRepository(db));
  });
  tearDown(() => db.close());

  Future<List<String>> composed(DateTime d) async {
    final view = await plan.dayFor(d);
    final day = await training.withV31Blocks(
        view!.day, d, await training.blockDay(view, d),
        planche: true);
    return [for (final e in day.exercises) e.name];
  }

  Future<List<PlannedNotification>> notices() async {
    await ReminderRepository(db).ensureDefaults();
    return ReminderScheduler(
            db: db,
            plan: plan,
            reminders: ReminderRepository(db),
            nutrition: NutritionRepository(db),
            body: BodyRepository(db),
            profile: ProfileRepository(db),
            service: _Sink())
        .reschedule(now: DateTime(2026, 10, 12, 6), horizonDays: 5);
  }

  test('rodar el lunes: torso el martes, piernas con su test el jueves', () async {
    final nominal = {
      for (final d in [mon, tue, wed, thu]) d: (await plan.dayFor(d))!.day.type
    };
    final mondayBlocks = await composed(mon);
    expect(await plan.droppedIfRolled(mon), [fri]);
    expect(await plan.rollDay(mon), isTrue);

    final monday = (await plan.dayFor(mon))!;
    expect((monday.vacated, monday.day.type, monday.vacatedFor),
        (true, DayType.descanso, tue));
    expect(monday.day.notes, contains('pasa al'));
    for (final (real, from) in [(tue, mon), (wed, tue), (thu, wed)]) {
      final view = (await plan.dayFor(real))!;
      expect((view.nominalDate, view.day.type), (from, nominal[from]),
          reason: '$real muestra $from');
    }
    expect((await plan.dayFor(fri))!.nominalDate, thu);
    expect((await plan.dayFor(sat))!.day.type, DayType.futbol,
        reason: 'el partido no se mueve');

    // El martes se arma como lunes (bloques de su día, muñecas del lunes).
    expect(await composed(tue), mondayBlocks);

    // Hoy, la agenda y los recordatorios leen la misma semana corrida.
    expect((await dashboard.today(now: tue)).fitnessTest?.part, TestPart.torso);
    expect((await dashboard.today(now: wed)).fitnessTest, isNull);
    final thursday = (await dashboard.today(now: thu)).fitnessTest!;
    expect((thursday.part, thursday.done), (TestPart.piernas, false));
    final legs = (await ReadinessRepository(db).testAgenda(
            scheme: 'v3.1',
            blockStart: mon,
            protocol: TestProtocolId.v31_12,
            gates: false))
        .singleWhere((t) => t.round == 1 && t.part == TestPart.piernas);
    expect((legs.planned, legs.date, legs.moves), (thu, thu, 0),
        reason: 'rodar no cuenta como mover el test');
    final sessions = (await notices())
        .where((n) => n.kind == ReminderKind.sesion)
        .toList();
    expect(sessions.where((n) => n.when.day == 12), isEmpty,
        reason: 'el lunes quedó libre');
    expect(sessions.singleWhere((n) => n.when.day == 15).title,
        contains('Test 1 de piernas'));
  });

  test('deshacer devuelve la semana nominal', () async {
    await plan.rollDay(mon);
    expect(await plan.undoRoll(mon), isTrue);
    expect((await plan.dayFor(tue))!.nominalDate, isNull);
    expect((await dashboard.today(now: wed)).fitnessTest?.part,
        TestPart.piernas);
    expect(await plan.undoRoll(mon), isFalse);
  });

  test('rodar dos veces corre dos días; el fútbol no se rueda', () async {
    expect(await plan.rollDay(sat), isFalse);
    expect(await plan.rollDay(mon), isTrue);
    expect(await plan.rollDay(mon), isFalse, reason: 'el lunes ya está libre');
    expect(await plan.rollDay(tue), isTrue);
    expect((await plan.dayFor(wed))!.nominalDate, mon);
    expect((await plan.dayFor(fri))!.nominalDate, wed);
    expect((await dashboard.today(now: fri)).fitnessTest?.part,
        TestPart.piernas);
  });

  test('la última vez de un ejercicio se busca por el contenido, no por la fecha',
      () async {
    // Semana anterior: lunes tirón (dominadas con mochila 8 kg) y martes con
    // dominadas a peso corporal; esta semana se rueda el lunes.
    final lastMon = addDays(mon, -7), lastTue = addDays(mon, -6);
    for (final (date, kg) in [(lastMon, 8.0), (lastTue, null)]) {
      await training.save(SessionDraft(
          date: date,
          type: SessionType.trenSuperior,
          totalSec: 1800,
          planDayId: (await plan.dayFor(date))!.dayId,
          sets: [SetDraft(exercise: 'Dominadas', reps: 6, loadKg: kg)]));
    }
    await plan.rollDay(mon);
    final last = await training.lastStrengthSets('Dominadas', tue);
    expect(last.single.loadKg, 8.0,
        reason: 'el martes hace lo del lunes: compara con el lunes');
  });

  test('la semana siguiente vuelve a lo normal', () async {
    await plan.rollDay(mon);
    final next = addDays(mon, 7);
    expect((await plan.dayFor(next))!.nominalDate, isNull);
    expect((await plan.dayFor(next))!.vacated, isFalse);
  });
}
