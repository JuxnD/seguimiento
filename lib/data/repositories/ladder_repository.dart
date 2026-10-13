import 'package:drift/drift.dart';
import 'dart:convert';

import '../../domain/core_ladders.dart';
import '../../domain/dates.dart';
import '../../domain/plan_v3.dart' show v31Scheme;
import '../../domain/plan_v32.dart';
import 'fitness_test_repository.dart';
import '../../domain/series_side_proof.dart';
import '../../domain/ladder_prescription_proof.dart';
import '../../domain/accessory_quality_proof.dart';
import '../../domain/daily_routines.dart' show dailyRoutineIds;
import '../../domain/fitness_test.dart' show recordedTestDate;
import '../database.dart';
import '../../domain/adaptive_coach.dart' show ProposalStatus, ladderProposalId;
import 'goal_repository.dart';

/// Peldaño actual de cada escalera de core (§19.10).
class LadderState {
  const LadderState(
      {required this.ladder,
      required this.step,
      required this.since,
      this.lumbarOn,
      this.sessionsAfter = 0,
      this.epoch = 0});

  final CoreLadder ladder;
  final int step;
  final DateTime since;
  final DateTime? lumbarOn;
  final int sessionsAfter;
  final int epoch;
  String get identity => '$step:$epoch';

  LadderStep get current => ladder.stepAt(step);
}

class LadderRepository {
  LadderRepository(this.db);

  final AppDatabase db;

  Stream<Map<String, LadderAdvice>> watchAdvice(DateTime today,
          {bool ringsAvailable = false}) =>
      db
          .customSelect(
            'SELECT 1',
            readsFrom: {
              db.sessions,
              db.sessionSets,
              db.exercises,
              db.ladderStates,
              db.ladderEvents,
              db.planVersions,
              db.coachProposals
            },
          )
          .watch()
          .asyncMap((_) async => {
                for (final l in await activeLadders(today))
                  l.id: await advice(l, today, ringsAvailable: ringsAvailable)
              });

  Future<List<CoreLadder>> activeLadders(DateTime date) async {
    final plan = await (db.select(db.planVersions)
          ..where((t) => t.validFrom.isSmallerOrEqualValue(dayKey(date)))
          ..orderBy([
            (t) => OrderingTerm.desc(t.validFrom),
            (t) => OrderingTerm.desc(t.id)
          ])
          ..limit(1))
        .getSingleOrNull();
    return plan?.scheme == v32Scheme ? allLadders : coreLadders;
  }

  /// Sin registro, peldaño 1 desde el primer lunes del v3.1 (o desde hoy si
  /// aún no hay v3.1).
  Future<LadderState> state(CoreLadder ladder, {DateTime? today}) async {
    final row = await (db.select(db.ladderStates)
          ..where((t) => t.ladder.equals(ladder.id)))
        .getSingleOrNull();
    if (row != null) {
      return LadderState(
        ladder: ladder,
        step: row.step.clamp(ladder.bottom, ladder.top),
        since: parseDay(row.since),
        lumbarOn: row.lumbarOn == null ? null : parseDay(row.lumbarOn!),
        sessionsAfter: row.sessionsAfter,
        epoch: row.epoch,
      );
    }
    final first = await (db.select(db.planVersions)
          ..where((t) => t.scheme.equals(
              ladder.id == 'reverse_plank' || ladder.accessory
                  ? v32Scheme
                  : v31Scheme))
          ..orderBy([(t) => OrderingTerm(expression: t.validFrom)])
          ..limit(1))
        .getSingleOrNull();
    var initial = 1;
    if (ladder.id == 'reverse_plank') {
      final repo = FitnessTestRepository(db);
      final attempts = (await repo.attempts())
          .where(
              (a) => a.scheme == v32Scheme && a.blockStart == first?.validFrom)
          .map((a) => a.id)
          .toSet();
      final observed = (await repo.all())
          .where((r) =>
              attempts.contains(r.attemptId) &&
              r.item == 'reverse_plank_forearm' &&
              r.protocolId == 'v32_13' &&
              r.clean &&
              r.value.isFinite &&
              r.value > 0 &&
              r.date != null &&
              !r.date!.isAfter(dateOnly(today ?? DateTime.now())))
          .toList()
        ..sort((a, b) => b.date!.compareTo(a.date!));
      if (observed.isNotEmpty && observed.first.value > 90) initial = 2;
    }
    return LadderState(
      ladder: ladder,
      step: initial,
      since: first == null
          ? dateOnly(today ?? DateTime.now())
          : parseDay(first.validFrom),
    );
  }

  Future<void> _write(
      CoreLadder ladder, int step, DateTime since, DateTime? lumbarOn) async {
    final previous = await state(ladder, today: since);
    final boundary = await db
        .customSelect('SELECT COALESCE(MAX(id),0) AS n FROM sessions')
        .getSingle();
    await db
        .into(db.ladderStates)
        .insertOnConflictUpdate(LadderStatesCompanion.insert(
          ladder: ladder.id,
          step: step.clamp(ladder.bottom, ladder.top),
          since: dayKey(since),
          lumbarOn: Value(lumbarOn == null ? null : dayKey(lumbarOn)),
          sessionsAfter: Value(boundary.read<int>('n')),
          epoch: Value(previous.epoch + 1),
        ));
  }

  /// Sube un peldaño (lo confirma el usuario).
  Future<int> stepUp(CoreLadder ladder, DateTime date) =>
      db.transaction(() async {
        final s = await state(ladder, today: date);
        if (!(await advice(ladder, date)).canStepUp) return s.step;
        final next = (s.step + 1).clamp(ladder.bottom, ladder.top);
        await _write(ladder, next, date, s.lumbarOn);
        return next;
      });

  /// "Subir a…" como una sola decisión (plan 009, R2): registra la
  /// aceptación de la propuesta de ese peldaño y sube, en la misma
  /// transacción. Si algo falla en medio no queda aceptación sin peldaño; un
  /// segundo toque ya no ve la propuesta (otro peldaño) y no sube dos.
  /// `beforeStep` sólo existe para inyectar un fallo en pruebas.
  Future<int> acceptStepUp(CoreLadder ladder, DateTime date,
          {Future<void> Function()? beforeStep, bool ringsAvailable = false}) =>
      db.transaction(() async {
        final s = await state(ladder, today: date);
        final a = await advice(ladder, date, ringsAvailable: ringsAvailable);
        if (!a.canStepUp) return s.step;
        final since = addDays(dateOnly(date), -a.daysOnStep);
        await GoalRepository(db).decideProposal(
            ladderProposalId(ladder.id, a.step.step, since),
            'escalera:${ladder.id}',
            ProposalStatus.aceptada,
            today: date);
        if (beforeStep != null) await beforeStep();
        final next = (s.step + 1).clamp(ladder.bottom, ladder.top);
        await _write(ladder, next, date, s.lumbarOn);
        return next;
      });

  /// Molestia lumbar: baja un peldaño y esa sesión no cuenta como limpia. En
  /// el peldaño 1 se queda, pero la cuenta de semanas vuelve a empezar.
  Future<int> lumbar(CoreLadder ladder, DateTime date, {String? eventKey}) =>
      db.transaction(() async {
        // El mismo incidente sigue siendo uno tras reabrir la pantalla/app.
        final key = eventKey ?? 'manual:${dayKey(date)}';
        final previous = await (db.select(db.ladderEvents)
              ..where(
                  (t) => t.eventKey.equals(key) & t.ladder.equals(ladder.id)))
            .getSingleOrNull();
        if (previous != null) return previous.step;
        final s = await state(ladder, today: date);
        final down = (s.step - 1).clamp(ladder.bottom, ladder.top);
        await _write(ladder, down, date, date);
        await db.into(db.ladderEvents).insert(LadderEventsCompanion.insert(
            eventKey: key, ladder: ladder.id, date: dayKey(date), step: down));
        return down;
      });

  Future<List<String>> lumbarFor(String eventKey) async => [
        for (final r in await (db.select(db.ladderEvents)
              ..where((t) => t.eventKey.equals(eventKey)))
            .get())
          r.ladder,
      ];

  Future<int> accessoryAlarm(CoreLadder ladder, String alarm, DateTime date,
          {required String eventKey}) =>
      db.transaction(() async {
        const allowed = AccessoryQualityProof.alarmsByLadder;
        if (!ladder.accessory || allowed[ladder.id] != alarm) {
          throw const FormatException('Señal no pertinente');
        }
        final key = 'accessoryAlarm:$alarm:${dayKey(date)}:$eventKey';
        final previous = await (db.select(db.ladderEvents)
              ..where(
                  (t) => t.eventKey.equals(key) & t.ladder.equals(ladder.id)))
            .getSingleOrNull();
        if (previous != null) return previous.step;
        final s = await state(ladder, today: date);
        final next = alarm == 'groin_over_3'
            ? (s.step - 1).clamp(ladder.bottom, ladder.top)
            : s.step;
        if (alarm == 'groin_over_3') {
          await _write(ladder, next, date, s.lumbarOn);
        }
        await db.into(db.ladderEvents).insert(LadderEventsCompanion.insert(
            eventKey: key, ladder: ladder.id, date: dayKey(date), step: next));
        return next;
      });

  /// Elegir el peldaño a mano (p. ej. tras el test: el primero cuyo criterio
  /// no se cumple).
  Future<void> setStep(CoreLadder ladder, int step, DateTime date) =>
      db.transaction(() async {
        final s = await state(ladder, today: date);
        await _write(ladder, step, date, s.lumbarOn);
      });

  /// Sesiones del peldaño actual con sus series de la escalera (y el hollow
  /// del peldaño 1), desde que se llegó al peldaño y sin el día de la
  /// molestia lumbar. Lo importado no cuenta.
  Future<List<LadderSession>> sessions(LadderState s, {DateTime? asOf}) async {
    final step = s.current;
    final names = {step.exercise, for (final g in step.goals) g.exercise};
    final rows = await (db.select(db.sessionSets).join([
      innerJoin(
          db.sessions, db.sessions.id.equalsExp(db.sessionSets.sessionId)),
      innerJoin(
          db.exercises, db.exercises.id.equalsExp(db.sessionSets.exerciseId)),
    ])
          ..where(db.exercises.name.isIn(names) &
              db.sessions.id.isBiggerThanValue(s.sessionsAfter) &
              db.sessions.imported.equals(false))
          ..orderBy([OrderingTerm(expression: db.sessionSets.setIndex)]))
        .get();
    final bySession = <int, (DateTime?, Map<String, List<int>>)>{};
    final sideBySession = <int, Map<String, List<String?>>>{};
    final rirBySession = <int, Map<String, List<int?>>>{};
    final accessoryQualified = <int>{};
    final invalidSessions = <int>{};
    final targetSessions = <int>{};
    final prescriptions = <int, ({int sets, int minimum, bool perSide})>{};
    for (final r in rows) {
      final session = r.readTable(db.sessions);
      if (s.ladder.accessory && dailyRoutineIds.contains(session.mode)) {
        continue;
      }
      final date = recordedTestDate(session.date);
      if (date != null &&
          (date.isBefore(s.since) ||
              date.isAfter(dateOnly(asOf ?? DateTime.now())))) continue;
      if (date != null && s.lumbarOn != null && !date.isAfter(s.lumbarOn!)) {
        continue;
      }
      var invalidMetadata = false;
      Map<String, String>? epochs;
      if (session.coreEpochs != null) {
        try {
          epochs =
              (jsonDecode(session.coreEpochs!) as Map).cast<String, String>();
          if (epochs.containsKey(s.ladder.id) &&
              epochs[s.ladder.id] != s.identity) continue;
        } catch (_) {
          invalidMetadata = true;
        }
      }
      final entry = bySession.putIfAbsent(
          session.id, () => (date, <String, List<int>>{}));
      final quality = AccessoryQualityProof.decode(
          epochs?[AccessoryQualityProof.key(s.ladder.id)]);
      final achillesChecked = quality?.achillesCheckedDate;
      if (s.ladder.accessory &&
          quality?.identity == s.identity &&
          quality?.variantConfirmed == true &&
          (s.ladder.alarm == null || quality?.alarmFree == true) &&
          (s.ladder.id != 'seated_soleus' ||
              (date != null &&
                  achillesChecked != null &&
                  achillesChecked.isAfter(date) &&
                  !achillesChecked
                      .isAfter(dateOnly(asOf ?? DateTime.now())))) &&
          quality?.alarm == null &&
          (step.pauseSec == null || quality?.pause2Confirmed == true) &&
          (!step.relaxed || quality?.relaxed == true)) {
        accessoryQualified.add(session.id);
      }
      final prescription = LadderPrescriptionProof.decode(
          epochs?[LadderPrescriptionProof.key(s.ladder.id)], s.identity);
      if (prescription != null) prescriptions[session.id] = prescription;
      if (epochs?[s.ladder.id] == s.identity ||
          r.readTable(db.exercises).name == step.exercise) {
        targetSessions.add(session.id);
      }
      if (invalidSessions.contains(session.id) ||
          date == null ||
          invalidMetadata ||
          session.context?.contains('Molestia lumbar: ${s.ladder.id}') ==
              true ||
          session.techniqueOk != true ||
          session.fullRange != true ||
          session.recoveryOk != true ||
          session.incomplete ||
          session.pendingReview ||
          r.readTable(db.sessionSets).split ||
          r.readTable(db.sessionSets).toFailure) {
        entry.$2[step.exercise] = <int>[];
        invalidSessions.add(session.id);
        continue;
      }
      final exercise = r.readTable(db.exercises).name;
      final set = r.readTable(db.sessionSets);
      entry.$2.putIfAbsent(exercise, () => []).add(set.reps);
      rirBySession
          .putIfAbsent(session.id, () => {})
          .putIfAbsent(exercise, () => [])
          .add(set.rir);
      final proof =
          SeriesSideProof.decode(epochs?[SeriesSideProof.key(exercise)]);
      sideBySession
          .putIfAbsent(session.id, () => {})
          .putIfAbsent(exercise, () => [])
          .add(proof == null || set.setIndex < 1 || set.setIndex > proof.length
              ? null
              : proof[set.setIndex - 1]);
    }
    return [
      for (final entry in bySession.entries)
        if (targetSessions.contains(entry.key))
          LadderSession(
              date: entry.value.$1,
              sets: entry.value.$2,
              sessionId: entry.key,
              sides: sideBySession[entry.key] ?? const {},
              rirs: rirBySession[entry.key] ?? const {},
              accessoryQualified: accessoryQualified.contains(entry.key) &&
                  !invalidSessions.contains(entry.key),
              maintenance: !invalidSessions.contains(entry.key) &&
                  (!s.ladder.accessory ||
                      accessoryQualified.contains(entry.key)) &&
                  _completedMaintenance(
                      prescriptions[entry.key],
                      entry.value.$2[step.exercise],
                      sideBySession[entry.key]?[step.exercise])),
    ];
  }

  bool _completedMaintenance(({int sets, int minimum, bool perSide})? p,
      List<int>? values, List<String?>? sides) {
    if (p == null ||
        values == null ||
        values.length != p.sets * (p.perSide ? 2 : 1) ||
        values.any((v) => v < p.minimum)) return false;
    if (!p.perSide) return true;
    return sides != null &&
        sides.length == values.length &&
        ['I', 'D']
            .every((side) => sides.where((s) => s == side).length == p.sets);
  }

  Future<LadderAdvice> advice(CoreLadder ladder, DateTime today,
      {bool ringsAvailable = false}) async {
    final s = await state(ladder, today: today);
    final result = ladderAdvice(
        ladder, s.step, s.since, await sessions(s, asOf: today), today);
    if (ladder.id == 'support_hold' &&
        s.step == 2 &&
        !ringsAvailable &&
        result.canStepUp) {
      return LadderAdvice(
          step: result.step,
          daysOnStep: result.daysOnStep,
          cleanInARow: result.cleanInARow,
          canStepUp: false,
          nextStepBlockedReason:
              'Criterio cumplido; mantén protracción hasta confirmar anillas disponibles en Plan.');
    }
    if (ladder.id == 'support_hold' && s.step == 3 && !ringsAvailable) {
      return LadderAdvice(
          step: result.step,
          daysOnStep: result.daysOnStep,
          cleanInARow: result.cleanInARow,
          canStepUp: false,
          nextStepBlockedReason:
              'Nivel3 histórico conservado; anillas no confirmadas. Revisa el equipo en Plan o elige empezar sin ese bloque.');
    }
    return result;
  }
}
