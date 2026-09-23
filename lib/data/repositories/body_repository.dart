import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../database.dart';

/// Una toma de medidas: todas las del mismo día.
class MeasurementCheckIn {
  MeasurementCheckIn(this.date, this.fasted, this.valuesCm);

  final DateTime date;
  final bool fasted;
  final Map<MeasureSite, double> valuesCm;
}

class BodyRepository {
  BodyRepository(this.db);

  final AppDatabase db;

  // ---------- Peso ----------

  Stream<List<BodyWeightRow>> watchWeights({int limit = 90}) => (db.select(db.bodyWeights)
        ..orderBy([
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ])
        ..limit(limit))
      .watch();

  /// Un pesaje por día **y** condición: volver a pesarse en ayunas el mismo
  /// día corrige el anterior en vez de duplicar el punto de la gráfica. Uno
  /// en ayunas y otro sin ayunas conviven (el informe prefiere el de ayunas).
  Future<void> addWeight(DateTime date, double kg, {bool fasted = true}) => db.transaction(() async {
        await (db.delete(db.bodyWeights)..where((t) => t.date.equals(dayKey(date)) & t.fasted.equals(fasted))).go();
        await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(date: dayKey(date), kg: kg, fasted: Value(fasted)));
      });

  /// Primer pesaje registrado: la línea base del "desde…".
  Stream<BodyWeightRow?> watchFirstWeight() => (db.select(db.bodyWeights)
        ..orderBy([(t) => OrderingTerm(expression: t.date), (t) => OrderingTerm(expression: t.id)])
        ..limit(1))
      .watchSingleOrNull();

  Future<void> deleteWeight(int id) => (db.delete(db.bodyWeights)..where((t) => t.id.equals(id))).go();

  // ---------- Medidas ----------

  Stream<List<MeasurementCheckIn>> watchCheckIns() =>
      (db.select(db.measurements)..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
          .watch()
          .map(_group);

  List<MeasurementCheckIn> _group(List<MeasurementRow> rows) {
    final byDate = <String, List<MeasurementRow>>{};
    for (final r in rows) {
      byDate.putIfAbsent(r.date, () => []).add(r);
    }
    return byDate.entries
        .map((e) => MeasurementCheckIn(
              parseDay(e.key),
              e.value.every((r) => r.fasted),
              {for (final r in e.value) r.site: r.valueCm},
            ))
        .toList();
  }

  /// Reemplaza la toma de ese día. Valores ya en cm.
  ///
  /// `replacing`: fecha original al editar una toma. Si la fecha cambió, la
  /// toma vieja se borra en la misma transacción (si no, quedaría duplicada).
  Future<void> saveCheckIn(DateTime date, bool fasted, Map<MeasureSite, double> valuesCm, {DateTime? replacing}) =>
      db.transaction(() async {
        if (replacing != null && dayKey(replacing) != dayKey(date)) await deleteCheckIn(replacing);
        await deleteCheckIn(date);
        for (final e in valuesCm.entries) {
          await db.into(db.measurements).insert(MeasurementsCompanion.insert(
                date: dayKey(date),
                fasted: Value(fasted),
                site: e.key,
                valueCm: e.value,
              ));
        }
      });

  Future<void> deleteCheckIn(DateTime date) =>
      (db.delete(db.measurements)..where((t) => t.date.equals(dayKey(date)))).go();

  /// Última toma estrictamente anterior a `date`.
  Future<DateTime?> lastCheckInBefore(DateTime date) async {
    final r = await (db.select(db.measurements)
          ..where((t) => t.date.isSmallerThanValue(dayKey(date)))
          ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return r == null ? null : parseDay(r.date);
  }
}
