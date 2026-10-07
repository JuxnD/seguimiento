import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart';
import '../../domain/plan_v3.dart' show v31Scheme;
import '../database.dart';

/// Resultados del test de condición (§19.11).
class FitnessTestRepository {
  FitnessTestRepository(this.db);

  final AppDatabase db;

  Future<List<TestResult>> all() async => [
        for (final r in await (db.select(db.fitnessTests)..orderBy([(t) => OrderingTerm(expression: t.id)])).get())
          TestResult(round: r.round, item: r.item, value: r.value, side: r.side, clean: r.clean),
      ];

  /// Completo sólo cuando están todos los intentos, incluidos ambos lados.
  Future<bool> done(int round, TestPart part) async {
    final results = await all();
    return itemsFor(part).every((t) => testValue(results, round, t.id) != null);
  }

  Future<TestStatus> status(int round, TestPart part) async {
    if (await done(round, part)) return TestStatus.complete;
    final ids = itemsFor(part).map((t) => t.id).toSet();
    return (await all()).any((r) => r.round == round && ids.contains(r.item)) ? TestStatus.partial : TestStatus.pending;
  }

  /// Editar desde Cuerpo conserva el día original; no crea actividad hoy.
  Future<DateTime?> dateFor(int round, TestPart part) async {
    final row = await (db.select(db.fitnessTests)
          ..where((t) => t.round.equals(round) & t.item.isIn(itemsFor(part).map((t) => t.id)))
          ..orderBy([(t) => OrderingTerm(expression: t.id)])
          ..limit(1))
        .getSingleOrNull();
    if (row != null) return parseDay(row.date);
    final plan = await (db.select(db.planVersions)
          ..where((t) => t.scheme.equals(v31Scheme))
          ..orderBy([(t) => OrderingTerm(expression: t.validFrom)])
          ..limit(1))
        .getSingleOrNull();
    if (plan == null) return null;
    final start = parseDay(plan.validFrom);
    for (var i = 0; i < 70; i++) {
      final date = addDays(start, i);
      final t = scheduledTest(start, date);
      if (t?.round == round && t?.part == part) return date;
    }
    return null;
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
  }) {
    if (round < 1 || round > 3 || totalSec < 0 || results.isEmpty) {
      throw const FormatException('Test vacío o duración inválida');
    }
    final allowed = itemsFor(part).map((t) => t.id).toSet();
    final keys = <String>{};
    for (final r in results) {
      final item = testItem(r.item);
      if (r.round != round ||
          item == null ||
          !allowed.contains(r.item) ||
          testResultError(item, r.value) != null ||
          (item.perSide ? r.side != 'I' && r.side != 'D' : r.side != null) ||
          !keys.add('${r.item}|${r.side}')) throw FormatException('Resultado inválido: ${r.item}');
    }
    return db.transaction(() async {
      final ids = itemsFor(part).map((t) => t.id).toSet();
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
      final detail =
          '$context · duración sin medir\n${results.map((r) => '${testItem(r.item)!.name}${r.side == null ? '' : ' (${r.side})'}: ${formatTestValue(testItem(r.item)!, r.value)}${r.clean ? '' : ' (con dudas)'}').join('\n')}';
      final existing = await (db.select(db.sessions)
            ..where((t) => t.date.equals(dayKey(date)) & t.mode.equals('test') & t.context.like('$context%')))
          .getSingleOrNull();
      if (existing == null) {
        await db.into(db.sessions).insert(SessionsCompanion.insert(
              date: dayKey(date),
              type: SessionType.otro,
              // Introducir resultados no mide trabajo. No convertir el
              // tiempo con la pantalla abierta en gasto energético.
              totalSec: const Value(0),
              mode: const Value('test'),
              context: Value(detail),
            ));
      } else {
        await (db.update(db.sessions)..where((t) => t.id.equals(existing.id))).write(SessionsCompanion(
            context: Value(detail),
            totalSec: const Value(0),
            warmupSec: const Value(0),
            cooldownSec: const Value(0),
            restSec: const Value(0)));
      }
    });
  }
}
