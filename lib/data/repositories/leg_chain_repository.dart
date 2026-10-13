import 'package:drift/drift.dart';

import '../../domain/dates.dart';
import '../../domain/leg_chain.dart';
import '../../domain/readiness.dart' show ReadinessLevel, readinessHrBaseMax, readinessHrBaseMin;
import '../../domain/recovery.dart' show legZones;
import '../database.dart';
import 'readiness_repository.dart';

/// Lo que la cadena de §16.24 lee de la base (plan 039). Una sola lectura
/// para Hoy y el informe.
class LegChainRepository {
  LegChainRepository(this.db);

  final AppDatabase db;

  /// Sesiones (incluidas las que se excluyen: la exclusión la decide el
  /// dominio) y partidos de los `days` días hasta `through`.
  Future<List<ChainSession>> sessions(DateTime through, {int days = 60}) async {
    final to = dayKey(dateOnly(through));
    final from = dayKey(addDays(dateOnly(through), -days));
    final rows = await (db.select(db.sessions)..where((t) => t.date.isBetweenValues(from, to))).get();
    final ids = [for (final r in rows) r.id];
    final sets = ids.isEmpty
        ? const <TypedResult>[]
        : await (db.select(db.sessionSets).join([
            innerJoin(db.exercises, db.exercises.id.equalsExp(db.sessionSets.exerciseId)),
          ])
                ..where(db.sessionSets.sessionId.isIn(ids)))
            .get();
    final names = <int, Set<String>>{};
    final minRir = <int, int>{};
    for (final r in sets) {
      final set = r.readTable(db.sessionSets);
      (names[set.sessionId] ??= {}).add(r.readTable(db.exercises).name);
      final rir = set.rir;
      if (rir != null) {
        final prev = minRir[set.sessionId];
        if (prev == null || rir < prev) minRir[set.sessionId] = rir;
      }
    }
    final games = await (db.select(db.footballGames)..where((t) => t.date.isBetweenValues(from, to))).get();
    return [
      for (final s in rows)
        ChainSession(
          date: parseDay(s.date),
          type: s.type,
          mode: s.mode,
          rpe: s.rpe,
          // Trabajo medido: sin minutos registrados no se inventan.
          workMinutes: s.totalSec <= 0 ? null : (s.totalSec - s.warmupSec - s.cooldownSec) ~/ 60,
          minRealRir: minRir[s.id],
          imported: s.imported,
          exercises: names[s.id] ?? const {},
        ),
      for (final g in games)
        ChainSession(
          date: parseDay(g.date),
          rpe: g.intensity,
          workMinutes: g.minutes,
          isFootball: true,
          imported: g.imported,
        ),
    ];
  }

  Future<({GroupChain legs, GroupChain torso})> chains(DateTime date) async =>
      intenseChains(await sessions(date), date);

  /// Plan B de hoy con sus motivos.
  Future<PlanBAdvice> planB(DateTime date, {required bool dayHasLegs, required GroupChain legs}) async {
    if (!dayHasLegs) return PlanBAdvice.none;
    final d0 = dateOnly(date);
    final key = dayKey(d0);
    final morning = await (db.select(db.morningChecks)..where((t) => t.date.equals(key))).getSingleOrNull();
    // Molestias por zona de pierna, hoy o ayer (§16.15), con su fecha.
    final sore = await (db.select(db.sorenessLogs)
          ..where((t) => t.date.isBetweenValues(dayKey(addDays(d0, -1)), key)))
        .get();
    final legSoreness = <String, (int, DateTime)>{};
    for (final r in sore) {
      if (!legZones.contains(r.zone)) continue;
      final prev = legSoreness[r.zone];
      if (prev == null || r.level > prev.$1) legSoreness[r.zone] = (r.level, parseDay(r.date));
    }
    // Mañana verde: escaleras ≤ 2 y pulso por debajo de base + 5, los dos
    // anotados. null en cualquiera = no hay verde que suprima la cadena.
    var green = false;
    final hr = morning?.restingHr;
    final stairs = morning?.kneeStairs;
    if (stairs != null && stairs <= 2 && hr != null) {
      final base = await (db.select(db.morningChecks)
            ..where((t) => t.date.isSmallerThanValue(key) & t.restingHr.isNotNull())
            ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)])
            ..limit(readinessHrBaseMax))
          .get();
      if (base.length >= readinessHrBaseMin) {
        final mean = base.fold<int>(0, (a, r) => a + r.restingHr!) / base.length;
        green = hr < mean + 5;
      }
    }
    final restOnly = (await ReadinessRepository(db).readinessOn(d0)).level == ReadinessLevel.red;
    return planBAdvice(
      dayHasLegs: dayHasLegs,
      legs: legs,
      kneeStairs: stairs,
      kneeStairsDate: stairs == null ? null : d0,
      legSoreness: legSoreness,
      greenMorning: green,
      restOnly: restOnly,
    );
  }
}
