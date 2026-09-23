import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/reminder_scheduler.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/reminders.dart';

import '../support/sqlite_host.dart';

/// Recibe lo programado sin tocar el sistema de notificaciones.
class _FakeSink implements NotificationSink {
  List<PlannedNotification> last = [];

  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async => last = planned;
}

void main() {
  setUpAll(useHostSqlite);

  late AppDatabase db;
  late ReminderScheduler scheduler;
  late _FakeSink sink;
  late NutritionRepository nutrition;
  late TrainingRepository training;

  // Lunes de circuito según el plan sembrado.
  final lunes = DateTime(2026, 9, 28, 9);

  setUp(() async {
    db = openInMemoryDatabase();
    final exercises = ExerciseRepository(db);
    final plan = PlanRepository(db, exercises);
    nutrition = NutritionRepository(db);
    training = TrainingRepository(db, exercises);
    await seedIfEmpty(db, plan);
    await seedFoodsIfEmpty(db);
    final reminders = ReminderRepository(db);
    await reminders.ensureDefaults();
    sink = _FakeSink();
    scheduler = ReminderScheduler(
      db: db,
      plan: plan,
      reminders: reminders,
      nutrition: nutrition,
      body: BodyRepository(db),
      profile: ProfileRepository(db),
      service: sink,
    );
  });

  tearDown(() => db.close());

  Future<List<PlannedNotification>> run({DateTime? now, int days = 1}) =>
      scheduler.reschedule(now: now ?? lunes, horizonDays: days);

  PlannedNotification? of(List<PlannedNotification> list, ReminderKind kind) =>
      list.where((n) => n.kind == kind).firstOrNull;

  test('el aviso de sesión dice lo que toca ese día', () async {
    final planned = await run();
    final sesion = of(planned, ReminderKind.sesion)!;
    expect(sesion.when, DateTime(2026, 9, 28, 14, 45), reason: '15 min antes de las 3 p. m.');
    expect(sesion.title, 'En 15 min: Circuito');
    expect(sesion.body, contains('6 rondas'));
    expect(sesion.body, contains('Dominadas'));
  });

  test('un martes de bloques nombra los ejercicios del bloque', () async {
    final planned = await run(now: DateTime(2026, 9, 29, 9));
    final sesion = of(planned, ReminderKind.sesion)!;
    expect(sesion.title, 'En 15 min: Bloques');
    expect(sesion.body, contains('Dominadas 4×6–8'));
  });

  test('registrar la sesión calla los avisos de ese día', () async {
    expect(of(await run(), ReminderKind.sesion), isNotNull);
    await training.save(SessionDraft(date: DateTime(2026, 9, 28), type: SessionType.circuito));

    final planned = await run();
    expect(of(planned, ReminderKind.sesion), isNull);
    expect(of(planned, ReminderKind.sesionSinRegistrar), isNull);
  });

  test('el aviso de proteína usa lo comido hoy', () async {
    final cena = (await nutrition.templates()).firstWhere((t) => t.name.startsWith('Cena base'));
    await nutrition.logTemplate(cena, DateTime(2026, 9, 28)); // 43 g

    final proteina = of(await run(), ReminderKind.proteina)!;
    expect(proteina.title, 'Proteína: 43 g');
    expect(proteina.body, 'Faltan 87 g para el mínimo de 130 g.');
  });

  test('con la proteína cubierta no se programa ese aviso', () async {
    await nutrition.saveMeal(MealDraft(date: DateTime(2026, 9, 28), slot: MealSlot.almuerzo)
      ..items.add(MealItemDraft(label: 'Pollo', macros: const Macros(kcal: 600, protein: 120))));
    expect(of(await run(), ReminderKind.proteina), isNull);
  });

  test('la medición usa la fecha acordada del perfil', () async {
    final medicion = of(await run(), ReminderKind.medicion)!;
    expect(medicion.when, DateTime(2026, 10, 2, 7), reason: 'la sembrada en el perfil');
    expect(medicion.body, contains('ayunas'));
  });

  test('tras medir, el siguiente aviso sale del intervalo', () async {
    await BodyRepository(db).saveCheckIn(DateTime(2026, 9, 28), true, {MeasureSite.abdomen: 90});
    await ProfileRepository(db).save(const ProfilesCompanion(nextMeasurementDate: Value(null)));

    final medicion = of(await run(), ReminderKind.medicion)!;
    expect(medicion.when, DateTime(2026, 10, 19, 7), reason: '28 sep + 21 días');
    expect(medicion.body, contains('21 días'));
  });

  test('apagar un recordatorio lo saca de la cola', () async {
    await ReminderRepository(db).save(ReminderKind.comidaCena, enabled: false);
    expect(of(await run(), ReminderKind.comidaCena), isNull);
    expect(of(await run(), ReminderKind.comidaMerienda), isNotNull);
  });

  test('programa varios días y respeta el fútbol del sábado', () async {
    final planned = await run(days: 7);
    final sesiones = planned.where((n) => n.kind == ReminderKind.sesion).toList();
    // lun, mar, mié, jue, vie entrenan; sáb y dom son fútbol.
    expect(sesiones.length, 5);
    expect(sesiones.last.when.day, 2, reason: 'el viernes 2 de octubre');
  });

  test('lo programado llega al sistema de notificaciones', () async {
    await run(days: 2);
    expect(sink.last, isNotEmpty);
    expect(sink.last.map((n) => n.id).toSet().length, sink.last.length, reason: 'ids únicos');
  });
}
