import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/adaptive_coach.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:seguimiento/domain/recovery.dart';

/// Plan 009: metas con historia y lectura de pasos (ADR 0016).
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);
  const calm = LoadReading(todayLoad: 0, todayCount: 0, intenseStreak: 0);
  const streak = LoadReading(todayLoad: 0, todayCount: 0, intenseStreak: 3);

  /// Pasos entre semana de la ventana que termina el día antes de `today`.
  Map<DateTime, int> weekdays(DateTime today, int Function(int i) value, {int skip = 0}) {
    final w = coachWindow(today);
    return {for (var i = skip; i < w.length; i++) w[i]: value(i)};
  }

  CoachReading read(
    DateTime today,
    Map<DateTime, int> steps, {
    int goal = 5000,
    DateTime? since,
    LoadReading load = calm,
    bool fatigue = false,
    bool recoveryKnown = true,
    ProposalRecord? last,
  }) =>
      stepsReading(
        today: today,
        steps: steps,
        goal: goal,
        goalSince: since,
        stepsGoalOn: (_) => goal,
        load: load,
        fatigue: fatigue,
        recoveryKnown: recoveryKnown,
        last: last,
      );

  group('metas con historia', () {
    final history = GoalHistory([
      GoalVersion(metric: GoalMetric.pasos, value: 7500, effectiveFrom: null, acceptedAt: d(10, 10), origin: GoalOrigin.legado),
      GoalVersion(id: 2, metric: GoalMetric.pasos, value: 5000, effectiveFrom: d(10, 12), acceptedAt: d(10, 11), origin: GoalOrigin.perfil),
    ]);

    test('un día anterior al cambio no se reclasifica con la meta nueva', () {
      final before = history.on(GoalMetric.pasos, d(10, 9))!;
      expect((before.value, before.known), (7500, false), reason: 'legado: meta histórica no registrada');
      final after = history.on(GoalMetric.pasos, d(10, 12))!;
      expect((after.value, after.known, after.since), (5000, true, d(10, 12)));
      expect(6000 >= after.value!, isTrue);
      expect(before.known, isFalse, reason: 'el 6.000 del 9 oct no se cuenta como cumplido ni fallido');
    });

    test('mismo día: gana la última registrada; la anterior queda para volver', () {
      final h = GoalHistory([
        ...history.versions,
        GoalVersion(id: 3, metric: GoalMetric.pasos, value: 6000, effectiveFrom: d(10, 12), acceptedAt: d(10, 12), origin: GoalOrigin.perfil),
      ]);
      expect(h.on(GoalMetric.pasos, d(10, 12))!.value, 6000);
      expect(h.current(GoalMetric.pasos, d(10, 20))!.value, 6000);
      expect(h.previous(GoalMetric.pasos, d(10, 20))!.value, 5000);
    });

    test('una vigencia futura no rige hoy', () {
      final h = GoalHistory([
        ...history.versions,
        GoalVersion(id: 4, metric: GoalMetric.pasos, value: 6500, effectiveFrom: d(10, 21), acceptedAt: d(10, 20), origin: GoalOrigin.propuesta),
      ]);
      expect(h.on(GoalMetric.pasos, d(10, 20))!.value, 5000);
      expect(h.on(GoalMetric.pasos, d(10, 21))!.value, 6500);
    });
  });

  group('lectura de pasos', () {
    final today = d(11, 2);

    test('nuevo perfil sin datos: faltan datos, sin éxitos inventados', () {
      final r = read(today, const {});
      expect(r.state, CoachState.faltanDatos);
      expect(r.proposal, isNull);
      expect(r.reason, contains('0 de 10'));
    });

    test('pocos días registrados: faltan datos aunque los que hay sean buenos', () {
      final r = read(today, weekdays(today, (_) => 9000, skip: 3));
      expect(r.state, CoachState.faltanDatos);
    });

    test('racha intensa o cansancio declarado: recuperación primero, sin presión de caminatas', () {
      final steps = weekdays(today, (_) => 9000);
      for (final r in [read(today, steps, load: streak), read(today, steps, fatigue: true)]) {
        expect(r.state, CoachState.recuperacion);
        expect(r.recoveryFirst, isTrue);
        expect(r.proposal, isNull);
        expect(r.action, contains('Sin caminata extra'));
      }
    });

    test('diez rondas sin chequeo: no presume cansancio ni recuperación', () {
      expect(declaredFatigue(rpeTodayAndYesterday: const [null, null]), isFalse);
      expect(declaredFatigue(rpeTodayAndYesterday: const [10, null]), isTrue);
      expect(declaredFatigue(rpeTodayAndYesterday: const [7], morningFeeling: 3), isTrue);
      expect(declaredFatigue(rpeTodayAndYesterday: const [7], morningFeeling: 2), isFalse);
    });

    test('cumple holgado: propone subir a su promedio redondeado, con ID estable', () {
      final steps = weekdays(today, (i) => 6400 + i * 20);
      final r = read(today, steps);
      expect(r.state, CoachState.propuesta);
      expect((r.proposal!.from, r.proposal!.to), (5000, 6000), reason: 'promedio 6.490 → 6.000, nunca por encima');
      expect(r.proposal!.id, 'pasos:5000>6000:p1');
      expect(read(today, steps).proposal!.id, r.proposal!.id, reason: 'misma entrada, misma decisión');
      expect(read(addDays(today, 1), weekdays(addDays(today, 1), (i) => 6400 + i * 20)).proposal!.id, r.proposal!.id,
          reason: 'al día siguiente, misma evidencia: no es otra propuesta');
    });

    test('sin ninguna señal de recuperación conocida no se propone subir', () {
      final r = read(today, weekdays(today, (i) => 6400 + i * 20), recoveryKnown: false);
      expect((r.state, r.proposal), (CoachState.faltanDatos, null));
      expect(r.reason, contains('falta saber cómo te recuperas'));
    });

    test('carga alta hoy (90 min a RPE 8) o dos sesiones hoy frenan la propuesta ese día', () {
      final steps = weekdays(today, (i) => 6400 + i * 20);
      const heavy = LoadReading(todayLoad: 720, todayCount: 1, intenseStreak: 1);
      const twice = LoadReading(todayLoad: 300, todayCount: 2, intenseStreak: 1);
      for (final load in [heavy, twice]) {
        final r = read(today, steps, load: load);
        expect((r.state, r.proposal), (CoachState.observar, null));
        expect(r.reason, contains('la revisión espera'));
      }
    });

    test('un rechazo vale para su ventana: con una ventana nueva completa se reconsidera', () {
      final rejected = ProposalRecord(id: 'pasos:5000>6000:p1', status: ProposalStatus.rechazada, decidedOn: today);
      final steps = weekdays(today, (i) => 6400 + i * 20);
      expect(read(today, steps, last: rejected).state, CoachState.observar);
      final d13 = addDays(today, 13);
      expect(read(d13, weekdays(d13, (i) => 6400 + i * 20), last: rejected).state, CoachState.observar,
          reason: 'sin repetirse cada mañana dentro de la ventana');
      final d14 = addDays(today, 14);
      expect(read(d14, weekdays(d14, (i) => 6400 + i * 20), last: rejected).state, CoachState.propuesta);
    });

    test('cumple justo: se mantiene, no propone', () {
      final r = read(today, weekdays(today, (i) => i.isEven ? 5200 : 4800));
      expect(r.state, CoachState.observar);
      expect(r.proposal, isNull);
    });

    test('rechazada con la misma evidencia no insiste; pospuesta espera su fecha', () {
      final steps = weekdays(today, (i) => 6400 + i * 20);
      final rejected = read(today, steps,
          last: const ProposalRecord(id: 'pasos:5000>6000:p1', status: ProposalStatus.rechazada));
      expect(rejected.state, CoachState.observar);
      expect(rejected.reason, contains('rechazaste'));

      final postponed = ProposalRecord(id: 'pasos:5000>6000:p1', status: ProposalStatus.pospuesta, reviewAfter: d(11, 5));
      expect(read(today, steps, last: postponed).state, CoachState.observar);
      expect(read(d(11, 5), weekdays(d(11, 5), (i) => 6400 + i * 20), last: postponed).state, CoachState.propuesta);

      final accepted = read(today, steps,
          last: ProposalRecord(id: 'pasos:5000>6000:p1', status: ProposalStatus.aceptada, decidedOn: today));
      expect((accepted.state, accepted.proposal, accepted.nextReview), (CoachState.aceptada, null, d(11, 17)));

      final otherEvidence = read(today, weekdays(today, (i) => 7600 + i * 20),
          last: const ProposalRecord(id: 'pasos:5000>6000:p1', status: ProposalStatus.rechazada));
      expect(otherEvidence.proposal?.id, 'pasos:5000>7500:p1', reason: 'otra cifra es otra evidencia');
    });

    test('meta recién cambiada: en prueba hasta su revisión; luego, si no se sostiene, revisar', () {
      final steps = weekdays(today, (_) => 4000);
      final trial = read(today, steps, goal: 6000, since: d(10, 26));
      expect(trial.state, CoachState.aceptada);
      expect(trial.nextReview, d(11, 9));
      final review = read(d(11, 9), weekdays(d(11, 9), (_) => 4000), goal: 6000, since: d(10, 26));
      expect(review.state, CoachState.revisar);
      expect(review.proposal, isNull, reason: 'bajar la meta lo decide la persona');
    });

    test('días con meta histórica no registrada no se clasifican', () {
      final steps = weekdays(today, (_) => 9000);
      final w = coachWindow(today);
      final r = stepsReading(
        today: today,
        steps: steps,
        goal: 5000,
        stepsGoalOn: (day) => day.isBefore(w[5]) ? null : 5000,
        load: calm,
        fatigue: false,
      );
      expect(r.evidence, contains('5 días con meta histórica no registrada'));
      expect(r.proposal, isNull, reason: 'sólo 5 días juzgables: menos que la cobertura mínima');
    });
  });
}
