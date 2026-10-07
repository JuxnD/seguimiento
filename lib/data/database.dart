import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/dates.dart';
import '../domain/enums.dart';
import '../domain/reminders.dart';
import 'catalog_updates.dart';
import 'seed_foods.dart';
import 'tables.dart';

part 'database.g.dart';

const databaseFileName = 'seguimiento.sqlite';

@DriftDatabase(tables: [
  Profiles,
  Exercises,
  PlanVersions,
  PlanDays,
  PlanExercises,
  Sessions,
  SessionRounds,
  SessionSets,
  FootballGames,
  Foods,
  Meals,
  MealItems,
  MealTemplates,
  MealTemplateItems,
  BodyWeights,
  Measurements,
  WeekNotes,
  Reminders,
  ProgressPhotos,
  ClosedDays,
  DailySteps,
  ExercisePhotos,
  CustomReminders,
  SleepLogs,
  MorningChecks,
  SorenessLogs,
  SkillAchievements,
  AiConversations,
  AiMessages,
  FitnessTests,
  LadderStates,
  LadderEvents,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Subir este número exige un paso en `onUpgrade` y una entrada en
  /// docs/modelo-datos.md (sección Migraciones).
  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // El programa arranca el día de la instalación; se ajusta en Perfil.
          await into(profiles).insert(ProfilesCompanion.insert(startDate: dayKey(DateTime.now())));
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: el plan admite bloques extra, sostenes, RIR y rangos de
            // descanso; la sesión guarda las condiciones de progresión.
            await m.addColumn(profiles, profiles.measureIntervalMaxDays);
            await m.addColumn(profiles, profiles.nextMeasurementDate);
            await m.addColumn(profiles, profiles.cooldownTargetSec);
            await m.addColumn(profiles, profiles.neverToFailure);
            await m.addColumn(planDays, planDays.restBetweenRoundsSec);
            for (final column in [
              planExercises.restSecMax,
              planExercises.block,
              planExercises.variant,
              planExercises.holdSecMin,
              planExercises.holdSecMax,
              planExercises.perSide,
              planExercises.rirMin,
              planExercises.rirMax,
              planExercises.notes,
            ]) {
              await m.addColumn(planExercises, column);
            }
            await m.addColumn(sessions, sessions.techniqueOk);
            await m.addColumn(sessions, sessions.fullRange);
            await m.addColumn(sessions, sessions.recoveryOk);
          }
          if (from < 3) {
            // v3: el alimento dice de dónde salen sus macros y aparecen los
            // combos de un toque.
            await m.addColumn(foods, foods.servingGrams);
            await m.addColumn(foods, foods.source);
            await m.addColumn(mealItems, mealItems.sourceVerified);
            await m.createTable(mealTemplates);
            await m.createTable(mealTemplateItems);
          }
          if (from < 4) {
            // v4: la sesión sabe si se salió del plan o se cerró antes.
            await m.addColumn(sessions, sessions.outOfPlan);
            await m.addColumn(sessions, sessions.incomplete);
            await m.addColumn(sessions, sessions.plannedRounds);
          }
          if (from < 5) {
            // v5: ajustes de recordatorios (una fila por tipo).
            await m.createTable(reminders);
          }
          if (from < 6) {
            // v6: fotos de progreso.
            await m.createTable(progressPhotos);
          }
          if (from < 7) {
            // v7: el descanso se registra aparte del trabajo neto.
            await m.addColumn(sessions, sessions.restSec);
          }
          if (from < 8) {
            // v8: cada ronda separa trabajo y descanso, las series guardan la
            // carga externa, los ejercicios traen claves de técnica y los
            // días de comida se pueden cerrar a mano.
            await m.addColumn(exercises, exercises.mediaUrl);
            await m.addColumn(exercises, exercises.formCues);
            await m.addColumn(exercises, exercises.progressionNote);
            await m.addColumn(exercises, exercises.tracksLoad);
            await m.addColumn(sessionRounds, sessionRounds.workSec);
            await m.addColumn(sessionRounds, sessionRounds.restSec);
            await m.addColumn(sessionSets, sessionSets.loadKg);
            await m.createTable(closedDays);
            // Las guías se completan al final (paso 16): escriben columnas
            // que llegan después (`exercises.anchor`, esquema 15).
          }
          if (from >= 5 && from < 9) {
            // v9 (solo datos): los recordatorios vuelven una vez a los valores
            // acordados el 26 sep 2026 (sesión 3:00 p. m., proteína y calorías
            // 8:00 p. m., comidas sin registrar 10:00 p. m.…). Al borrar las
            // filas, `ReminderRepository.ensureDefaults` las recrea al abrir.
            await delete(reminders).go();
          }
          if (from < 10) {
            // v10: pasos diarios con su meta, golpe o molestia en el fútbol, y
            // el catálogo distingue lo sembrado de lo creado por el usuario
            // (las entradas libres se guardan solas y se pueden marcar).
            await m.addColumn(profiles, profiles.stepsTarget);
            await m.addColumn(footballGames, footballGames.knock);
            await m.addColumn(foods, foods.origin);
            await m.addColumn(foods, foods.favorite);
            await m.createTable(dailySteps);
            await (update(foods)..where((t) => t.name.isIn(initialFoods.map((f) => f.name))))
                .write(const FoodsCompanion(origin: Value(FoodOrigin.semilla)));
            await addMissingCatalog(this);
          }
          if (from < 11) {
            // v11: foto de referencia por ejercicio.
            await m.createTable(exercisePhotos);
          }
          if (from < 12) {
            // v12: recordatorios que crea el usuario.
            await m.createTable(customReminders);
          }
          if (from < 13) {
            // v13 (solo datos): pan y salchichón por gramos (§16.3, §17).
            await applyGramsCatalog(this);
          }
          if (from < 14) {
            // v14: sesiones guardadas solas al terminar el cronómetro y hora
            // de cada toma de medidas.
            await m.addColumn(sessions, sessions.pendingReview);
            await m.addColumn(measurements, measurements.time);
          }
          if (from < 15) {
            // v15: Plan v3 (§18): periodización por versión, superseries,
            // anclaje de la banda, variante por serie y formato de las
            // sesiones de resistencia (Cindy, Tabata, por tiempo).
            await m.addColumn(planVersions, planVersions.scheme);
            await m.addColumn(planExercises, planExercises.supersetGroup);
            await m.addColumn(exercises, exercises.anchor);
            await m.addColumn(sessionSets, sessionSets.variant);
            await m.addColumn(sessions, sessions.mode);
            await m.addColumn(sessions, sessions.extraReps);
          }
          if (from < 16) {
            // v16: Plan v3.1 (§19): RIR por serie, meta de kcal de los días de
            // fútbol, hidratación del partido y horas de sueño.
            await m.addColumn(sessionSets, sessionSets.rir);
            await m.addColumn(profiles, profiles.kcalTargetFootball);
            await m.addColumn(footballGames, footballGames.weightBeforeKg);
            await m.addColumn(footballGames, footballGames.weightAfterKg);
            await m.addColumn(footballGames, footballGames.fluidMl);
            await m.createTable(sleepLogs);
          }
          if (from < 17) {
            // v17: momento y hora del pesaje, registro de la mañana (pulso en
            // reposo y molestias) y huevos por porción de cada alimento.
            await m.addColumn(bodyWeights, bodyWeights.moment);
            await m.addColumn(bodyWeights, bodyWeights.time);
            await m.addColumn(foods, foods.eggsPerUnit);
            await m.createTable(morningChecks);
            await m.createTable(sorenessLogs);
            await m.createTable(skillAchievements);
          }
          if (from < 18) {
            // v18 conserva snapshot y turnos validados sin credenciales.
            await m.createTable(aiConversations);
            await m.createTable(aiMessages);
          }
          if (from < 19) {
            // v19: historial importado (§16.16), tests (§19.11) y escaleras de
            // core (§19.10).
            await m.addColumn(sessions, sessions.imported);
            await m.addColumn(footballGames, footballGames.imported);
            await m.createTable(fitnessTests);
            await m.createTable(ladderStates);
          }
          if (from < 20) {
            // Desde 18 createTable usa la definición actual (incluye la
            // frontera); una candidata 19 necesita añadirla explícitamente.
            if (from >= 19) await m.addColumn(ladderStates, ladderStates.sessionsAfter);
            if (from >= 19) await m.addColumn(ladderStates, ladderStates.epoch);
            await m.addColumn(sessions, sessions.coreEpochs);
            await m.createTable(ladderEvents);
            // La candidata19 midió pantalla abierta como trabajo; no hubo
            // cronómetro de esfuerzo. Conservar resultados, quitar duración
            // inferida para no producir energía ficticia.
            await customStatement(
                "UPDATE sessions SET total_sec=0, warmup_sec=0, cooldown_sec=0, rest_sec=0 WHERE mode='test'");
          }
          if (from < 16) {
            // Guías del catálogo con todas las columnas ya creadas: las de
            // antes del 8 y las del v3.1 (dominadas con carga, ejercicios
            // nuevos). Solo llena campos vacíos.
            await applyExerciseGuides(this);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Sesiones cuyas rondas cuentan para el récord: de circuito y **contadas**.
  /// Una estimación por tiempo no es una marca. Las incompletas sí cuentan:
  /// sus rondas se hicieron de verdad. Una sola definición para Hoy, el
  /// cierre de sesión y el informe.
  Expression<bool> get countedCircuitRounds =>
      sessions.type.isIn(SessionType.values.where((t) => t.isCircuit).map((t) => t.name).toList()) &
      sessions.roundsEstimated.equals(false) &
      // El historial importado (lo prescrito, no lo medido) no es marca.
      sessions.imported.equals(false);

  /// Sesiones que cuentan como entrenamiento del plan: todas menos la
  /// movilidad, que es opcional y no suma adherencia, racha ni avisos.
  Expression<bool> get trainingSessions => sessions.type.equalsValue(SessionType.movilidad).not();

  /// Copia consistente de la base para respaldo (la hace SQLite, no una copia
  /// del archivo: sirve aunque haya una escritura en curso).
  Future<File> exportTo(String path) async {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    await customStatement('VACUUM INTO ?', [path]);
    return f;
  }
}

Future<File> databaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, databaseFileName));
}

Future<AppDatabase> openAppDatabase() async {
  final file = await databaseFile();
  return AppDatabase(NativeDatabase.createInBackground(file));
}

/// Para pruebas.
AppDatabase openInMemoryDatabase() => AppDatabase(NativeDatabase.memory());
