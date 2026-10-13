import 'package:drift/drift.dart';
import '../../domain/dates.dart';
import '../../domain/fitness_test.dart';
import '../../domain/plan_v32.dart';
import '../../domain/test_protocol.dart';
import '../database.dart';
import 'readiness_repository.dart';

/// Las cinco pruebas de movilidad (§19.13). `knee_to_wall` va por lado.
const mobilityBenchmarkItems = [
  'knee_to_wall',
  'seated_pike',
  'pancake',
  'shoulder_wall',
  'deep_squat',
];

enum BenchmarkStatus { pending, partial, complete }

/// Una toma de los benchmarks del bloque: el día previsto (cada 28 días desde
/// el miércoles de la primera semana) y el de ahora, que sigue al test de
/// piernas si ese test se movió.
class BenchmarkOccurrence {
  const BenchmarkOccurrence({
    required this.planned,
    required this.date,
    required this.withMovedLegTest,
    required this.status,
    required this.missing,
  });

  final DateTime planned;
  final DateTime date;

  /// El día cambió porque el test de piernas de ese día se movió.
  final bool withMovedLegTest;
  final BenchmarkStatus status;

  /// Lo que falta: ids de `mobilityBenchmarkItems`; `knee_to_wall (I)` o
  /// `(D)` cuando falta un lado.
  final List<String> missing;
}

class MobilityBenchmarkRepository {
  MobilityBenchmarkRepository(this.db);
  final AppDatabase db;
  Stream<List<MobilityBenchmark>> watch() => (db.select(db.mobilityBenchmarks)
        ..orderBy(
            [(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]))
      .watch();
  Future<int> save(
      {required DateTime date,
      required String item,
      String? side,
      double? value,
      bool? touches,
      String? conditions,
      DateTime? blockStart}) {
    final error = benchmarkError(item, value, touches, side);
    if (error != null) throw FormatException(error);
    return db.into(db.mobilityBenchmarks).insert(
        MobilityBenchmarksCompanion.insert(
            date: dayKey(date),
            item: item,
            side: Value(side),
            value: Value(value),
            touches: Value(touches),
            conditions: Value(conditions),
            blockStart: Value(blockStart == null ? null : dayKey(blockStart))));
  }

  /// Las tomas del bloque que empezó `blockStart` cuyo día (el de ahora) cae
  /// entre `from` y `to`. Una toma cuenta las mediciones de ese bloque, o sin
  /// bloque anotado, desde su día previsto o el de ahora (el que sea antes)
  /// hasta antes de la siguiente toma prevista, pero nunca después de `asOf`
  /// (por defecto, `to`): lo que se midió más tarde no cuenta para una
  /// consulta anterior. Sin valor no hay medición: no se supone nada.
  Future<List<BenchmarkOccurrence>> schedule({
    required String scheme,
    required DateTime blockStart,
    required TestProtocolId protocol,
    required DateTime from,
    required DateTime to,
    DateTime? asOf,
  }) async {
    final s = dateOnly(blockStart);
    final cutoff = dateOnly(asOf ?? to);
    final agenda = await ReadinessRepository(db).testAgenda(
        scheme: scheme, blockStart: s, protocol: protocol, gates: false);
    final out = <BenchmarkOccurrence>[];
    // Un movimiento sólo lleva la toma hacia adelante: basta mirar las
    // previstas hasta `to`.
    for (var planned = addDays(s, 2);
        !planned.isAfter(dateOnly(to));
        planned = addDays(planned, 28)) {
      if (!mobilityBenchmarkDue(s, planned)) continue;
      final leg = agenda
          .where((t) => t.part == TestPart.piernas && t.planned == planned)
          .firstOrNull;
      final date = leg?.date ?? planned;
      if (date.isBefore(dateOnly(from)) || date.isAfter(dateOnly(to))) continue;
      final windowStart = date.isBefore(planned) ? date : planned;
      final windowEnd = addDays(planned, 27);
      final rows = await (db.select(db.mobilityBenchmarks)
            ..where((t) =>
                t.date.isBetweenValues(dayKey(windowStart),
                    dayKey(cutoff.isBefore(windowEnd) ? cutoff : windowEnd)) &
                (t.blockStart.isNull() | t.blockStart.equals(dayKey(s)))))
          .get();
      final missing = <String>[];
      for (final item in mobilityBenchmarkItems) {
        bool measured(MobilityBenchmark r) =>
            r.item == item &&
            (item == 'shoulder_wall' ? r.touches != null : r.value != null);
        if (item == 'knee_to_wall') {
          for (final side in ['I', 'D']) {
            if (!rows.any((r) => measured(r) && r.side == side)) {
              missing.add('$item ($side)');
            }
          }
        } else if (!rows.any(measured)) {
          missing.add(item);
        }
      }
      out.add(BenchmarkOccurrence(
        planned: planned,
        date: date,
        withMovedLegTest: leg != null && leg.moved,
        status: missing.isEmpty
            ? BenchmarkStatus.complete
            // knee_to_wall cuenta dos veces (un lado cada vez).
            : missing.length == mobilityBenchmarkItems.length + 1
                ? BenchmarkStatus.pending
                : BenchmarkStatus.partial,
        missing: missing,
      ));
    }
    return out;
  }

  /// La toma que toca `date`, o null. `asOf`: hasta dónde se miran las
  /// mediciones (por defecto, `date`).
  Future<BenchmarkOccurrence?> dueOn(DateTime date,
          {required String scheme,
          required DateTime blockStart,
          required TestProtocolId protocol,
          DateTime? asOf}) async =>
      (await schedule(
              scheme: scheme,
              blockStart: blockStart,
              protocol: protocol,
              from: date,
              to: date,
              asOf: asOf))
          .firstOrNull;
}
