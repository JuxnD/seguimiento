import 'package:drift/drift.dart';

import '../../domain/adaptive_coach.dart';
import '../../domain/dates.dart';
import '../../domain/goal_history.dart';
import '../database.dart';

/// Metas del perfil como valores comparables por métrica.
Map<GoalMetric, double?> goalsOfProfile(ProfileRow p) => {
      GoalMetric.pasos: p.stepsTarget.toDouble(),
      GoalMetric.proteinaMin: p.proteinMin.toDouble(),
      GoalMetric.proteinaMax: p.proteinMax.toDouble(),
      GoalMetric.kcal: p.kcalTarget.toDouble(),
      GoalMetric.kcalFutbol: p.kcalTargetFootball?.toDouble(),
    };

/// Primera vigencia de cada meta. Instalación nueva: conocida desde hoy.
/// Base migrada (`effectiveFrom` null): el pasado queda incierto (fila sin
/// fecha) y el mismo valor se sabe vigente **desde la migración** (revisión
/// de Codex: si no, el legado nunca se podría revisar). No duplica.
Future<void> seedGoalVersions(AppDatabase db,
    {required DateTime? effectiveFrom, required String origin, DateTime? now}) async {
  final existing = await db.select(db.goalVersions).get();
  if (existing.isNotEmpty) return;
  final profile = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingleOrNull();
  if (profile == null) return;
  final today = dateOnly(now ?? DateTime.now());
  for (final e in goalsOfProfile(profile).entries) {
    Future<void> add(DateTime? from) => db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
          metric: e.key.name,
          value: Value(e.value),
          effectiveFrom: Value(from == null ? null : dayKey(from)),
          acceptedAt: dayKey(today),
          origin: origin,
        ));
    await add(effectiveFrom);
    if (effectiveFrom == null) await add(today);
  }
}

GoalVersion _version(GoalVersionRow r) => GoalVersion(
      id: r.id,
      metric: GoalMetric.values.byName(r.metric),
      value: r.value,
      effectiveFrom: r.effectiveFrom == null ? null : parseDay(r.effectiveFrom!),
      acceptedAt: parseDay(r.acceptedAt),
      origin: r.origin,
      reason: r.reason,
      policy: r.policy,
    );

/// Única puerta para cambiar metas del perfil: escribe el perfil y, por cada
/// meta que cambió, una vigencia desde `effectiveFrom` (hoy por defecto). Lo
/// demás del perfil se escribe igual que antes.
class GoalRepository {
  GoalRepository(this.db);

  final AppDatabase db;

  Future<GoalHistory> history() async =>
      GoalHistory([for (final r in await db.select(db.goalVersions).get()) _version(r)]);

  Stream<GoalHistory> watchHistory() =>
      db.select(db.goalVersions).watch().map((rows) => GoalHistory([for (final r in rows) _version(r)]));

  /// Proyecta al perfil lo que ya rige hoy (p. ej. una propuesta aceptada
  /// ayer para hoy). Idempotente y sin crear vigencias. El perfil es la
  /// proyección; la verdad está en `goal_versions`.
  Future<void> projectDueGoals(DateTime today) async {
    final h = await history();
    final profile = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingleOrNull();
    if (profile == null) return;
    final current = goalsOfProfile(profile);
    // Value.absent = no cambia. Para kcal de fútbol, una vigencia con null
    // ("la misma de entre semana") se proyecta como null.
    Value<int> req(GoalMetric m) {
      final v = h.current(m, today);
      if (v?.value == null || current[m] == v!.value) return const Value.absent();
      return Value(v.value!.round());
    }

    Value<int?> football() {
      final v = h.current(GoalMetric.kcalFutbol, today);
      if (v == null || current[GoalMetric.kcalFutbol] == v.value) return const Value.absent();
      return Value(v.value?.round());
    }

    final change = ProfilesCompanion(
      stepsTarget: req(GoalMetric.pasos),
      proteinMin: req(GoalMetric.proteinaMin),
      proteinMax: req(GoalMetric.proteinaMax),
      kcalTarget: req(GoalMetric.kcal),
      kcalTargetFootball: football(),
    );
    if (!change.stepsTarget.present &&
        !change.proteinMin.present &&
        !change.proteinMax.present &&
        !change.kcalTarget.present &&
        !change.kcalTargetFootball.present) {
      return;
    }
    await (db.update(db.profiles)..where((t) => t.id.equals(1))).write(change);
  }

  /// Programa una meta con su vigencia sin tocar el perfil.
  Future<void> scheduleGoal(GoalMetric metric, double? value,
          {required DateTime effectiveFrom, required String origin, String? reason, DateTime? now}) =>
      db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
            metric: metric.name,
            value: Value(value),
            effectiveFrom: Value(dayKey(effectiveFrom)),
            acceptedAt: dayKey(dateOnly(now ?? DateTime.now())),
            origin: origin,
            reason: Value(reason),
          ));

  /// Referencia del radar (plan 011): sólo con aceptación explícita, con
  /// vigencia, sin proyección al perfil. null = sin referencia.
  Future<void> setReference(GoalMetric metric, double? value, {DateTime? effectiveFrom, DateTime? now}) {
    if (!metric.reference) throw ArgumentError.value(metric, 'metric', 'no es una referencia del radar');
    // 0, negativos o NaN no permiten normalizar el radar (revisión de Codex).
    if (value != null && (!value.isFinite || value <= 0)) {
      throw ArgumentError.value(value, 'value', 'una referencia es null o una cifra finita mayor que 0');
    }
    final today = dateOnly(now ?? DateTime.now());
    return scheduleGoal(metric, value,
        effectiveFrom: effectiveFrom ?? today, origin: GoalOrigin.perfil, reason: 'Referencia aceptada', now: today);
  }

  Future<void> updateProfile(
    ProfilesCompanion data, {
    required String origin,
    String? reason,
    DateTime? effectiveFrom,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final today = dateOnly(now ?? DateTime.now());
        // El perfil es lo que rige hoy: una vigencia futura va por
        // `scheduleGoal`, nunca escribiendo el perfil antes de tiempo.
        if (effectiveFrom != null && dateOnly(effectiveFrom).isAfter(today)) {
          throw ArgumentError.value(effectiveFrom, 'effectiveFrom', 'futura: usar scheduleGoal');
        }
        final before = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();
        await (db.update(db.profiles)..where((t) => t.id.equals(1))).write(data);
        final after = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingle();
        final old = goalsOfProfile(before);
        for (final e in goalsOfProfile(after).entries) {
          if (old[e.key] == e.value) continue;
          await db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
                metric: e.key.name,
                value: Value(e.value),
                effectiveFrom: Value(dayKey(effectiveFrom ?? today)),
                acceptedAt: dayKey(today),
                origin: origin,
                reason: Value(reason),
              ));
        }
      });

  // ---------- Propuestas ----------

  Future<ProposalRecord?> lastProposal(String kind) async {
    final row = await (db.select(db.coachProposals)
          ..where((t) => t.kind.equals(kind))
          ..orderBy([(t) => OrderingTerm(expression: t.createdOn, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _record(row);
  }

  Future<ProposalRecord?> proposal(String id) async {
    final row = await (db.select(db.coachProposals)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _record(row);
  }

  ProposalRecord _record(CoachProposalRow r) => ProposalRecord(
        id: r.id,
        status: ProposalStatus.values.byName(r.status),
        reviewAfter: r.reviewAfter == null ? null : parseDay(r.reviewAfter!),
        decidedOn: r.decidedOn == null ? null : parseDay(r.decidedOn!),
      );

  /// Decide una propuesta de rondas, fuerza o escalera (criterios existentes).
  /// Idempotente por ID; "pospuesta" dura `postponeDays` (hoy no = 1).
  Future<void> decideProposal(
    String id,
    String kind,
    ProposalStatus status, {
    required DateTime today,
    int postponeDays = proposalTodayOnlyDays,
    String evidence = '',
  }) {
    final d0 = dateOnly(today);
    return db.into(db.coachProposals).insertOnConflictUpdate(CoachProposalsCompanion.insert(
          id: id,
          kind: kind,
          status: status.name,
          evidence: evidence,
          createdOn: dayKey(d0),
          decidedOn: Value(dayKey(d0)),
          reviewAfter: Value(status == ProposalStatus.pospuesta ? dayKey(addDays(d0, postponeDays)) : null),
          policy: const Value(coachPolicy),
        ));
  }

  /// Decisión de un ejercicio de fuerza más reciente (para revisar si una
  /// subida aceptada se sostuvo).
  Future<(String, ProposalRecord)?> lastDecision(String kind) async {
    final row = await (db.select(db.coachProposals)
          ..where((t) => t.kind.equals(kind))
          ..orderBy([(t) => OrderingTerm(expression: t.decidedOn, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : (row.id, _record(row));
  }

  /// Decide una propuesta de pasos. Idempotente por ID: decidir dos veces
  /// deja la última decisión y una sola vigencia.
  Future<void> decideSteps(
    StepsProposal p,
    ProposalStatus status, {
    required DateTime today,
    int? acceptedValue,
    String evidence = '',
  }) =>
      db.transaction(() async {
        final d0 = dateOnly(today);
        final previous = await proposal(p.id);
        if (previous?.status == ProposalStatus.aceptada && status == ProposalStatus.aceptada) return;
        await db.into(db.coachProposals).insertOnConflictUpdate(CoachProposalsCompanion.insert(
              id: p.id,
              kind: 'pasos',
              status: status.name,
              evidence: evidence,
              createdOn: dayKey(d0),
              decidedOn: Value(dayKey(d0)),
              reviewAfter: Value(status == ProposalStatus.pospuesta ? dayKey(addDays(d0, coachPostponeDays)) : null),
              acceptedValue: Value(status == ProposalStatus.aceptada ? (acceptedValue ?? p.to).toDouble() : null),
              policy: const Value(coachPolicy),
            ));
        if (status == ProposalStatus.aceptada) {
          // Aceptar cambia sólo el futuro: rige desde mañana. El perfil (lo
          // que leen Hoy y los avisos) no cambia hoy; lo proyecta
          // `projectDueGoals` cuando la vigencia llega.
          await scheduleGoal(
            GoalMetric.pasos,
            (acceptedValue ?? p.to).toDouble(),
            effectiveFrom: addDays(d0, 1),
            origin: GoalOrigin.propuesta,
            reason: 'Propuesta ${p.id}: ${p.daysAtGoal} días en la meta, promedio ${p.average}',
            now: d0,
          );
        }
      });
}
