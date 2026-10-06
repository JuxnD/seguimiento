import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../database.dart';

/// Registro de la mañana (pulso en reposo y molestias) y habilidades logradas
/// (§16.15, §19.6, §19.8).
class RecoveryRepository {
  RecoveryRepository(this.db);

  final AppDatabase db;

  // ---------- Pulso en reposo ----------

  /// null borra la lectura del día.
  Future<void> setRestingHr(DateTime day, int? bpm) => bpm == null
      ? (db.delete(db.morningChecks)..where((t) => t.date.equals(dayKey(day)))).go()
      : db.into(db.morningChecks).insertOnConflictUpdate(
            MorningChecksCompanion.insert(date: dayKey(day), restingHr: Value(bpm)),
          );

  Future<int?> restingHrOn(DateTime day) async =>
      (await (db.select(db.morningChecks)..where((t) => t.date.equals(dayKey(day)))).getSingleOrNull())?.restingHr;

  /// Lecturas de los últimos `days` días hasta `today` (incluido).
  Future<Map<DateTime, int>> restingHrRange(DateTime today, {int days = 14}) async {
    final rows = await (db.select(db.morningChecks)
          ..where((t) => t.date.isBetweenValues(dayKey(addDays(today, -(days - 1))), dayKey(today))))
        .get();
    return {for (final r in rows) if (r.restingHr != null) parseDay(r.date): r.restingHr!};
  }

  // ---------- Molestias ----------

  /// Reemplaza las molestias del día. Las de nivel 0 no se guardan.
  Future<void> setSoreness(DateTime day, Map<String, int> levels) => db.transaction(() async {
        await (db.delete(db.sorenessLogs)..where((t) => t.date.equals(dayKey(day)))).go();
        for (final e in levels.entries.where((e) => e.value > 0)) {
          await db.into(db.sorenessLogs).insert(SorenessLogsCompanion.insert(date: dayKey(day), zone: e.key, level: e.value));
        }
      });

  /// Día → zona → nivel, de los últimos `days` días hasta `today`.
  Future<Map<DateTime, Map<String, int>>> sorenessRange(DateTime today, {int days = 7}) async {
    final rows = await (db.select(db.sorenessLogs)
          ..where((t) => t.date.isBetweenValues(dayKey(addDays(today, -(days - 1))), dayKey(today))))
        .get();
    final out = <DateTime, Map<String, int>>{};
    for (final r in rows) {
      out.putIfAbsent(parseDay(r.date), () => {})[r.zone] = r.level;
    }
    return out;
  }

  Stream<List<SorenessLogRowView>> watchDay(DateTime day) => (db.select(db.sorenessLogs)
        ..where((t) => t.date.equals(dayKey(day))))
      .watch()
      .map((rows) => [for (final r in rows) SorenessLogRowView(r.zone, r.level)]);

  // ---------- Habilidades ----------

  Stream<Map<String, DateTime>> watchSkills() => db
      .select(db.skillAchievements)
      .watch()
      .map((rows) => {for (final r in rows) r.skill: parseDay(r.date)});

  /// null quita el logro.
  Future<void> setSkill(String skill, DateTime? date) => date == null
      ? (db.delete(db.skillAchievements)..where((t) => t.skill.equals(skill))).go()
      : db.into(db.skillAchievements).insertOnConflictUpdate(
            SkillAchievementsCompanion.insert(skill: skill, date: dayKey(date)),
          );
}

/// Molestia de una zona en un día.
class SorenessLogRowView {
  const SorenessLogRowView(this.zone, this.level);

  final String zone;
  final int level;
}
