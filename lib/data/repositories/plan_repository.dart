import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../database.dart';
import '../exercise_details.dart';
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
    this.supersetGroup,
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

  /// Superserie: los del mismo grupo se alternan serie a serie (§18.9).
  String? supersetGroup;

  bool get isHold => holdSecMin != null;

  PlanExerciseDraft copyWith({int? sets}) => PlanExerciseDraft(
        name: name,
        sets: sets ?? this.sets,
        repsMin: repsMin,
        repsMax: repsMax,
        restSec: restSec,
        restSecMax: restSecMax,
        grip: grip,
        block: block,
        variant: variant,
        holdSecMin: holdSecMin,
        holdSecMax: holdSecMax,
        perSide: perSide,
        rirMin: rirMin,
        rirMax: rirMax,
        notes: notes,
        supersetGroup: supersetGroup,
      );

  /// '(A) ' cuando el bloque alterna variantes.
  String get variantPrefix => variant == null ? '' : '($variant) ';

  String get targetLabel {
    final reps = repsMin == null
        ? null
        : (repsMax == null || repsMax == repsMin)
            ? '$repsMin'
            : '$repsMin–$repsMax';
    final hold = holdLabel(holdSecMin, holdSecMax, compact: true);
    // Un descanso de 0 (dentro de la ronda del circuito) no se anuncia.
    final rest = restSec == null || restSec == 0
        ? null
        : (restSecMax == null || restSecMax == restSec)
            ? formatDuration(restSec!)
            : '${formatDuration(restSec!)}–${formatDuration(restSecMax!)}';
    // Metros, saltos o sprints en lugar de repeticiones (guía v3.1).
    final unit = repsUnit(name);
    final per = unit == 'reps' ? '' : ' $unit';
    final parts = [
      if (sets == 1 && hold != null)
        hold
      else if (sets != null && hold != null)
        '$sets×$hold'
      else if (sets != null && reps != null)
        '$sets×$reps$per'
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
    this.coreEpochs = const {},
  }) : exercises = exercises ?? [];

  final int weekday;
  DayType type;
  int? targetRounds;
  int? restBetweenRoundsSec;
  String? notes;
  final List<PlanExerciseDraft> exercises;
  final Map<String, String> coreEpochs;

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

/// Versión ligera de un día, para cuando el cuerpo viene cargado (fútbol
/// intenso o con golpe el día antes). No cambia el objetivo del día, solo le
/// quita margen:
/// - circuito: una ronda menos (mínimo 1);
/// - bloques extra (core, hombro…) y días de bloques: una serie menos si
///   tiene 3 o más (3 → 2; 2 se queda) y el rango recortado por arriba:
///   8–12 → 8–10, 20–40 s → 20–30 s.
/// El trabajo principal del circuito no cambia de repeticiones.
PlanDayDraft lightVersion(PlanDayDraft day) {
  PlanExerciseDraft lighter(PlanExerciseDraft e) => PlanExerciseDraft(
        name: e.name,
        sets: e.sets == null || e.sets! < 3 ? e.sets : e.sets! - 1,
        repsMin: e.repsMin,
        repsMax: e.repsMin == null || e.repsMax == null || e.repsMax! - e.repsMin! <= 2 ? e.repsMax : e.repsMin! + 2,
        restSec: e.restSec,
        restSecMax: e.restSecMax,
        grip: e.grip,
        block: e.block,
        variant: e.variant,
        holdSecMin: e.holdSecMin,
        holdSecMax: e.holdSecMin == null || e.holdSecMax == null || e.holdSecMax! - e.holdSecMin! <= 10
            ? e.holdSecMax
            : e.holdSecMin! + 10,
        perSide: e.perSide,
        rirMin: e.rirMin,
        rirMax: e.rirMax,
        notes: e.notes,
        supersetGroup: e.supersetGroup,
      );

  final circuit = day.type.isCircuit;
  return PlanDayDraft(
    weekday: day.weekday,
    type: day.type,
    targetRounds: day.targetRounds == null ? null : (day.targetRounds! > 1 ? day.targetRounds! - 1 : 1),
    restBetweenRoundsSec: day.restBetweenRoundsSec,
    notes: day.notes,
    coreEpochs: day.coreEpochs,
    exercises: [
      for (final e in day.exercises)
        if (circuit && e.block == null) e else lighter(e),
    ],
  );
}

/// Descarga del Plan v3 (§18.6): una serie menos en cada ejercicio de series
/// (mínimo 1), sin tocar las rondas del circuito ni los tiempos. El lastre se
/// quita a mano: el cronómetro lo recuerda. `half`: la del v3.1 (§19.4), la
/// mitad de las series redondeando hacia arriba (4 → 2, 3 → 2, 2 → 1).
PlanDayDraft deloadVersion(PlanDayDraft day, {bool half = false}) => PlanDayDraft(
      weekday: day.weekday,
      type: day.type,
      targetRounds: day.targetRounds,
      restBetweenRoundsSec: day.restBetweenRoundsSec,
      notes: day.notes,
      exercises: [
        for (final e in day.exercises)
          if (e.sets == null || (day.type.isCircuit && e.block == null))
            e
          else
            e.copyWith(sets: half ? (e.sets! + 1) ~/ 2 : (e.sets! > 1 ? e.sets! - 1 : 1)),
      ],
    );

class PlanDraft {
  PlanDraft({required this.validFrom, this.notes, required this.days, this.scheme});

  factory PlanDraft.empty(DateTime validFrom) =>
      PlanDraft(validFrom: validFrom, days: [for (var w = 1; w <= 7; w++) PlanDayDraft(weekday: w)]);

  DateTime validFrom;
  String? notes;

  /// Periodización ('v3'); null = todas las semanas iguales.
  String? scheme;

  /// Siempre 7 elementos, lunes → domingo.
  final List<PlanDayDraft> days;
}

/// Día del plan vigente para una fecha, con su versión.
class PlanDayView {
  PlanDayView({
    required this.versionNumber,
    required this.dayId,
    required this.day,
    this.validFrom,
    this.scheme,
  });

  final int versionNumber;
  final int dayId;
  final PlanDayDraft day;

  /// Desde cuándo rige la versión y su periodización: con 'v3', la semana del
  /// bloque sale de aquí.
  final DateTime? validFrom;
  final String? scheme;
}

/// Primer problema que impide guardar el plan, o null. Valida lo que el
/// teclado no puede impedir: rangos al revés y ceros donde no tienen sentido.
String? planDraftProblem(PlanDraft draft) {
  for (final day in draft.days) {
    final label = weekdayLong(day.weekday);
    if (day.type.isCircuit && day.targetRounds != null && day.targetRounds! <= 0) {
      return '$label: la meta de rondas debe ser mayor que 0';
    }
    if (!day.type.isTraining) continue;
    for (final e in day.exercises.where((e) => e.name.trim().isNotEmpty)) {
      final name = '$label, ${e.name.trim()}';
      if (e.sets != null && e.sets! <= 0) return '$name: las series deben ser más de 0';
      if (e.repsMin != null && e.repsMax != null && e.repsMin! > e.repsMax!) {
        return '$name: reps mínimas (${e.repsMin}) mayores que las máximas (${e.repsMax})';
      }
      if (e.restSec != null && e.restSecMax != null && e.restSec! > e.restSecMax!) {
        return '$name: descanso mínimo mayor que el máximo';
      }
      if (e.holdSecMin != null && e.holdSecMax != null && e.holdSecMin! > e.holdSecMax!) {
        return '$name: sostén mínimo mayor que el máximo';
      }
    }
  }
  return null;
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

  /// Desde cuándo cuenta la periodización de una versión: la primera versión
  /// seguida con el mismo esquema. Editar el v3 a mitad de bloque crea otra
  /// versión, pero las semanas siguen contando desde el inicio del bloque.
  Future<DateTime> schemeStart(PlanVersionRow v) async {
    if (v.scheme == null) return parseDay(v.validFrom);
    final all = await (db.select(db.planVersions)
          ..where((t) => t.validFrom.isSmallerOrEqualValue(v.validFrom))
          ..orderBy([(t) => OrderingTerm(expression: t.validFrom, mode: OrderingMode.desc)]))
        .get();
    var start = parseDay(v.validFrom);
    for (final x in all) {
      if (x.scheme != v.scheme) break;
      start = parseDay(x.validFrom);
    }
    return start;
  }

  /// ¿Ya hay una versión con este esquema (el v3)?
  Future<bool> hasScheme(String scheme) async =>
      (await (db.select(db.planVersions)..where((t) => t.scheme.equals(scheme))).get()).isNotEmpty;

  Future<int> versionNumber(int versionId) async {
    final all = await versions();
    return all.indexWhere((v) => v.id == versionId) + 1;
  }

  Future<PlanDraft> load(int versionId) async {
    final v = await (db.select(db.planVersions)..where((t) => t.id.equals(versionId))).getSingle();
    final days = await (db.select(db.planDays)..where((t) => t.planVersionId.equals(versionId))).get();
    final names = await exercises.namesById();
    final draft = PlanDraft.empty(parseDay(v.validFrom))
      ..notes = v.notes
      ..scheme = v.scheme;
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
            supersetGroup: e.supersetGroup,
          )));
    }
    return draft;
  }

  /// Las versiones son inmutables: guardar siempre crea una nueva.
  Future<int> saveAsNewVersion(PlanDraft draft) => db.transaction(() async {
        final versionId = await db.into(db.planVersions).insert(PlanVersionsCompanion.insert(
              validFrom: dayKey(draft.validFrom),
              notes: Value(_blankToNull(draft.notes)),
              scheme: Value(draft.scheme),
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
                  supersetGroup: Value(_blankToNull(e.supersetGroup)),
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
    return PlanDayView(
      versionNumber: await versionNumber(v.id),
      dayId: row.id,
      day: draft.days[date.weekday - 1],
      validFrom: await schemeStart(v),
      scheme: draft.scheme,
    );
  }

  /// Un día concreto del plan por su id (para retomar una sesión: las
  /// versiones son inmutables, así que es el mismo guion). null si ya no existe.
  Future<PlanDayView?> dayById(int planDayId) async {
    final row = await (db.select(db.planDays)..where((t) => t.id.equals(planDayId))).getSingleOrNull();
    if (row == null) return null;
    final draft = await load(row.planVersionId);
    final version = await (db.select(db.planVersions)..where((t) => t.id.equals(row.planVersionId))).getSingle();
    return PlanDayView(
      versionNumber: await versionNumber(row.planVersionId),
      dayId: row.id,
      day: draft.days[row.weekday - 1],
      validFrom: await schemeStart(version),
      scheme: draft.scheme,
    );
  }

  /// Cambia cuando cambia cualquier versión; útil para refrescar "Hoy".
  Stream<PlanDayView?> watchDayFor(DateTime date) => db.select(db.planVersions).watch().asyncMap((_) => dayFor(date));
}

String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
