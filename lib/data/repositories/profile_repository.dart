import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/report/report_input.dart';
import '../../domain/goal_history.dart' show GoalOrigin;
import '../database.dart';
import 'goal_repository.dart';

class ProfileRepository {
  ProfileRepository(this.db);

  final AppDatabase db;

  Stream<ProfileRow> watch() => (db.select(db.profiles)..where((t) => t.id.equals(1))).watchSingle();

  Future<ProfileRow> get() => (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();

  /// Guarda el perfil; cada meta que cambie queda con su vigencia desde hoy
  /// (plan 009). El pasado se sigue evaluando con la meta que regía.
  Future<void> save(ProfilesCompanion data) => GoalRepository(db).updateProfile(data, origin: GoalOrigin.perfil);

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
        kcalTargetFootball: kcalTargetFootball,
        kcalFloor: kcalFloor,
        minWarmupSec: minWarmupSec,
        measureIntervalDays: measureIntervalDays,
        lengthUnit: lengthUnit,
        stepsTarget: stepsTarget,
      );
}
