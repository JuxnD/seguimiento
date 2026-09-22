import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/dates.dart';
import '../domain/enums.dart';
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Subir este número exige un paso en `onUpgrade` y una entrada en
  /// docs/modelo-datos.md (sección Migraciones).
  @override
  int get schemaVersion => 3;

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
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Copia consistente de la base (incluye WAL) para respaldo.
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

