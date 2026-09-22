import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/enums.dart';
import 'tables.dart';

part 'database.g.dart';

/// Fecha de inicio del programa por defecto (26 ago 2026). Editable en Perfil.
const defaultStartDate = '2026-08-26';
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
  BodyWeights,
  Measurements,
  WeekNotes,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Subir este número exige un paso en `onUpgrade` y una entrada en
  /// docs/modelo-datos.md (sección Migraciones).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(profiles).insert(ProfilesCompanion.insert(startDate: defaultStartDate));
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

