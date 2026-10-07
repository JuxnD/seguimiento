import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart';
import '../database.dart';

/// Resultados del test de condición (§19.11).
class FitnessTestRepository {
  FitnessTestRepository(this.db);

  final AppDatabase db;

  Future<List<TestResult>> all() async => [
        for (final r in await (db.select(db.fitnessTests)..orderBy([(t) => OrderingTerm(expression: t.id)])).get())
          TestResult(round: r.round, item: r.item, value: r.value, side: r.side, clean: r.clean),
      ];

  /// ¿Ya se hizo esa parte del test? (al menos una prueba guardada ese día).
  Future<bool> done(int round, TestPart part) async {
    final ids = [for (final t in part == TestPart.torso ? torsoTests : legTests) t.id];
    final rows = await (db.select(db.fitnessTests)..where((t) => t.round.equals(round) & t.item.isIn(ids))).get();
    return rows.isNotEmpty;
  }

  /// Guarda una parte del test (reemplaza lo que hubiera de esas pruebas en
  /// esa ronda) y una sesión de tipo "otro" en modo test, para que el día
  /// cuente como entrenado.
  Future<void> save({
    required DateTime date,
    required int round,
    required TestPart part,
    required List<TestResult> results,
    required int totalSec,
  }) =>
      db.transaction(() async {
        final ids = {for (final r in results) r.item};
        await (db.delete(db.fitnessTests)..where((t) => t.round.equals(round) & t.item.isIn(ids))).go();
        for (final r in results) {
          await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
                date: dayKey(date),
                round: round,
                item: r.item,
                side: Value(r.side),
                value: r.value,
                clean: Value(r.clean),
              ));
        }
        final context = 'Test $round · ${part == TestPart.torso ? 'torso, core y habilidades' : 'piernas'}';
        final existing = await (db.select(db.sessions)
              ..where((t) => t.date.equals(dayKey(date)) & t.mode.equals('test') & t.context.equals(context)))
            .getSingleOrNull();
        if (existing == null) {
          await db.into(db.sessions).insert(SessionsCompanion.insert(
                date: dayKey(date),
                type: SessionType.otro,
                totalSec: Value(totalSec),
                mode: const Value('test'),
                context: Value(context),
              ));
        }
      });
}
