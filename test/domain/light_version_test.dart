import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/active_session.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/session_script.dart';

/// Lunes 28 sep: plan v2 tras un domingo de fútbol intenso.
void main() {
  final monday = planV2().days[0];

  test('Hoy muestra el core además del circuito, una línea por variante', () {
    expect(monday.main.map((e) => e.name), ['Dominadas', 'Flexiones', 'Sentadillas']);
    expect(blockLines(monday), [
      'Core A: Elevación de piernas colgado 3×8–12 · Hollow body hold 2×20–40s',
      'Core B: Elevación de piernas colgado 3×8–12 · Plancha lateral 2×30–45s · por lado',
    ]);
  });

  test('la versión ligera: 5 rondas, elevaciones 2×8–10 y hollow 2×20–30 s', () {
    final light = lightVersion(monday);
    expect(light.targetRounds, 5);
    expect(light.main.map((e) => e.targetLabel), monday.main.map((e) => e.targetLabel),
        reason: 'el circuito no cambia de repeticiones');
    final coreA = light.exercises.where((e) => e.variant == 'A').toList();
    expect(coreA.map((e) => '${e.name} ${e.targetLabel}'), [
      'Elevación de piernas colgado 2×8–10',
      'Hollow body hold 2×20–30s',
    ]);
    expect(monday.targetRounds, 6, reason: 'el plan original no se toca');
  });

  test('el guion de la versión ligera tiene 5 rondas y el core recortado', () {
    final light = lightVersion(monday);
    final script = buildScript(
      ScriptDay(
        type: light.type,
        targetRounds: light.targetRounds,
        restBetweenRoundsSec: light.restBetweenRoundsSec,
        exercises: [
          for (final e in light.exercises)
            ScriptExercise(
              name: e.name,
              sets: e.sets,
              repsMin: e.repsMin,
              repsMax: e.repsMax,
              holdSecMin: e.holdSecMin,
              holdSecMax: e.holdSecMax,
              perSide: e.perSide,
              blockName: e.block,
              variant: e.variant,
            ),
        ],
      ),
      coreVariant: 'A',
    );
    final work = script.whereType<WorkStep>().toList();
    expect(work.where((s) => s.isRound).length, 5 * 3);
    expect(work.where((s) => s.exercise == 'Elevación de piernas colgado').length, 2);
    expect(work.where((s) => s.exercise == 'Hollow body hold').length, 2);
  });

  test('un día de bloques pierde una serie en lo que tiene 3 o más', () {
    final day = PlanDayDraft(weekday: 2, type: DayType.bloques, exercises: [
      PlanExerciseDraft(name: 'Dominadas', sets: 4, repsMin: 6, repsMax: 8),
      PlanExerciseDraft(name: 'Fondos', sets: 2, repsMin: 8, repsMax: 12),
    ]);
    final light = lightVersion(day);
    expect(light.exercises.map((e) => e.targetLabel), ['3×6–8', '2×8–10']);
  });

  test('retomar una sesión ligera la reconstruye ligera', () {
    final snap = GuidedSnapshot(
      date: '2026-09-28',
      startedAt: DateTime(2026, 9, 28, 15),
      planDayId: 1,
      phase: GuidedPhase.trabajo,
      index: 3,
      light: true,
    );
    final back = ActiveSession.fromJson(snap.toJson()) as GuidedSnapshot;
    expect(back.light, isTrue);
    final old = Map.of(snap.toJson())..remove('light');
    expect((ActiveSession.fromJson(old) as GuidedSnapshot).light, isFalse, reason: 'fotos viejas');
  });
}
