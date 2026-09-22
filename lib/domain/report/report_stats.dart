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
    loggedDays = days.where((d) => dayMacros.containsKey(dayKey(d))).toList();
    unloggedDays = elapsedDays.where((d) => !dayMacros.containsKey(dayKey(d))).toList();
    daysBelowFloor = loggedDays.where((d) => dayMacros[dayKey(d)]!.kcal < input.targets.kcalFloor).toList();

    final sortedPlans = [...input.planVersions]..sort((a, b) => a.validFrom.compareTo(b.validFrom));
    _plans = sortedPlans;
    for (final d in days) {
      final p = planFor(d);
      if (p == null) continue;
      final t = p.typeFor(d.weekday);
      if (t.isTraining) expectedTraining++;
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
  late final List<DateTime> daysBelowFloor;
  late final List<PlanVersionInfo> _plans;
  int expectedTraining = 0;
  int expectedFootball = 0;

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

  double? get avgKcal => loggedDays.isEmpty ? null : _avg((m) => m.kcal);
  double? get avgProtein => loggedDays.isEmpty ? null : _avg((m) => m.protein);
  double? get avgCarbs => loggedDays.isEmpty ? null : _avg((m) => m.carbs);
  double? get avgFat => loggedDays.isEmpty ? null : _avg((m) => m.fat);

  double _avg(double Function(Macros) f) =>
      loggedDays.map((d) => f(dayMacros[dayKey(d)]!)).reduce((a, b) => a + b) / loggedDays.length;

  List<SessionEntry> get sessionsSorted =>
      [...input.sessions]..sort((a, b) => '${dayKey(a.date)} ${a.startTime ?? ''}'
          .compareTo('${dayKey(b.date)} ${b.startTime ?? ''}'));

  int? get maxRoundsInRange {
    final r = input.sessions.where((s) => s.type.isCircuit && s.roundsDone != null).map((s) => s.roundsDone!);
    return r.isEmpty ? null : r.reduce((a, b) => a > b ? a : b);
  }

  /// Rachas de días consecutivos (con registro) bajo el piso de kcal.
  List<List<DateTime>> get lowKcalStreaks {
    final streaks = <List<DateTime>>[];
    var current = <DateTime>[];
    for (final d in days) {
      final m = macrosOn(d);
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
