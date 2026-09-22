import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/report/report_input.dart';
import '../database.dart';

class ProfileRepository {
  ProfileRepository(this.db);

  final AppDatabase db;

  Stream<ProfileRow> watch() => (db.select(db.profiles)..where((t) => t.id.equals(1))).watchSingle();

  Future<ProfileRow> get() => (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();

  Future<void> save(ProfilesCompanion data) =>
      (db.update(db.profiles)..where((t) => t.id.equals(1))).write(data);

  Stream<String?> watchWeekNote(int weekIndex) => (db.select(db.weekNotes)
        ..where((t) => t.weekIndex.equals(weekIndex)))
      .watchSingleOrNull()
      .map((r) => r?.body);

  Future<void> saveWeekNote(int weekIndex, String body) async {
    if (body.trim().isEmpty) {
      await (db.delete(db.weekNotes)..where((t) => t.weekIndex.equals(weekIndex))).go();
    } else {
      await db.into(db.weekNotes).insertOnConflictUpdate(WeekNotesCompanion.insert(
            weekIndex: Value(weekIndex),
            body: body.trim(),
          ));
    }
  }
}

extension ProfileRowX on ProfileRow {
  DateTime get programStart => parseDay(startDate);

  Targets get targets => Targets(
        proteinMin: proteinMin,
        proteinMax: proteinMax,
        kcalTarget: kcalTarget,
        kcalFloor: kcalFloor,
        minWarmupSec: minWarmupSec,
        measureIntervalDays: measureIntervalDays,
        lengthUnit: lengthUnit,
      );
}
