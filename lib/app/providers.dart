import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../data/database.dart';
import '../data/notification_service.dart';
import '../data/reminder_scheduler.dart';
import '../data/repositories/reminder_repository.dart';
import '../data/database_host.dart';
import '../data/update_service.dart';
import '../data/repositories/body_repository.dart';
import '../data/repositories/chart_repository.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/exercise_repository.dart';
import '../data/repositories/nutrition_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../data/repositories/plan_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/report_repository.dart';
import '../data/repositories/training_repository.dart';
import '../domain/dates.dart';
import '../domain/enums.dart';
import '../domain/report/report_builder.dart';

/// Se sobreescribe en `main` con la base ya abierta.
final databaseHostProvider = Provider<DatabaseHost>((ref) => throw UnimplementedError());

/// Cambia al restaurar un respaldo: obliga a recrear repositorios y streams
/// contra la base nueva.
final databaseGenerationProvider = StateProvider<int>((ref) => 0);

final databaseProvider = Provider<AppDatabase>((ref) {
  ref.watch(databaseGenerationProvider);
  return ref.watch(databaseHostProvider).db;
});

final profileRepositoryProvider = Provider((ref) => ProfileRepository(ref.watch(databaseProvider)));
final exerciseRepositoryProvider = Provider((ref) => ExerciseRepository(ref.watch(databaseProvider)));
final planRepositoryProvider =
    Provider((ref) => PlanRepository(ref.watch(databaseProvider), ref.watch(exerciseRepositoryProvider)));
final trainingRepositoryProvider =
    Provider((ref) => TrainingRepository(ref.watch(databaseProvider), ref.watch(exerciseRepositoryProvider)));
final nutritionRepositoryProvider = Provider((ref) => NutritionRepository(ref.watch(databaseProvider)));
final bodyRepositoryProvider = Provider((ref) => BodyRepository(ref.watch(databaseProvider)));
final reportRepositoryProvider =
    Provider((ref) => ReportRepository(ref.watch(databaseProvider), ref.watch(nutritionRepositoryProvider)));

final reminderRepositoryProvider = Provider((ref) => ReminderRepository(ref.watch(databaseProvider)));
final notificationServiceProvider = Provider((ref) => NotificationService());

final reminderSchedulerProvider = Provider((ref) => ReminderScheduler(
      db: ref.watch(databaseProvider),
      plan: ref.watch(planRepositoryProvider),
      reminders: ref.watch(reminderRepositoryProvider),
      nutrition: ref.watch(nutritionRepositoryProvider),
      body: ref.watch(bodyRepositoryProvider),
      profile: ref.watch(profileRepositoryProvider),
      service: ref.watch(notificationServiceProvider),
    ));

final remindersProvider = StreamProvider((ref) => ref.watch(reminderRepositoryProvider).watchAll());

final dashboardRepositoryProvider = Provider((ref) => DashboardRepository(
      ref.watch(databaseProvider),
      ref.watch(planRepositoryProvider),
      ref.watch(nutritionRepositoryProvider),
      ref.watch(profileRepositoryProvider),
    ));

final photoRepositoryProvider = Provider((ref) => PhotoRepository(ref.watch(databaseProvider)));
final photoCheckInsProvider = StreamProvider((ref) => ref.watch(photoRepositoryProvider).watchCheckIns());

final chartRepositoryProvider =
    Provider((ref) => ChartRepository(ref.watch(databaseProvider), ref.watch(nutritionRepositoryProvider)));

/// Rondas de cada sesión de circuito: la línea que debe subir.
final roundsSeriesProvider = FutureProvider((ref) {
  ref.watch(sessionsProvider);
  return ref.watch(chartRepositoryProvider).rounds();
});

/// Proteína por día del rango del informe.
final proteinSeriesProvider = FutureProvider.family((ref, (String, String) range) {
  ref.watch(mealsRangeRefreshProvider(range));
  return ref.watch(chartRepositoryProvider).nutritionDaily(parseDay(range.$1), parseDay(range.$2));
});

final weightSeriesProvider = FutureProvider((ref) {
  ref.watch(weightsProvider);
  return ref.watch(chartRepositoryProvider).weights();
});

final measurementSitesProvider = FutureProvider((ref) {
  ref.watch(checkInsProvider);
  return ref.watch(chartRepositoryProvider).sitesWithHistory();
});

final measurementSeriesProvider = FutureProvider.family((ref, MeasureSite site) {
  ref.watch(checkInsProvider);
  final unit = ref.watch(profileProvider).value?.lengthUnit ?? LengthUnit.cm;
  return ref.watch(chartRepositoryProvider).measurements(site, unit: unit);
});

/// Resumen de Hoy. Se recalcula cuando cambia cualquier dato que muestre.
final dashboardProvider = FutureProvider((ref) {
  ref.watch(sessionsProvider);
  ref.watch(planVersionsProvider);
  ref.watch(profileProvider);
  ref.watch(checkInsProvider);
  ref.watch(mealsForDayProvider(dayKey(dateOnly(DateTime.now()))));
  return ref.watch(dashboardRepositoryProvider).today();
});

/// Reprograma los avisos cuando cambia algo que los afecta: una sesión, una
/// comida de hoy, una medida, el plan o los propios ajustes. Se observa desde
/// el shell para que viva mientras la app esté abierta.
final reminderSyncProvider = Provider<void>((ref) {
  final scheduler = ref.watch(reminderSchedulerProvider);
  var pending = false;
  Future<void> run() async {
    if (pending) return;
    pending = true;
    try {
      await scheduler.reschedule();
    } on Object {
      // Sin permiso de notificaciones o sin canal: la app sigue igual.
    } finally {
      pending = false;
    }
  }

  ref.listen(sessionsProvider, (_, __) => run());
  ref.listen(checkInsProvider, (_, __) => run());
  ref.listen(planVersionsProvider, (_, __) => run());
  ref.listen(remindersProvider, (_, __) => run());
  ref.listen(profileProvider, (_, __) => run());
  ref.listen(mealsForDayProvider(dayKey(dateOnly(DateTime.now()))), (_, __) => run());
  run();
});

final profileProvider = StreamProvider((ref) => ref.watch(profileRepositoryProvider).watch());
final exercisesProvider = StreamProvider((ref) => ref.watch(exerciseRepositoryProvider).watchAll());
final planVersionsProvider = StreamProvider((ref) => ref.watch(planRepositoryProvider).watchVersions());
final sessionsProvider = StreamProvider((ref) => ref.watch(trainingRepositoryProvider).watchRecent());
final footballProvider = StreamProvider((ref) => ref.watch(trainingRepositoryProvider).watchFootball());
final foodsProvider = StreamProvider((ref) => ref.watch(nutritionRepositoryProvider).watchFoods());
final mealTemplatesProvider =
    StreamProvider((ref) => ref.watch(nutritionRepositoryProvider).watchTemplates());
final weightsProvider = StreamProvider((ref) => ref.watch(bodyRepositoryProvider).watchWeights());
final checkInsProvider = StreamProvider((ref) => ref.watch(bodyRepositoryProvider).watchCheckIns());

/// La clave es `dayKey` para que la familia compare por valor.
final mealsForDayProvider = StreamProvider.family(
    (ref, String day) => ref.watch(nutritionRepositoryProvider).watchDay(parseDay(day)));

final planDayProvider = StreamProvider.family(
    (ref, String day) => ref.watch(planRepositoryProvider).watchDayFor(parseDay(day)));

final weekNoteProvider =
    StreamProvider.family((ref, int week) => ref.watch(profileRepositoryProvider).watchWeekNote(week));

/// Informe de un rango. Se recalcula cuando cambia cualquier dato de entrada.
final reportProvider = FutureProvider.family<String, (String, String)>((ref, range) async {
  // Dependencias explícitas: al cambiar cualquiera, el informe se regenera.
  ref.watch(sessionsProvider);
  ref.watch(footballProvider);
  ref.watch(weightsProvider);
  ref.watch(checkInsProvider);
  ref.watch(planVersionsProvider);
  ref.watch(profileProvider);
  final from = parseDay(range.$1), to = parseDay(range.$2);
  ref.watch(mealsRangeRefreshProvider((range.$1, range.$2)));
  final input = await ref.watch(reportRepositoryProvider).load(from, to);
  return buildReport(input);
});

/// Stream auxiliar: hace que el informe reaccione a cambios de comidas.
final mealsRangeRefreshProvider = StreamProvider.family(
    (ref, (String, String) range) => ref
        .watch(nutritionRepositoryProvider)
        .watchRange(parseDay(range.$1), parseDay(range.$2))
        .map((meals) => meals.map((m) => '${m.meal.id}:${m.items.length}:${m.macros.kcal}').join(',')));

/// Versión instalada, leída del propio paquete.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

final updateServiceProvider = Provider((ref) {
  final service = UpdateService();
  ref.onDispose(service.close);
  return service;
});

/// Consulta a GitHub. Se refresca con `ref.invalidate(updateCheckProvider)`.
final updateCheckProvider = FutureProvider<UpdateCheck>((ref) async {
  final version = await ref.watch(appVersionProvider.future);
  return ref.watch(updateServiceProvider).check(currentVersion: version);
});
