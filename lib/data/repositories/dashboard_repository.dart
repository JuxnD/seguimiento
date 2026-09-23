import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/nutrition.dart';
import '../../domain/progress.dart';
import '../database.dart';
import 'nutrition_repository.dart';
import 'plan_repository.dart';
import 'profile_repository.dart';

/// Todo lo que la pantalla Hoy necesita, resuelto de una vez.
class TodayDashboard {
  const TodayDashboard({
    required this.date,
    required this.weekIndex,
    required this.dayType,
    required this.planVersion,
    required this.planSummary,
    required this.mainExercises,
    required this.targetRounds,
    required this.roundsDone,
    required this.sessionsToday,
    required this.streak,
    required this.macros,
    required this.proteinMin,
    required this.proteinMax,
    required this.kcalTarget,
    required this.roundsRecord,
    required this.measurement,
  });

  final DateTime date;
  final int weekIndex;
  final DayType dayType;
  final int? planVersion;

  /// "6 rondas · Dominadas 5 · Flexiones 10 · Sentadillas 15".
  final String? planSummary;
  final List<String> mainExercises;
  final int? targetRounds;

  /// Rondas de la sesión de hoy, si ya se registró.
  final int? roundsDone;
  final int sessionsToday;
  final int streak;
  final Macros macros;
  final int proteinMin;
  final int proteinMax;
  final int kcalTarget;

  /// Mejor marca de rondas hasta hoy.
  final int? roundsRecord;

  /// Cuándo toca medir. null = sin línea base ni fecha acordada.
  final MeasurementDue? measurement;

  bool get trained => sessionsToday > 0;
  double get proteinProgress => goalProgress(macros.protein, proteinMin);
  double get kcalProgress => goalProgress(macros.kcal, kcalTarget);
  double get roundsProgress => goalProgress(roundsDone ?? 0, targetRounds ?? 0);
}

class DashboardRepository {
  DashboardRepository(this.db, this.plan, this.nutrition, this.profile);

  final AppDatabase db;
  final PlanRepository plan;
  final NutritionRepository nutrition;
  final ProfileRepository profile;

  Future<TodayDashboard> today({DateTime? now}) async {
    final date = dateOnly(now ?? DateTime.now());
    final p = await profile.get();
    final view = await plan.dayFor(date);
    final type = view?.day.type ?? DayType.descanso;

    final sessions = await (db.select(db.sessions)..where((t) => t.date.equals(dayKey(date)))).get();
    final meals = await nutrition.range(date, date);

    final maxRounds = db.sessions.roundsDone.max();
    final record = await (db.selectOnly(db.sessions)
          ..addColumns([maxRounds])
          ..where(db.countedCircuitRounds))
        .map((r) => r.read(maxRounds))
        .getSingle();

    final lastMeasurement = await (db.select(db.measurements)
          ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();

    return TodayDashboard(
      date: date,
      weekIndex: weekIndexFor(p.programStart, date),
      dayType: type,
      planVersion: view?.versionNumber,
      planSummary: view == null ? null : _summary(view.day),
      mainExercises: view == null
          ? const []
          : view.day.main.map((e) => '${e.name} ${e.targetLabel}'.trim()).toList(),
      targetRounds: view?.day.targetRounds,
      roundsDone: sessions.map((s) => s.roundsDone).whereType<int>().firstOrNull,
      sessionsToday: sessions.length,
      streak: await _streak(date),
      macros: Macros.sum(meals.map((m) => m.macros)),
      proteinMin: p.proteinMin,
      proteinMax: p.proteinMax,
      kcalTarget: p.kcalTarget,
      roundsRecord: record,
      measurement: measurementDue(
        today: date,
        lastMeasurement: lastMeasurement == null ? null : parseDay(lastMeasurement.date),
        agreed: p.nextMeasurementDate == null ? null : parseDay(p.nextMeasurementDate!),
        minDays: p.measureIntervalDays,
        maxDays: p.measureIntervalMaxDays,
      ),
    );
  }

  String _summary(PlanDayDraft day) {
    final rounds = day.targetRounds == null ? null : '${day.targetRounds} rondas';
    final exercises = day.main.map((e) => '${e.name} ${e.targetLabel}'.trim()).join(' · ');
    return [if (rounds != null) rounds, if (exercises.isNotEmpty) exercises].join(' · ');
  }

  /// Días seguidos entrenando, sin que el descanso planificado los rompa.
  Future<int> _streak(DateTime today) async {
    final rows = await db.select(db.sessions).get();
    final dates = rows.map((s) => s.date).toSet();
    final versions = await plan.versions();
    if (versions.isEmpty) return dates.contains(dayKey(today)) ? 1 : 0;

    // Mapa weekday → tipo por versión, para no recargar el plan por día.
    final byVersion = <int, Map<int, DayType>>{};
    for (final v in versions) {
      final days = await (db.select(db.planDays)..where((t) => t.planVersionId.equals(v.id))).get();
      byVersion[v.id] = {for (final d in days) d.weekday: d.type};
    }
    DayType typeFor(DateTime day) {
      PlanVersionRow? active;
      for (final v in versions) {
        if (!parseDay(v.validFrom).isAfter(day)) active = v;
      }
      if (active == null) return DayType.descanso;
      return byVersion[active.id]?[day.weekday] ?? DayType.descanso;
    }

    return currentStreak(
      today: today,
      trainingDates: dates,
      isRestDay: (d) => !typeFor(d).isTraining,
    );
  }
}
