import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/session_script.dart';
import 'package:seguimiento/domain/warmup.dart';

/// Calentamiento guiado (§16.23).
void main() {
  ScriptExercise ex(String name, {int? reps, int? hold, bool perSide = false, String? block}) =>
      ScriptExercise(name: name, sets: 3, repsMin: reps, repsMax: reps, holdSecMin: hold, perSide: perSide, blockName: block);

  final circuit = ScriptDay(type: DayType.progresion, exercises: [
    ex('Pino pecho a la pared', hold: 300, block: 'pino'),
    ex('Dominadas', reps: 5),
    ex('Flexiones', reps: 10),
    ex('Sentadillas', reps: 15),
  ]);
  final push = ScriptDay(type: DayType.trenSuperior, exercises: [ex('Fondos en barra', reps: 6), ex('Flexión a una mano', reps: 3, perSide: true)]);
  final legs = ScriptDay(type: DayType.piernas, exercises: [ex('Sentadilla búlgara', reps: 8, perSide: true)]);

  test('aproximación: 40 % hacia abajo, mínimo 1', () {
    expect([5, 10, 15, 8, 3, 1, 2].map(approachReps), [2, 4, 6, 3, 1, 1, 1]);
  });

  test('circuito: movilidad, activación de tirón y una ronda de aproximación', () {
    final w = buildWarmup(circuit);
    expect(w.where((i) => i.stage == WarmupStage.movilidad).map((i) => i.seconds), [30, 30, 30, 30]);
    expect(warmupFocusFor(circuit), WarmupFocus.tiron);
    expect(w.where((i) => i.stage == WarmupStage.activacion).map((i) => i.exercise),
        ['Colgado pasivo', 'Retracciones escapulares']);
    expect(w.where((i) => i.stage == WarmupStage.aproximacion).map((i) => '${i.exercise} ${i.reps}'),
        ['Dominadas 2', 'Flexiones 4', 'Sentadillas 6'],
        reason: 'el pino es bloque previo, no entra en la aproximación');
  });

  test('empuje y piernas activan distinto; sólo el primer ejercicio se aproxima', () {
    expect(buildWarmup(push).where((i) => i.stage == WarmupStage.activacion).map((i) => i.exercise),
        ['Flexiones escapulares', 'Muñecas (planche)']);
    final approach = buildWarmup(push).where((i) => i.stage == WarmupStage.aproximacion).toList();
    expect(approach.map((i) => '${i.exercise} ${i.reps}'), ['Fondos en barra 2']);
    expect(buildWarmup(legs).where((i) => i.stage == WarmupStage.activacion).map((i) => i.exercise),
        ['Sentadillas', 'Puente de glúteo']);
    expect(buildWarmup(legs).last.note, 'Por lado');
  });

  test('con FIFA 11+ sólo queda la aproximación', () {
    final w = buildWarmup(legs, ownWarmup: true);
    expect(w.map((i) => i.stage).toSet(), {WarmupStage.aproximacion});
  });

  test('una molestia se avisa, no agrega un ejercicio', () {
    expect(buildWarmup(push).length, buildWarmup(push).length);
    final notes = soreWarmupNotes({'Hombro': 5, 'Rodilla': 2, 'Codo': 3}, order: ['Rodilla', 'Hombro', 'Codo']);
    expect(notes, hasLength(2), reason: 'rodilla 2/10 no llega al umbral');
    expect(notes.first, startsWith('Molestia en hombro (5/10)'));
    expect(soreWarmupNotes(const {}), isEmpty);
  });

  test('las claves son estables y el registro dice lo hecho', () {
    final keys = buildWarmup(circuit).map((i) => i.key).toList();
    expect(keys.toSet(), hasLength(keys.length));
    expect(warmupRecord(done: 7, total: 9, seconds: 340, skipped: false), 'Calentamiento: 7 de 9 pasos (5:40)');
    expect(warmupRecord(done: 0, total: 9, seconds: 0, skipped: true), 'Calentamiento saltado');
  });

  test('antes de un test: torso sin aproximación; piernas con el FIFA 11+', () {
    final torso = testWarmup(torso: true);
    expect(torso.where((i) => i.stage == WarmupStage.aproximacion), isEmpty);
    expect(torso.map((i) => i.exercise), containsAll(['Colgado pasivo', 'Flexiones escapulares']));
    expect(testWarmup(torso: false).single.exercise, 'Calentamiento tipo FIFA 11+');
    expect(preAttemptChecklist, hasLength(4));
  });
}
