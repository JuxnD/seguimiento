import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/goal_history.dart';

/// Plan 022: desde el esquema 23 una base recién creada es un alta pendiente
/// sin metas. Las pruebas que modelan a alguien que ya usa la app (el dueño o
/// una base migrada) la dejan como la deja la migración: legacyUnknown/ready
/// y, si piden metas, vigentes desde [since] (antes: lo que hacía onCreate).
Future<AppDatabase> asExistingUser(AppDatabase db, {bool goals = true, DateTime? since}) async {
  await db.customStatement(
      "UPDATE profiles SET profile_origin = 'legacyUnknown', setup_state = 'ready', setup_confirmed_at = NULL");
  if (goals) {
    await seedGoalVersions(db, effectiveFrom: dateOnly(since ?? DateTime.now()), origin: GoalOrigin.inicio);
  }
  return db;
}
