import 'package:drift/drift.dart';

import '../../domain/core_ladders.dart';
import '../../domain/dates.dart';
import '../../domain/plan_v3.dart' show v31Scheme;
import '../database.dart';

/// Peldaño actual de cada escalera de core (§19.10).
class LadderState {
  const LadderState({required this.ladder, required this.step, required this.since, this.lumbarOn});

  final CoreLadder ladder;
  final int step;
  final DateTime since;
  final DateTime? lumbarOn;

  LadderStep get current => ladder.stepAt(step);
}

class LadderRepository {
  LadderRepository(this.db);

  final AppDatabase db;

  /// Sin registro, peldaño 1 desde el primer lunes del v3.1 (o desde hoy si
  /// aún no hay v3.1).
  Future<LadderState> state(CoreLadder ladder, {DateTime? today}) async {
    final row = await (db.select(db.ladderStates)..where((t) => t.ladder.equals(ladder.id))).getSingleOrNull();
    if (row != null) {
      return LadderState(
        ladder: ladder,
        step: row.step.clamp(1, ladder.top),
        since: parseDay(row.since),
        lumbarOn: row.lumbarOn == null ? null : parseDay(row.lumbarOn!),
      );
    }
    final first = await (db.select(db.planVersions)
          ..where((t) => t.scheme.equals(v31Scheme))
          ..orderBy([(t) => OrderingTerm(expression: t.validFrom)])
          ..limit(1))
        .getSingleOrNull();
    return LadderState(
      ladder: ladder,
      step: 1,
      since: first == null ? dateOnly(today ?? DateTime.now()) : parseDay(first.validFrom),
    );
  }

  Future<void> _write(CoreLadder ladder, int step, DateTime since, DateTime? lumbarOn) =>
      db.into(db.ladderStates).insertOnConflictUpdate(LadderStatesCompanion.insert(
            ladder: ladder.id,
            step: step.clamp(1, ladder.top),
            since: dayKey(since),
            lumbarOn: Value(lumbarOn == null ? null : dayKey(lumbarOn)),
          ));

  /// Sube un peldaño (lo confirma el usuario).
  Future<int> stepUp(CoreLadder ladder, DateTime date) async {
    final s = await state(ladder, today: date);
    final next = (s.step + 1).clamp(1, ladder.top);
    await _write(ladder, next, date, s.lumbarOn);
    return next;
  }

  /// Molestia lumbar: baja un peldaño y esa sesión no cuenta como limpia. En
  /// el peldaño 1 se queda, pero la cuenta de semanas vuelve a empezar.
  Future<int> lumbar(CoreLadder ladder, DateTime date) async {
    final s = await state(ladder, today: date);
    final down = (s.step - 1).clamp(1, ladder.top);
    await _write(ladder, down, date, date);
    return down;
  }

  /// Elegir el peldaño a mano (p. ej. tras el test: el primero cuyo criterio
  /// no se cumple).
  Future<void> setStep(CoreLadder ladder, int step, DateTime date) async {
    final s = await state(ladder, today: date);
    await _write(ladder, step, date, s.lumbarOn);
  }

  /// Sesiones del peldaño actual con sus series de la escalera (y el hollow
  /// del peldaño 1), desde que se llegó al peldaño y sin el día de la
  /// molestia lumbar. Lo importado no cuenta.
  Future<List<LadderSession>> sessions(LadderState s) async {
    final step = s.current;
    final names = {step.exercise, for (final g in step.goals) g.exercise};
    final rows = await (db.select(db.sessionSets).join([
      innerJoin(db.sessions, db.sessions.id.equalsExp(db.sessionSets.sessionId)),
      innerJoin(db.exercises, db.exercises.id.equalsExp(db.sessionSets.exerciseId)),
    ])
          ..where(db.exercises.name.isIn(names) &
              db.sessions.date.isBiggerOrEqualValue(dayKey(s.since)) &
              db.sessions.imported.equals(false))
          ..orderBy([OrderingTerm(expression: db.sessionSets.setIndex)]))
        .get();
    final bySession = <int, (DateTime, Map<String, List<int>>)>{};
    for (final r in rows) {
      final session = r.readTable(db.sessions);
      final date = parseDay(session.date);
      if (s.lumbarOn != null && !date.isAfter(s.lumbarOn!)) continue;
      final entry = bySession.putIfAbsent(session.id, () => (date, <String, List<int>>{}));
      entry.$2.putIfAbsent(r.readTable(db.exercises).name, () => []).add(r.readTable(db.sessionSets).reps);
    }
    return [
      for (final (date, sets) in bySession.values)
        if (sets.containsKey(step.exercise)) LadderSession(date: date, sets: sets),
    ];
  }

  Future<LadderAdvice> advice(CoreLadder ladder, DateTime today) async {
    final s = await state(ladder, today: today);
    return ladderAdvice(ladder, s.step, s.since, await sessions(s), today);
  }
}
