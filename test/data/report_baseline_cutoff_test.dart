import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/report/report_input.dart';

import '../support/sqlite_host.dart';

void main() {
  late AppDatabase db;
  setUpAll(useHostSqlite);
  setUp(() => db = openInMemoryDatabase());
  tearDown(() => db.close());
  Future<int> measure(String date, double cm, {bool fasted = true}) =>
      db.into(db.measurements).insert(MeasurementsCompanion.insert(
            date: date,
            site: MeasureSite.abdomen,
            valueCm: cm,
            fasted: Value(fasted),
          ));
  Future<int> weight(String date, double kg) => db
      .into(db.bodyWeights)
      .insert(BodyWeightsCompanion.insert(date: date, kg: kg));
  Future<ReportInput> report() => ReportRepository(db, NutritionRepository(db))
      .load(DateTime(2026, 9, 1), DateTime(2026, 9, 30),
          today: DateTime(2026, 10, 12), withPrevious: false);

  test('añadir primera medida en ayunas futura no cambia el informe histórico',
      () async {
    await measure('2026-09-01', 90, fasted: false);
    await measure('2026-09-20', 89, fasted: false);
    final before = buildReport(await report());
    await measure('2026-10-01', 85);
    final after = await report();
    expect(after.baselineMeasurements[MeasureSite.abdomen]!.valueCm, 90);
    expect(buildReport(after), before);
  });
  test('sin registros o sólo registros futuros no hay líneas base', () async {
    expect((await report()).baselineWeight, isNull);
    expect((await report()).baselineMeasurements, isEmpty);
    await weight('2026-10-01', 80);
    await measure('2026-10-01', 90);
    final input = await report();
    expect(input.baselineWeight, isNull);
    expect(input.baselineMeasurements, isEmpty);
  });
  test('conserva ayunas anterior y admite tomas en el último día', () async {
    await measure('2026-08-01', 95, fasted: false);
    await measure('2026-08-02', 93);
    await measure('2026-09-30', 90);
    await weight('2026-09-30', 80);
    await weight('2026-10-01', 78);
    final input = await report();
    expect(input.baselineMeasurements[MeasureSite.abdomen]!.valueCm, 93);
    expect(input.baselineWeight!.kg, 80);
    expect(input.weightsInRange.length, 1);
  });
}
