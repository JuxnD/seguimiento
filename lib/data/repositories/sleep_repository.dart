import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../database.dart';

/// Horas en cama por noche (§19.3). La fecha es la mañana en que se anota:
/// la noche del lunes al martes queda en el martes.
class SleepRepository {
  SleepRepository(this.db);

  final AppDatabase db;

  Future<void> set(DateTime day, double hours) => db.into(db.sleepLogs).insertOnConflictUpdate(
        SleepLogsCompanion.insert(date: dayKey(day), hours: hours),
      );

  Future<void> remove(DateTime day) => (db.delete(db.sleepLogs)..where((t) => t.date.equals(dayKey(day)))).go();

  Stream<double?> watchDay(DateTime day) =>
      (db.select(db.sleepLogs)..where((t) => t.date.equals(dayKey(day)))).watchSingleOrNull().map((r) => r?.hours);

  /// Noches anotadas en el rango (incluidos los dos extremos).
  Future<Map<String, double>> range(DateTime from, DateTime to) async {
    final rows = await (db.select(db.sleepLogs)
          ..where((t) => t.date.isBetweenValues(dayKey(from), dayKey(to))))
        .get();
    return {for (final r in rows) r.date: r.hours};
  }
}
