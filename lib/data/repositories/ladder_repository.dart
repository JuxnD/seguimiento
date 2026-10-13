import 'package:drift/drift.dart';
import 'dart:convert';

import '../../domain/core_ladders.dart';
import '../../domain/dates.dart';
import '../../domain/plan_v3.dart' show v31Scheme;
import '../../domain/plan_v32.dart';
import 'fitness_test_repository.dart';
import 'plan_repository.dart';
import 'exercise_repository.dart';
import '../../domain/series_side_proof.dart';
import '../../domain/ladder_prescription_proof.dart';
import '../../domain/accessory_quality_proof.dart';
import '../../domain/daily_routines.dart' show dailyRoutineIds;
import '../../domain/fitness_test.dart' show recordedTestDate;
import '../../domain/test_protocol.dart';
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
          ..where((t) => ladder.id == 'reverse_plank' || ladder.accessory
              ? t.scheme.equals(v32Scheme)
              : t.scheme.isIn([v31Scheme, v32Scheme]))
          ..orderBy([(t) => OrderingTerm(expression: t.validFrom)])
          ..limit(1))
        .getSingleOrNull();
    var initial = 1;
    if (ladder.id == 'reverse_plank' && first != null) {
      final observed = await FitnessTestRepository(db).latestMeasurement(
          item: 'reverse_plank_forearm',
          scheme: v32Scheme,
          blockStart: weekAnchor(parseDay(first.validFrom)),
          protocol: TestProtocolId.v32_13,
          asOf: dateOnly(today ?? DateTime.now()));
      if (observed != null && observed.value > 90) initial = 2;
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
    final deloadCompanions = <int, Map<String, Object?>>{};
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
      final rawPrescription = epochs?[LadderPrescriptionProof.key(s.ladder.id)];
      var prescription =
          LadderPrescriptionProof.decode(rawPrescription, s.identity);
      if (prescription == null && date != null && rawPrescription != null) {
        final plan = await (db.select(db.planVersions)
              ..where((t) => t.validFrom.isSmallerOrEqualValue(dayKey(date)))
              ..orderBy([
                (t) => OrderingTerm.desc(t.validFrom),
                (t) => OrderingTerm.desc(t.id)
              ])
              ..limit(1))
            .getSingleOrNull();
        if (plan?.scheme == v32Scheme) {
          final expected = await _expectedDeload(s, date);
          if (expected != null) {
            prescription = LadderPrescriptionProof.decodeDeload(
                rawPrescription, s.identity,
                sessionDate: date,
                blockStart: dayKey(
                    await PlanRepository(db, ExerciseRepository(db))
                        .schemeStart(plan!)),
                physicalVariant:
                    step.physicalVariantKey ?? 'base:${step.exercise}',
                perSide: step.perSide,
                expectedSets: expected.sets,
                expectedMinimum: expected.minimum,
                expectedCompanions: expected.companions);
            if (prescription != null) {
              deloadCompanions[session.id] = expected.companions;
            }
          }
        }
      }
      if (rawPrescription != null && prescription == null) {
        invalidMetadata =
            true; // un tag desconocido/corrupto no acredita un intento.
      }
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
    for (final id in deloadCompanions.keys) {
      final entry = bySession[id];
      final matches = entry != null &&
          _completedMaintenance(prescriptions[id], entry.$2[step.exercise],
              sideBySession[id]?[step.exercise]) &&
          _completedDeloadCompanions(
              deloadCompanions[id], entry.$2, sideBySession[id]);
      if (!matches) {
        invalidSessions.add(id);
        if (entry != null) {
          entry.$2[step.exercise] = <int>[];
        }
      }
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
                  _completedDeloadCompanions(deloadCompanions[entry.key],
                      entry.value.$2, sideBySession[entry.key]) &&
                  (step.rir == null ||
                      !deloadCompanions.containsKey(entry.key) ||
                      (rirBySession[entry.key]?[step.exercise]
                              ?.every((r) => r != null && r <= step.rir!) ==
                          true)) &&
                  _completedMaintenance(
                      prescriptions[entry.key],
                      entry.value.$2[step.exercise],
                      sideBySession[entry.key]?[step.exercise])),
    ];
  }

  /// Deriva la dosis esperada del plan persistido + peldaño compartido;
  /// un tag con una dosis arbitrariamente menor no neutraliza un fallo.
  Future<({int sets, int minimum, Map<String, Object?> companions})?>
      _expectedDeload(LadderState s, DateTime date) async {
    final view = await PlanRepository(db, ExerciseRepository(db)).dayFor(date);
    if (view == null || view.scheme != v32Scheme) return null;
    final step = s.current, id = s.ladder.id;
    int? sets, minimum;
    if (s.ladder.accessory) {
      final base =
          view.day.exercises.where((e) => e.name == step.exercise).firstOrNull;
      if (id == 'support_hold') {
        if (![DateTime.tuesday, DateTime.thursday].contains(date.weekday)) {
          return null;
        }
        sets = date.weekday == DateTime.thursday ? 2 : 3;
        minimum = date.weekday == DateTime.thursday ? 30 : 20;
      } else {
        if (base == null) return null;
        sets = id == 'flying_sprint' ? step.sets : base.sets;
        minimum = base.holdSecMin ?? base.repsMin;
        if (id == 'copenhagen') minimum = step.step == 1 ? 12 : 5;
      }
    } else {
      if (date.weekday != s.ladder.weekday &&
          !(id == 'reverse_plank' && date.weekday == DateTime.friday)) {
        return null;
      }
      sets = id == 'reverse_plank' && date.weekday == DateTime.friday
          ? 2
          : step.sets;
      minimum = step.holdMin ?? step.repsMin;
      if (id == 'reverse_plank' && step.step == 1 && view.validFrom != null) {
        final observed = await FitnessTestRepository(db).latestMeasurement(
            item: 'reverse_plank_forearm',
            scheme: v32Scheme,
            blockStart: view.validFrom!,
            protocol: TestProtocolId.v32_13,
            asOf: date);
        if (observed != null && observed.value > 0 && observed.value <= 90) {
          minimum = (observed.value * .5).round();
        }
      }
    }
    if (sets == null || minimum == null || minimum < 1) return null;
    return (
      sets: (sets + 1) ~/ 2,
      minimum: minimum,
      companions: {
        for (final goal in step.goals.where((g) => g.exercise != step.exercise))
          goal.exercise: {
            'sets': (goal.sets + 1) ~/ 2,
            'minimum': goal.exercise == hollowHold && step.hollowSec != null
                ? 30
                : goal.value,
            'perSide': goal.perSide
          }
      }
    );
  }

  bool _completedDeloadCompanions(Map<String, Object?>? companions,
      Map<String, List<int>> values, Map<String, List<String?>>? sides) {
    if (companions == null) return true; // maintenance/v1 stays unchanged.
    for (final entry in companions.entries) {
      final dose = (entry.value! as Map).cast<String, Object?>();
      if (!_completedMaintenance((
        sets: dose['sets']! as int,
        minimum: dose['minimum']! as int,
        perSide: dose['perSide']! as bool
      ), values[entry.key], sides?[entry.key])) return false;
    }
    return true;
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
