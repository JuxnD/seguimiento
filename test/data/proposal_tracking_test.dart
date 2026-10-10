import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/adaptive_coach.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

/// Plan 009: seguimiento de propuestas con criterios existentes (fuerza de
/// 008, rondas de §2, escaleras de §19.10). Aceptar, posponer y rechazar
/// cambian el futuro; nada se sube solo.
void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late DashboardRepository dashboard;
  late GoalRepository goals;

  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);

  setUp(() async {
    db = openInMemoryDatabase();
    plan = PlanRepository(db, ExerciseRepository(db));
    training = TrainingRepository(db, ExerciseRepository(db));
    dashboard = DashboardRepository(db, plan, NutritionRepository(db), ProfileRepository(db));
    goals = GoalRepository(db);
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, d(10, 12));
  });

  tearDown(() => db.close());

  group('dominio', () {
    test('IDs estables por evidencia y visibilidad de la decisión', () {
      expect(strengthProposalId('Fondos en barra', 41), 'fuerza:Fondos en barra:s41:p1');
      expect(proposalSessionId('fuerza:Fondos en barra:s41:p1'), 41);
      expect(roundsProposalId(fromRounds: 8, toRounds: 9, sessionId: 7), 'rondas:8>9:s7:p1');
      expect(ladderProposalId('v_up', 1, d(10, 15)), 'escalera:v_up:1>2:2026-10-15:p1');
      const rejected = ProposalRecord(id: 'x', status: ProposalStatus.rechazada);
      final postponed = ProposalRecord(id: 'x', status: ProposalStatus.pospuesta, reviewAfter: d(10, 21));
      expect(
          [proposalHidden(null, d(10, 20)), proposalHidden(rejected, d(12, 1)), proposalHidden(postponed, d(10, 20))],
          [false, true, true]);
      expect(proposalHidden(postponed, d(10, 21)), isFalse, reason: 'hoy no = sólo hoy');
    });
  });

  group('fuerza', () {
    Future<int> tuesdaySession(DateTime date,
        {int reps = 10, bool failure = false, double? loadKg, int sets = 4, String? mode}) async {
      final tuesday = (await plan.dayFor(date))!;
      return training.save(SessionDraft(
        date: date,
        type: SessionType.trenSuperior,
        planDayId: tuesday.dayId,
        mode: mode,
        sets: [
          for (var i = 0; i < sets; i++)
            SetDraft(exercise: 'Fondos en barra', reps: reps, rir: 2, toFailure: failure && i == sets - 1, loadKg: loadKg),
        ],
      ));
    }

    Future<StrengthAdvice> dips(DateTime date) async =>
        (await dashboard.today(now: date)).strength.firstWhere((a) => a.exercise == 'Fondos en barra');

    test('mantener oculta la subida para esa evidencia; otra sesión es otra propuesta', () async {
      await tuesdaySession(d(10, 13));
      final a = await dips(d(10, 20));
      expect(a.status, StrengthStatus.subir);
      await goals.decideProposal(a.proposalId!, strengthProposalKind(a.exercise), ProposalStatus.rechazada, today: d(10, 20));
      final kept = await dips(d(10, 20));
      expect((kept.status, kept.text), (StrengthStatus.mantener, 'decidiste mantener la dosis con esta evidencia'));
      await tuesdaySession(d(10, 20));
      final next = await dips(d(10, 27));
      expect((next.status, next.decision), (StrengthStatus.subir, null), reason: 'evidencia nueva, propuesta nueva');
    });

    test('"hoy no" vale sólo hoy: el próximo martes vuelve', () async {
      await tuesdaySession(d(10, 13));
      final a = await dips(d(10, 20));
      await goals.decideProposal(a.proposalId!, strengthProposalKind(a.exercise), ProposalStatus.pospuesta, today: d(10, 20));
      expect((await dips(d(10, 20))).text, 'hoy no (lo pospusiste)');
      expect((await dips(d(10, 27))).status, StrengthStatus.subir, reason: 'martes siguiente, misma evidencia');
    });

    /// Martes 13 con 4×10 limpias: la regla propone +2–5 kg; se acepta el 20
    /// con la dosis guardada y la sesión del 20 la intenta (o no).
    Future<String?> reviewAfter(Future<void> Function() attempt, {bool withDose = true}) async {
      await db.delete(db.sessions).go();
      await db.delete(db.coachProposals).go();
      await tuesdaySession(d(10, 13));
      final a = await dips(d(10, 20));
      expect((a.status, a.dose?.kind, a.dose?.sets), (StrengthStatus.subir, DoseKind.carga, 4));
      await goals.decideProposal(a.proposalId!, strengthProposalKind(a.exercise), ProposalStatus.aceptada,
          today: d(10, 20), evidence: withDose ? a.dose!.encode() : a.text);
      expect((await dips(d(10, 20))).decision, ProposalStatus.aceptada);
      expect((await dips(d(10, 20))).review, isNull, reason: 'sin sesión todavía no hay revisión');
      await attempt();
      return (await dips(d(10, 27))).review;
    }

    test('subida aceptada (R2): sólo "subiste" si lo guardado lo demuestra', () async {
      expect(await reviewAfter(() => tuesdaySession(d(10, 20), reps: 10)),
          'aceptaste subir; el 20 oct repetiste peso corporal: no demuestra la subida',
          reason: 'mismo peso: aceptar "Lo intento hoy" no es subir');
      expect(await reviewAfter(() => tuesdaySession(d(10, 20), reps: 7, loadKg: 4)),
          'subiste a 4 kg y se sostuvo el 20 oct (4 series limpias)');
      expect(await reviewAfter(() => tuesdaySession(d(10, 20), reps: 7, loadKg: 4, sets: 1)),
          'aceptaste subir a 4 kg; el 20 oct sólo 1 de 4 series con la subida: no demostrada');
      expect(await reviewAfter(() => tuesdaySession(d(10, 20), reps: 7, loadKg: 4, failure: true)),
          'subiste a 4 kg; el 20 oct no se sostuvo: llegaste al fallo');
      expect(await reviewAfter(() => tuesdaySession(d(10, 20), reps: 5, loadKg: 4)),
          'subiste a 4 kg; el 20 oct no se sostuvo: la más baja fue 5, bajo el piso de 6');
      expect(await reviewAfter(() => tuesdaySession(d(10, 20), reps: 7, loadKg: 4, mode: 'tecnica')),
          'aceptaste subir; el 20 oct fue otro protocolo: no demuestra la subida');
      expect(await reviewAfter(() => tuesdaySession(d(10, 20), reps: 7, loadKg: 10)),
          'aceptaste subir (+2–5 kg de mochila); el 20 oct usaste 10 kg: no es la subida acordada',
          reason: 'no se inventa otra cifra de subida');
      expect(await reviewAfter(() => tuesdaySession(d(10, 20), reps: 7, loadKg: 4), withDose: false),
          'aceptaste subir; no quedó guardada la dosis acordada: no se puede revisar',
          reason: 'no se infiere la dosis desde el texto');
    });
  });

  group('rondas', () {
    test('"hoy no" deja las rondas de la última vez hoy; el viernes siguiente vuelve', () async {
      await training.save(SessionDraft(
        date: d(10, 9),
        type: SessionType.progresion,
        roundsDone: 8,
        plannedRounds: 8,
        rpe: 7,
        techniqueOk: true,
        fullRange: true,
        recoveryOk: true,
      ));
      final today = await dashboard.today(now: d(10, 16));
      final p = today.proposal!;
      expect((p.canProgress, p.rounds, today.roundsDecision), (true, 9, null));
      await goals.decideProposal(
          roundsProposalId(fromRounds: p.lastRounds, toRounds: p.rounds, sessionId: p.sessionId!), 'rondas',
          ProposalStatus.pospuesta,
          today: d(10, 16));
      final held = await dashboard.today(now: d(10, 16));
      expect((held.proposal!.canProgress, held.targetRounds, held.roundsDecision),
          (false, 8, ProposalStatus.pospuesta));
      expect(held.proposal!.unmet, ['hoy no (lo pospusiste)']);
      final later = await dashboard.today(now: d(10, 23));
      expect(later.proposal!.rounds, 9, reason: 'la regla vuelve a ofrecerla');
    });
  });

  group('escaleras', () {
    test('"en 7 días" oculta la propuesta de subir en Hoy hasta su fecha; subir sigue en la confirmación existente', () async {
      for (final day in [d(10, 19), d(10, 26)]) {
        await training.save(SessionDraft(date: day, type: SessionType.trenSuperior, sets: [
          for (var i = 0; i < 3; i++) SetDraft(exercise: 'Encogimiento inverso', reps: 12),
          for (var i = 0; i < 3; i++) SetDraft(exercise: hollowHold, reps: 40),
        ]));
      }
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        todayProvider.overrideWith(() => _Fixed(d(10, 27))),
      ]);
      addTearDown(container.dispose);
      final advice = await container.read(ladderAdviceProvider.future);
      expect(advice['dragon_flag']!.canStepUp, isTrue);
      final decisions = await container.read(ladderDecisionsProvider.future);
      final entry = decisions['dragon_flag']!;
      expect(entry.decision, isNull);
      await goals.decideProposal(entry.id, 'escalera:dragon_flag', ProposalStatus.pospuesta,
          today: d(10, 27), postponeDays: coachPostponeDays);
      container.invalidate(ladderDecisionsProvider);
      final after = (await container.read(ladderDecisionsProvider.future))['dragon_flag']!;
      expect(proposalHidden(after.decision, d(10, 27)), isTrue);
      expect(proposalHidden(after.decision, d(11, 3)), isFalse);
    });
  });
}

class _Fixed extends TodayNotifier {
  _Fixed(this.day);
  final DateTime day;
  @override
  DateTime build() => dateOnly(day);
}
