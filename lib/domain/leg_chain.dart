/// Cadena de días intensos por grupo y Plan B de solo torso (§16.24, plan
/// 039). Una sola clasificación para Hoy y el informe. Lógica pura.
///
/// - Exclusiones primero: movilidad (y las rutinas de 032), técnica, test,
///   lo importado y RPE ≤ 5 no cuentan.
/// - Intensa: circuito o bloques con una serie real a RIR ≤ 2; RPE ≥ 7 con
///   ≥ 20 min de trabajo medidos; fútbol ≥ 45 min.
/// - Moderada (RPE 6, RIR 3–4, fútbol corto, RPE ≥ 7 de menos de 20 min): no
///   suma ni rompe. RIR 5 sin RPE queda desconocida.
/// - Sin datos para clasificar: desconocida; no suma ni reinicia y se lista.
/// - Día sin intensa, moderada ni desconocida: reinicia la cadena. No es
///   evidencia de descanso.
/// - Piernas y torso por separado; el Plan B lo dispara la de piernas.
library;

import 'daily_routines.dart' show dailyRoutineIds;
import 'dates.dart';
import 'enums.dart';
import 'recovery.dart' show legExercises;

// ---------------------------------------------------------------------------
// Registro de grupos (plan 039). Propio de la cadena: no cambia el conjunto
// `legExercises` de antes (Plan B por ejercicios del día, 009). Al integrar
// 034 se reconcilian estos nombres con su catálogo.
// ---------------------------------------------------------------------------

/// Pierna: lo de antes, los nueve del Plan v3.2 (034) y otros del catálogo.
const chainLegExercises = {
  ...legExercises,
  // Plan v3.2 (contrato 034).
  'Copenhague',
  'Sóleo sentado con mochila',
  'Tibial en la pared',
  'Sprint lanzado',
  'Sentadilla isométrica en la pared',
  'Abducción de cadera de lado',
  'Nórdico inverso',
  'Bajada lateral del escalón',
  'Aterrizaje clavado',
  // Catálogo y planes anteriores.
  'Sentadilla con salto',
  'Puente de glúteo',
  'Rodillas arriba',
};

/// Torso (tren superior y core): inventario explícito. Un nombre que no está
/// aquí ni en pierna no se supone torso.
const chainTorsoExercises = {
  'Dominadas',
  'Flexiones',
  'Flexiones diamante',
  'Flexiones con pies elevados',
  'Flexión a una mano',
  'Flexión arquero',
  'Flexión pseudo-planche',
  'Pike push-up',
  'Fondos en barra',
  'Remo invertido (mesa)',
  'Remo con banda',
  'Separaciones con banda',
  'Face pull con banda',
  'Elevaciones laterales con banda',
  'Curl con banda',
  'Extensión de tríceps sobre la cabeza con banda',
  'Colgarse de la barra',
  'Pino pecho a la pared',
  'Inclinación de planche',
  'Tuck planche',
  'Muñecas (planche)',
  'Flexiones escapulares',
  'Retracciones escapulares',
  // Plan v3.2 (contrato 034).
  'Rotación externa con banda',
  'Y-T prono',
  'Support hold en paralelas',
  'Scap pull-up',
  // Escalera de plancha inversa (contrato 034).
  'Mesa invertida',
  'Plancha inversa sobre antebrazos',
  'Plancha inversa sobre las manos',
  'Plancha inversa a una pierna',
  'Plancha inversa con pies elevados',
  'Hollow body hold',
  'Hollow rocks',
  'Plancha lateral',
  'Plancha inversa con patada',
  'L-sit',
  'Barca / V-sit',
  'Elevaciones en pike sentado',
  'Elevaciones en straddle',
  'Elevación de piernas colgado',
  'Toes-to-bar',
  'Rollout con toalla',
  'Pallof press con banda',
  'Escaladores',
  'Encogimiento inverso',
  'Vela',
  'Negativo de dragon flag recogido',
  'Negativo de dragon flag a una pierna',
  'Negativo de dragon flag',
  'Dragon flag',
  'Tuck-up',
  'V-up a una pierna',
  'V-up',
  'V-up con bajada lenta',
};

/// Cuentan para los dos grupos.
const chainBothExercises = {'Burpees'};

enum DayIntensity { intense, moderate, unknown, none }

enum ChainGroup { legs, torso }

/// Una sesión o un partido, con lo necesario para clasificarlo.
class ChainSession {
  const ChainSession({
    required this.date,
    this.type,
    this.mode,
    this.rpe,
    this.workMinutes,
    this.minRealRir,
    this.isFootball = false,
    this.imported = false,
    this.exercises = const {},
  });

  final DateTime date;

  /// null en los partidos.
  final SessionType? type;
  final String? mode;

  /// RPE de la sesión o intensidad del partido. null = no se anotó.
  final int? rpe;

  /// Minutos de trabajo medidos (sin calentamiento ni enfriamiento) o
  /// minutos jugados. null = no se midieron.
  final int? workMinutes;

  /// El RIR más bajo de las series anotadas. null = ninguna serie con RIR.
  final int? minRealRir;
  final bool isFootball;
  final bool imported;

  /// Ejercicios con series guardadas.
  final Set<String> exercises;
}

/// Clase de una sesión: intensidad, grupos probados (null = ninguno se
/// sabe) y `doubt`: hay ejercicios sin grupo conocido, así que los grupos no
/// probados quedan en duda (no "nada"). null si está excluida.
({DayIntensity intensity, Set<ChainGroup>? groups, bool doubt, String label})?
    classifySession(ChainSession s) {
  final rpe = s.rpe;
  if (s.imported ||
      s.type == SessionType.movilidad ||
      dailyRoutineIds.contains(s.mode) ||
      s.mode == 'tecnica' ||
      s.mode == 'test') {
    return null;
  }
  if (rpe != null && rpe <= 5) return null;

  if (s.isFootball) {
    final min = s.workMinutes;
    final intensity = min == null
        ? DayIntensity.unknown
        : min >= 45
            ? DayIntensity.intense
            : DayIntensity.moderate;
    return (
      intensity: intensity,
      groups: {ChainGroup.legs},
      doubt: false,
      label: 'fútbol${min == null ? '' : ' $min min'}'
    );
  }

  final type = s.type;
  Set<ChainGroup>? groups;
  var doubt = false;
  if (s.exercises.isNotEmpty) {
    final known = {
      if (s.exercises.any((e) =>
          chainLegExercises.contains(e) || chainBothExercises.contains(e)))
        ChainGroup.legs,
      if (s.exercises.any((e) =>
          chainTorsoExercises.contains(e) || chainBothExercises.contains(e)))
        ChainGroup.torso,
    };
    doubt = s.exercises.any((e) =>
        !chainLegExercises.contains(e) &&
        !chainTorsoExercises.contains(e) &&
        !chainBothExercises.contains(e));
    groups = known.isEmpty ? null : known;
  } else if (type == SessionType.resistencia && s.mode == 'running1515') {
    groups = {ChainGroup.legs};
  } else if (type == SessionType.piernas) {
    groups = {ChainGroup.legs};
  } else if (type == SessionType.trenSuperior) {
    groups = {ChainGroup.torso};
  } else if (type != null && type.isCircuit) {
    groups = {ChainGroup.legs, ChainGroup.torso};
  }

  final name = type?.label.toLowerCase() ?? 'sesión';
  final rir = s.minRealRir;
  final min = s.workMinutes;
  // Circuito o bloques (también los bloques del v3: tren superior y piernas).
  final strength = type != null &&
      (type.isCircuit ||
          type == SessionType.bloques ||
          type == SessionType.trenSuperior ||
          type == SessionType.piernas);
  if (strength && rir != null && rir <= 2) {
    return (
      intensity: DayIntensity.intense,
      groups: groups,
      doubt: doubt,
      label: '$name RIR $rir'
    );
  }
  if (rpe != null && rpe >= 7 && min != null && min >= 20) {
    return (
      intensity: DayIntensity.intense,
      groups: groups,
      doubt: doubt,
      label: '$name RPE $rpe'
    );
  }
  // Moderada: RPE 6, RPE ≥ 7 de menos de 20 min medidos, o RIR 3–4 (§16.24).
  // RIR 5 sin RPE no dice cuánto costó: queda desconocida.
  if (rpe == 6 ||
      (rpe != null && rpe >= 7 && min != null && min > 0) ||
      (rir != null && rir >= 3 && rir <= 4)) {
    return (
      intensity: DayIntensity.moderate,
      groups: groups,
      doubt: doubt,
      label: name
    );
  }
  // Sin RPE ni RIR, o RPE ≥ 7 sin minutos medidos: no se puede decir.
  return (
    intensity: DayIntensity.unknown,
    groups: groups,
    doubt: doubt,
    label: name
  );
}

class GroupChain {
  const GroupChain(
      {required this.days,
      required this.evidence,
      required this.unknownDays,
      required this.moderateDays});

  /// Días intensos de la cadena.
  final int days;

  /// Un texto por día intenso, del más reciente al más viejo: "dom fútbol 90 min".
  final List<(DateTime, String)> evidence;

  /// Días dentro de la cadena que no se pudieron clasificar.
  final List<DateTime> unknownDays;

  /// Días moderados dentro de la cadena (no suman ni rompen).
  final List<DateTime> moderateDays;

  static const empty =
      GroupChain(days: 0, evidence: [], unknownDays: [], moderateDays: []);

  /// "dom 3 mar fútbol 90 min · lun 4 mar circuito RPE 7", del más viejo al
  /// más reciente.
  String get evidenceText => [
        for (final (d, l) in evidence.reversed)
          '${weekdayShort(d.weekday)} ${formatShort(d)} $l'
      ].join(' · ');
}

/// Cadenas de piernas y de torso hasta `today`. Si hoy todavía no hay nada,
/// se cuenta desde ayer (hoy aún puede entrenarse).
({GroupChain legs, GroupChain torso}) intenseChains(
    List<ChainSession> sessions, DateTime today,
    {int lookback = 60}) {
  final d0 = dateOnly(today);
  final byDay = <DateTime,
      List<
          ({
            DayIntensity intensity,
            Set<ChainGroup>? groups,
            bool doubt,
            String label
          })>>{};
  for (final s in sessions) {
    final c = classifySession(s);
    if (c == null) continue;
    (byDay[dateOnly(s.date)] ??= []).add(c);
  }

  (DayIntensity, String?) dayFor(DateTime d, ChainGroup g) {
    final items = byDay[d] ?? const [];
    final mine = items.where((c) => c.groups != null && c.groups!.contains(g));
    // Sin grupo conocido, o con un ejercicio desconocido que podría ser de
    // este grupo: duda, salvo que sea moderada (no suma ni rompe igual).
    final unknownGroup = items.where((c) =>
        (c.groups == null || (c.doubt && !c.groups!.contains(g))) &&
        c.intensity != DayIntensity.moderate);
    final intense =
        mine.where((c) => c.intensity == DayIntensity.intense).firstOrNull;
    if (intense != null) return (DayIntensity.intense, intense.label);
    if (mine.any((c) => c.intensity == DayIntensity.unknown) ||
        unknownGroup.isNotEmpty) {
      return (DayIntensity.unknown, null);
    }
    if (mine.any((c) => c.intensity == DayIntensity.moderate) ||
        items.any(
            (c) => c.groups == null || (c.doubt && !c.groups!.contains(g)))) {
      return (DayIntensity.moderate, null);
    }
    return (DayIntensity.none, null);
  }

  GroupChain chain(ChainGroup g) {
    var day = d0;
    if (dayFor(d0, g).$1 == DayIntensity.none) day = addDays(d0, -1);
    final evidence = <(DateTime, String)>[];
    final unknown = <DateTime>[];
    final moderate = <DateTime>[];
    for (var i = 0; i < lookback; i++) {
      final (kind, label) = dayFor(day, g);
      if (kind == DayIntensity.none) break;
      switch (kind) {
        case DayIntensity.intense:
          evidence.add((day, label!));
        case DayIntensity.unknown:
          unknown.add(day);
        case DayIntensity.moderate:
          moderate.add(day);
        case DayIntensity.none:
          break;
      }
      day = addDays(day, -1);
    }
    // Sólo lo que queda entre los días intensos está "en medio"; lo anterior
    // al más viejo no es parte de la cadena.
    if (evidence.isNotEmpty) {
      final oldest = evidence.last.$1;
      unknown.removeWhere((d) => d.isBefore(oldest));
      moderate.removeWhere((d) => d.isBefore(oldest));
    }
    return GroupChain(
        days: evidence.length,
        evidence: evidence,
        unknownDays: unknown,
        moderateDays: moderate);
  }

  return (legs: chain(ChainGroup.legs), torso: chain(ChainGroup.torso));
}

/// Días de piernas a partir de los cuales se propone el Plan B.
const planBLegChainDays = 3;

/// Escaleras (0–10, `kneeStairs`) a partir de las cuales se propone.
const planBKneeStairs = 4;

/// Molestia en otra zona de pierna a partir de la cual se propone (§16.15).
const planBLegSoreness = 3;

enum PlanBReason { legChain, kneeStairs, legSoreness }

class PlanBAdvice {
  const PlanBAdvice({
    required this.show,
    required this.reasons,
    required this.chainSuppressedByGreenMorning,
    this.unknownDays = const [],
  });

  static const none = PlanBAdvice(
      show: false, reasons: [], chainSuppressedByGreenMorning: false);

  final bool show;

  /// Cada motivo con sus datos: días de la cadena, o valor y fecha.
  final List<(PlanBReason, String)> reasons;

  /// La cadena llegaba a 3 pero la mañana salió bien: sólo una nota.
  final bool chainSuppressedByGreenMorning;

  /// Días de la cadena de piernas sin clasificar (para decirlo, no para contar).
  final List<DateTime> unknownDays;

  /// El pulso de la noche + 7 dos noches (§16.24) no se evalúa: no hay fuente
  /// nocturna (Health Connect, frente D) y el pulso de la mañana no lo
  /// sustituye.
  bool get nightHrEvaluable => false;
}

/// ¿Plan B hoy y por qué? `restOnly`: la recuperación de 032 está en rojo;
/// manda el descanso y el Plan B no propone entrenar.
PlanBAdvice planBAdvice({
  required bool dayHasLegs,
  required GroupChain legs,
  int? kneeStairs,
  DateTime? kneeStairsDate,
  Map<String, (int, DateTime)> legSoreness = const {},
  bool greenMorning = false,
  bool restOnly = false,
}) {
  if (!dayHasLegs || restOnly) return PlanBAdvice.none;
  final reasons = <(PlanBReason, String)>[];
  final chainReached =
      legs.days >= planBLegChainDays && legs.evidence.length == legs.days;
  if (chainReached && !greenMorning) {
    final gaps = [
      if (legs.moderateDays.isNotEmpty)
        '${legs.moderateDays.length} moderado${legs.moderateDays.length == 1 ? '' : 's'} en medio',
      if (legs.unknownDays.isNotEmpty)
        '${legs.unknownDays.length} sin clasificar',
    ];
    reasons.add((
      PlanBReason.legChain,
      'Piernas: ${legs.days} días intensos (${legs.evidenceText})${gaps.isEmpty ? '' : '; ${gaps.join(', ')}'}',
    ));
  }
  if (kneeStairs != null && kneeStairs >= planBKneeStairs) {
    final when = kneeStairsDate == null
        ? ''
        : ' (${weekdayShort(kneeStairsDate.weekday)} ${formatShort(kneeStairsDate)})';
    reasons.add(
        (PlanBReason.kneeStairs, 'Rodilla en escaleras $kneeStairs/10$when'));
  }
  for (final e in legSoreness.entries) {
    final (level, date) = e.value;
    if (level < planBLegSoreness) continue;
    reasons.add((
      PlanBReason.legSoreness,
      'Molestia en ${e.key} $level/10 (${weekdayShort(date.weekday)} ${formatShort(date)})',
    ));
  }
  return PlanBAdvice(
    show: reasons.isNotEmpty,
    reasons: reasons,
    chainSuppressedByGreenMorning: chainReached && greenMorning,
    unknownDays: legs.unknownDays,
  );
}

/// Sección del informe: la misma cadena que ve Hoy, al cierre del periodo.
/// Vacía si no hay días intensos ni días sin clasificar.
List<String> legChainReportLines(GroupChain legs, GroupChain torso) {
  if (legs.days == 0 &&
      torso.days == 0 &&
      legs.unknownDays.isEmpty &&
      torso.unknownDays.isEmpty) return const [];
  String line(String name, GroupChain c) => [
        '$name: ${c.days} día${c.days == 1 ? '' : 's'} intenso${c.days == 1 ? '' : 's'} al cierre'
            '${c.evidence.isEmpty ? '' : ' (${c.evidenceText})'}',
        if (c.moderateDays.isNotEmpty)
          '${c.moderateDays.length} moderado${c.moderateDays.length == 1 ? '' : 's'} en medio',
        if (c.unknownDays.isNotEmpty)
          '${c.unknownDays.length} sin datos para clasificar',
      ].join('; ');
  return [
    line('Piernas', legs),
    line('Torso', torso),
    'Pulso de la noche: no evaluable (sin fuente nocturna)',
  ];
}
