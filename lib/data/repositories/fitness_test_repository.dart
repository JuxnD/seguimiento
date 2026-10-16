import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/readiness.dart';
import 'readiness_repository.dart';
import '../../domain/fitness_test.dart';
import '../../domain/test_attempt_evidence.dart';
import '../../domain/test_protocol.dart';
import '../../domain/plan_v3.dart' show v31Scheme;
import '../database.dart';

/// Resultados del test de condición (§19.11).
class FitnessTestRepository {
  FitnessTestRepository(this.db);

  final AppDatabase db;

  Future<List<TestResult>> all() async {
    final attempts = {
      for (final a in await db.select(db.fitnessTestAttempts).get()) a.id: a
    };
    return [
      for (final r in await (db.select(db.fitnessTests)
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get())
        TestResult(
            round: r.round,
            item: r.item,
            value: r.value,
            side: r.side,
            clean: r.clean,
            attemptId: r.attemptId,
            protocolId: attempts[r.attemptId]?.protocolId ?? 'v31_12',
            conditions: r.conditions,
            baselineKey: r.baselineKey,
            limitedBy: r.limitedBy,
            date: recordedTestDate(r.date)),
    ];
  }

  /// Plan 052: pruebas no hechas de un intento.
  Future<List<TestPendingRow>> pendingFor(int attemptId) =>
      (db.select(db.fitnessTestPending)
            ..where((t) => t.attemptId.equals(attemptId)))
          .get();

  /// Pendientes que siguen sin medirse en un intento posterior del mismo
  /// protocolo y parte.
  Future<List<({TestPendingRow pending, FitnessTestAttempt attempt})>>
      openPending() async {
    final attempts = {
      for (final a in await db.select(db.fitnessTestAttempts).get()) a.id: a
    };
    final rows = await db.select(db.fitnessTests).get();
    return [
      for (final p in await db.select(db.fitnessTestPending).get())
        if (attempts[p.attemptId] case final attempt?)
          if (!rows.any((r) =>
              r.item == p.item &&
              r.attemptId != null &&
              r.attemptId! > p.attemptId &&
              attempts[r.attemptId]?.protocolId == attempt.protocolId &&
              attempts[r.attemptId]?.part == attempt.part))
            (pending: p, attempt: attempt),
    ];
  }

  /// Completo sólo cuando están todos los intentos, incluidos ambos lados.
  Future<List<TestResult>> resultsFor(int round, TestPart part,
      {TestProtocolId protocol = TestProtocolId.v31_12,
      TestScheduleKey? key,
      int? attemptId}) async {
    final headers = (await attempts()).where((a) =>
        a.round == round &&
        a.part == part.name &&
        a.protocolId == protocol.name &&
        (key == null ||
            (a.scheme == key.scheme &&
                a.blockStart == dayKey(key.blockStart))));
    final selected = attemptId ?? headers.firstOrNull?.id;
    return (await all())
        .where((r) =>
            r.round == round &&
            protocolItems(protocol, part).any((i) => i.id == r.item) &&
            (selected != null
                ? r.attemptId == selected
                : protocol == TestProtocolId.v31_12 && r.attemptId == null))
        .toList();
  }

  Future<bool> done(int round, TestPart part,
      {TestProtocolId protocol = TestProtocolId.v31_12,
      TestScheduleKey? key}) async {
    final results = await resultsFor(round, part, protocol: protocol, key: key);
    return protocolItems(protocol, part)
        .every((t) => testValue(results, round, t.id) != null);
  }

  Future<TestStatus> status(int round, TestPart part) async {
    if (await done(round, part)) return TestStatus.complete;
    final ids = itemsFor(part).map((t) => t.id).toSet();
    return (await all()).any((r) => r.round == round && ids.contains(r.item))
        ? TestStatus.partial
        : TestStatus.pending;
  }

  /// Editar desde Cuerpo conserva el día original; no crea actividad hoy.
  Future<DateTime?> dateFor(int round, TestPart part) async {
    final recorded = await recordedDateFor(round, part);
    if (recorded != null) return recorded;
    return plannedDateFor(round, part);
  }

  Future<DateTime?> recordedDateFor(int round, TestPart part) async {
    final row = await (db.select(db.fitnessTests)
          ..where((t) =>
              t.round.equals(round) &
              t.item.isIn(itemsFor(part).map((t) => t.id)))
          ..orderBy([(t) => OrderingTerm(expression: t.id)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : recordedTestDate(row.date);
  }

  /// Calendario previsto, nunca la fecha de un intento nuevo.
  Future<DateTime?> plannedDateFor(int round, TestPart part) async {
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

  Future<List<FitnessTestAttempt>> attempts() =>
      (db.select(db.fitnessTestAttempts)
            ..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .get();

  /// El último intento del ítem en este bloque/protocolo, incluso si su
  /// evidencia es desconocida. No se salta un último dato malo para subir.
  Future<TestAttemptEvidence?> latestMeasurement(
      {required String item,
      required String scheme,
      required DateTime blockStart,
      required TestProtocolId protocol,
      required DateTime asOf}) async {
    final results = await all();
    final headers = (await attempts())
        .where((a) =>
            a.scheme == scheme &&
            a.blockStart == dayKey(blockStart) &&
            a.protocolId == protocol.name &&
            recordedTestDate(a.date) != null &&
            !recordedTestDate(a.date)!.isAfter(dateOnly(asOf)) &&
            results.any((r) => r.attemptId == a.id && r.item == item))
        .toList()
      ..sort((a, b) {
        final date = a.date.compareTo(b.date);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
    return headers.isEmpty
        ? null
        : observedAttemptValue(results, headers.last.id, item, asOf: asOf);
  }

  /// Plan 057 (§16.30.1): el último máximo de `item` dentro del bloque,
  /// con el v3.1 o con el v3.2. El v3.2 activado sobre el v3.1 sigue el
  /// mismo bloque, y las pruebas comparten id entre los dos protocolos: el
  /// Test 1 de torso del v3.1 sirve para dosificar el v3.2.
  Future<TestAttemptEvidence?> latestInBlock(
      {required String item,
      required DateTime blockStart,
      required DateTime asOf}) async {
    TestAttemptEvidence? best;
    for (final (scheme, protocol) in const [
      ('v3.1', TestProtocolId.v31_12),
      ('v3.2', TestProtocolId.v32_13),
    ]) {
      final m = await latestMeasurement(
          item: item,
          scheme: scheme,
          blockStart: blockStart,
          protocol: protocol,
          asOf: asOf);
      if (m != null &&
          (best == null ||
              m.date.isAfter(best.date) ||
              (m.date == best.date && m.attemptId > best.attemptId))) {
        best = m;
      }
    }
    return best;
  }

  /// La ausencia de escaleras no se convierte en cero. El aviso de
  /// descanso mantiene su fuente propia y domina cualquier entrada de test.
  Future<String?> jumpRestriction(DateTime date) async {
    final readiness = await ReadinessRepository(db).readinessOn(date);
    if (readiness.action == SuggestedAction.restOnly) {
      return 'Salto aplazado: descanso indicado (${readiness.reasons.join(' · ')}).';
    }
    final morning = await (db.select(db.morningChecks)
          ..where((t) => t.date.equals(dayKey(date))))
        .getSingleOrNull();
    if (morning?.kneeStairs != null && morning!.kneeStairs! >= 3) {
      return 'Salto aplazado: escaleras ${morning.kneeStairs}/10. Queda pendiente, sin inventar resultado.';
    }
    return null;
  }

  Future<int> save({
    required DateTime date,
    required int round,
    required TestPart part,
    required List<TestResult> results,
    required int totalSec,
    TestProtocolId protocol = TestProtocolId.v31_12,
    String scheme = 'v3.1',
    DateTime? blockStart,
    int? attemptId,
    Map<String, Map<String, Object?>> conditions = const {},
    List<TestPendingItem> pending = const [],
  }) async {
    if (round < 1 || round > 3 || totalSec < 0 || (results.isEmpty && pending.isEmpty)) {
      throw const FormatException('Test vacío o duración inválida');
    }
    if ((protocol == TestProtocolId.v32_13 &&
            (scheme != 'v3.2' || blockStart == null)) ||
        (protocol == TestProtocolId.v31_12 && scheme == 'v3.2')) {
      throw const FormatException('Identidad de plan y protocolo incompleta');
    }
    final allowed = {for (final t in protocolItems(protocol, part)) t.id: t};
    final keys = <String>{};
    final normalized = <String, String?>{};
    for (final r in results) {
      final item = allowed[r.item];
      if (r.round != round ||
          item == null ||
          testResultError(item, r.value) != null ||
          (item.perSide ? r.side != 'I' && r.side != 'D' : r.side != null) ||
          !keys.add('${r.item}|${r.side}')) {
        throw FormatException('Resultado inválido: ${r.item}');
      }
      normalized[r.item] =
          conditions.containsKey(r.item) && conditions[r.item]!.isNotEmpty
              ? canonicalTestConditions(r.item, conditions[r.item]!)
              : null;
    }
    return db.transaction(() async {
      FitnessTestAttempt? previous;
      var editId = attemptId;
      if (attemptId != null) {
        previous = await (db.select(db.fitnessTestAttempts)
              ..where((t) => t.id.equals(attemptId)))
            .getSingle();
        if (previous.protocolId != protocol.name ||
            previous.round != round ||
            previous.part != part.name ||
            previous.scheme != scheme ||
            previous.blockStart !=
                (blockStart == null ? null : dayKey(blockStart))) {
          throw const FormatException('La identidad del intento no coincide');
        }
        final oldRows = await (db.select(db.fitnessTests)
              ..where((t) => t.attemptId.equals(attemptId)))
            .get();
        if (oldRows.any((r) =>
            normalized.containsKey(r.item) &&
            r.conditions != normalized[r.item])) {
          // A changed measurement setup is another baseline, not a rewrite.
          editId = null;
          previous = null;
        }
      }
      // Editar un intento ya medido conserva el historial; crear un
      // intento nuevo (también al cambiar condiciones) respeta el día real.
      if (editId == null && results.any((r) => r.item == 'broad_jump')) {
        final reason = await jumpRestriction(date);
        if (reason != null) throw FormatException(reason);
      }
      final title =
          'Test $round · ${part == TestPart.torso ? 'torso, core y habilidades' : 'piernas'}';
      final detail = '$title · ${protocol.name} · duración sin medir\n'
          '${results.map((r) => '${allowed[r.item]!.name}${r.side == null ? '' : ' (${r.side})'}: '
              '${formatTestValue(allowed[r.item]!, r.value)}${r.clean ? '' : ' (con dudas)'}'
              ' · condiciones: ${normalized[r.item] ?? 'desconocidas'}').join('\n')}';
      int sessionId;
      if (previous?.sessionId case final linked?) {
        sessionId = linked;
        await (db.update(db.sessions)..where((t) => t.id.equals(linked))).write(
            SessionsCompanion(
                date: Value(dayKey(date)), context: Value(detail)));
      } else {
        sessionId = await db.into(db.sessions).insert(SessionsCompanion.insert(
            date: dayKey(date),
            type: SessionType.otro,
            totalSec: const Value(0),
            mode: const Value('test'),
            context: Value(detail)));
      }
      final id = editId ??
          await db.into(db.fitnessTestAttempts).insert(
              FitnessTestAttemptsCompanion.insert(
                  date: dayKey(date),
                  round: round,
                  part: part.name,
                  protocolId: protocol.name,
                  scheme: scheme,
                  blockStart:
                      Value(blockStart == null ? null : dayKey(blockStart)),
                  sessionId: Value(sessionId)));
      if (editId != null) {
        await (db.update(db.fitnessTestAttempts)..where((t) => t.id.equals(id)))
            .write(FitnessTestAttemptsCompanion(
                date: Value(dayKey(date)), sessionId: Value(sessionId)));
        await (db.delete(db.fitnessTests)..where((t) => t.attemptId.equals(id)))
            .go();
      }
      for (final r in results) {
        final condition = normalized[r.item];
        await db.into(db.fitnessTests).insert(FitnessTestsCompanion.insert(
            date: dayKey(date),
            round: round,
            item: r.item,
            side: Value(r.side),
            value: r.value,
            clean: Value(r.clean),
            attemptId: Value(id),
            conditions: Value(condition),
            baselineKey:
                Value(testBaselineKey(protocol, r.item, r.side, condition)),
            limitedBy: Value(testLimits.containsKey(r.limitedBy) ? r.limitedBy : null)));
      }
      // Plan 052: las no hechas quedan pendientes con su motivo; medirlas
      // en este mismo intento las quita.
      await (db.delete(db.fitnessTestPending)
            ..where((t) => t.attemptId.equals(id)))
          .go();
      for (final p in pending) {
        if (results.any((r) => r.item == p.item) ||
            !allowed.containsKey(p.item) ||
            p.reason.trim().isEmpty) {
          continue;
        }
        await db.into(db.fitnessTestPending).insert(
            FitnessTestPendingCompanion.insert(
                attemptId: id,
                item: p.item,
                reason: p.reason.trim(),
                requires: Value(p.requires.isEmpty ? null : p.requires.join(','))),
            mode: InsertMode.insertOrReplace);
      }
      return id;
    });
  }
}
