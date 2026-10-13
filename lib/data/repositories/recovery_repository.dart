import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../database.dart';

/// Registro de la mañana (pulso en reposo y molestias) y habilidades logradas
/// (§16.15, §19.6, §19.8).
class RecoveryRepository {
  RecoveryRepository(this.db);

  final AppDatabase db;

  // ---------- Pulso en reposo ----------

  /// null borra la lectura del día (la fila se va si tampoco hay cómo
  /// amaneció).
  Future<void> setRestingHr(DateTime day, int? bpm) =>
      _setMorning(day, MorningChecksCompanion(restingHr: Value(bpm)));

  /// Cómo amaneció (plan 009): 1 descansado, 2 normal, 3 cansado; null borra.
  Future<void> setFeeling(DateTime day, int? feeling) =>
      _setMorning(day, MorningChecksCompanion(feeling: Value(feeling)));

  /// Dolor muscular general 0–10 y "enfermo, fiebre o dolor agudo"
  /// (§19.17); null borra la respuesta.
  Future<void> setReadinessAnswers(DateTime day, {required int? muscleSoreness, required bool? ill}) =>
      _setMorning(day, MorningChecksCompanion(muscleSoreness: Value(muscleSoreness), ill: Value(ill)));

  Future<MorningCheckRow?> morningOn(DateTime day) =>
      (db.select(db.morningChecks)..where((t) => t.date.equals(dayKey(day)))).getSingleOrNull();

  Future<int?> feelingOn(DateTime day) async =>
      (await (db.select(db.morningChecks)..where((t) => t.date.equals(dayKey(day)))).getSingleOrNull())?.feeling;

  Future<void> _setMorning(DateTime day, MorningChecksCompanion change) => db.transaction(() async {
        final key = dayKey(day);
        await db
            .into(db.morningChecks)
            .insert(MorningChecksCompanion.insert(date: key), mode: InsertMode.insertOrIgnore);
        await (db.update(db.morningChecks)..where((t) => t.date.equals(key))).write(change);
        final row = await (db.select(db.morningChecks)..where((t) => t.date.equals(key))).getSingle();
        if (row.restingHr == null && row.feeling == null && row.muscleSoreness == null && row.ill == null) {
          await (db.delete(db.morningChecks)..where((t) => t.date.equals(key))).go();
        }
      });

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

  /// Una molestia suelta (al terminar una rutina): queda la más alta del día
  /// para esa zona; no borra las demás.
  Future<void> addSoreness(DateTime day, String zone, int level) => db.transaction(() async {
        final key = dayKey(day);
        final prev = await (db.select(db.sorenessLogs)..where((t) => t.date.equals(key) & t.zone.equals(zone)))
            .getSingleOrNull();
        if (prev != null && prev.level >= level) return;
        await db
            .into(db.sorenessLogs)
            .insertOnConflictUpdate(SorenessLogsCompanion.insert(date: key, zone: zone, level: level));
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
