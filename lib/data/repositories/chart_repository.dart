import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/nutrition.dart';
import '../../domain/progress.dart';
import '../database.dart';
import 'nutrition_repository.dart';

/// Series para las gráficas del informe. Consultas, sin decisiones: la forma
/// de las series la define `domain/progress.dart`.
class ChartRepository {
  ChartRepository(this.db, this.nutrition);

  final AppDatabase db;
  final NutritionRepository nutrition;

  /// Rondas de cada sesión de circuito, en orden. Es la línea que debe subir.
  Future<List<SeriesPoint>> rounds({int limit = 20, SessionType? only}) async {
    final types = only == null
        ? SessionType.values.where((t) => t.isCircuit).map((t) => t.name).toList()
        : [only.name];
    final rows = await (db.select(db.sessions)
          ..where((t) => t.type.isIn(types) & t.roundsDone.isNotNull())
          ..orderBy([(t) => OrderingTerm(expression: t.date)]))
        .get();
    final points = [
      for (final s in rows)
        SeriesPoint(parseDay(s.date), s.roundsDone!.toDouble(), label: s.type.label),
    ];
    return points.length <= limit ? points : points.sublist(points.length - limit);
  }

  /// Proteína (o kcal) por día en un rango, con los días vacíos en cero.
  Future<List<SeriesPoint>> nutritionDaily(DateTime from, DateTime to, {bool protein = true}) async {
    final meals = await nutrition.range(from, to);
    final totals = dailyTotals([
      for (final m in meals) (parseDay(m.meal.date), protein ? m.macros.protein : m.macros.kcal),
    ]);
    return fillDays(totals, from, to);
  }

  /// Una medida a lo largo del tiempo, en la unidad pedida.
  Future<List<SeriesPoint>> measurements(MeasureSite site, {LengthUnit unit = LengthUnit.cm}) async {
    final rows = await (db.select(db.measurements)
          ..where((t) => t.site.equalsValue(site))
          ..orderBy([(t) => OrderingTerm(expression: t.date)]))
        .get();
    return [for (final m in rows) SeriesPoint(parseDay(m.date), fromCm(m.valueCm, unit))];
  }

  /// Peso a lo largo del tiempo (solo pesajes en ayunas si los hay).
  Future<List<SeriesPoint>> weights() async {
    final rows = await (db.select(db.bodyWeights)
          ..orderBy([(t) => OrderingTerm(expression: t.date)]))
        .get();
    final fasted = rows.where((w) => w.fasted).toList();
    final source = fasted.isEmpty ? rows : fasted;
    return [for (final w in source) SeriesPoint(parseDay(w.date), w.kg)];
  }

  /// Sitios con al menos dos tomas: los únicos que dibujan una línea.
  Future<List<MeasureSite>> sitesWithHistory() async {
    final rows = await db.select(db.measurements).get();
    final counts = <MeasureSite, int>{};
    for (final m in rows) {
      counts[m.site] = (counts[m.site] ?? 0) + 1;
    }
    return [for (final e in counts.entries) if (e.value >= 2) e.key];
  }
}
