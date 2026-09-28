import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../database.dart';

/// Pasos del día, uno por fecha. Hoy se escriben a mano (leídos del reloj o
/// del teléfono); `source` queda para cuando lleguen de otra fuente.
class StepsRepository {
  StepsRepository(this.db);

  final AppDatabase db;

  /// Registrar otra vez el mismo día reemplaza la cifra: el reloj va sumando.
  Future<void> setSteps(DateTime day, int steps, {String source = 'manual'}) =>
      db.into(db.dailySteps).insertOnConflictUpdate(
            DailyStepsCompanion.insert(date: dayKey(day), steps: steps, source: Value(source)),
          );

  Future<void> clear(DateTime day) => (db.delete(db.dailySteps)..where((t) => t.date.equals(dayKey(day)))).go();

  Future<int?> day(DateTime day) async =>
      (await (db.select(db.dailySteps)..where((t) => t.date.equals(dayKey(day)))).getSingleOrNull())?.steps;

  Stream<int?> watchDay(DateTime day) => (db.select(db.dailySteps)..where((t) => t.date.equals(dayKey(day))))
      .watchSingleOrNull()
      .map((r) => r?.steps);

  /// Pasos por día (`YYYY-MM-DD`) en el rango, solo los días registrados.
  Future<Map<String, int>> range(DateTime from, DateTime to) async {
    final rows = await (db.select(db.dailySteps)..where((t) => t.date.isBetweenValues(dayKey(from), dayKey(to)))).get();
    return {for (final r in rows) r.date: r.steps};
  }

  Stream<List<DailyStepsRow>> watchAll() =>
      (db.select(db.dailySteps)..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)])).watch();
}
