import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/recovery.dart';
import '../database.dart';

/// Una toma de medidas: todas las del mismo día.
class MeasurementCheckIn {
  MeasurementCheckIn(this.date, this.fasted, this.valuesCm, {this.time});

  final DateTime date;
  final bool fasted;
  final Map<MeasureSite, double> valuesCm;

  /// Hora de la toma, si se anotó.
  final String? time;

  /// Hombros ÷ cintura estrecha: la proporción en V (referencia estética
  /// ≈ 1,6). null si falta alguna de las dos.
  double? get shoulderWaistRatio {
    final s = valuesCm[MeasureSite.hombros], w = valuesCm[MeasureSite.cinturaEstrecha];
    return s == null || w == null || w == 0 ? null : s / w;
  }
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
  /// Un pesaje. En ayunas, antes de dormir y antes o después del fútbol hay
  /// uno por día (registrar otro lo reemplaza); "otro" admite varios
  /// (§18.10). Sin `moment`, se deduce de `fasted` como antes.
  Future<void> addWeight(DateTime date, double kg, {bool fasted = true, WeighMoment? moment, String? time}) =>
      db.transaction(() async {
        final m = moment ?? (fasted ? WeighMoment.ayunas : WeighMoment.otro);
        if (m.onePerDay) {
          final same = await (db.select(db.bodyWeights)..where((t) => t.date.equals(dayKey(date)))).get();
          for (final w in same.where((w) => weighMomentOf(w.moment, fasted: w.fasted) == m)) {
            await (db.delete(db.bodyWeights)..where((t) => t.id.equals(w.id))).go();
          }
        }
        await db.into(db.bodyWeights).insert(BodyWeightsCompanion.insert(
              date: dayKey(date),
              kg: kg,
              fasted: Value(m == WeighMoment.ayunas),
              moment: Value(m.name),
              time: Value(time),
            ));
      });

  /// Pesajes de un día (para prellenar el fútbol con antes y después).
  Future<List<BodyWeightRow>> weightsOn(DateTime date) =>
      (db.select(db.bodyWeights)..where((t) => t.date.equals(dayKey(date)))).get();

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
              time: e.value.map((r) => r.time).whereType<String>().firstOrNull,
            ))
        .toList();
  }

  /// Reemplaza la toma de ese día. Valores ya en cm.
  ///
  /// `replacing`: fecha original al editar una toma. Si la fecha cambió, la
  /// toma vieja se borra en la misma transacción (si no, quedaría duplicada).
  Future<void> saveCheckIn(DateTime date, bool fasted, Map<MeasureSite, double> valuesCm,
          {DateTime? replacing, String? time}) =>
      db.transaction(() async {
        if (replacing != null && dayKey(replacing) != dayKey(date)) await deleteCheckIn(replacing);
        await deleteCheckIn(date);
        for (final e in valuesCm.entries) {
          await db.into(db.measurements).insert(MeasurementsCompanion.insert(
                date: dayKey(date),
                fasted: Value(fasted),
                site: e.key,
                valueCm: e.value,
                time: Value(time),
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
