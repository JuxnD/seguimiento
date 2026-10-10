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

/// Primera vigencia de cada meta: la instalación nueva desde hoy, la base
/// migrada como legado (sin fecha). No duplica si ya hay vigencias.
Future<void> seedGoalVersions(AppDatabase db, {required DateTime? effectiveFrom, required String origin}) async {
  final existing = await db.select(db.goalVersions).get();
  if (existing.isNotEmpty) return;
  final profile = await (db.select(db.profiles)..where((t) => t.id.equals(1))).getSingleOrNull();
  if (profile == null) return;
  final now = dateOnly(DateTime.now());
  for (final e in goalsOfProfile(profile).entries) {
    await db.into(db.goalVersions).insert(GoalVersionsCompanion.insert(
          metric: e.key.name,
          value: Value(e.value),
          effectiveFrom: Value(effectiveFrom == null ? null : dayKey(effectiveFrom)),
          acceptedAt: dayKey(now),
          origin: origin,
        ));
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

  Future<void> updateProfile(
    ProfilesCompanion data, {
    required String origin,
    String? reason,
    DateTime? effectiveFrom,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final today = dateOnly(now ?? DateTime.now());
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
          // Aceptar cambia sólo el futuro: rige desde mañana.
          await updateProfile(
            ProfilesCompanion(stepsTarget: Value(acceptedValue ?? p.to)),
            origin: GoalOrigin.propuesta,
            reason: 'Propuesta ${p.id}: ${p.daysAtGoal} días en la meta, promedio ${p.average}',
            effectiveFrom: addDays(d0, 1),
            now: d0,
          );
        }
      });
}
