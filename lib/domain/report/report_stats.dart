import '../dates.dart';
import '../enums.dart';
import '../nutrition.dart';
import 'report_input.dart';

/// Métricas derivadas del rango. Alertas e informe leen de aquí para que un
/// número nunca se calcule de dos formas distintas.
class ReportStats {
  ReportStats(this.input) {
    days = [
      for (var d = dateOnly(input.rangeStart); !d.isAfter(input.rangeEnd); d = addDays(d, 1)) d,
    ];
    final today = dateOnly(input.today);
    elapsedDays = days.where((d) => !d.isAfter(today)).toList();

    for (final m in input.meals) {
      final k = dayKey(m.date);
      dayMacros[k] = (dayMacros[k] ?? Macros.zero) + m.macros;
    }
    final slotsByDay = <String, Set<MealSlot>>{};
    for (final m in input.meals) {
      slotsByDay.putIfAbsent(dayKey(m.date), () => {}).add(m.slot);
    }
    loggedDays = days.where((d) => dayMacros.containsKey(dayKey(d))).toList();
    unloggedDays = elapsedDays.where((d) => !dayMacros.containsKey(dayKey(d))).toList();
    closedDays = loggedDays
        .where((d) => isDayClosed(slotsByDay[dayKey(d)] ?? const {}, manuallyClosed: input.closedDays.contains(dayKey(d))))
        .toList();
    incompleteDays = loggedDays.where((d) => !closedDays.contains(d)).toList();
    daysBelowFloor = closedDays.where((d) => dayMacros[dayKey(d)]!.kcal < input.targets.kcalFloor).toList();

    final sortedPlans = [...input.planVersions]..sort((a, b) => a.validFrom.compareTo(b.validFrom));
    _plans = sortedPlans;
    for (final d in days) {
      final p = planFor(d);
      if (p == null) continue;
      final t = p.typeFor(d.weekday);
      if (t.isTraining) {
        expectedTraining++;
        if (d.isBefore(today)) expectedTrainingClosed++;
      }
      if (t == DayType.futbol) expectedFootball++;
    }
  }

  final ReportInput input;
  late final List<DateTime> days;

  /// Días del rango que ya pasaron (≤ hoy).
  late final List<DateTime> elapsedDays;
  final Map<String, Macros> dayMacros = {};
  late final List<DateTime> loggedDays;
  late final List<DateTime> unloggedDays;

  /// Días con registro que cuentan para promedios y alertas: con desayuno,
  /// almuerzo y cena, o cerrados a mano. Un día con solo el desayuno no dice
  /// nada del día y solo metería ruido en las alertas.
  late final List<DateTime> closedDays;

  /// Días con algo registrado pero sin cerrar: se muestran, no se promedian.
  late final List<DateTime> incompleteDays;
  late final List<DateTime> daysBelowFloor;
  late final List<PlanVersionInfo> _plans;
  int expectedTraining = 0;

  /// Sesiones que el plan pedía en días ya cerrados (antes de hoy). Es contra
  /// esto que se juzga si vas por debajo: hoy todavía se puede entrenar y los
  /// días que no han llegado no cuentan como faltas.
  int expectedTrainingClosed = 0;
  int expectedFootball = 0;

  /// Sesiones del plan que aún quedan por delante en el rango (hoy incluido).
  int get expectedTrainingAhead => expectedTraining - expectedTrainingClosed;

  PlanVersionInfo? planFor(DateTime day) {
    PlanVersionInfo? found;
    for (final p in _plans) {
      if (!p.validFrom.isAfter(day)) found = p;
    }
    return found;
  }

  /// Versiones vigentes en algún día del rango, en orden.
  List<PlanVersionInfo> get plansInRange {
    final seen = <int, PlanVersionInfo>{};
    for (final d in days) {
      final p = planFor(d);
      if (p != null) seen[p.number] = p;
    }
    return seen.values.toList();
  }

  Macros? macrosOn(DateTime d) => dayMacros[dayKey(d)];

  /// Reparto de las kcal del rango según de dónde salen sus macros.
  /// (verificadas de etiqueta, de tabla de referencia, estimadas a ojo)
  (double, double, double) get kcalBySource {
    var label = 0.0, reference = 0.0, free = 0.0;
    for (final item in input.meals.expand((m) => m.items)) {
      switch (item.sourceVerified) {
        case true:
          label += item.macros.kcal;
        case false:
          reference += item.macros.kcal;
        case null:
          free += item.macros.kcal;
      }
    }
    return (label, reference, free);
  }

  double? get avgKcal => closedDays.isEmpty ? null : _avg((m) => m.kcal);
  double? get avgProtein => closedDays.isEmpty ? null : _avg((m) => m.protein);
  double? get avgCarbs => closedDays.isEmpty ? null : _avg((m) => m.carbs);
  double? get avgFat => closedDays.isEmpty ? null : _avg((m) => m.fat);

  double _avg(double Function(Macros) f) =>
      closedDays.map((d) => f(dayMacros[dayKey(d)]!)).reduce((a, b) => a + b) / closedDays.length;

  bool isClosed(DateTime d) => closedDays.any((c) => dayKey(c) == dayKey(d));

  /// Repeticiones totales por ejercicio en el rango (volumen).
  Map<String, int> get volumeByExercise {
    final out = <String, int>{};
    for (final set in input.sessions.expand((x) => x.sets)) {
      out[set.exercise] = (out[set.exercise] ?? 0) + set.reps;
    }
    return out;
  }

  /// Estadísticas del rango anterior, si se cargó.
  late final ReportStats? previous = input.previous == null ? null : ReportStats(input.previous!);

  List<SessionEntry> get sessionsSorted =>
      [...input.sessions]..sort((a, b) => '${dayKey(a.date)} ${a.startTime ?? ''}'
          .compareTo('${dayKey(b.date)} ${b.startTime ?? ''}'));

  /// Máximo de rondas **contadas**: una estimación por tiempo no es marca.
  int? get maxRoundsInRange {
    final r = input.sessions
        .where((s) => s.type.isCircuit && s.roundsDone != null && !s.roundsEstimated)
        .map((s) => s.roundsDone!);
    return r.isEmpty ? null : r.reduce((a, b) => a > b ? a : b);
  }

  /// Rachas de días consecutivos (con registro) bajo el piso de kcal.
  List<List<DateTime>> get lowKcalStreaks {
    final streaks = <List<DateTime>>[];
    var current = <DateTime>[];
    for (final d in days) {
      final m = isClosed(d) ? macrosOn(d) : null;
      if (m != null && m.kcal < input.targets.kcalFloor) {
        current.add(d);
      } else {
        if (current.isNotEmpty) streaks.add(current);
        current = [];
      }
    }
    if (current.isNotEmpty) streaks.add(current);
    return streaks;
  }
}

/// Sesiones de circuito que subieron de ronda sin cumplir la regla de
/// progresión, con el motivo. Orden cronológico.
List<(SessionEntry, int, List<String>)> progressionViolations(ReportStats s) {
  final out = <(SessionEntry, int, List<String>)>[];
  final previous = <SessionType, int>{...s.input.roundsBeforeRange};
  for (final session in s.sessionsSorted.where((x) => x.type.isCircuit && x.roundsDone != null)) {
    final before = previous[session.type];
    final blockers = session.progressionBlockers;
    if (before != null && session.roundsDone! > before && blockers.isNotEmpty) {
      out.add((session, before, blockers));
    }
    previous[session.type] = session.roundsDone!;
  }
  return out;
}
