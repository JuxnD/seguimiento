import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../database.dart';
import 'exercise_repository.dart';

class PlanExerciseDraft {
  PlanExerciseDraft({
    required this.name,
    this.sets,
    this.repsMin,
    this.repsMax,
    this.restSec,
    this.restSecMax,
    this.grip,
    this.block,
    this.variant,
    this.holdSecMin,
    this.holdSecMax,
    this.perSide = false,
    this.rirMin,
    this.rirMax,
    this.notes,
  });

  String name;
  int? sets;
  int? repsMin;
  int? repsMax;
  int? restSec;
  int? restSecMax;
  String? grip;

  /// null = trabajo principal; si no, el bloque extra ('core', 'hombro'…).
  String? block;

  /// 'A' o 'B' cuando el bloque alterna entre variantes.
  String? variant;
  int? holdSecMin;
  int? holdSecMax;
  bool perSide;
  int? rirMin;
  int? rirMax;
  String? notes;

  bool get isHold => holdSecMin != null;

  /// '(A) ' cuando el bloque alterna variantes.
  String get variantPrefix => variant == null ? '' : '($variant) ';

  String get targetLabel {
    final reps = repsMin == null
        ? null
        : (repsMax == null || repsMax == repsMin)
            ? '$repsMin'
            : '$repsMin–$repsMax';
    final hold = holdSecMin == null
        ? null
        : (holdSecMax == null || holdSecMax == holdSecMin)
            ? '${holdSecMin}s'
            : '$holdSecMin–${holdSecMax}s';
    // Un descanso de 0 (dentro de la ronda del circuito) no se anuncia.
    final rest = restSec == null || restSec == 0
        ? null
        : (restSecMax == null || restSecMax == restSec)
            ? formatDuration(restSec!)
            : '${formatDuration(restSec!)}–${formatDuration(restSecMax!)}';
    final parts = [
      if (sets != null && hold != null)
        '$sets×$hold'
      else if (sets != null && reps != null)
        '$sets×$reps'
      else if (hold != null)
        hold
      else if (reps != null)
        '$reps reps',
      if (perSide) 'por lado',
      if (rirMin != null) (rirMax == null || rirMax == rirMin) ? 'RIR $rirMin' : 'RIR $rirMin–$rirMax',
      if (rest != null) 'desc. $rest',
      if (grip != null && grip!.isNotEmpty) grip!,
    ];
    return parts.join(' · ');
  }
}

class PlanDayDraft {
  PlanDayDraft({
    required this.weekday,
    this.type = DayType.descanso,
    this.targetRounds,
    this.restBetweenRoundsSec,
    this.notes,
    List<PlanExerciseDraft>? exercises,
  }) : exercises = exercises ?? [];

  final int weekday;
  DayType type;
  int? targetRounds;
  int? restBetweenRoundsSec;
  String? notes;
  final List<PlanExerciseDraft> exercises;

  /// Trabajo principal del día (sin los bloques extra).
  List<PlanExerciseDraft> get main => exercises.where((e) => e.block == null).toList();

  /// Bloques extra, agrupados por nombre de bloque.
  Map<String, List<PlanExerciseDraft>> get blocks {
    final out = <String, List<PlanExerciseDraft>>{};
    for (final e in exercises.where((e) => e.block != null)) {
      out.putIfAbsent(e.block!, () => []).add(e);
    }
    return out;
  }
}

class PlanDraft {
  PlanDraft({required this.validFrom, this.notes, required this.days});

  factory PlanDraft.empty(DateTime validFrom) =>
      PlanDraft(validFrom: validFrom, days: [for (var w = 1; w <= 7; w++) PlanDayDraft(weekday: w)]);

  DateTime validFrom;
  String? notes;

  /// Siempre 7 elementos, lunes → domingo.
  final List<PlanDayDraft> days;
}

/// Día del plan vigente para una fecha, con su versión.
class PlanDayView {
  PlanDayView({required this.versionNumber, required this.dayId, required this.day});

  final int versionNumber;
  final int dayId;
  final PlanDayDraft day;
}

class PlanRepository {
  PlanRepository(this.db, this.exercises);

  final AppDatabase db;
  final ExerciseRepository exercises;

  /// Orden de creación: define el número de versión (v1, v2…).
  Stream<List<PlanVersionRow>> watchVersions() =>
      (db.select(db.planVersions)..orderBy([(t) => OrderingTerm(expression: t.id)])).watch();

  Future<List<PlanVersionRow>> versions() =>
      (db.select(db.planVersions)..orderBy([(t) => OrderingTerm(expression: t.id)])).get();

  /// Vigente en `day`: mayor validFrom ≤ day; empate → la más reciente.
  Future<PlanVersionRow?> activeVersion(DateTime day) => (db.select(db.planVersions)
        ..where((t) => t.validFrom.isSmallerOrEqualValue(dayKey(day)))
        ..orderBy([
          (t) => OrderingTerm(expression: t.validFrom, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
        ])
        ..limit(1))
      .getSingleOrNull();

  Future<int> versionNumber(int versionId) async {
    final all = await versions();
    return all.indexWhere((v) => v.id == versionId) + 1;
  }

  Future<PlanDraft> load(int versionId) async {
    final v = await (db.select(db.planVersions)..where((t) => t.id.equals(versionId))).getSingle();
    final days = await (db.select(db.planDays)..where((t) => t.planVersionId.equals(versionId))).get();
    final names = await exercises.namesById();
    final draft = PlanDraft.empty(parseDay(v.validFrom))..notes = v.notes;
    for (final d in days) {
      final target = draft.days[d.weekday - 1]
        ..type = d.type
        ..targetRounds = d.targetRounds
        ..restBetweenRoundsSec = d.restBetweenRoundsSec
        ..notes = d.notes;
      final ex = await (db.select(db.planExercises)
            ..where((t) => t.planDayId.equals(d.id))
            ..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .get();
      target.exercises.addAll(ex.map((e) => PlanExerciseDraft(
            name: names[e.exerciseId] ?? '?',
            sets: e.sets,
            repsMin: e.repsMin,
            repsMax: e.repsMax,
            restSec: e.restSec,
            restSecMax: e.restSecMax,
            grip: e.grip,
            block: e.block,
            variant: e.variant,
            holdSecMin: e.holdSecMin,
            holdSecMax: e.holdSecMax,
            perSide: e.perSide,
            rirMin: e.rirMin,
            rirMax: e.rirMax,
            notes: e.notes,
          )));
    }
    return draft;
  }

  /// Las versiones son inmutables: guardar siempre crea una nueva.
  Future<int> saveAsNewVersion(PlanDraft draft) => db.transaction(() async {
        final versionId = await db.into(db.planVersions).insert(PlanVersionsCompanion.insert(
              validFrom: dayKey(draft.validFrom),
              notes: Value(_blankToNull(draft.notes)),
            ));
        for (final d in draft.days) {
          final dayId = await db.into(db.planDays).insert(PlanDaysCompanion.insert(
                planVersionId: versionId,
                weekday: d.weekday,
                type: d.type,
                targetRounds: Value(d.type.isCircuit ? d.targetRounds : null),
                restBetweenRoundsSec: Value(d.type.isCircuit ? d.restBetweenRoundsSec : null),
                notes: Value(_blankToNull(d.notes)),
              ));
          if (!d.type.isTraining) continue;
          var pos = 0;
          for (final e in d.exercises.where((e) => e.name.trim().isNotEmpty)) {
            await db.into(db.planExercises).insert(PlanExercisesCompanion.insert(
                  planDayId: dayId,
                  position: pos++,
                  exerciseId: await exercises.getOrCreate(e.name),
                  sets: Value(e.sets),
                  repsMin: Value(e.repsMin),
                  repsMax: Value(e.repsMax ?? e.repsMin),
                  restSec: Value(e.restSec),
                  restSecMax: Value(e.restSecMax),
                  grip: Value(_blankToNull(e.grip)),
                  block: Value(_blankToNull(e.block)),
                  variant: Value(_blankToNull(e.variant)),
                  holdSecMin: Value(e.holdSecMin),
                  holdSecMax: Value(e.holdSecMax),
                  perSide: Value(e.perSide),
                  rirMin: Value(e.rirMin),
                  rirMax: Value(e.rirMax),
                  notes: Value(_blankToNull(e.notes)),
                ));
          }
        }
        return versionId;
      });

  Future<PlanDayView?> dayFor(DateTime date) async {
    final v = await activeVersion(date);
    if (v == null) return null;
    final row = await (db.select(db.planDays)
          ..where((t) => t.planVersionId.equals(v.id) & t.weekday.equals(date.weekday)))
        .getSingleOrNull();
    if (row == null) return null;
    final draft = await load(v.id);
    return PlanDayView(versionNumber: await versionNumber(v.id), dayId: row.id, day: draft.days[date.weekday - 1]);
  }

  /// Cambia cuando cambia cualquier versión; útil para refrescar "Hoy".
  Stream<PlanDayView?> watchDayFor(DateTime date) =>
      db.select(db.planVersions).watch().asyncMap((_) => dayFor(date));
}

String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
