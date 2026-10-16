import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/sleep_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/readiness.dart';

import '../support/sqlite_host.dart';

/// Recuperación activa sobre la base (§19.17). Fechas ficticias: sáb 2, dom 3
/// y lun 4 de marzo de 2030.
void main() {
  late AppDatabase db;
  late TrainingRepository training;
  late RecoveryRepository recovery;
  late ReadinessRepository repo;

  final sat = DateTime(2030, 3, 2);
  final sun = DateTime(2030, 3, 3);
  final mon = DateTime(2030, 3, 4);

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    training = TrainingRepository(db, exercises);
    recovery = RecoveryRepository(db);
    repo = ReadinessRepository(db);
  });

  tearDown(() => db.close());

  Future<void> game(DateTime d, int minutes, int intensity,
          {bool imported = false}) =>
      db.into(db.footballGames).insert(FootballGamesCompanion.insert(
          date: dayKey(d),
          minutes: minutes,
          intensity: Value(intensity),
          imported: Value(imported)));

  Future<void> weekend() async {
    await game(sat, 60, 5);
    await game(sun, 90, 7);
    await game(sun, 60, 8);
  }

  Future<void> calmMorning(DateTime d) async {
    await recovery.setReadinessAnswers(d, muscleSoreness: 1, ill: false);
    await SleepRepository(db).set(d, 8);
  }

  test(
      'el fin de semana de tres partidos da amarillo; lo importado, la movilidad y el test no suman',
      () async {
    await weekend();
    await game(sat, 120, 9, imported: true);
    await training.save(SessionDraft(
        date: sun,
        type: SessionType.movilidad,
        mode: recoveryActiveId,
        totalSec: 1800,
        rpe: 4,
        notes: 'Recuperación'));
    await training.save(SessionDraft(
        date: sun,
        type: SessionType.otro,
        mode: 'test',
        totalSec: 3600,
        rpe: 9));
    await calmMorning(mon);

    final a = await repo.readinessOn(mon, testOrAttemptToday: true);
    expect(a.load3Days, 1410);
    expect(a.level, ReadinessLevel.yellow);
    expect(a.reasons, contains('2 partidos entre ayer y hoy'));
    expect(a.moveTestToTomorrow, isTrue);
  });

  group('rodilla en escaleras', () {
    test('sin registro de la mañana: sin dato', () async {
      final a = await repo.readinessOn(mon);
      expect(a.missing, contains('Escaleras: sin dato'));
      expect(a.missing, contains('Dolor muscular: sin dato'));
    });

    test('responder dolor y enfermo no vale como 0 en escaleras', () async {
      await calmMorning(mon);
      await recovery.setSoreness(mon, {});
      final a = await repo.readinessOn(mon);
      expect(a.missing, contains('Escaleras: sin dato'),
          reason: 'el campo propio escaleras sigue sin respuesta');
      expect(a.missing, isNot(contains('Dolor muscular: sin dato')));
      expect(a.level, ReadinessLevel.green);
      expect(a.confident, isFalse);
    });

    test('escaleras 3 explícitas: amarillo y sin hueco de escaleras', () async {
      await calmMorning(mon);
      await recovery.setKneeStairs(mon, 3);
      final a = await repo.readinessOn(mon);
      expect(a.level, ReadinessLevel.yellow);
      expect(a.missing, isNot(contains('Escaleras: sin dato')));
    });

    test('rodilla 5 es rojo; enfermo también', () async {
      await calmMorning(mon);
      await recovery.setSoreness(mon, {'Rodilla': 5});
      expect((await repo.readinessOn(mon)).level, ReadinessLevel.red);
      await recovery.setSoreness(mon, {});
      await recovery.setReadinessAnswers(mon, muscleSoreness: 0, ill: true);
      final ill = await repo.readinessOn(mon);
      expect(ill.level, ReadinessLevel.red);
      expect(ill.action, SuggestedAction.restOnly);
    });
  });

  test('base del pulso: solo lecturas anteriores a hoy, las 14 más recientes',
      () async {
    for (var k = 1; k <= 20; k++) {
      await recovery.setRestingHr(addDays(mon, -k), k <= 14 ? 60 : 90);
    }
    await recovery.setRestingHr(addDays(mon, 1), 99); // mañana: no entra
    await recovery.setRestingHr(mon, 70);
    await calmMorning(mon);
    final a = await repo.readinessOn(mon);
    expect(a.level, ReadinessLevel.red);
    expect(a.reasons.first, 'Pulso en reposo 70: +10 sobre tu base (60)');
  });

  test('responder dolor y enfermo no borra el pulso; borrar todo quita la fila',
      () async {
    await recovery.setRestingHr(mon, 58);
    await recovery.setReadinessAnswers(mon, muscleSoreness: 4, ill: false);
    var row = await recovery.morningOn(mon);
    expect((row!.restingHr, row.muscleSoreness, row.ill), (58, 4, false));
    await recovery.setRestingHr(mon, null);
    row = await recovery.morningOn(mon);
    expect(row, isNotNull, reason: 'queda la respuesta de dolor');
    await recovery.setReadinessAnswers(mon, muscleSoreness: null, ill: null);
    expect(await recovery.morningOn(mon), isNull);
  });

  test(
      '"Entrenar igual" guarda fecha y razones; la aceptación es la sesión guardada',
      () async {
    await weekend();
    await calmMorning(mon);
    final a = await repo.readinessOn(mon);
    expect(await repo.trainedAnyway(mon), isFalse);
    expect(await repo.recoveryDone(mon), isFalse);

    await repo.trainAnyway(mon, a, now: DateTime(2030, 3, 4, 9));
    expect(await repo.trainedAnyway(mon), isTrue);
    final row = await (db.select(db.coachProposals)
          ..where((t) => t.kind.equals(readinessProposalKind)))
        .getSingle();
    expect((row.status, row.createdOn, row.decidedOn),
        ('rechazada', '2030-03-04', '2030-03-04'));
    final evidence = jsonDecode(row.evidence) as Map<String, Object?>;
    expect(evidence['level'], 'yellow');
    expect((evidence['reasons'] as List).first,
        startsWith('Carga de anteayer y ayer: 1.410'));

    // Abrir una rutina no es aceptar: solo cuenta la sesión guardada.
    await training.save(SessionDraft(
        date: mon,
        type: SessionType.movilidad,
        mode: morningActivaId,
        totalSec: 600));
    expect(await repo.recoveryDone(mon), isFalse);
    await training.save(SessionDraft(
        date: mon,
        type: SessionType.movilidad,
        mode: recoveryActiveId,
        totalSec: 1800));
    expect(await repo.recoveryDone(mon), isTrue);
  });

  group('tests movidos', () {
    // Lunes de inicio del v3.1 ficticio: el Test 1 de torso es ese lunes.
    final start = mon;
    final tue = DateTime(2030, 3, 5);
    final wed = DateTime(2030, 3, 6);

    test('se mueve conservando plan, ronda y parte; máximo 2 veces', () async {
      expect(scheduledTest(start, mon), (round: 1, part: TestPart.torso));
      expect(await repo.effectiveScheduledTest(start, mon),
          (round: 1, part: TestPart.torso, moves: 0));

      final to = await repo.moveTest(
          start: start,
          round: 1,
          part: TestPart.torso,
          from: mon,
          reasons: ['Carga alta']);
      expect(to, tue);
      expect(await repo.effectiveScheduledTest(start, mon), isNull,
          reason: 'el lunes ya no tiene test');
      expect(await repo.effectiveScheduledTest(start, tue),
          (round: 1, part: TestPart.torso, moves: 1));
      expect(await repo.currentTestDate(start, 1, TestPart.torso), tue);

      final second = await repo.moveTest(
          start: start,
          round: 1,
          part: TestPart.torso,
          from: tue,
          reasons: ['Sigue']);
      expect(second, wed);
      expect(
          await repo.moveTest(
              start: start,
              round: 1,
              part: TestPart.torso,
              from: wed,
              reasons: ['Otra']),
          isNull,
          reason:
              'la tercera vez toca la versión ligera, no otro aplazamiento');

      final moves = await repo.moves(start, 1, TestPart.torso);
      expect([
        for (final m in moves)
          (dayKey(m.start), dayKey(m.from), dayKey(m.to), m.reasons.join('|'))
      ], [
        ('2030-03-04', '2030-03-04', '2030-03-05', 'Carga alta'),
        ('2030-03-04', '2030-03-05', '2030-03-06', 'Sigue'),
      ]);
      expect(await repo.moves(start, 1, TestPart.piernas), isEmpty,
          reason: 'las piernas no se movieron');
    });

    test(
        'no se mueve desde una fecha que no le toca ni se repite el mismo movimiento',
        () async {
      await expectLater(
          repo.moveTest(
              start: start,
              round: 1,
              part: TestPart.torso,
              from: tue,
              reasons: const []),
          throwsArgumentError,
          reason: 'el martes no le toca: no se mueve una fecha cualquiera');
      await repo.moveTest(
          start: start,
          round: 1,
          part: TestPart.torso,
          from: mon,
          reasons: const []);
      await expectLater(
          repo.moveTest(
              start: start,
              round: 1,
              part: TestPart.torso,
              from: mon,
              reasons: const []),
          throwsArgumentError,
          reason: 'repetir el lunes no gasta el segundo movimiento');
      expect(await repo.moves(start, 1, TestPart.torso), hasLength(1));
    });

    test(
        'los movimientos de un plan no tocan otro plan con la misma ronda y parte',
        () async {
      final otherStart = DateTime(2030, 4, 1); // otro v3.1, también lunes
      await repo.moveTest(
          start: start,
          round: 1,
          part: TestPart.torso,
          from: mon,
          reasons: const []);
      await repo.moveTest(
          start: start,
          round: 1,
          part: TestPart.torso,
          from: tue,
          reasons: const []);
      expect(await repo.moves(otherStart, 1, TestPart.torso), isEmpty);
      expect(await repo.effectiveScheduledTest(otherStart, otherStart),
          (round: 1, part: TestPart.torso, moves: 0));
      expect(
          await repo.effectiveScheduledTest(otherStart, DateTime(2030, 4, 2)),
          isNull);
      // El otro plan tiene sus propios 2 movimientos.
      expect(
          await repo.moveTest(
              start: otherStart,
              round: 1,
              part: TestPart.torso,
              from: otherStart,
              reasons: const []),
          DateTime(2030, 4, 2));
    });
  });

  test('rutinas del día y racha de movilidad', () async {
    await training.save(SessionDraft(
        date: sat,
        type: SessionType.movilidad,
        mode: nightSueltaId,
        totalSec: 600));
    await training.save(SessionDraft(
        date: sun,
        type: SessionType.movilidad,
        mode: morningActivaId,
        totalSec: 600));
    await training.save(SessionDraft(
        date: sun,
        type: SessionType.movilidad,
        mode: nightSueltaId,
        totalSec: 600));
    await training.save(SessionDraft(
        date: sun,
        type: SessionType.movilidad,
        notes: 'Movilidad nocturna',
        totalSec: 600));
    expect(await repo.routinesOn(sun), {morningActivaId, nightSueltaId});
    expect(await repo.mobilityStreak(mon), 2,
        reason: 'hoy sin rutina todavía no rompe');
    expect(await repo.mobilityStreak(DateTime(2030, 3, 6)), 0);
  });

  test('aviso de la noche con la carga de ayer y hoy', () async {
    await weekend();
    expect(await repo.eveningNotice(sun),
        contains('Mañana probablemente toca recuperación activa'));
    expect(await repo.eveningNotice(DateTime(2030, 3, 8)), isNull);
  });

  test('semana del informe: propuestos, aceptados y entrenó igual', () async {
    await weekend();
    await calmMorning(mon);
    final a = await repo.readinessOn(mon);
    await repo.trainAnyway(sun, a);
    await training.save(SessionDraft(
        date: mon,
        type: SessionType.movilidad,
        mode: recoveryActiveId,
        totalSec: 1800));
    final w = await repo.week(DateTime(2030, 2, 26), mon);
    expect(w.maxLoad3Days, 1410);
    expect(w.proposed, greaterThanOrEqualTo(2),
        reason: 'domingo y lunes pasan de 900 en 3 días');
    expect(w.accepted, 1);
    expect(w.trainedAnyway, 1);
    final lines = readinessReportLines(w);
    expect(
        lines.first,
        startsWith(
            'Días de recuperación propuestos: ${w.proposed} · aceptados: 1 · entrenó igual: 1'));
    expect(lines[1], startsWith('Carga máxima de 3 días: 1.410'));
  });

  group('racha de constancia', () {
    late DashboardRepository dashboard;

    setUp(() async {
      final exercises = ExerciseRepository(db);
      final plan = PlanRepository(db, exercises);
      dashboard = DashboardRepository(
          db, plan, NutritionRepository(db), ProfileRepository(db));
      await seedIfEmpty(db, plan);
    });

    test('Activa, Suelta y recuperación guardadas mantienen la racha de actividad',
        () async {
      final today = dateOnly(DateTime.now());
      await training.save(SessionDraft(
          date: today,
          type: SessionType.movilidad,
          mode: morningActivaId,
          totalSec: 600));
      await training.save(SessionDraft(
          date: today,
          type: SessionType.movilidad,
          mode: nightSueltaId,
          totalSec: 600));
      expect((await dashboard.today(now: today)).streak, 1);
      await training.save(SessionDraft(
          date: today,
          type: SessionType.movilidad,
          mode: recoveryActiveId,
          totalSec: 1800));
      expect((await dashboard.today(now: today)).streak, 1);
    });
  });
}
