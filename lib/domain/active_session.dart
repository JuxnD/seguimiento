/// Foto del cronómetro en curso, para reanudarlo si Android mata la app a
/// mitad de la sesión. Lógica pura: sabe convertirse a JSON y volver, nada más.
///
/// Todos los tiempos son marcas de reloj absolutas: al reanudar, el reloj ya
/// avanzó lo que la app estuvo muerta, igual que si hubiera seguido abierta.
library;

import 'enums.dart';

sealed class ActiveSession {
  const ActiveSession({required this.date, required this.startedAt});

  /// Día al que pertenece la sesión (`YYYY-MM-DD`).
  final String date;
  final DateTime startedAt;

  Map<String, Object?> toJson();

  /// null si el JSON no es una sesión reconocible: nunca lanza.
  static ActiveSession? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    try {
      return switch (json['kind']) {
        'guided' => GuidedSnapshot._fromJson(json),
        'counter' => CounterSnapshot._fromJson(json),
        _ => null,
      };
    } on Object {
      return null;
    }
  }
}

/// Una serie o parada ya hecha en el cronómetro guiado.
class DoneStep {
  const DoneStep(this.exercise, this.reps, this.isRound, {this.loadKg});

  final String exercise;
  final int reps;
  final bool isRound;

  /// Carga externa de la serie (kg). null = peso corporal.
  final double? loadKg;

  Map<String, Object?> toJson() => {'e': exercise, 'r': reps, 'round': isRound, if (loadKg != null) 'kg': loadKg};

  static DoneStep fromJson(Map<String, Object?> j) => DoneStep(
        j['e']! as String,
        (j['r']! as num).toInt(),
        j['round']! as bool,
        loadKg: (j['kg'] as num?)?.toDouble(),
      );
}

/// Fases del cronómetro guiado. El nombre se persiste.
enum GuidedPhase { calentamiento, trabajo, enfriamiento, terminado }

class GuidedSnapshot extends ActiveSession {
  const GuidedSnapshot({
    required super.date,
    required super.startedAt,
    required this.planDayId,
    required this.phase,
    required this.index,
    this.sessionType,
    this.coreVariant,
    this.roundsOverride,
    this.workStartedAt,
    this.workEndedAt,
    this.endedAt,
    this.restStartedAt,
    this.restAccumSec = 0,
    this.reps,
    this.done = const [],
    this.roundMarks = const [],
    this.roundRests = const [],
  });

  /// El día del plan se relee por id: las versiones del plan son inmutables,
  /// así que el guion que se reconstruye es el mismo que se estaba siguiendo.
  final int planDayId;
  final SessionType? sessionType;
  final String? coreVariant;
  final int? roundsOverride;

  final GuidedPhase phase;
  final int index;
  final DateTime? workStartedAt;
  final DateTime? workEndedAt;
  final DateTime? endedAt;
  final DateTime? restStartedAt;

  /// Descansos ya cerrados (s). Falta en fotos anteriores a la 1.7: vale 0.
  final int restAccumSec;
  final int? reps;
  final List<DoneStep> done;
  final List<int> roundMarks;

  /// Descanso después de cada ronda (s), en paralelo a `roundMarks`. Falta en
  /// fotos anteriores al esquema 8: sin él no se separa el trabajo por ronda.
  final List<int> roundRests;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'guided',
        'date': date,
        'startedAt': startedAt.toIso8601String(),
        'planDayId': planDayId,
        'sessionType': sessionType?.name,
        'coreVariant': coreVariant,
        'roundsOverride': roundsOverride,
        'phase': phase.name,
        'index': index,
        'workStartedAt': workStartedAt?.toIso8601String(),
        'workEndedAt': workEndedAt?.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'restStartedAt': restStartedAt?.toIso8601String(),
        'restAccumSec': restAccumSec,
        'reps': reps,
        'done': [for (final d in done) d.toJson()],
        'roundMarks': roundMarks,
        'roundRests': roundRests,
      };

  static GuidedSnapshot _fromJson(Map<String, Object?> j) => GuidedSnapshot(
        date: j['date']! as String,
        startedAt: DateTime.parse(j['startedAt']! as String),
        planDayId: (j['planDayId']! as num).toInt(),
        sessionType: _enumOrNull(SessionType.values, j['sessionType']),
        coreVariant: j['coreVariant'] as String?,
        roundsOverride: (j['roundsOverride'] as num?)?.toInt(),
        phase: GuidedPhase.values.byName(j['phase']! as String),
        index: (j['index']! as num).toInt(),
        workStartedAt: _date(j['workStartedAt']),
        workEndedAt: _date(j['workEndedAt']),
        endedAt: _date(j['endedAt']),
        restStartedAt: _date(j['restStartedAt']),
        restAccumSec: (j['restAccumSec'] as num?)?.toInt() ?? 0,
        reps: (j['reps'] as num?)?.toInt(),
        done: [for (final d in j['done']! as List) DoneStep.fromJson((d as Map).cast<String, Object?>())],
        roundMarks: [for (final m in j['roundMarks']! as List) (m as num).toInt()],
        roundRests: [for (final m in (j['roundRests'] as List?) ?? const []) (m as num).toInt()],
      );
}

/// Fases del cronómetro libre. El nombre se persiste.
enum CounterPhase { warmup, circuit, cooldown }

class CounterSnapshot extends ActiveSession {
  const CounterSnapshot({
    required super.date,
    required super.startedAt,
    required this.phase,
    this.outOfPlan = false,
    this.circuitStart,
    this.circuitEnd,
    this.marks = const [],
  });

  final CounterPhase phase;
  final bool outOfPlan;
  final DateTime? circuitStart;
  final DateTime? circuitEnd;
  final List<int> marks;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'counter',
        'date': date,
        'startedAt': startedAt.toIso8601String(),
        'phase': phase.name,
        'outOfPlan': outOfPlan,
        'circuitStart': circuitStart?.toIso8601String(),
        'circuitEnd': circuitEnd?.toIso8601String(),
        'marks': marks,
      };

  static CounterSnapshot _fromJson(Map<String, Object?> j) => CounterSnapshot(
        date: j['date']! as String,
        startedAt: DateTime.parse(j['startedAt']! as String),
        phase: CounterPhase.values.byName(j['phase']! as String),
        outOfPlan: j['outOfPlan'] as bool? ?? false,
        circuitStart: _date(j['circuitStart']),
        circuitEnd: _date(j['circuitEnd']),
        marks: [for (final m in j['marks']! as List) (m as num).toInt()],
      );
}

DateTime? _date(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;

T? _enumOrNull<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
