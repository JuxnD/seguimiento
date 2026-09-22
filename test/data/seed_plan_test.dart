import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);

  late AppDatabase db;
  late PlanRepository plan;

  setUp(() async {
    db = openInMemoryDatabase();
    plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
  });

  tearDown(() => db.close());

  test('siembra las dos versiones y el perfil', () async {
    expect((await plan.versions()).length, 2);
    final profile = await ProfileRepository(db).get();
    expect(profile.startDate, '2026-08-26');
    expect(profile.nextMeasurementDate, '2026-10-02');
    expect(profile.cooldownTargetSec, 180);
    expect(profile.measureIntervalDays, 21);
    expect(profile.measureIntervalMaxDays, 28);
    expect(profile.neverToFailure, isTrue);
  });

  test('v1 rige hasta el 27 sep y v2 desde el 28', () async {
    final versions = await plan.versions();
    expect((await plan.activeVersion(DateTime(2026, 9, 25)))!.id, versions.first.id);
    expect((await plan.activeVersion(DateTime(2026, 9, 27)))!.id, versions.first.id);
    expect((await plan.activeVersion(DateTime(2026, 9, 28)))!.id, versions.last.id);
  });

  test('v1: la semana queda como el plan real', () async {
    final v1 = await plan.load((await plan.versions()).first.id);
    expect(v1.days.map((d) => d.type), [
      DayType.circuito,
      DayType.bloques,
      DayType.circuitoLigero,
      DayType.bloques,
      DayType.progresion,
      DayType.futbol,
      DayType.futbol,
    ]);
    expect(v1.days[0].targetRounds, 6);
    expect(v1.days[2].targetRounds, 5);
    expect(v1.days[4].targetRounds, 8);
    expect(v1.days[0].restBetweenRoundsSec, 30);

    // Ronda del circuito: 5 dominadas prona + 10 flexiones + 15 sentadillas.
    expect(v1.days[0].main.map((e) => '${e.name} ${e.repsMin}'), ['Dominadas 5', 'Flexiones 10', 'Sentadillas 15']);
    expect(v1.days[0].main.first.grip, 'prona');

    // Martes: dominadas 4×6–8 con descanso 90–120 s.
    final martes = v1.days[1].main;
    expect(martes.first.targetLabel, '4×6–8 · desc. 1:30–2:00 · prona');
    expect(v1.days[3].main.first.grip, 'supina');
    expect(v1.days[1].blocks, isEmpty);
  });

  test('v2: añade los bloques y protege jueves y viernes', () async {
    final v2 = await plan.load((await plan.versions()).last.id);

    final core = v2.days[0].blocks['core']!;
    expect(core.map((e) => '${e.variant}:${e.name}'), [
      'A:Elevación de piernas colgado',
      'A:Hollow body hold',
      'B:Elevación de piernas colgado',
      'B:Plancha lateral',
    ]);
    expect(core[1].targetLabel, '2×20–40s');
    expect(core[3].targetLabel, '2×30–45s · por lado');

    final cuadriceps = v2.days[1].blocks['cuádriceps']!.single;
    expect(cuadriceps.name, 'Sentadilla búlgara');
    expect(cuadriceps.targetLabel, '3×8–12 · por lado · RIR 1–2');
    expect(cuadriceps.notes, contains('añadir carga'));

    final hombro = v2.days[2].blocks['hombro']!.single;
    expect(hombro.name, 'Pike push-up');
    expect(hombro.targetLabel, '3×6–8 · RIR 2–3');

    expect(v2.days[3].blocks, isEmpty);
    expect(v2.days[4].blocks, isEmpty);
    expect(v2.days[3].notes, contains('Protegido'));

    // El trabajo principal sigue siendo el de v1.
    expect(v2.days[0].main.length, 3);
  });

  test('sembrar es idempotente: no duplica el plan', () async {
    expect(await seedIfEmpty(db, plan), isFalse);
    expect((await plan.versions()).length, 2);
  });
}
