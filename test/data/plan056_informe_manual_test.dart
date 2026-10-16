import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/manual_export.dart';
import 'package:seguimiento/data/repositories/equipment_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/readiness_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/equipment.dart';
import 'package:seguimiento/domain/report/report_builder.dart'
    show isDistanceExercise;
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 056: segunda tanda de §16.29/§16.30 y «Exportar manual» (§16.28.4 B).
/// Bloque v3.1 desde el lun 12 oct 2026, sin datos personales.
void main() {
  setUpAll(useHostSqlite);
  final mon = DateTime(2026, 10, 12);
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;

  setUp(() async {
    db = openInMemoryDatabase();
    await asExistingUser(db, since: mon);
    plan = PlanRepository(db, ExerciseRepository(db));
    training = TrainingRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, mon, now: mon);
  });
  tearDown(() => db.close());

  test('recuperación aceptada: 30 min de movilidad terminada cuentan (§16.29.3)',
      () async {
    final readiness = ReadinessRepository(db);
    final day = DateTime(2026, 10, 12);
    expect(await readiness.recoveryAccepted(day), isFalse);
    await db.into(db.sessions).insert(SessionsCompanion.insert(
        date: dayKey(day),
        type: SessionType.movilidad,
        totalSec: const Value(60 * 60)));
    expect(await readiness.recoveryAccepted(day), isTrue);
    expect(await readiness.recoveryDone(day), isFalse,
        reason: 'Hoy sigue pidiendo la recuperación activa completa');
  });

  test('nórdico sin anclaje: curl femoral deslizando; con anclaje, el nórdico',
      () async {
    Future<PlanExerciseDraft> nordic() async {
      final wed = DateTime(2026, 10, 14);
      final view = (await plan.dayFor(wed))!;
      final applied = await training.withV31BlocksChecked(
          view.day, wed, await training.blockDay(view, wed),
          planche: false);
      return applied.day.exercises
          .singleWhere((e) => e.name == 'Nórdico (isquios)');
    }

    expect((await nordic()).notes ?? '', isNot(contains('Sin anclaje')),
        reason: 'por omisión hay anclaje');
    await EquipmentRepository(db)
        .set(EquipmentKeys.anchor, EquipmentStatus.noTengo);
    expect((await nordic()).notes, contains('curl femoral deslizando'));
  });

  test('el informe mide las cargas en metros', () {
    expect(isDistanceExercise('Carga de maleta con mochila'), isTrue);
    expect(isDistanceExercise('Sentadilla búlgara'), isFalse);
  });

  test('«Exportar manual» sale de los datos: versión, días, tests y metas',
      () async {
    await ReminderRepository(db).ensureDefaults();
    final text = await buildAppManual(db,
        appVersion: '1.28.1', now: DateTime(2026, 10, 19));
    expect(text, contains('# Manual de My Prime 1.28.1'));
    expect(text, contains('semana 2 de 9'));
    expect(text, contains('## 2. Próximos 14 días'));
    expect(text, contains('Sentadilla búlgara'));
    expect(text, contains('Test 2 de torso: lun 2026-11-16'));
    expect(text, contains('Test 3 de torso: lun 2026-12-07'));
    expect(text, contains('Grasa: 60–75 g'));
    expect(text, contains('Víspera de un test: 20:00'));
  });
}
