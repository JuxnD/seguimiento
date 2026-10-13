import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/sleep_entry.dart';
import '../database.dart';

/// Una noche anotada con lo que se sabe de ella (plan 040). En las de antes
/// sólo hay horas: inicio, despertar y procedencia quedan sin dato.
class SleepDetail {
  const SleepDetail({required this.day, required this.hours, this.start, this.wake, this.source, this.note});

  /// La mañana en que se anota (la noche del lunes al martes es el martes).
  final DateTime day;
  final double hours;
  final DateTime? start;
  final DateTime? wake;

  /// `manual`, `clock`, `edit_manual` o null (de antes).
  final String? source;
  final String? note;
}

/// Horas en cama por noche (§19.3). La fecha es la mañana en que se anota:
/// la noche del lunes al martes queda en el martes.
class SleepRepository {
  SleepRepository(this.db);

  final AppDatabase db;

  /// Sólo las horas (botones de Hoy y registro de la mañana). Si no
  /// cambian, no se toca nada; si cambian, la hora de acostarse y de
  /// despertar dejan de cuadrar y se borran. La nota se conserva.
  Future<void> set(DateTime day, double hours) => db.transaction(() async {
        final key = dayKey(day);
        final prev = await (db.select(db.sleepLogs)..where((t) => t.date.equals(key))).getSingleOrNull();
        if (prev != null && prev.hours == hours) return;
        await db.into(db.sleepLogs).insertOnConflictUpdate(SleepLogsCompanion(
              date: Value(key),
              hours: Value(hours),
              sleepStart: const Value(null),
              wakeAt: const Value(null),
              source: Value(sleepSourceAfterEdit(prev?.source, fromClock: false)),
              note: Value(prev?.note),
            ));
      });

  /// Diferencia admitida entre las horas y las que salen de inicio y
  /// despertar: el redondeo a dos decimales (minutos → horas).
  static const hoursTolerance = 0.01;

  /// Guarda la noche completa desde el diálogo de edición. Con inicio y
  /// despertar, las horas tienen que salir de ellos (si no cuadran, no se
  /// escribe nada). Admite 0–16 h como la tabla: una noche de 0 h de antes se
  /// puede conservar al editar sólo la nota o la procedencia.
  Future<void> save(
    DateTime day, {
    required double hours,
    DateTime? start,
    DateTime? wake,
    required String source,
    String? note,
  }) async {
    if (!hours.isFinite || hours < 0 || hours > maxSleepHours) {
      throw ArgumentError.value(hours, 'hours', 'entre 0 y $maxSleepHours');
    }
    if ((start == null) != (wake == null)) throw ArgumentError('inicio y despertar van juntos');
    if (start != null) {
      final derived = hoursBetween(start, wake!);
      if (derived == null) {
        throw ArgumentError('el despertar tiene que ser después de acostarse y no pasar de $maxSleepHours h');
      }
      if ((derived - hours).abs() > hoursTolerance) {
        throw ArgumentError.value(hours, 'hours', 'no cuadra con acostarse y despertar ($derived h)');
      }
    }
    final trimmed = note?.trim();
    await db.into(db.sleepLogs).insertOnConflictUpdate(SleepLogsCompanion(
          date: Value(dayKey(day)),
          hours: Value(hours),
          sleepStart: Value(start?.toIso8601String()),
          wakeAt: Value(wake?.toIso8601String()),
          source: Value(source),
          note: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
        ));
  }

  Future<void> remove(DateTime day) => (db.delete(db.sleepLogs)..where((t) => t.date.equals(dayKey(day)))).go();

  Stream<double?> watchDay(DateTime day) =>
      (db.select(db.sleepLogs)..where((t) => t.date.equals(dayKey(day)))).watchSingleOrNull().map((r) => r?.hours);

  Future<SleepDetail?> detail(DateTime day) async =>
      _detail((await (db.select(db.sleepLogs)..where((t) => t.date.equals(dayKey(day)))).getSingleOrNull()));

  Stream<SleepDetail?> watchDetail(DateTime day) =>
      (db.select(db.sleepLogs)..where((t) => t.date.equals(dayKey(day)))).watchSingleOrNull().map(_detail);

  static SleepDetail? _detail(SleepLogRow? r) => r == null
      ? null
      : SleepDetail(
          day: parseDay(r.date),
          hours: r.hours,
          start: r.sleepStart == null ? null : DateTime.tryParse(r.sleepStart!),
          wake: r.wakeAt == null ? null : DateTime.tryParse(r.wakeAt!),
          source: r.source,
          note: r.note,
        );

  Stream<Map<String, double>> watchRange(DateTime from, DateTime to) =>
      (db.select(db.sleepLogs)..where((t) => t.date.isBetweenValues(dayKey(from), dayKey(to))))
          .watch()
          .map((rows) => {for (final row in rows) row.date: row.hours});

  /// Noches anotadas en el rango (incluidos los dos extremos).
  Future<Map<String, double>> range(DateTime from, DateTime to) async {
    final rows = await (db.select(db.sleepLogs)
          ..where((t) => t.date.isBetweenValues(dayKey(from), dayKey(to))))
        .get();
    return {for (final r in rows) r.date: r.hours};
  }
}
