import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/daily_routines.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart';
import '../../domain/test_protocol.dart';
import '../../domain/readiness.dart';
import '../database.dart';
import 'coach_repository.dart';
import 'recovery_repository.dart';

/// Tipo de decisión en `coach_proposals` para "Entrenar igual" (§19.17).
const readinessProposalKind = 'recuperacion';

/// Tipo de decisión en `coach_proposals` para un test movido (§19.17).
const testMoveProposalKind = 'mover_test';

/// Veces que un mismo test puede moverse; después se propone su versión
/// ligera (solo los 6 principales).
const maxTestMoves = 2;

/// Un test movido: conserva su identidad (plan, ronda y parte) y de dónde a
/// dónde.
class TestMove {
  const TestMove({
    required this.start,
    required this.round,
    required this.part,
    required this.from,
    required this.to,
    required this.reasons,
  });

  /// Lunes de inicio del v3.1 al que pertenece el test.
  final DateTime start;
  final int round;
  final TestPart part;
  final DateTime from;
  final DateTime to;
  final List<String> reasons;
}

/// Si el test de ese día se puede hacer.
enum TestDayStatus {
  /// Se hace.
  ready,

  /// Piernas sin escaleras anotadas ese día: se hace sólo si salen ≤ 2.
  stairsUnknown,

  /// Piernas con escaleras > 2: ese día no se hace (§19.16).
  stairsHigh,

  /// El rojo de 032 manda: descanso, sin test.
  rest,
}

class TestDayGate {
  const TestDayGate(this.status, {this.kneeStairs});
  final TestDayStatus status;
  final int? kneeStairs;

  /// Lo que se dice de ese día en avisos e informe; null = se hace.
  String? get label => switch (status) {
        TestDayStatus.ready => null,
        TestDayStatus.stairsUnknown =>
          'sólo si las escaleras salen ≤ 2 al despertar; si no, se mueve',
        TestDayStatus.stairsHigh =>
          'escaleras $kneeStairs/10: ese día no se hace el test de piernas',
        TestDayStatus.rest => 'toca descanso: el test no se hace',
      };
}

/// Un test de la agenda efectiva: su identidad, el día previsto y el de ahora.
class EffectiveTest {
  const EffectiveTest({
    required this.key,
    required this.planned,
    required this.date,
    required this.moves,
    this.gate,
  });

  final TestScheduleKey key;
  final DateTime planned;
  final DateTime date;
  final int moves;

  /// null cuando se leyó sin mirar el día.
  final TestDayGate? gate;

  int get round => key.round;
  TestPart get part => key.part;
  bool get moved => moves > 0;
  bool get canMove => moves < maxTestMoves;

  EffectiveTest withGate(TestDayGate gate) => EffectiveTest(
      key: key, planned: planned, date: date, moves: moves, gate: gate);
}

/// Recuperación activa propuesta por la carga (§19.17). Una lectura para Hoy,
/// el aviso de la noche y el informe.
class ReadinessRepository {
  ReadinessRepository(this.db);

  final AppDatabase db;

  /// Lectura del día. `testOrAttemptToday`: hoy toca test o intento.
  Future<ReadinessAdvice> readinessOn(DateTime date,
      {bool testOrAttemptToday = false}) async {
    final d0 = dateOnly(date);
    final key = dayKey(d0);
    final load = await CoachRepository(db).loadItems(d0);
    final morning = await RecoveryRepository(db).morningOn(d0);
    // Datos independientes: escaleras tiene respuesta nullable propia.
    final sore = await (db.select(db.sorenessLogs)
          ..where((t) => t.date.equals(key) & t.zone.equals('Rodilla')))
        .getSingleOrNull();
    final stairs = morning?.kneeStairs;
    final hrRows = await (db.select(db.morningChecks)
          ..where(
              (t) => t.date.isSmallerThanValue(key) & t.restingHr.isNotNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
          ])
          ..limit(readinessHrBaseMax))
        .get();
    final sleep = await (db.select(db.sleepLogs)
          ..where((t) => t.date.equals(key)))
        .getSingleOrNull();
    return readiness(ReadinessInput(
      today: d0,
      load: load,
      stairs: stairs,
      kneeSoreness: sore?.level,
      muscleSoreness: morning?.muscleSoreness,
      ill: morning?.ill,
      restingHrToday: morning?.restingHr,
      restingHrBaseline: [for (final r in hrRows) r.restingHr!],
      sleepHours: sleep?.hours,
      testOrAttemptToday: testOrAttemptToday,
    ));
  }

  /// Aviso de la noche (22:00) para mañana; null si la carga no lo pide.
  Future<String?> eveningNotice(DateTime date) async =>
      readinessEveningNotice(await CoachRepository(db).loadItems(date), date);

  // ---------- Decisiones ----------

  String _decisionId(DateTime date) => '$readinessProposalKind:${dayKey(date)}';

  /// "Entrenar igual": se guarda con la fecha y las razones que se vieron.
  Future<void> trainAnyway(DateTime date, ReadinessAdvice advice,
      {DateTime? now}) {
    final today = dayKey(dateOnly(now ?? DateTime.now()));
    return db
        .into(db.coachProposals)
        .insertOnConflictUpdate(CoachProposalsCompanion.insert(
          id: _decisionId(date),
          kind: readinessProposalKind,
          status: 'rechazada',
          evidence: jsonEncode({
            'level': advice.level.name,
            'reasons': advice.reasons,
            'missing': advice.missing
          }),
          createdOn: dayKey(dateOnly(date)),
          decidedOn: Value(today),
        ));
  }

  /// ¿Se eligió entrenar igual ese día?
  Future<bool> trainedAnyway(DateTime date) async =>
      (await (db.select(db.coachProposals)
                ..where((t) => t.id.equals(_decisionId(date))))
              .getSingleOrNull())
          ?.status ==
      'rechazada';

  /// Se guardó la recuperación activa **completa** ese día. La aceptación es
  /// la sesión terminada, no abrir la rutina ni guardarla a medias: una
  /// parcial queda registrada pero Hoy sigue proponiendo recuperar.
  Future<bool> recoveryDone(DateTime date) async =>
      (await (db.select(db.sessions)
                ..where((t) =>
                    t.date.equals(dayKey(dateOnly(date))) &
                    t.type.equalsValue(SessionType.movilidad) &
                    t.mode.equals(recoveryActiveId) &
                    t.incomplete.equals(false)))
              .get())
          .isNotEmpty;

  /// Rutinas diarias terminadas ese día (ids de `daily_routines.dart`). Las
  /// guardadas a medias no cuentan: ni ✓ ni silencian el aviso.
  Future<Set<String>> routinesOn(DateTime date) async {
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.date.equals(dayKey(dateOnly(date))) &
              t.type.equalsValue(SessionType.movilidad) &
              t.mode.isIn(dailyRoutineIds.toList()) &
              t.incomplete.equals(false)))
        .get();
    return {for (final r in rows) r.mode!};
  }

  /// Días seguidos con alguna rutina diaria terminada (Activa, Suelta o
  /// recuperación), hasta hoy; hoy sin rutina todavía no rompe.
  Future<int> mobilityStreak(DateTime today) async {
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.type.equalsValue(SessionType.movilidad) &
              t.mode.isIn(dailyRoutineIds.toList()) &
              t.incomplete.equals(false)))
        .get();
    final days = {for (final r in rows) r.date};
    var streak = 0;
    var day = dateOnly(today);
    if (!days.contains(dayKey(day))) day = addDays(day, -1);
    while (days.contains(dayKey(day))) {
      streak++;
      day = addDays(day, -1);
    }
    return streak;
  }

  // ---------- Tests movidos ----------

  /// Prefijo de los movimientos de un test. El v3.1 (12 pruebas) usa siempre
  /// el prefijo de antes, con o sin clave tipada: así sus movimientos viejos y
  /// los nuevos son una sola historia. Otro protocolo usa su clave completa
  /// (esquema, inicio, protocolo, ronda y parte) y nunca lee los de antes.
  String _movePrefix(DateTime start, int round, TestPart part,
          [TestScheduleKey? key]) =>
      key == null || key.protocolId == TestProtocolId.v31_12
          ? '$testMoveProposalKind:${dayKey(dateOnly(key?.blockStart ?? start))}:'
              '${key?.round ?? round}:${(key?.part ?? part).name}:'
          : key.prefix;

  /// Movimientos de un test de un plan (el v3.1 que empezó `start`), en orden.
  Future<List<TestMove>> moves(DateTime start, int round, TestPart part,
      {TestScheduleKey? key}) async {
    final prefix = _movePrefix(start, round, part, key);
    final rows = await (db.select(db.coachProposals)
          ..where((t) =>
              t.kind.equals(testMoveProposalKind) & t.id.like('$prefix%'))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    return [for (final r in rows) _move(r)];
  }

  TestMove _move(CoachProposalRow r) {
    final e = jsonDecode(r.evidence) as Map<String, Object?>;
    return TestMove(
      start: parseDay(e['start']! as String),
      round: e['round']! as int,
      part: TestPart.values.byName(e['part']! as String),
      from: parseDay(e['from']! as String),
      to: parseDay(r.reviewAfter!),
      reasons: (e['reasons'] as List? ?? const []).cast<String>(),
    );
  }

  /// Día del calendario de ese test, sin movimientos.
  DateTime? plannedTestDate(DateTime start, int round, TestPart part) {
    final s = dateOnly(start);
    for (var i = 0; i < 70; i++) {
      final d = addDays(s, i);
      final t = scheduledTest(s, d);
      if (t?.round == round && t?.part == part) return d;
    }
    return null;
  }

  /// Fecha real completa del último intento de esta identidad. Los legados
  /// sin cabecera/bloque o fecha válida siguen desconocidos: no se les asigna
  /// arbitrariamente un bloque ni se mezclan intentos para completar un test.
  Future<DateTime?> _completedTestDate(TestScheduleKey key) async {
    final header = await (db.select(db.fitnessTestAttempts)
          ..where((t) =>
              t.scheme.equals(key.scheme) &
              t.blockStart.equals(dayKey(key.blockStart)) &
              t.protocolId.equals(key.protocolId.name) &
              t.round.equals(key.round) &
              t.part.equals(key.part.name))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
    if (header == null) return _legacyCompletedTestDate(key);
    final date = recordedTestDate(header.date);
    if (date == null) return null;
    final rows = await (db.select(db.fitnessTests)
          ..where((t) => t.attemptId.equals(header.id)))
        .get();
    if (rows.any((r) => recordedTestDate(r.date) != date)) return null;
    final results = [
      for (final r in rows)
        TestResult(round: r.round, item: r.item, side: r.side, value: r.value)
    ];
    return protocolItems(key.protocolId, key.part)
            .every((item) => testValue(results, key.round, item.id) != null)
        ? date
        : null;
  }

  /// Inferencia de calendario para resultados v3.1 anteriores a las cabeceras.
  /// Exige una sola fecha completa dentro de la ventana de esta ronda y que
  /// el plan vigente ese día sea exactamente este bloque. No crea atribución
  /// persistida ni combina días/lados de otras mediciones. Sin evidencia,
  /// devuelve desconocido y conserva el calendario nominal.
  Future<DateTime?> _legacyCompletedTestDate(TestScheduleKey key) async {
    if (key.protocolId != TestProtocolId.v31_12 || key.scheme != 'v3.1') {
      return null;
    }
    final items = protocolItems(key.protocolId, key.part);
    final rows = await (db.select(db.fitnessTests)
          ..where((t) =>
              t.attemptId.isNull() &
              t.round.equals(key.round) &
              t.item.isIn(items.map((item) => item.id))))
        .get();
    if (rows.isEmpty) return null;
    final dates = rows.map((r) => recordedTestDate(r.date)).toSet();
    if (dates.length != 1 || dates.single == null) return null;
    final date = dates.single!;
    final nominal = plannedTestDate(key.blockStart, key.round, key.part);
    final next = key.round < 3
        ? plannedTestDate(key.blockStart, key.round + 1, TestPart.torso)
        : addDays(key.blockStart, 70);
    if (nominal == null ||
        next == null ||
        date.isBefore(nominal) ||
        !date.isBefore(next)) return null;
    final active = await (db.select(db.planVersions)
          ..where((t) => t.validFrom.isSmallerOrEqualValue(dayKey(date)))
          ..orderBy([
            (t) => OrderingTerm.desc(t.validFrom),
            (t) => OrderingTerm.desc(t.id)
          ])
          ..limit(1))
        .getSingleOrNull();
    if (active?.scheme != key.scheme ||
        active?.validFrom != dayKey(key.blockStart)) {
      return null;
    }
    final results = [
      for (final r in rows)
        TestResult(round: r.round, item: r.item, side: r.side, value: r.value)
    ];
    return items.every((item) => testValue(results, key.round, item.id) != null)
        ? date
        : null;
  }

  /// Fecha efectiva común: conserva movimientos explícitos y, para piernas
  /// pendientes, al menos dos días de calendario desde el torso completo real.
  /// No adelanta el calendario nominal ni modifica resultados/movimientos.
  Future<DateTime?> _resolvedTestDate(
      TestScheduleKey key, List<TestMove> movements) async {
    final planned = plannedTestDate(key.blockStart, key.round, key.part);
    if (planned == null) return null;
    var date = movements.isEmpty ? planned : movements.last.to;
    if (key.part != TestPart.piernas || await _completedTestDate(key) != null) {
      return date;
    }
    final plannedTorso =
        plannedTestDate(key.blockStart, key.round, TestPart.torso);
    // El Test3 tiene piernas antes del torso: conserva su orden propio.
    if (plannedTorso == null || plannedTorso.isAfter(planned)) {
      return date;
    }
    final torso = await _completedTestDate(TestScheduleKey(
            scheme: key.scheme,
            blockStart: key.blockStart,
            protocolId: key.protocolId,
            round: key.round,
            part: TestPart.torso)) ??
        await _priorProtocolTorsoDate(key);
    if (torso != null) {
      final earliest = addDays(torso, 2);
      if (earliest.isAfter(date)) date = earliest;
    }
    return date;
  }

  /// Transición explícita 31→32 en la primera semana: la fecha del torso12
  /// previo sólo determina descanso de calendario. No completa torso13 ni
  /// comparte marcas, dosis o identidad de resultados entre protocolos.
  Future<DateTime?> _priorProtocolTorsoDate(TestScheduleKey key) async {
    if (key.protocolId != TestProtocolId.v32_13 ||
        key.scheme != 'v3.2' ||
        key.round != 1) return null;
    final date = await _completedTestDate(TestScheduleKey(
        scheme: 'v3.1',
        blockStart: key.blockStart,
        protocolId: TestProtocolId.v31_12,
        round: 1,
        part: TestPart.torso));
    if (date == null ||
        date.isBefore(key.blockStart) ||
        !date.isBefore(addDays(key.blockStart, 7))) return null;
    final versions = await (db.select(db.planVersions)
          ..orderBy([
            (t) => OrderingTerm(expression: t.validFrom),
            (t) => OrderingTerm(expression: t.id)
          ]))
        .get();
    final origin =
        versions.where((v) => !parseDay(v.validFrom).isAfter(date)).lastOrNull;
    if (origin == null ||
        origin.scheme != 'v3.1' ||
        origin.validFrom != dayKey(key.blockStart)) return null;
    final target = versions
        .where((v) =>
            v.scheme == key.scheme &&
            parseDay(v.validFrom).isAfter(date) &&
            !parseDay(v.validFrom).isBefore(key.blockStart) &&
            parseDay(v.validFrom).isBefore(addDays(key.blockStart, 7)))
        .firstOrNull;
    if (target == null) return null;
    return date;
  }

  /// Día que le toca ahora a ese test, con la misma resolución que la agenda.
  Future<DateTime?> currentTestDate(DateTime start, int round, TestPart part,
      {TestScheduleKey? key}) async {
    final done = await moves(start, round, part, key: key);
    return _resolvedTestDate(
        key ??
            TestScheduleKey(
                scheme: 'v3.1',
                blockStart: dateOnly(start),
                protocolId: TestProtocolId.v31_12,
                round: round,
                part: part),
        done);
  }

  /// Mueve el test al día siguiente de `from`, que tiene que ser el día que
  /// le toca ahora: no se mueve una fecha cualquiera ni se repite un
  /// movimiento. null si ya se movió 2 veces: entonces toca la versión
  /// ligera, no otro aplazamiento.
  Future<DateTime?> moveTest({
    required DateTime start,
    required int round,
    required TestPart part,
    required DateTime from,
    required List<String> reasons,
    DateTime? now,
    TestScheduleKey? key,
  }) =>
      db.transaction(() async {
        final done = await moves(start, round, part, key: key);
        if (done.length >= maxTestMoves) return null;
        final current = await currentTestDate(start, round, part, key: key);
        if (current == null || current != dateOnly(from)) {
          throw ArgumentError(
              'El test $round (${part.name}) no toca el ${dayKey(dateOnly(from))}');
        }
        final to = addDays(current, 1);
        await db.into(db.coachProposals).insert(CoachProposalsCompanion.insert(
              id: '${_movePrefix(start, round, part, key)}${done.length + 1}',
              kind: testMoveProposalKind,
              status: 'aceptada',
              evidence: jsonEncode({
                'start': dayKey(dateOnly(key?.blockStart ?? start)),
                'round': round,
                'part': part.name,
                'from': dayKey(current),
                'reasons': reasons,
                if (key != null) 'scheme': key.scheme,
                if (key != null) 'protocol': key.protocolId.name,
              }),
              createdOn: dayKey(current),
              decidedOn: Value(dayKey(dateOnly(now ?? DateTime.now()))),
              reviewAfter: Value(dayKey(to)),
            ));
        return to;
      });

  /// El test que toca `date` en el v3.1 que empezó `start`, con los
  /// movimientos de ese plan aplicados. `moves`: veces que ya se movió.
  Future<({int round, TestPart part, int moves})?> effectiveScheduledTest(
      DateTime start, DateTime date,
      {String scheme = 'v3.1',
      TestProtocolId protocol = TestProtocolId.v31_12}) async {
    final t = await effectiveTestOn(date,
        scheme: scheme, blockStart: start, protocol: protocol, gate: false);
    return t == null ? null : (round: t.round, part: t.part, moves: t.moves);
  }

  /// El test prioritario de `date`, o null: más movimientos primero.
  /// La agenda conserva las otras identidades del mismo día; no las aplaza.
  /// Con `gate`, si el test seleccionado se puede hacer ese día.
  Future<EffectiveTest?> effectiveTestOn(DateTime date,
      {required String scheme,
      required DateTime blockStart,
      required TestProtocolId protocol,
      bool gate = true}) async {
    final t = (await testAgenda(
            scheme: scheme,
            blockStart: blockStart,
            protocol: protocol,
            gates: false))
        .where((t) => t.date == dateOnly(date))
        .firstOrNull;
    if (t == null || !gate) return t;
    return t.withGate(await _gate(t.part, t.date));
  }

  /// La agenda efectiva de los tests de un bloque: los de cada ronda y parte,
  /// con su día previsto, el de ahora y cuántas veces se movieron. La misma
  /// lectura para Hoy, los recordatorios y el informe. Con `gates`, cada test
  /// lleva si ese día se puede hacer: el descanso de 032 manda, y el de
  /// piernas sólo se hace con escaleras ≤ 2 anotadas (§19.16, §16.26.7).
  Future<List<EffectiveTest>> testAgenda({
    required String scheme,
    required DateTime blockStart,
    required TestProtocolId protocol,
    bool gates = true,
  }) async {
    final s = dateOnly(blockStart);
    final out = <EffectiveTest>[];
    for (final round in [1, 2, 3]) {
      for (final part in TestPart.values) {
        final key = TestScheduleKey(
            scheme: scheme,
            blockStart: s,
            protocolId: protocol,
            round: round,
            part: part);
        final planned = plannedTestDate(s, round, part);
        if (planned == null) continue;
        final done = await moves(s, round, part, key: key);
        final date = (await _resolvedTestDate(key, done))!;
        out.add(EffectiveTest(
          key: key,
          planned: planned,
          date: date,
          moves: done.length,
          gate: gates ? await _gate(part, date) : null,
        ));
      }
    }
    // Orden compartido: el selector diario prioriza el test más movido.
    // Una fecha compartida no elimina ninguna identidad de la agenda.
    out.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : b.moves.compareTo(a.moves);
    });
    return out;
  }

  Future<TestDayGate> _gate(TestPart part, DateTime date) async {
    final advice = await readinessOn(date, testOrAttemptToday: true);
    if (advice.action == SuggestedAction.restOnly) {
      return const TestDayGate(TestDayStatus.rest);
    }
    if (part == TestPart.torso) return const TestDayGate(TestDayStatus.ready);
    final stairs = (await RecoveryRepository(db).morningOn(date))?.kneeStairs;
    return TestDayGate(
        stairs == null
            ? TestDayStatus.stairsUnknown
            : stairs <= 2
                ? TestDayStatus.ready
                : TestDayStatus.stairsHigh,
        kneeStairs: stairs);
  }

  // ---------- Informe ----------

  Future<ReadinessWeek> week(DateTime from, DateTime to) async {
    final days = <(DateTime, ReadinessAdvice)>[];
    var accepted = 0;
    var anyway = 0;
    var maxLoad = 0;
    ReadinessAdvice? last;
    for (var d = dateOnly(from); !d.isAfter(dateOnly(to)); d = addDays(d, 1)) {
      final a = await readinessOn(d);
      last = a;
      if (a.load3Days > maxLoad) maxLoad = a.load3Days;
      if (a.level == ReadinessLevel.green) continue;
      days.add((d, a));
      if (await recoveryDone(d)) accepted++;
      if (await trainedAnyway(d)) anyway++;
    }
    return ReadinessWeek(
      proposed: days.length,
      accepted: accepted,
      trainedAnyway: anyway,
      days: days,
      maxLoad3Days: maxLoad,
      acuteChronic: last?.acuteChronic,
    );
  }
}
