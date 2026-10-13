import 'package:drift/drift.dart';
import '../../domain/dates.dart';
import '../../domain/plan_v32.dart';
import '../database.dart';

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
}
