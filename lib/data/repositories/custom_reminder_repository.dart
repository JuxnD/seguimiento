import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/reminders.dart';
import '../database.dart';

/// Recordatorios propios: crear, editar, borrar y marcar como hechos.
class CustomReminderRepository {
  CustomReminderRepository(this.db);

  final AppDatabase db;

  Stream<List<CustomReminder>> watchAll() =>
      (db.select(db.customReminders)..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .watch()
          .map((rows) => [for (final r in rows) r.toDomain()]);

  Future<List<CustomReminder>> all() async =>
      [for (final r in await (db.select(db.customReminders)..orderBy([(t) => OrderingTerm(expression: t.id)])).get()) r.toDomain()];

  /// Crea (sin `id`) o reemplaza (con `id`). Devuelve el id.
  Future<int> save({
    int? id,
    required String title,
    String? note,
    required int intervalDays,
    required int hour,
    required int minute,
    required DateTime startDate,
    bool enabled = true,
  }) async {
    final data = CustomRemindersCompanion(
      title: Value(title.trim()),
      note: Value(note == null || note.trim().isEmpty ? null : note.trim()),
      intervalDays: Value(intervalDays),
      hour: Value(hour),
      minute: Value(minute),
      startDate: Value(dayKey(startDate)),
      enabled: Value(enabled),
    );
    if (id == null) return db.into(db.customReminders).insert(data);
    await (db.update(db.customReminders)..where((t) => t.id.equals(id))).write(data);
    return id;
  }

  Future<void> setEnabled(int id, bool enabled) =>
      (db.update(db.customReminders)..where((t) => t.id.equals(id))).write(CustomRemindersCompanion(enabled: Value(enabled)));

  /// Hecho ese día: la cuenta vuelve a empezar desde ahí.
  Future<void> markDone(int id, DateTime day) => (db.update(db.customReminders)..where((t) => t.id.equals(id)))
      .write(CustomRemindersCompanion(lastDone: Value(dayKey(day))));

  /// Deshacer un "hecho" marcado por error.
  Future<void> setLastDone(int id, DateTime? day) => (db.update(db.customReminders)..where((t) => t.id.equals(id)))
      .write(CustomRemindersCompanion(lastDone: Value(day == null ? null : dayKey(day))));

  Future<void> delete(int id) => (db.delete(db.customReminders)..where((t) => t.id.equals(id))).go();
}

extension CustomReminderRowX on CustomReminderRow {
  CustomReminder toDomain() => CustomReminder(
        id: id,
        title: title,
        note: note,
        intervalDays: intervalDays,
        hour: hour,
        minute: minute,
        startDate: parseDay(startDate),
        lastDone: lastDone == null ? null : parseDay(lastDone!),
        enabled: enabled,
      );
}
