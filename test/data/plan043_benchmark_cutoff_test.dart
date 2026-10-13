import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/mobility_benchmark_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/report/report_builder.dart';

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

/// Plan 043, observación del root (ROOT-043-WIP-BENCHMARK-CUTOFF): una toma
/// de benchmarks no puede darse por hecha con mediciones posteriores al
/// corte que se consulta. Las seis mediciones se guardan diez días después
/// del día previsto, no el mismo día. Fechas ficticias: bloque v3.2 desde el
/// lunes 4 de marzo de 2030; la toma toca el miércoles 6.
void main() {
  setUpAll(useHostSqlite);

  final start = DateTime(2030, 3, 4);
  final later = DateTime(2030, 3, 16);

  late AppDatabase db;
  setUp(() async {
    db = await asExistingUser(openInMemoryDatabase(), since: DateTime(2030, 1, 1));
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV32(db, plan, start);
    final benchmarks = MobilityBenchmarkRepository(db);
    for (final (item, side, value, touches) in <(String, String?, double?, bool?)>[
      ('knee_to_wall', 'I', 9, null),
      ('knee_to_wall', 'D', 10, null),
      ('seated_pike', null, -8, null),
      ('pancake', null, 30, null),
      ('shoulder_wall', null, null, true),
      ('deep_squat', null, 40, null),
    ]) {
      await benchmarks.save(
          date: later, item: item, side: side, value: value, touches: touches, blockStart: start);
    }
  });
  tearDown(() => db.close());

  test('el informe de la semana de la toma no la da por hecha con mediciones de diez días después', () async {
    final end = DateTime(2030, 3, 10);
    final text = buildReport(await ReportRepository(db, NutritionRepository(db)).load(start, end, today: end));
    expect(text, contains('Benchmarks de movilidad: mié 6 mar · pendiente'));
    expect(text, isNot(contains('Benchmarks de movilidad: mié 6 mar · completa')));
  });
}
