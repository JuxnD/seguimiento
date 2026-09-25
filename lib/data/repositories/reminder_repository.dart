import 'package:drift/drift.dart';

import '../../domain/reminders.dart';
import '../database.dart';

/// Ajustes por defecto: lo que el usuario pidió, listo desde la instalación.
const defaultReminders = <ReminderKind, (bool, int?, int, int?)>{
  // tipo: (activo, hora, minuto, umbral)
  ReminderKind.sesion: (true, 15, 0, null),
  ReminderKind.sesionSinRegistrar: (true, 21, 0, null),
  ReminderKind.comidaDesayuno: (false, 8, 0, null),
  ReminderKind.comidaMerienda: (true, 16, 30, null),
  ReminderKind.comidaCena: (true, 20, 0, null),
  ReminderKind.proteina: (true, 20, 0, 100),
  ReminderKind.medicion: (true, 7, 0, null),
  ReminderKind.descanso: (true, null, 0, null),
  ReminderKind.calorias: (true, 20, 0, 1800),
  ReminderKind.comidasSinRegistrar: (true, 22, 0, null),
};

class ReminderRepository {
  ReminderRepository(this.db);

  final AppDatabase db;

  /// Crea las filas que falten con sus valores por defecto. Idempotente: no
  /// pisa lo que el usuario haya cambiado.
  Future<void> ensureDefaults() async {
    final existing = (await db.select(db.reminders).get()).map((r) => r.kind).toSet();
    for (final entry in defaultReminders.entries) {
      if (existing.contains(entry.key)) continue;
      final (enabled, hour, minute, threshold) = entry.value;
      await db.into(db.reminders).insert(RemindersCompanion.insert(
            kind: entry.key,
            enabled: Value(enabled),
            hour: Value(hour),
            minute: Value(minute),
            threshold: Value(threshold),
          ));
    }
  }

  Stream<List<ReminderRow>> watchAll() => db.select(db.reminders).watch();

  Future<Map<ReminderKind, ReminderSetting>> settings() async {
    final rows = await db.select(db.reminders).get();
    return {for (final r in rows) r.kind: r.toSetting()};
  }

  Future<void> save(ReminderKind kind, {bool? enabled, int? hour, int? minute, int? threshold}) =>
      (db.update(db.reminders)..where((t) => t.kind.equalsValue(kind))).write(RemindersCompanion(
        enabled: enabled == null ? const Value.absent() : Value(enabled),
        hour: hour == null ? const Value.absent() : Value(hour),
        minute: minute == null ? const Value.absent() : Value(minute),
        threshold: threshold == null ? const Value.absent() : Value(threshold),
      ));
}

extension ReminderRowX on ReminderRow {
  ReminderSetting toSetting() =>
      ReminderSetting(kind: kind, enabled: enabled, hour: hour, minute: minute, threshold: threshold);
}
