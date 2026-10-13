import 'package:drift/drift.dart';
import 'dart:convert';
import 'package:clock/clock.dart';

import '../../domain/core_ladders.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/plan_v3.dart';
import '../../domain/plan_v32.dart';
import '../../domain/leg_chain.dart';
import '../../domain/progress.dart';
import '../../domain/progress_evidence.dart';
import '../../domain/session_math.dart';
import '../database.dart';
import '../exercise_details.dart' show exercisePurpose;
import '../seed_plan.dart' show plancheBlock;
import '../plan_v32_template.dart' show orderV32Exercises;
import 'exercise_repository.dart';
import 'ladder_repository.dart';
import 'plan_repository.dart';
import 'readiness_repository.dart';
import 'fitness_test_repository.dart';
import '../../domain/test_protocol.dart';
import '../../domain/readiness.dart';
import '../../domain/series_side_proof.dart';
import '../../domain/ladder_prescription_proof.dart';
import '../../domain/accessory_quality_proof.dart';

class SetDraft {
  SetDraft({
    required this.exercise,
    this.reps = 0,
    this.split = false,
    this.splitDetail,
    this.toFailure = false,
    this.loadKg,
    this.variant,
    this.rir,
  });

  String exercise;
  int reps;
  bool split;
  String? splitDetail;
  bool toFailure;

  /// Carga externa (mochila, garrafas). null = peso corporal.
  double? loadKg;

  /// Variante de la progresión ("arquero", "pies elevados"). null = la del plan.
  String? variant;

  /// Repeticiones en reserva (0–5). null = no se anotó.
  int? rir;
}

class SessionDraft {
  SessionDraft({
    this.id,
    required this.date,
    this.startTime,
    this.type = SessionType.circuito,
    this.planDayId,
    this.totalSec = 0,
    this.warmupSec = 0,
    this.cooldownSec = 0,
    this.restSec = 0,
    this.roundsDone,
    this.roundsEstimated = false,
    this.rpe,
    this.limitingExercise,
    this.context,
    this.notes,
    this.techniqueOk,
    this.fullRange,
    this.recoveryOk,
    this.outOfPlan = false,
    this.incomplete = false,
    this.plannedRounds,
    this.pendingReview = false,
    this.mode,
    this.extraReps,
    this.imported = false,
    this.coreEpochs,
    this.sideEvidenceAuthored = false,
    List<SetDraft>? sets,
    List<int>? roundMarksSec,
    List<int>? roundRestSec,
  })  : sets = sets ?? [],
        roundMarksSec = roundMarksSec ?? [],
        roundRestSec = roundRestSec ?? [];

  int? id;
  DateTime date;
  String? startTime;
  SessionType type;
  int? planDayId;
  int totalSec;
  int warmupSec;
  int cooldownSec;

  /// Descansos sumados: van aparte del trabajo neto.
  int restSec;
  int? roundsDone;
  bool roundsEstimated;
  int? rpe;
  String? limitingExercise;
  String? context;
  String? notes;

  /// El tipo registrado no coincide con el plan de ese día.
  bool outOfPlan;

  /// Se cerró antes de completar el plan.
  bool incomplete;
  int? plannedRounds;

  // Condiciones de la regla de progresión (null = sin registrar).
  bool? techniqueOk;
  bool? fullRange;
  bool? recoveryOk;

  /// Guardada sola al terminar el cronómetro; falta revisarla (RPE).
  bool pendingReview;

  /// Resistencia v3: 'cindy', 'tabata' o 'porTiempo'.
  String? mode;

  /// AMRAP: repeticiones de la ronda que quedó a medias.
  int? extraReps;

  /// Del historial anterior a la app (§16.16): editar la conserva.
  bool imported;
  String? coreEpochs;
  bool sideEvidenceAuthored;
  Map<String, List<List<Object?>>>? manualSeriesBaseline;
  final Map<String, String> accessoryCriteriaEdits = {};

  void enterManualEditing() {
    if (sideEvidenceAuthored) manualSeriesBaseline = seriesSignatures(sets);
    sideEvidenceAuthored = false;
  }

  static Map<String, List<List<Object?>>> seriesSignatures(
          List<SetDraft> sets) =>
      {
        for (final name in sets.map((s) => s.exercise).toSet())
          name: [
            for (final s in sets.where((s) => s.exercise == name))
              [
                s.reps,
                s.loadKg,
                s.variant,
                s.rir,
                s.split,
                s.splitDetail,
                s.toFailure
              ]
          ]
      };

  /// En orden de ejecución; el índice de serie se calcula por ejercicio.
  final List<SetDraft> sets;

  /// Marcas acumuladas del contador (s desde el inicio del circuito).
  final List<int> roundMarksSec;

  /// Descanso después de cada ronda, en paralelo a `roundMarksSec`. Vacío si
  /// no se midió (contador libre, sesiones anteriores al esquema 8).
  final List<int> roundRestSec;

  /// Trabajo de cada ronda, sin descansos. null si no hay descansos medidos.
  List<int>? get roundWorkSec => roundWork(roundMarksSec, roundRestSec);

  ProgressionProposal? get progressionEvidence => imported || roundsEstimated
      ? null
      : proposeProgression(
          lastRounds: roundsDone,
          lastPlanned: plannedRounds,
          lastDate: date,
          sessionId: id,
          anySplit: sets.any((s) => s.split),
          anyFailure: sets.any((s) => s.toFailure),
          techniqueOk: techniqueOk,
          fullRange: fullRange,
          recoveryOk: recoveryOk,
          incomplete: incomplete);

  bool get cleanTen =>
      type == SessionType.progresion &&
      (roundsDone ?? 0) >= 10 &&
      progressionEvidence?.canProgress == true;

  /// Only recorded dose and equipment form the comparison protocol. No side
  /// is inferred from set ordering and missing exercises stay unknown.
  String? get exerciseProtocol {
    if (sets.isEmpty) return null;
    final keys = sets
        .map((s) => '${s.exercise}|${s.reps}|${s.variant}|${s.loadKg}')
        .toSet()
        .toList()
      ..sort();
    return keys.join(';');
  }

  /// Trabajo neto: sin calentamiento, enfriamiento ni descansos.
  int get netSec => circuitNetSec(
      totalSec: totalSec,
      warmupSec: warmupSec,
      cooldownSec: cooldownSec,
      restSec: restSec);

  /// Tiempo de circuito con descansos: sobre esto se miden las vueltas.
  int get spanSec => circuitSpanSec(
      totalSec: totalSec, warmupSec: warmupSec, cooldownSec: cooldownSec);
}

/// Fila de lista: sesión con conteos para mostrar sin abrirla.
class SessionSummary {
  SessionSummary(this.row, this.splitSets);

  final SessionRow row;
  final int splitSets;
}

class TrainingRepository {
  TrainingRepository(this.db, this.exercises);

  final AppDatabase db;
  final ExerciseRepository exercises;

  // ---------- Sesiones ----------

  Stream<List<SessionSummary>> watchRecent({int limit = 60}) {
    final splitCount =
        db.sessionSets.id.count(filter: db.sessionSets.split.equals(true));
    final q = db.select(db.sessions).join([
      leftOuterJoin(
          db.sessionSets, db.sessionSets.sessionId.equalsExp(db.sessions.id)),
    ])
      ..addColumns([splitCount])
      ..groupBy([db.sessions.id])
      ..orderBy([
        OrderingTerm(expression: db.sessions.date, mode: OrderingMode.desc),
        OrderingTerm(
            expression: db.sessions.startTime, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows
        .map((r) =>
            SessionSummary(r.readTable(db.sessions), r.read(splitCount) ?? 0))
        .toList());
  }

  Future<int> save(SessionDraft d) => db.transaction(() async {
        final original = d.id == null
            ? null
            : await (db.select(db.sessions)..where((t) => t.id.equals(d.id!)))
                .getSingle();
        final originalMetadata = original?.coreEpochs == null
            ? <String, String>{}
            : (jsonDecode(original!.coreEpochs!) as Map).cast<String, String>();

        var effectiveCoreEpochs = d.coreEpochs;
        if (!d.sideEvidenceAuthored) {
          if (d.id == null) {
            if (effectiveCoreEpochs != null) {
              final metadata = (jsonDecode(effectiveCoreEpochs) as Map)
                  .cast<String, String>();
              if (d.manualSeriesBaseline == null) {
                metadata.removeWhere((key, _) =>
                    key.startsWith(SeriesSideProof.prefix) ||
                    key.startsWith(LadderPrescriptionProof.prefix) ||
                    key.startsWith(AccessoryQualityProof.prefix));
              } else {
                final after = SessionDraft.seriesSignatures(d.sets);
                for (final name in {
                  ...d.manualSeriesBaseline!.keys,
                  ...after.keys
                }) {
                  if (jsonEncode(d.manualSeriesBaseline![name]) ==
                      jsonEncode(after[name])) continue;
                  metadata.remove(SeriesSideProof.key(name));
                  final ladder = ladderOf(name);
                  if (ladder != null) {
                    metadata.remove(LadderPrescriptionProof.key(ladder.id));
                    _invalidateAccessoryProof(metadata, ladder.id);
                  }
                }
              }
              effectiveCoreEpochs =
                  metadata.isEmpty ? null : jsonEncode(metadata);
            }
          } else {
            final previous = await (db.select(db.sessions)
                  ..where((t) => t.id.equals(d.id!)))
                .getSingle();
            effectiveCoreEpochs = previous.coreEpochs;
            if (effectiveCoreEpochs != null) {
              final metadata = (jsonDecode(effectiveCoreEpochs) as Map)
                  .cast<String, String>();
              final before = await (db.select(db.sessionSets)
                    ..where((t) => t.sessionId.equals(d.id!))
                    ..orderBy([(t) => OrderingTerm(expression: t.setIndex)]))
                  .get();
              final names = await exercises.namesById();
              final changedNames = {
                ...before.map((s) => names[s.exerciseId]),
                ...d.sets.map((s) => s.exercise)
              };
              for (final name in changedNames.whereType<String>()) {
                final oldSignature = [
                  for (final s
                      in before.where((s) => names[s.exerciseId] == name))
                    [
                      s.reps,
                      s.loadKg,
                      s.variant,
                      s.rir,
                      s.split,
                      s.splitDetail,
                      s.toFailure
                    ]
                ];
                final newSignature = [
                  for (final s in d.sets.where((s) => s.exercise == name))
                    [
                      s.reps,
                      s.loadKg,
                      s.variant,
                      s.rir,
                      s.split,
                      s.splitDetail,
                      s.toFailure
                    ]
                ];
                if (jsonEncode(oldSignature) != jsonEncode(newSignature)) {
                  metadata.remove(SeriesSideProof.key(name));
                  final ladder = ladderOf(name);
                  if (ladder != null) {
                    metadata.remove(LadderPrescriptionProof.key(ladder.id));
                    _invalidateAccessoryProof(metadata, ladder.id);
                  }
                }
              }
              effectiveCoreEpochs =
                  metadata.isEmpty ? null : jsonEncode(metadata);
            }
          }
        }
        if (d.accessoryCriteriaEdits.isNotEmpty) {
          final metadata = effectiveCoreEpochs == null
              ? <String, String>{}
              : (jsonDecode(effectiveCoreEpochs) as Map).cast<String, String>();
          for (final entry in d.accessoryCriteriaEdits.entries) {
            final ladder = ladderById(entry.key),
                proof = AccessoryQualityProof.decode(entry.value);
            if (ladder?.accessory != true ||
                proof == null ||
                metadata[entry.key] != proof.identity) {
              throw const FormatException(
                  'La evidencia editada no corresponde a la prescripción de origen');
            }
            _validateAccessoryObservation(entry.key, proof, d.date,
                previous: AccessoryQualityProof.decode(
                    originalMetadata[AccessoryQualityProof.key(entry.key)]));
            metadata[AccessoryQualityProof.key(entry.key)] = entry.value;
          }
          effectiveCoreEpochs = jsonEncode(metadata);
        }
        final limitingId =
            (d.limitingExercise == null || d.limitingExercise!.trim().isEmpty)
                ? null
                : await exercises.getOrCreate(d.limitingExercise!);
        final data = SessionsCompanion(
          date: Value(dayKey(d.date)),
          startTime: Value(d.startTime),
          type: Value(d.type),
          planDayId: Value(d.planDayId),
          totalSec: Value(d.totalSec),
          warmupSec: Value(d.warmupSec),
          cooldownSec: Value(d.cooldownSec),
          restSec: Value(d.restSec),
          roundsDone: Value(d.roundsDone),
          roundsEstimated: Value(d.roundsEstimated),
          rpe: Value(d.rpe),
          limitingExerciseId: Value(limitingId),
          context: Value(_blankToNull(d.context)),
          notes: Value(_blankToNull(d.notes)),
          outOfPlan: Value(d.outOfPlan),
          incomplete: Value(d.incomplete),
          plannedRounds: Value(d.plannedRounds),
          techniqueOk: Value(d.techniqueOk),
          fullRange: Value(d.fullRange),
          recoveryOk: Value(d.recoveryOk),
          pendingReview: Value(d.pendingReview),
          mode: Value(d.mode),
          extraReps: Value(d.extraReps),
          imported: Value(d.imported),
          coreEpochs: Value(effectiveCoreEpochs),
        );
        final int id;
        if (d.id == null) {
          id = await db.into(db.sessions).insert(data);
        } else {
          id = d.id!;
          await (db.update(db.sessions)..where((t) => t.id.equals(id)))
              .write(data);
          await (db.delete(db.sessionSets)
                ..where((t) => t.sessionId.equals(id)))
              .go();
          await (db.delete(db.sessionRounds)
                ..where((t) => t.sessionId.equals(id)))
              .go();
        }

        final perExercise = <int, int>{};
        for (final s in d.sets.where((s) => s.exercise.trim().isNotEmpty)) {
          final exId = await exercises.getOrCreate(s.exercise);
          final idx = perExercise[exId] = (perExercise[exId] ?? 0) + 1;
          await db.into(db.sessionSets).insert(SessionSetsCompanion.insert(
                sessionId: id,
                exerciseId: exId,
                setIndex: idx,
                reps: s.reps,
                split: Value(s.split),
                splitDetail:
                    Value(s.split ? _blankToNull(s.splitDetail) : null),
                toFailure: Value(s.toFailure),
                loadKg: Value(s.loadKg),
                variant: Value(_blankToNull(s.variant)),
                rir: Value(s.rir),
              ));
        }
        final work = d.roundWorkSec;
        for (var i = 0; i < d.roundMarksSec.length; i++) {
          await db.into(db.sessionRounds).insert(SessionRoundsCompanion.insert(
                sessionId: id,
                roundIndex: i + 1,
                elapsedSec: d.roundMarksSec[i],
                workSec: Value(work?[i]),
                restSec: Value(work == null ? null : d.roundRestSec[i]),
              ));
        }
        for (final entry in d.accessoryCriteriaEdits.entries) {
          await _recordAccessoryAlarmOnce(
              id, entry.key, AccessoryQualityProof.decode(entry.value)!);
        }
        d.id = id;
        return id;
      });

  Future<SessionDraft> load(int id) async {
    final r = await (db.select(db.sessions)..where((t) => t.id.equals(id)))
        .getSingle();
    final names = await exercises.namesById();
    final sets = await (db.select(db.sessionSets)
          ..where((t) => t.sessionId.equals(id))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    final rounds = await (db.select(db.sessionRounds)
          ..where((t) => t.sessionId.equals(id))
          ..orderBy([(t) => OrderingTerm(expression: t.roundIndex)]))
        .get();
    return SessionDraft(
      id: r.id,
      date: parseDay(r.date),
      startTime: r.startTime,
      type: r.type,
      planDayId: r.planDayId,
      totalSec: r.totalSec,
      warmupSec: r.warmupSec,
      cooldownSec: r.cooldownSec,
      restSec: r.restSec,
      roundsDone: r.roundsDone,
      roundsEstimated: r.roundsEstimated,
      rpe: r.rpe,
      limitingExercise:
          r.limitingExerciseId == null ? null : names[r.limitingExerciseId],
      context: r.context,
      notes: r.notes,
      outOfPlan: r.outOfPlan,
      incomplete: r.incomplete,
      plannedRounds: r.plannedRounds,
      techniqueOk: r.techniqueOk,
      fullRange: r.fullRange,
      recoveryOk: r.recoveryOk,
      pendingReview: r.pendingReview,
      mode: r.mode,
      extraReps: r.extraReps,
      imported: r.imported,
      coreEpochs: r.coreEpochs,
      sets: [
        for (final s in sets)
          SetDraft(
            exercise: names[s.exerciseId] ?? '?',
            reps: s.reps,
            split: s.split,
            splitDetail: s.splitDetail,
            toFailure: s.toFailure,
            loadKg: s.loadKg,
            variant: s.variant,
            rir: s.rir,
          ),
      ],
      roundMarksSec: rounds.map((x) => x.elapsedSec).toList(),
      roundRestSec: rounds.every((x) => x.restSec != null)
          ? rounds.map((x) => x.restSec!).toList()
          : null,
    );
  }

  /// Mejor marca de rondas en circuito, sin contar una sesión concreta
  /// (la recién guardada, para saber si acaba de romper el récord).
  Future<int?> bestRounds({int? excludeSessionId}) async {
    final best = db.sessions.roundsDone.max();
    final query = db.selectOnly(db.sessions)..addColumns([best]);
    query.where(excludeSessionId == null
        ? db.countedCircuitRounds
        : db.countedCircuitRounds &
            db.sessions.id.equals(excludeSessionId).not());
    return query.map((r) => r.read(best)).getSingle();
  }

  /// La sesión anterior del mismo tipo (antes de `date`), con el trabajo de
  /// cada ronda (o sus vueltas, si es anterior al esquema 8), para comparar al
  /// cerrar. null si es la primera.
  Future<(DateTime, int?, List<int>)?> previousOfType(
      SessionType type, DateTime date) async {
    final evidence = await previousTiming(type, date);
    return evidence == null
        ? null
        : (evidence.date, evidence.rounds, evidence.durationsSec);
  }

  Future<RoundTimingEvidence?> previousTiming(SessionType type, DateTime date,
      {int? planDayId, String? mode}) async {
    final row = await (db.select(db.sessions)
          ..where((t) =>
              t.type.equalsValue(type) &
              t.date.isSmallerThanValue(dayKey(date)) &
              t.imported.equals(false) &
              t.roundsEstimated.equals(false) &
              t.incomplete.equals(false) &
              (planDayId == null
                  ? const Constant(true)
                  : t.planDayId.equals(planDayId)) &
              (mode == null ? t.mode.isNull() : t.mode.equals(mode)))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    final rounds = await (db.select(db.sessionRounds)
          ..where((t) => t.sessionId.equals(row.id))
          ..orderBy([(t) => OrderingTerm(expression: t.roundIndex)]))
        .get();
    final measuredWork =
        rounds.isNotEmpty && rounds.every((r) => r.workSec != null);
    final work = measuredWork
        ? rounds.map((r) => r.workSec!).toList()
        : lapDurations(rounds.map((r) => r.elapsedSec).toList());
    final detail = await load(row.id);
    return RoundTimingEvidence(
        sessionId: row.id,
        date: parseDay(row.date),
        type: row.type,
        planDayId: row.planDayId,
        mode: row.mode,
        exerciseProtocol: detail.exerciseProtocol,
        rounds: row.roundsDone,
        basis: measuredWork ? TimingBasis.work : TimingBasis.lap,
        durationsSec: work,
        imported: row.imported,
        estimated: row.roundsEstimated,
        incomplete: row.incomplete);
  }

  /// Últimas rondas hechas antes de una fecha, por tipo de circuito.
  Future<Map<SessionType, int>> lastRoundsBefore(DateTime date) async {
    final out = <SessionType, int>{};
    for (final type in SessionType.values.where((t) => t.isCircuit)) {
      final row = await (db.select(db.sessions)
            ..where((t) =>
                t.date.isSmallerThanValue(dayKey(date)) &
                t.type.equalsValue(type))
            ..where((t) => t.roundsDone.isNotNull())
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();
      if (row?.roundsDone != null) out[type] = row!.roundsDone!;
    }
    return out;
  }

  /// Última sesión de un tipo antes de `date`, completa (con series).
  Future<SessionDraft?> lastOfType(SessionType type, DateTime date) async {
    final row = await (db.select(db.sessions)
          ..where((t) =>
              t.type.equalsValue(type) &
              t.date.isSmallerThanValue(dayKey(date)))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : load(row.id);
  }

  /// Propuesta de la regla de progresión para el intento de `date`, a partir
  /// de la última sesión de progresión anterior. Hoy y el cronómetro leen de
  /// aquí para que la meta sea la misma en las dos pantallas.
  Future<ProgressionProposal?> progressionProposal(DateTime date) async {
    final last = await lastOfType(SessionType.progresion, date);
    return last?.progressionEvidence;
  }

  /// Última sesión de la plantilla/protocolo comparable, excluyendo el ID
  /// editado. Una coincidencia parcial de series no se considera duplicado.
  Future<SessionDraft?> repeatedSetsBefore(SessionDraft draft) async {
    if (draft.sets.isEmpty ||
        draft.sets.any((s) => s.exercise.trim().isEmpty)) {
      return null;
    }
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.type.equalsValue(draft.type) &
              t.date.isSmallerOrEqualValue(dayKey(draft.date)) &
              (draft.id == null
                  ? const Constant(true)
                  : t.id.equals(draft.id!).not()) &
              (draft.mode == null
                  ? t.mode.isNull()
                  : t.mode.equals(draft.mode!)) &
              (draft.planDayId == null
                  ? t.planDayId.isNull()
                  : t.planDayId.equals(draft.planDayId!)))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ]))
        .get();
    for (final row in rows) {
      final previous = await load(row.id);
      final protocol = previous.sets.length == draft.sets.length &&
          List.generate(
              draft.sets.length,
              (i) =>
                  previous.sets[i].exercise.trim() ==
                  draft.sets[i].exercise.trim()).every((same) => same);
      if (draft.planDayId == null && !protocol) continue;
      if (!protocol) return null;
      for (var i = 0; i < draft.sets.length; i++) {
        final a = draft.sets[i], b = previous.sets[i];
        if (a.reps != b.reps ||
            a.loadKg != b.loadKg ||
            a.rir != b.rir ||
            a.split != b.split ||
            a.toFailure != b.toFailure ||
            _blankToNull(a.variant) != _blankToNull(b.variant) ||
            (a.split &&
                _blankToNull(a.splitDetail) != _blankToNull(b.splitDetail))) {
          return null;
        }
      }
      return previous;
    }
    return null;
  }

  /// La marca física no autoriza afirmar un hito de otro programa. Una
  /// sesión guiada desvinculada conserva su guion, pero no se retargetea al
  /// plan del día para acreditar el hito específico del circuito legado.
  Future<bool> v2ProgressionContext(SessionDraft draft,
      {bool requireLink = false}) async {
    if (!draft.cleanTen || (requireLink && draft.planDayId == null)) {
      return false;
    }
    final plan = PlanRepository(db, exercises);
    final view = draft.planDayId == null
        ? await plan.dayFor(draft.date)
        : await plan.dayById(draft.planDayId!);
    return view != null &&
        view.scheme == null &&
        view.day.type == DayType.progresion;
  }

  /// Fecha de la primera progresión de 10 rondas o más que cumplió la regla
  /// de calidad, antes de `before`. Desde el viernes siguiente, el viernes del
  /// v3.1 deja el circuito y alterna Cindy y Tabata (§19.1).
  Future<DateTime?> firstCleanTen(
      {DateTime? before, int? excludeSessionId}) async {
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.type.equalsValue(SessionType.progresion) &
              t.roundsDone.isBiggerOrEqualValue(10) &
              (excludeSessionId == null
                  ? const Constant(true)
                  : t.id.equals(excludeSessionId).not()) &
              (before == null
                  ? const Constant(true)
                  : t.date.isSmallerThanValue(dayKey(before))))
          ..orderBy([(t) => OrderingTerm(expression: t.date)]))
        .get();
    for (final r in rows) {
      final s = await load(r.id);
      if (s.cleanTen) return s.date;
    }
    return null;
  }

  /// Día del bloque (v3 o v3.1) para el día del plan `view`. El viernes del
  /// v3.1 depende de si ya salieron 10 rondas limpias. null fuera del bloque.
  Future<V3Day?> blockDay(PlanDayView? view, DateTime date) async {
    if (view == null || !isBlockScheme(view.scheme) || view.validFrom == null) {
      return null;
    }
    final cleanTen = view.scheme == v31Scheme && date.weekday == DateTime.friday
        ? await firstCleanTen(before: date)
        : null;
    return v3Day(view.validFrom!, date,
        scheme: view.scheme!, cleanTen: cleanTen);
  }

  /// Series del ejercicio en la última sesión de fuerza del mismo día de la
  /// semana antes de `date` (el lunes se compara con el lunes: las dominadas
  /// del lunes van con mochila y las del jueves son supinas). Vacío si no hay.
  Future<List<SetDraft>> lastStrengthSets(
      String exercise, DateTime date) async {
    final exId = await exercises.idOf(exercise);
    if (exId == null) return const [];
    final circuit = SessionType.values
        .where((t) => t.isCircuit || t == SessionType.resistencia)
        .map((t) => t.name);
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.date.isSmallerThanValue(dayKey(date)) & t.type.isNotIn(circuit))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(40))
        .get();
    for (final r
        in rows.where((r) => parseDay(r.date).weekday == date.weekday)) {
      final sets = await (db.select(db.sessionSets)
            ..where((t) => t.sessionId.equals(r.id) & t.exerciseId.equals(exId))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      if (sets.isEmpty) continue;
      return [
        for (final s in sets)
          SetDraft(
              exercise: exercise,
              reps: s.reps,
              loadKg: s.loadKg,
              variant: s.variant,
              rir: s.rir,
              split: s.split,
              splitDetail: s.splitDetail,
              toFailure: s.toFailure),
      ];
    }
    return const [];
  }

  /// Same weekday limits weekly protocol changes; explicit session/plan and
  /// set provenance remain available to the policy instead of being discarded.
  Future<StrengthSessionEvidence?> lastStrengthEvidence(
      String exercise, DateTime date,
      {String? mode}) async {
    final exId = await exercises.idOf(exercise);
    if (exId == null) return null;
    final circuit = SessionType.values
        .where((t) => t.isCircuit || t == SessionType.resistencia)
        .map((t) => t.name);
    final rows = await (db.select(db.sessions)
          ..where((t) =>
              t.date.isSmallerThanValue(dayKey(date)) &
              t.type.isNotIn(circuit) &
              (mode == null ? t.mode.isNull() : t.mode.equals(mode)))
          ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)
          ]))
        .get();
    for (final row
        in rows.where((r) => parseDay(r.date).weekday == date.weekday)) {
      final sets = await (db.select(db.sessionSets)
            ..where(
                (t) => t.sessionId.equals(row.id) & t.exerciseId.equals(exId))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      if (sets.isEmpty) continue;
      return StrengthSessionEvidence(
          sessionId: row.id,
          date: parseDay(row.date),
          type: row.type,
          exercise: exercise,
          planDayId: row.planDayId,
          mode: row.mode,
          incomplete: row.incomplete,
          imported: row.imported,
          sets: [
            for (final s in sets)
              StrengthSetEvidence(
                  reps: s.reps,
                  rir: s.rir,
                  split: s.split,
                  splitDetail: s.splitDetail,
                  toFailure: s.toFailure,
                  loadKg: s.loadKg,
                  variant: s.variant)
          ]);
    }
    return null;
  }

  /// ¿La última inclinación de planche llegó a 3 × 30 s? Entonces entra el
  /// tuck (§19.7).
  Future<bool> plancheTuckReady(DateTime before) async {
    final exId = await exercises.idOf('Inclinación de planche');
    if (exId == null) return false;
    final last = await (db.select(db.sessionSets).join([
      innerJoin(
          db.sessions, db.sessions.id.equalsExp(db.sessionSets.sessionId)),
    ])
          ..where(db.sessionSets.exerciseId.equals(exId) &
              db.sessions.date.isSmallerThanValue(dayKey(before)))
          ..orderBy([
            OrderingTerm(expression: db.sessions.date, mode: OrderingMode.desc)
          ]))
        .get();
    if (last.isEmpty) return false;
    final sessionId = last.first.readTable(db.sessions).id;
    final sets = [
      for (final r in last)
        if (r.readTable(db.sessions).id == sessionId)
          r.readTable(db.sessionSets)
    ];
    return sets.where((s) => s.reps >= 30).length >= 3;
  }

  /// El día con el bloque de planche al inicio, si toca (v3.1, mini
  /// paralelas, martes/jueves/viernes). Igual para empezar y para retomar: el
  /// guion tiene que ser el mismo.
  Future<PlanDayDraft> withPlanche(PlanDayDraft day, DateTime date, V3Day? v3,
      {required bool enabled}) async {
    if (!enabled || v3 == null || !v3.isV31) return day;
    final block = v3.isV32 && date.weekday == DateTime.thursday
        ? <PlanExerciseDraft>[
            PlanExerciseDraft(
                name: 'Muñecas (planche)',
                sets: 1,
                holdSecMin: 120,
                block: 'planche'),
            PlanExerciseDraft(
                name: 'Support hold en paralelas',
                sets: 2,
                holdSecMin: 30,
                block: 'planche',
                physicalVariantKey: 'support_parallels',
                purpose: v32Purposes['Support hold en paralelas']),
          ]
        : plancheBlock(
            weekday: date.weekday,
            deload: v3.reducedVolume,
            tuckReady: await plancheTuckReady(date),
          );
    if (block.isEmpty) return day;
    if (v3.isV32 && date.weekday == DateTime.tuesday) {
      block.add(PlanExerciseDraft(
          name: 'Support hold en paralelas',
          sets: 3,
          holdSecMin: 20,
          holdSecMax: 30,
          block: 'planche',
          physicalVariantKey: 'support_parallels',
          purpose: v32Purposes['Support hold en paralelas']));
    }
    return PlanDayDraft(
      weekday: day.weekday,
      type: day.type,
      targetRounds: day.targetRounds,
      restBetweenRoundsSec: day.restBetweenRoundsSec,
      notes: day.notes,
      exercises: [...block, ...day.exercises],
      coreEpochs: day.coreEpochs,
    );
  }

  /// El día con el peldaño actual de la escalera de core (§19.10): dragon
  /// flag el lunes y V-up el jueves del v3.1. Va antes de lo opcional. En la
  /// descarga, dos series.
  Future<PlanDayDraft> withLadder(
      PlanDayDraft day, DateTime date, V3Day? v3) async {
    if (v3 == null || !v3.isV31) return day;
    final ladder = coreLadders
        .where((l) => l.id != 'reverse_plank' && l.weekday == date.weekday)
        .firstOrNull;
    if (ladder == null) return day;
    final state = await LadderRepository(db).state(ladder, today: date);
    final step = state.current;
    final sets = v3.reducedVolume && !v3.isV32 ? 2 : step.sets;
    final block = [
      PlanExerciseDraft(
        name: step.exercise,
        sets: sets,
        repsMin: step.repsMin,
        repsMax: step.repsMax ?? step.repsMin,
        holdSecMin: step.holdMin,
        holdSecMax: step.holdMax,
        restSec: step.rest,
        restSecMax: step.restMax,
        rirMin: step.rir,
        rirMax: step.rir,
        perSide: step.perSide,
        block: ladderBlock,
        purpose: exercisePurpose(step.exercise),
        notes:
            'Peldaño ${step.step} de ${ladder.top} de la escalera del ${ladder.name}.'
            '${step.notes == null ? '' : ' ${step.notes}'}',
      ),
      if (step.hollowSec case final sec?)
        PlanExerciseDraft(
          name: hollowHold,
          sets: sets,
          holdSecMin: 30,
          holdSecMax: sec,
          restSec: 60,
          block: ladderBlock,
          purpose: exercisePurpose(hollowHold),
          notes: 'Lumbar pegada al suelo. Para subir de peldaño: 3 × $sec s.',
        ),
    ];
    final optional = day.exercises.indexWhere((e) => e.block == 'opcional');
    final at = optional < 0 ? day.exercises.length : optional;
    return PlanDayDraft(
      weekday: day.weekday,
      type: day.type,
      targetRounds: day.targetRounds,
      restBetweenRoundsSec: day.restBetweenRoundsSec,
      notes: day.notes,
      exercises: [
        ...day.exercises.take(at),
        ...block,
        ...day.exercises.skip(at)
      ],
      coreEpochs: {...day.coreEpochs, ladder.id: state.identity},
    );
  }

  /// Los bloques que el v3.1 agrega al día: planche (si hay paralelas) y la
  /// escalera de core. Igual para Hoy, para empezar y para retomar.
  Future<PlanDayDraft> withV31Blocks(PlanDayDraft day, DateTime date, V3Day? v3,
      {required bool planche, bool rings = false}) async {
    var result = await withLadder(
        await withPlanche(day, date, v3, enabled: planche), date, v3);
    if (v3?.isV32 != true) return result;
    final stopped = await (db.select(db.ladderEvents)
          ..where((t) =>
              t.date.equals(dayKey(date)) &
              t.eventKey.like('accessoryAlarm:hamstring_pinch:%')))
        .get();
    result = await withAccessoryLadders(result, date, v3!, rings: rings);
    if (!planche &&
        rings &&
        [DateTime.tuesday, DateTime.thursday].contains(date.weekday)) {
      final support = ladderById('support_hold')!;
      final state = await LadderRepository(db).state(support, today: date);
      if (state.current.physicalVariantKey == 'support_rings') {
        final e = PlanExerciseDraft(
            name: state.current.exercise,
            sets: date.weekday == DateTime.thursday ? 2 : 3,
            holdSecMin: date.weekday == DateTime.thursday ? 30 : 20,
            holdSecMax: 30,
            physicalVariantKey: 'support_rings',
            purpose: exercisePurpose(state.current.exercise));
        result.exercises.add(e);
        result = await withAccessoryLadders(result, date, v3, rings: rings);
      }
    }
    for (final exercise in result.exercises.where((e) =>
        e.name == 'Copenhague' && e.physicalVariantKey == 'copenhagen_short')) {
      exercise.repsMin = v3.week <= 2
          ? 3
          : v3.week <= 4
              ? 7
              : 12;
      exercise.repsMax = v3.week <= 2
          ? 5
          : v3.week <= 4
              ? 10
              : 15;
    }
    if (date.weekday == DateTime.tuesday) {
      final maximum = v3.blockStart == null
          ? null
          : await FitnessTestRepository(db).latestMeasurement(
              item: 'dead_hang',
              scheme: v32Scheme,
              blockStart: v3.blockStart!,
              protocol: TestProtocolId.v32_13,
              asOf: date);
      final dose = maximum != null && maximum.value >= 11
          ? (maximum.value - 10).floor()
          : null;
      final hang = result.exercises
          .where((e) => e.name == 'Colgarse de la barra')
          .firstOrNull;
      if (hang != null && dose != null) {
        hang.holdSecMin = dose;
        hang.holdSecMax = dose;
        hang.notes =
            'Máximo conocido menos 10 s: intento${maximum!.attemptId}, ${dayKey(maximum.date)}.';
      } else if (hang != null) {
        result.exercises.remove(hang);
        result.notes =
            '${result.notes ?? ''} Colgado pendiente: falta un máximo comparable mayor de 10 s; no se inventa duración.';
      }
    }
    if (date.weekday == DateTime.friday) {
      result.targetRounds = maintenanceRounds(v3.week);
    }
    if ([DateTime.thursday, DateTime.friday].contains(date.weekday)) {
      final state =
          await LadderRepository(db).state(reversePlankLadder, today: date);
      final step = state.current;
      final maximum = v3.blockStart == null
          ? null
          : await FitnessTestRepository(db).latestMeasurement(
              item: 'reverse_plank_forearm',
              scheme: v32Scheme,
              blockStart: v3.blockStart!,
              protocol: TestProtocolId.v32_13,
              asOf: date);
      final measuredDose = state.step == 1 &&
          maximum != null &&
          maximum.value > 0 &&
          maximum.value <= 90;
      final holdMin =
          measuredDose ? (maximum.value * .5).round() : step.holdMin;
      final holdMax =
          measuredDose ? (maximum.value * .6).round() : step.holdMax;
      result = PlanDayDraft(
          weekday: result.weekday,
          type: result.type,
          targetRounds: result.targetRounds,
          restBetweenRoundsSec: result.restBetweenRoundsSec,
          notes: result.notes,
          exercises: [
            ...result.exercises,
            PlanExerciseDraft(
                name: step.exercise,
                sets: date.weekday == DateTime.friday ? 2 : step.sets,
                repsMin: step.repsMin,
                repsMax: step.repsMax,
                holdSecMin: holdMin,
                holdSecMax: holdMax,
                perSide: step.perSide,
                restSec: step.rest,
                block: ladderBlock,
                purpose: 'Cadena posterior y control de cadera.',
                notes: measuredDose
                    ? '50–60% del máximo registrado: intento${maximum.attemptId}, ${dayKey(maximum.date)}; condiciones conocidas.'
                    : step.notes)
          ],
          coreEpochs: {
            ...result.coreEpochs,
            reversePlankLadder.id: state.identity,
            if (date.weekday == DateTime.friday)
              LadderPrescriptionProof.key(reversePlankLadder.id):
                  LadderPrescriptionProof.maintenance(
                      identity: state.identity,
                      sets: 2,
                      minimum: holdMin ?? step.repsMin ?? 1,
                      perSide: step.perSide)
          });
    }
    final morning = await (db.select(db.morningChecks)
          ..where((t) => t.date.equals(dayKey(date))))
        .getSingleOrNull();
    final readiness = await ReadinessRepository(db).readinessOn(date);
    if (morning?.kneeStairs == null) {
      result.notes =
          '${result.notes ?? ''} · Escaleras: sin registro, no equivale a0.';
    }
    final mode = kneeTrainingMode(morning?.kneeStairs,
        restOnly: readiness.action == SuggestedAction.restOnly);
    if (mode == KneeTrainingMode.rest) {
      return PlanDayDraft(
          weekday: result.weekday,
          type: DayType.descanso,
          notes: 'Descanso indicado: ${readiness.reasons.join(' · ')}'
              '${stopped.isEmpty ? '' : ' · Pinchazo en isquio confirmado: parar el día.'}');
    }
    if (stopped.isNotEmpty) {
      return PlanDayDraft(
          weekday: day.weekday,
          type: DayType.descanso,
          notes:
              'Pinchazo en isquio confirmado: parar el día. Registro conservado.');
    }
    if (mode == KneeTrainingMode.isometricsOnly) {
      return PlanDayDraft(
          weekday: result.weekday,
          type: DayType.trenSuperior,
          notes: 'Escaleras ≥5: sólo isométricos; avisa al entrenador.',
          exercises: [
            PlanExerciseDraft(
                name: 'Sentadilla isométrica en la pared',
                sets: 5,
                holdSecMin: 45,
                purpose: v32Purposes['Sentadilla isométrica en la pared'])
          ]);
    }
    final recentGames = date.weekday == DateTime.wednesday
        ? await (db.select(db.footballGames)
              ..where((t) => t.date.isBetweenValues(
                  dayKey(addDays(date, -2)), dayKey(addDays(date, -1)))))
            .get()
        : <FootballGameRow>[];
    final intenseGames = recentGames
        .where((g) =>
            classifySession(ChainSession(
                    date: parseDay(g.date),
                    isFootball: true,
                    imported: g.imported,
                    rpe: g.intensity,
                    workMinutes: g.minutes))
                ?.intensity ==
            DayIntensity.intense)
        .toList();
    if (mode == KneeTrainingMode.noImpact) {
      result.exercises.removeWhere((e) => [
            'Sprint lanzado',
            'Aceleración 10–20 m',
            'Salto vertical',
            'Salto largo',
            'Salto de patinador',
            'Aterrizaje clavado'
          ].contains(e.name));
      result.notes =
          '${result.notes ?? ''} · Escaleras ${morning!.kneeStairs}/10: saltos y sprints aplazados; la excepción de fútbol no aplica.';
    } else if (intenseGames.isNotEmpty &&
        morning?.kneeStairs != null &&
        morning!.kneeStairs! <= 2) {
      result.exercises.removeWhere((e) => e.name == 'Sprint lanzado');
      for (final e
          in result.exercises.where((e) => e.name == 'Aceleración 10–20 m')) {
        e.notes =
            'Sólo 80% por fútbol intenso del ${intenseGames.map((g) => g.date).join(', ')} (minutos/RPE registrados; criterio compartido). Escaleras ${morning.kneeStairs}/10.';
      }
    }
    orderV32Exercises(result);
    if (!v3.reducedVolume) return result;
    // v3.2 compone primero TODO el día: una única reducción compartida.
    final reduced = deloadVersion(result, half: true);
    final metadata = {...reduced.coreEpochs};
    if (v3.blockStart != null) {
      for (final ladder in allLadders) {
        final identity = metadata[ladder.id];
        final state = await LadderRepository(db).state(ladder, today: date);
        final exercise = reduced.exercises
            .where((e) => e.name == state.current.exercise)
            .firstOrNull;
        if (identity == null || exercise?.sets == null) continue;
        metadata[LadderPrescriptionProof.key(ladder.id)] =
            LadderPrescriptionProof.deload(
                identity: identity,
                blockStart: v3.blockStart!,
                week: v3.week,
                sets: exercise!.sets!,
                minimum: exercise.holdSecMin ?? exercise.repsMin ?? 1,
                perSide: exercise.perSide,
                physicalVariant:
                    exercise.physicalVariantKey ?? 'base:${exercise.name}',
                companionGoals: {
              for (final goal in state.current.goals
                  .where((g) => g.exercise != state.current.exercise))
                if (reduced.exercises
                        .where((e) => e.name == goal.exercise)
                        .firstOrNull
                    case final companion?)
                  goal.exercise: {
                    'sets': companion.sets,
                    'minimum': companion.holdSecMin ?? companion.repsMin,
                    'perSide': companion.perSide
                  }
            });
      }
    }
    return PlanDayDraft(
        weekday: reduced.weekday,
        type: reduced.type,
        targetRounds: reduced.targetRounds,
        restBetweenRoundsSec: reduced.restBetweenRoundsSec,
        notes: reduced.notes,
        exercises: reduced.exercises,
        coreEpochs: metadata);
  }

  /// Sesiones que se guardaron solas al terminar el cronómetro y aún no se
  Future<void> setAccessoryProofs(int id, Map<String, String> proofs) =>
      db.transaction(() async {
        final session = await (db.select(db.sessions)
              ..where((t) => t.id.equals(id)))
            .getSingle();
        final metadata = session.coreEpochs == null
            ? <String, String>{}
            : (jsonDecode(session.coreEpochs!) as Map).cast<String, String>();
        for (final entry in proofs.entries) {
          final ladder = ladderById(entry.key),
              proof = AccessoryQualityProof.decode(entry.value);
          if (ladder?.accessory != true ||
              proof == null ||
              metadata[entry.key] != proof.identity) {
            throw const FormatException(
                'La evidencia no coincide con el peldaño prescrito');
          }
          _validateAccessoryObservation(
              entry.key, proof, parseDay(session.date),
              previous: AccessoryQualityProof.decode(
                  metadata[AccessoryQualityProof.key(entry.key)]));
          await _recordAccessoryAlarmOnce(id, entry.key, proof);
          metadata[AccessoryQualityProof.key(entry.key)] = entry.value;
        }
        await (db.update(db.sessions)..where((t) => t.id.equals(id)))
            .write(SessionsCompanion(coreEpochs: Value(jsonEncode(metadata))));
      });

  void _invalidateAccessoryProof(Map<String, String> metadata, String ladder) {
    final key = AccessoryQualityProof.key(ladder),
        old = AccessoryQualityProof.decode(
            metadata[AccessoryQualityProof.key(ladder)]);
    if (old?.alarm == null) {
      metadata.remove(key);
    } else {
      // An edit invalidates achievement evidence, never an observed alarm.
      metadata[key] = AccessoryQualityProof(
              identity: old!.identity,
              alarmFree: false,
              alarm: old.alarm,
              achillesCheckedOn: old.achillesCheckedOn)
          .encode();
    }
  }

  void _validateAccessoryObservation(
      String ladder, AccessoryQualityProof proof, DateTime sessionDate,
      {AccessoryQualityProof? previous}) {
    if (proof.alarm != null &&
        AccessoryQualityProof.alarmsByLadder[ladder] != proof.alarm) {
      throw const FormatException('Señal no pertinente para esta guía');
    }
    if (previous?.alarm != null &&
        (proof.alarm != previous!.alarm || proof.alarmFree == true)) {
      throw const FormatException(
          'La señal observada forma parte del historial; no se borra al editar');
    }
    if (ladder == 'seated_soleus' &&
        (proof.alarmFree == true || proof.alarm == 'achilles_next_morning')) {
      final checked = proof.achillesCheckedDate;
      if (checked == null ||
          !checked.isAfter(dateOnly(sessionDate)) ||
          checked.isAfter(dateOnly(clock.now()))) {
        throw const FormatException(
            'La respuesta del Aquiles requiere fecha explícita desde la mañana siguiente, nunca futura');
      }
    }
  }

  Future<void> _recordAccessoryAlarmOnce(
      int sessionId, String ladderId, AccessoryQualityProof proof) async {
    final alarm = proof.alarm;
    if (alarm == null) return;
    final seen = await (db.select(db.ladderEvents)
          ..where((t) =>
              t.ladder.equals(ladderId) &
              t.eventKey.like('accessoryAlarm:$alarm:%:session:$sessionId')))
        .get();
    if (seen.isNotEmpty) return;
    await LadderRepository(db).accessoryAlarm(
        ladderById(ladderId)!, alarm, dateOnly(clock.now()),
        eventKey: 'session:$sessionId');
  }

  Future<PlanDayDraft> withAccessoryLadders(
      PlanDayDraft day, DateTime date, V3Day v3,
      {bool rings = false}) async {
    final metadata = <String, String>{...day.coreEpochs};
    for (final ladder in v32AccessoryLadders) {
      final candidates =
          day.exercises.where((e) => ladder.owns(e.name)).toList();
      if (candidates.isEmpty) continue;
      final state = await LadderRepository(db).state(ladder, today: date);
      final step = state.current;
      if (ladder.id == 'support_hold' &&
          step.physicalVariantKey == 'support_rings' &&
          !rings) {
        day.exercises.removeWhere((e) => ladder.owns(e.name));
        day.notes =
            '${day.notes ?? ''} · Support en anillas no incluido: equipo no confirmado.';
        continue;
      }
      metadata[ladder.id] = state.identity;
      for (final e in candidates) {
        final prescribedSets = e.sets;
        e.physicalVariantKey = step.physicalVariantKey;
        e.perSide = step.perSide;
        e.rirMin = step.rir ?? e.rirMin;
        e.rirMax = step.rir ?? e.rirMax;
        e.notes =
            'Peldaño ${step.step}: ${step.prescription}${ladder.alarm == null ? '' : ' · ${ladder.alarm}'}';
        if (ladder.id == 'copenhagen') {
          e.repsMin = step.step == 1
              ? (v3.week <= 2
                  ? 3
                  : v3.week <= 4
                      ? 7
                      : 12)
              : 5;
          e.repsMax = step.step == 1
              ? (v3.week <= 2
                  ? 5
                  : v3.week <= 4
                      ? 10
                      : 15)
              : 5;
        } else if (ladder.id == 'flying_sprint') {
          e.sets = step.sets;
          e.repsMin = 1;
          e.repsMax = 1;
          e.restSec = 120;
          e.restSecMax = 180;
        } else if (ladder.id == 'seated_soleus' &&
            date.weekday == DateTime.friday) {
          e.repsMin = 15;
          e.repsMax = 15;
        } else if (ladder.id == 'tibialis_wall' &&
            date.weekday == DateTime.friday) {
          e.repsMin = 20;
          e.repsMax = 20;
        }
        final maintenance = date.weekday == DateTime.thursday &&
                ['support_hold', 'band_external_rotation']
                    .contains(ladder.id) ||
            date.weekday == DateTime.friday &&
                ['seated_soleus', 'tibialis_wall'].contains(ladder.id);
        if (maintenance && prescribedSets != null) {
          metadata[LadderPrescriptionProof.key(ladder.id)] =
              LadderPrescriptionProof.maintenance(
                  identity: state.identity,
                  sets: prescribedSets,
                  minimum: e.holdSecMin ?? e.repsMin ?? 1,
                  perSide: step.perSide);
        }
      }
    }
    return PlanDayDraft(
        weekday: day.weekday,
        type: day.type,
        targetRounds: day.targetRounds,
        restBetweenRoundsSec: day.restBetweenRoundsSec,
        notes: day.notes,
        exercises: day.exercises,
        coreEpochs: metadata);
  }

  /// Sesiones que se guardaron solas al terminar el cronómetro y aún no se
  /// revisan (falta el RPE). Las más recientes primero.
  Stream<List<SessionRow>> watchPendingReview() => (db.select(db.sessions)
        ..where((t) => t.pendingReview.equals(true))
        ..orderBy(
            [(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
      .watch();

  /// La sesión de ese tipo en ese día (la última si hay varias), o null.
  Future<int?> sessionsOn(DateTime date, SessionType type) async {
    final row = await (db.select(db.sessions)
          ..where((t) => t.date.equals(dayKey(date)) & t.type.equalsValue(type))
          ..orderBy(
              [(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.id;
  }

  /// Anota los tres criterios de calidad de una sesión ya guardada.
  Future<void> setProgressionCriteria(int id,
          {bool? techniqueOk, bool? fullRange, bool? recoveryOk}) =>
      (db.update(db.sessions)..where((t) => t.id.equals(id)))
          .write(SessionsCompanion(
        techniqueOk: Value(techniqueOk),
        fullRange: Value(fullRange),
        recoveryOk: Value(recoveryOk),
      ));

  /// Última variante usada en un ejercicio, para proponerla de nuevo.
  Future<String?> lastVariant(String exercise) async {
    final exId = await exercises.idOf(exercise);
    if (exId == null) return null;
    final row = await (db.select(db.sessionSets)
          ..where((t) => t.exerciseId.equals(exId) & t.variant.isNotNull())
          ..orderBy(
              [(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.variant;
  }

  /// Última carga externa usada en un ejercicio, para proponerla de nuevo.
  Future<double?> lastLoad(String exercise) async {
    final exId = await exercises.idOf(exercise);
    if (exId == null) return null;
    final row = await (db.select(db.sessionSets)
          ..where((t) => t.exerciseId.equals(exId) & t.loadKg.isNotNull())
          ..orderBy(
              [(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row?.loadKg;
  }

  Future<void> delete(int id) => db.transaction(() async {
        // Results survive deletion of their auxiliary activity. No textual lookup.
        await (db.update(db.fitnessTestAttempts)
              ..where((t) => t.sessionId.equals(id)))
            .write(const FitnessTestAttemptsCompanion(sessionId: Value(null)));
        await (db.delete(db.sessions)..where((t) => t.id.equals(id))).go();
      });

  /// Duración media por ronda (incluye transición) en las últimas sesiones
  /// con contador. Base para estimar rondas cuando se pierde la cuenta.
  Future<int?> historicalMeanRoundSec({int lastSessions = 5}) async {
    final ids = await (db.selectOnly(db.sessionRounds, distinct: true)
          ..addColumns([db.sessionRounds.sessionId])
          ..orderBy([
            OrderingTerm(
                expression: db.sessionRounds.sessionId, mode: OrderingMode.desc)
          ])
          ..limit(lastSessions))
        .map((r) => r.read(db.sessionRounds.sessionId)!)
        .get();
    if (ids.isEmpty) return null;
    final laps = <int>[];
    for (final id in ids) {
      final marks = await (db.select(db.sessionRounds)
            ..where((t) => t.sessionId.equals(id))
            ..orderBy([(t) => OrderingTerm(expression: t.roundIndex)]))
          .map((r) => r.elapsedSec)
          .get();
      laps.addAll(lapDurations(marks));
    }
    return meanSec(laps);
  }

  // ---------- Fútbol ----------

  Stream<List<FootballGameRow>> watchFootball({int limit = 60}) =>
      (db.select(db.footballGames)
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .watch();

  Future<int> saveFootball(FootballGamesCompanion data) async {
    if (data.id.present) {
      await (db.update(db.footballGames)
            ..where((t) => t.id.equals(data.id.value)))
          .write(data);
      return data.id.value;
    }
    return db.into(db.footballGames).insert(data);
  }

  Future<void> deleteFootball(int id) =>
      (db.delete(db.footballGames)..where((t) => t.id.equals(id))).go();
}

String? _blankToNull(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();
