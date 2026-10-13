import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/daily_routines.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart';
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

/// Recuperación activa propuesta por la carga (§19.17). Una lectura para Hoy,
/// el aviso de la noche y el informe.
class ReadinessRepository {
  ReadinessRepository(this.db);

  final AppDatabase db;

  /// Lectura del día. `testOrAttemptToday`: hoy toca test o intento.
  Future<ReadinessAdvice> readinessOn(DateTime date, {bool testOrAttemptToday = false}) async {
    final d0 = dateOnly(date);
    final key = dayKey(d0);
    final load = await CoachRepository(db).loadItems(d0);
    final morning = await RecoveryRepository(db).morningOn(d0);
    // Escaleras: la molestia de rodilla anotada hoy. Un 0 no se guarda, así
    // que sin fila es "sin dato", no 0: responder dolor o enfermo no dice nada
    // de la rodilla. El campo propio de escaleras llega con 034.
    final sore = await (db.select(db.sorenessLogs)..where((t) => t.date.equals(key) & t.zone.equals('Rodilla')))
        .getSingleOrNull();
    final stairs = sore?.level;
    final hrRows = await (db.select(db.morningChecks)
          ..where((t) => t.date.isSmallerThanValue(key) & t.restingHr.isNotNull())
          ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)])
          ..limit(readinessHrBaseMax))
        .get();
    final sleep = await (db.select(db.sleepLogs)..where((t) => t.date.equals(key))).getSingleOrNull();
    return readiness(ReadinessInput(
      today: d0,
      load: load,
      stairs: stairs,
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
  Future<void> trainAnyway(DateTime date, ReadinessAdvice advice, {DateTime? now}) {
    final today = dayKey(dateOnly(now ?? DateTime.now()));
    return db.into(db.coachProposals).insertOnConflictUpdate(CoachProposalsCompanion.insert(
          id: _decisionId(date),
          kind: readinessProposalKind,
          status: 'rechazada',
          evidence: jsonEncode({'level': advice.level.name, 'reasons': advice.reasons, 'missing': advice.missing}),
          createdOn: dayKey(dateOnly(date)),
          decidedOn: Value(today),
        ));
  }

  /// ¿Se eligió entrenar igual ese día?
  Future<bool> trainedAnyway(DateTime date) async =>
      (await (db.select(db.coachProposals)..where((t) => t.id.equals(_decisionId(date)))).getSingleOrNull())?.status ==
      'rechazada';

  /// Se guardó la recuperación activa ese día (la aceptación es la sesión
  /// guardada, no abrir la rutina).
  Future<bool> recoveryDone(DateTime date) async =>
      (await (db.select(db.sessions)
                ..where((t) =>
                    t.date.equals(dayKey(dateOnly(date))) &
                    t.type.equalsValue(SessionType.movilidad) &
                    t.mode.equals(recoveryActiveId)))
              .get())
          .isNotEmpty;

  /// Rutinas diarias guardadas ese día (ids de `daily_routines.dart`).
  Future<Set<String>> routinesOn(DateTime date) async {
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.date.equals(dayKey(dateOnly(date))) &
              t.type.equalsValue(SessionType.movilidad) &
              t.mode.isIn(dailyRoutineIds.toList())))
        .get();
    return {for (final r in rows) r.mode!};
  }

  /// Días seguidos con alguna rutina diaria (Activa, Suelta o recuperación),
  /// hasta hoy; hoy sin rutina todavía no rompe.
  Future<int> mobilityStreak(DateTime today) async {
    final rows = await (db.select(db.sessions)
          ..where((t) => t.type.equalsValue(SessionType.movilidad) & t.mode.isIn(dailyRoutineIds.toList())))
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

  String _movePrefix(DateTime start, int round, TestPart part) =>
      '$testMoveProposalKind:${dayKey(dateOnly(start))}:$round:${part.name}:';

  /// Movimientos de un test de un plan (el v3.1 que empezó `start`), en orden.
  Future<List<TestMove>> moves(DateTime start, int round, TestPart part) async {
    final prefix = _movePrefix(start, round, part);
    final rows = await (db.select(db.coachProposals)
          ..where((t) => t.kind.equals(testMoveProposalKind) & t.id.like('$prefix%'))
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

  /// Día que le toca ahora a ese test: el del calendario o el del último
  /// movimiento.
  Future<DateTime?> currentTestDate(DateTime start, int round, TestPart part) async {
    final done = await moves(start, round, part);
    if (done.isNotEmpty) return done.last.to;
    final s = dateOnly(start);
    for (var i = 0; i < 70; i++) {
      final d = addDays(s, i);
      final t = scheduledTest(s, d);
      if (t?.round == round && t?.part == part) return d;
    }
    return null;
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
  }) =>
      db.transaction(() async {
        final done = await moves(start, round, part);
        if (done.length >= maxTestMoves) return null;
        final current = await currentTestDate(start, round, part);
        if (current == null || current != dateOnly(from)) {
          throw ArgumentError('El test $round (${part.name}) no toca el ${dayKey(dateOnly(from))}');
        }
        final to = addDays(current, 1);
        await db.into(db.coachProposals).insert(CoachProposalsCompanion.insert(
              id: '${_movePrefix(start, round, part)}${done.length + 1}',
              kind: testMoveProposalKind,
              status: 'aceptada',
              evidence: jsonEncode({
                'start': dayKey(dateOnly(start)),
                'round': round,
                'part': part.name,
                'from': dayKey(current),
                'reasons': reasons,
              }),
              createdOn: dayKey(current),
              decidedOn: Value(dayKey(dateOnly(now ?? DateTime.now()))),
              reviewAfter: Value(dayKey(to)),
            ));
        return to;
      });

  /// El test que toca `date` en el v3.1 que empezó `start`, con los
  /// movimientos de ese plan aplicados. `moves`: veces que ya se movió.
  Future<({int round, TestPart part, int moves})?> effectiveScheduledTest(DateTime start, DateTime date) async {
    final s = dateOnly(start);
    final d = dateOnly(date);
    final planned = scheduledTest(s, d);
    if (planned != null && (await moves(s, planned.round, planned.part)).isEmpty) {
      return (round: planned.round, part: planned.part, moves: 0);
    }
    // Un test de este plan movido a este día (manda su último movimiento).
    final rows = await (db.select(db.coachProposals)
          ..where((t) => t.kind.equals(testMoveProposalKind) & t.id.like('$testMoveProposalKind:${dayKey(s)}:%'))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    final last = <String, TestMove>{};
    for (final r in rows) {
      final m = _move(r);
      last['${m.round}:${m.part.name}'] = m;
    }
    for (final m in last.values) {
      if (m.to != d) continue;
      return (round: m.round, part: m.part, moves: (await moves(s, m.round, m.part)).length);
    }
    return null;
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
