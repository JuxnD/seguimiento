import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/reminder_scheduler.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/recovery_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/reminders.dart';

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 009, R2: lo guardado en SQLite llega por los providers a la
/// programación real del aviso de pasos. Nada de llamar `planReminders` a
/// mano con un bool: el aviso se programa o se retira solo.
class _Sink implements NotificationSink {
  List<PlannedNotification> last = const [];
  int runs = 0;

  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async {
    last = planned;
    runs++;
  }
}

/// El reloj de la app, fijo para la prueba.
class _Pinned extends ReminderScheduler {
  _Pinned(AppDatabase db, PlanRepository plan, NotificationSink sink, this.now)
      : super(
          db: db,
          plan: plan,
          reminders: ReminderRepository(db),
          nutrition: NutritionRepository(db),
          body: BodyRepository(db),
          profile: ProfileRepository(db),
          service: sink,
        );

  DateTime now;

  @override
  Future<List<PlannedNotification>> reschedule({int horizonDays = 7, DateTime? now}) =>
      super.reschedule(horizonDays: 1, now: this.now);
}

void main() {
  setUpAll(useHostSqlite);

  late AppDatabase db;
  late _Sink sink;
  late _Pinned scheduler;
  late ProviderContainer container;

  final monday = DateTime(2026, 11, 2);

  setUp(() async {
    db = openInMemoryDatabase();
    // Avisos sólo con alta confirmada (plan 022): es la base del dueño.
    await asExistingUser(db, goals: false);
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    await ReminderRepository(db).ensureDefaults();
    await db.delete(db.goalVersions).go();
    await db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
        metric: GoalMetric.pasos.name,
        value: const Value(5000),
        effectiveFrom: const Value('2026-09-01'),
        acceptedAt: '2026-09-01',
        origin: GoalOrigin.inicio));
    sink = _Sink();
    scheduler = _Pinned(db, plan, sink, DateTime(2026, 11, 2, 9));
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      reminderSchedulerProvider.overrideWithValue(scheduler),
    ]);
    container.listen(reminderSyncProvider, (_, __) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  PlannedNotification? steps() => sink.last.where((n) => n.kind == ReminderKind.pasos).firstOrNull;

  /// Espera (tiempo real) a que la programación llegue a lo esperado.
  Future<void> until(bool Function() ok, String what) async {
    for (var i = 0; i < 250; i++) {
      if (sink.runs > 0 && ok()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('no llegó: $what (último: ${steps()?.title ?? 'sin aviso de pasos'})');
  }

  test('al despertar: guardar "cansado" retira el aviso; editar a "normal" o borrar lo vuelve a programar', () async {
    final recovery = RecoveryRepository(db);
    await until(() => steps()?.title == 'Pasos: sin anotar hoy', 'aviso inicial');

    await recovery.setFeeling(monday, 3);
    await until(() => steps() == null, 'retiro al guardar cansado');

    await recovery.setFeeling(monday, 2);
    await until(() => steps() != null, 'vuelve al editar a normal');

    await recovery.setFeeling(monday, 3);
    await until(() => steps() == null, 'retiro otra vez');
    await recovery.setFeeling(monday, null);
    await until(() => steps() != null, 'vuelve al borrar la declaración');
  });

  test('recoveryOk=false al cerrar la sesión retira el aviso; corregirla o borrarla lo devuelve', () async {
    final training = TrainingRepository(db, ExerciseRepository(db));
    await until(() => steps() != null, 'aviso inicial');
    final id = await training.save(SessionDraft(
      date: monday,
      type: SessionType.progresion,
      totalSec: 1200,
      roundsDone: 6,
      rpe: 7,
      recoveryOk: false,
    ));
    await until(() => steps() == null, 'retiro con recoveryOk=false y RPE 7');
    // Hoy (y su línea de caminatas) lee lo mismo: recuperación primero, con la señal.
    final plan = PlanRepository(db, ExerciseRepository(db));
    final dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    var coach = (await dashboard.today(now: monday)).coach!;
    expect((coach.recoveryFirst, coach.action), (true, 'Pasos suaves, en llano. Sin caminata extra por la meta.'));
    expect(coach.evidence, ['declaraste que no te recuperaste bien en los últimos 3 días']);

    await (db.update(db.sessions)..where((t) => t.id.equals(id))).write(const SessionsCompanion(recoveryOk: Value(true)));
    await until(() => steps() != null, 'vuelve con recoveryOk=true');
    coach = (await dashboard.today(now: monday)).coach!;
    expect(coach.recoveryFirst, isFalse, reason: 'recuperación favorable: las caminatas vuelven a contarse');

    await (db.update(db.sessions)..where((t) => t.id.equals(id))).write(const SessionsCompanion(recoveryOk: Value(false)));
    await until(() => steps() == null, 'retiro otra vez');
    await (db.delete(db.sessions)..where((t) => t.id.equals(id))).go();
    await until(() => steps() != null, 'vuelve al borrar la sesión');
  });

  test('una meta futura no cambia el aviso de hoy; cuando rige, el aviso usa la nueva', () async {
    final stepsRepo = StepsRepository(db);
    await stepsRepo.setSteps(monday, 1500);
    await until(() => steps()?.body.startsWith('Faltan 3.500 para 5.000.') ?? false, 'aviso con la meta vigente');

    await GoalRepository(db).scheduleGoal(GoalMetric.pasos, 1000,
        effectiveFrom: DateTime(2026, 11, 3), origin: GoalOrigin.perfil, now: monday);
    final before = sink.runs;
    await until(() => sink.runs > before, 'reprogramación al guardar la meta futura');
    expect(steps()!.body, startsWith('Faltan 3.500 para 5.000.'), reason: 'mañana no rige hoy');

    // Martes: la meta de 1.000 ya rige y 1.500 la cumplen.
    scheduler.now = DateTime(2026, 11, 3, 9);
    await stepsRepo.setSteps(DateTime(2026, 11, 3), 1500);
    await until(() => steps() == null, 'meta cumplida: sin aviso');
    expect((await ProfileRepository(db).get()).stepsTarget, 1000);
  });
}
