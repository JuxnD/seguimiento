import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/daily_routines.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart';
import '../../domain/test_protocol.dart';
import '../../domain/readiness.dart';
import '../../domain/leg_chain.dart' show chainLegExercises;
import '../database.dart';
import 'coach_repository.dart';
import 'exercise_repository.dart';
import 'plan_repository.dart';
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
/// Lo que la semana reorganizada pide a un día (plan 052, §16.27).
enum TestWeekRole {
  none,

  /// Día anterior al test de piernas (o su día nominal ya vacío): sólo
  /// movilidad y recuperación, sin carga de piernas.
  legsMobility,

  /// Día del test movido: FIFA 11+ → test + benchmarks → piernas corta. La
  /// sesión propia del día se descarta.
  legsTest,

  /// Día del test con escaleras 3–4: isométricos y benchmarks; el test pasa
  /// a la siguiente sesión de piernas.
  legsKneeIsometrics,

  /// Viernes tras el test: recibe la sesión que el test desplazó, sin
  /// piernas.
  displacedSession,

  /// Día anterior al test que no es de piernas: su sesión sin carga de
  /// piernas.
  noLegLoad,
}

class TestWeekDay {
  const TestWeekDay(this.role,
      {this.round,
      this.legsPlanned,
      this.legsDate,
      this.legsEffective,
      this.donor,
      this.reason});

  final TestWeekRole role;
  final int? round;
  final DateTime? legsPlanned, legsDate, legsEffective, donor;

  /// Por qué se reorganizó la semana; null en la semana nominal.
  final String? reason;

  bool get reorganized => reason != null;
}

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
      TestScheduleKey key, List<TestMove> movements,
      {bool kneePush = true}) async {
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
        await _priorProtocolTorsoDate(key) ??
        await _anyCompleteTorsoBefore(date);
    if (torso != null) {
      final earliest = addDays(torso, 2);
      if (earliest.isAfter(date)) date = earliest;
    }
    return _legsSafeDate(date, planned, kneePush: kneePush);
  }

  /// Plan 052 (§16.27): piernas nunca cae dentro de las 48 h siguientes a un
  /// partido (jugado o del plan) y, con escaleras 3–4 anotadas ese día, pasa
  /// a la siguiente sesión de piernas (mismo día de la semana que el
  /// nominal). Sólo lectura: no guarda movimientos.
  Future<DateTime> _legsSafeDate(DateTime date, DateTime planned,
      {required bool kneePush}) async {
    var d = date;
    for (var guard = 0; guard < 6; guard++) {
      if (kneePush) {
        final stairs = (await RecoveryRepository(db).morningOn(d))?.kneeStairs;
        if (stairs != null && stairs >= 3 && stairs <= 4) {
          d = _nextWeekday(d, planned.weekday);
          continue;
        }
      }
      if (await _footballWithin48h(d)) {
        d = _nextWeekday(d, planned.weekday);
        continue;
      }
      break;
    }
    return d;
  }

  static DateTime _nextWeekday(DateTime from, int weekday) {
    final ahead = (weekday - from.weekday) % 7;
    return addDays(from, ahead == 0 ? 7 : ahead);
  }

  Future<bool> _footballWithin48h(DateTime day) async {
    final games = await (db.select(db.footballGames)
          ..where((t) => t.date.isBetweenValues(
              dayKey(addDays(day, -2)), dayKey(addDays(day, -1)))))
        .get();
    if (games.isNotEmpty) return true;
    // Sin registro manda el plan: un partido previsto también protege piernas.
    final plan = PlanRepository(db, ExerciseRepository(db));
    for (final back in [1, 2]) {
      if ((await plan.dayFor(addDays(day, -back)))?.day.type == DayType.futbol) {
        return true;
      }
    }
    return false;
  }

  /// Plan 052 (§16.27, reorganizar la semana cuando se mueve un test): qué le
  /// toca a `date` si el test de piernas de su semana quedó en otra fecha. La
  /// semana nominal devuelve [TestWeekRole.none] y no cambia nada.
  Future<TestWeekDay> testWeekDay(DateTime date,
      {required String scheme,
      required DateTime blockStart,
      required TestProtocolId protocol}) async {
    final d = dateOnly(date);
    final s = dateOnly(blockStart);
    final plan = PlanRepository(db, ExerciseRepository(db));
    Future<bool> training(DateTime x) async =>
        (await plan.dayFor(x))?.day.type.isTraining ?? false;
    Future<bool> legsDay(DateTime x) async {
      final day = (await plan.dayFor(x))?.day;
      if (day == null) return false;
      if (day.type == DayType.piernas) return true;
      final legs = day.exercises.where((e) => chainLegExercises.contains(e.name));
      return day.exercises.isNotEmpty && legs.length * 2 >= day.exercises.length;
    }
    for (final round in [1, 2, 3]) {
      final planned = plannedTestDate(s, round, TestPart.piernas);
      final plannedTorso = plannedTestDate(s, round, TestPart.torso);
      if (planned == null || plannedTorso == null) continue;
      // El Test3 tiene piernas antes que torso: conserva su orden propio.
      if (plannedTorso.isAfter(planned)) continue;
      final key = TestScheduleKey(
          scheme: scheme,
          blockStart: s,
          protocolId: protocol,
          round: round,
          part: TestPart.piernas);
      final done = await moves(s, round, TestPart.piernas, key: key);
      final scheduled = (await _resolvedTestDate(key, done, kneePush: false))!;
      if (scheduled == planned) continue;
      final week = weekAnchor(planned);
      if (d.isBefore(week) || d.isAfter(addDays(scheduled, 1))) continue;
      final effective = (await _resolvedTestDate(key, done))!;
      final torso = await currentTestDate(s, round, TestPart.torso,
          key: TestScheduleKey(
              scheme: scheme,
              blockStart: s,
              protocolId: protocol,
              round: round,
              part: TestPart.torso));
      final why = done.isNotEmpty
          ? 'movido por recuperación'
          : torso != null && !addDays(torso, 2).isBefore(scheduled)
              ? 'para llegar descansado tras el test de torso del ${weekdayShort(torso.weekday).toLowerCase()} ${formatShort(torso)}'
              : 'a más de 48 h del partido';
      final reason =
          'Test $round de piernas: del ${weekdayShort(planned.weekday).toLowerCase()} ${formatShort(planned)} pasa al ${weekdayShort(scheduled.weekday).toLowerCase()} ${formatShort(scheduled)}, $why.'
          '${effective == scheduled ? '' : ' Con escaleras 3–4 ese día, va el ${weekdayShort(effective.weekday).toLowerCase()} ${formatShort(effective)} dentro de la sesión de piernas.'}';
      // En un día de piernas el test va dentro de su sesión, como en la
      // semana nominal; en otro día lo reemplaza con la sesión corta.
      final onLegsDay = await legsDay(scheduled);
      TestWeekRole role = TestWeekRole.none;
      DateTime? donor;
      if (d == scheduled) {
        role = effective != scheduled
            ? TestWeekRole.legsKneeIsometrics
            : onLegsDay
                ? TestWeekRole.none
                : TestWeekRole.legsTest;
      } else if (d == addDays(scheduled, -1) && await training(d)) {
        role = await legsDay(d)
            ? TestWeekRole.legsMobility
            : TestWeekRole.noLegLoad;
      } else if (!onLegsDay &&
          d == addDays(scheduled, 1) &&
          d.weekday == DateTime.friday &&
          await training(d) &&
          await training(scheduled)) {
        role = TestWeekRole.displacedSession;
        donor = scheduled;
      }
      return TestWeekDay(role,
          round: round,
          legsPlanned: planned,
          legsDate: scheduled,
          legsEffective: effective,
          donor: donor,
          reason: reason);
    }
    return const TestWeekDay(TestWeekRole.none);
  }

  /// Plan 052 (reporte del owner del 14 oct: torso completo el martes y
  /// piernas seguía el miércoles): el descanso entre torso y piernas depende
  /// del esfuerzo real, no de con qué identidad se guardó. Un torso completo
  /// según su propio protocolo y ronda, guardado en los 6 días anteriores a
  /// piernas, separa piernas aunque venga de otro bloque, de otro protocolo o
  /// del botón de Cuerpo sin agenda. Sólo mueve la fecha: no completa este
  /// test ni comparte marcas, dosis o identidad. Parciales y legados sin
  /// cabecera no cuentan.
  Future<DateTime?> _anyCompleteTorsoBefore(DateTime legs) async {
    final from = addDays(legs, -6);
    // Pocas filas; la fecha se interpreta igual que en el resto del resolver.
    final headers = await (db.select(db.fitnessTestAttempts)
          ..where((t) => t.part.equals(TestPart.torso.name)))
        .get();
    DateTime? latest;
    for (final header in headers) {
      final date = recordedTestDate(header.date);
      final protocol = TestProtocolId.values
          .where((p) => p.name == header.protocolId)
          .firstOrNull;
      if (date == null || protocol == null) continue;
      if (date.isBefore(from) || !date.isBefore(legs)) continue;
      final rows = await (db.select(db.fitnessTests)
            ..where((t) => t.attemptId.equals(header.id)))
          .get();
      if (rows.isEmpty || rows.any((r) => recordedTestDate(r.date) != date)) {
        continue;
      }
      final results = [
        for (final r in rows)
          TestResult(round: r.round, item: r.item, side: r.side, value: r.value)
      ];
      final complete = protocolItems(protocol, TestPart.torso).every(
          (item) => testValue(results, header.round, item.id) != null);
      if (complete && (latest == null || date.isAfter(latest))) latest = date;
    }
    return latest;
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
