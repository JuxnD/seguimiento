import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/session_script.dart';

/// Lunes del plan: 6 rondas de 5 dominadas + 10 flexiones + 15 sentadillas.
ScriptDay circuitDay({int rounds = 6, List<ScriptExercise> extras = const []}) => ScriptDay(
      type: DayType.circuito,
      targetRounds: rounds,
      restBetweenRoundsSec: 30,
      exercises: [
        const ScriptExercise(name: 'Dominadas', repsMin: 5),
        const ScriptExercise(name: 'Flexiones', repsMin: 10),
        const ScriptExercise(name: 'Sentadillas', repsMin: 15),
        ...extras,
      ],
    );

/// Martes del plan: dominadas 4×6–8, flexiones 4×14–16, sentadillas 3×25.
ScriptDay blockDay() => const ScriptDay(
      type: DayType.bloques,
      exercises: [
        ScriptExercise(name: 'Dominadas', sets: 4, repsMin: 6, repsMax: 8, restSec: 90, restSecMax: 120),
        ScriptExercise(name: 'Flexiones', sets: 4, repsMin: 14, repsMax: 16, restSec: 90, restSecMax: 120),
        ScriptExercise(name: 'Sentadillas', sets: 3, repsMin: 25, restSec: 60),
      ],
    );

void main() {
  group('circuito', () {
    test('cada ronda recorre los tres ejercicios seguidos', () {
      final steps = buildScript(circuitDay(rounds: 2));
      final work = steps.whereType<WorkStep>().toList();
      expect(work.map((s) => s.exercise), [
        'Dominadas', 'Flexiones', 'Sentadillas', //
        'Dominadas', 'Flexiones', 'Sentadillas',
      ]);
      expect(work.every((s) => s.isRound), isTrue);
      expect(work.first.counterLabel, 'Ronda 1/2');
      expect(work.last.counterLabel, 'Ronda 2/2');
    });

    test('no hay descanso dentro de la ronda, solo al cerrarla', () {
      final steps = buildScript(circuitDay(rounds: 3));
      // Entre los tres ejercicios de una ronda no debe haber descansos.
      expect(steps[0], isA<WorkStep>());
      expect(steps[1], isA<WorkStep>());
      expect(steps[2], isA<WorkStep>());
      expect(steps[3], isA<RestStep>());
      expect((steps[3] as RestStep).seconds, 30);
      expect((steps[3] as RestStep).nextLabel, 'Ronda 2: Dominadas');
    });

    test('la última ronda no termina en descanso', () {
      final steps = buildScript(circuitDay(rounds: 2));
      expect(steps.last, isA<WorkStep>());
      expect(steps.whereType<RestStep>().length, 1);
    });

    test('se puede bajar el objetivo de rondas del día', () {
      expect(workStepCount(buildScript(circuitDay(rounds: 6), rounds: 5)), 15);
    });
  });

  group('bloques', () {
    test('agota un ejercicio antes de pasar al siguiente', () {
      final work = buildScript(blockDay()).whereType<WorkStep>().toList();
      expect(work.length, 11, reason: '4 + 4 + 3 series');
      expect(work.take(4).map((s) => s.exercise).toSet(), {'Dominadas'});
      expect(work.map((s) => s.counterLabel).take(5).toList(),
          ['Serie 1/4', 'Serie 2/4', 'Serie 3/4', 'Serie 4/4', 'Serie 1/4']);
      expect(work.every((s) => s.isRound), isFalse);
    });

    test('el descanso sale del plan y anuncia qué sigue', () {
      final steps = buildScript(blockDay());
      final firstRest = steps[1] as RestStep;
      expect(firstRest.seconds, 90);
      expect(firstRest.maxSec, 120);
      expect(firstRest.label, '90–120 s');
      expect(firstRest.nextLabel, 'Dominadas, serie 2/4');

      // Al cerrar las 4 series de dominadas, anuncia el siguiente ejercicio.
      final rests = steps.whereType<RestStep>().toList();
      expect(rests[3].nextLabel, 'Siguiente: Flexiones');
      expect(rests.last.seconds, 60, reason: 'sentadillas descansan 60 s');
    });

    test('la última serie del último ejercicio no lleva descanso', () {
      final steps = buildScript(blockDay());
      expect(steps.last, isA<WorkStep>());
    });

    test('el objetivo de cada serie viene del plan', () {
      final work = buildScript(blockDay()).whereType<WorkStep>().toList();
      expect(work.first.targetLabel, '6–8');
      expect(work.first.targetReps, 6);
      expect(work[4].targetLabel, '14–16');
      expect(work.last.targetLabel, '25');
    });
  });

  group('bloques extra del plan v2', () {
    final core = [
      const ScriptExercise(name: 'Elevación de piernas colgado', sets: 2, repsMin: 8, repsMax: 12, blockName: 'core', variant: 'A'),
      const ScriptExercise(name: 'Hollow body hold', sets: 2, holdSecMin: 20, holdSecMax: 40, blockName: 'core', variant: 'A'),
      const ScriptExercise(name: 'Plancha lateral', sets: 2, holdSecMin: 30, holdSecMax: 45, perSide: true, blockName: 'core', variant: 'B'),
    ];

    test('van después del circuito y solo la variante elegida', () {
      final steps = buildScript(circuitDay(rounds: 1, extras: core), coreVariant: 'A');
      final work = steps.whereType<WorkStep>().toList();
      expect(work.take(3).map((s) => s.exercise), ['Dominadas', 'Flexiones', 'Sentadillas']);
      expect(work.skip(3).map((s) => s.exercise).toSet(),
          {'Elevación de piernas colgado', 'Hollow body hold'});
      expect(work.skip(3).every((s) => s.blockName == 'core'), isTrue);
      expect(work.any((s) => s.exercise == 'Plancha lateral'), isFalse);
    });

    test('los sostenes se muestran en segundos y por lado', () {
      final steps = buildScript(circuitDay(rounds: 1, extras: core), coreVariant: 'B');
      final plancha = steps.whereType<WorkStep>().firstWhere((s) => s.exercise == 'Plancha lateral');
      expect(plancha.targetLabel, '30–45 s · por lado');
      expect(plancha.holdSec, 30);
      expect(plancha.targetReps, isNull);
    });
  });

  group('cierre anticipado', () {
    test('cuenta solo las rondas completas', () {
      final steps = buildScript(circuitDay(rounds: 8));
      // 7 rondas completas = 21 trabajos + 6 descansos intercalados.
      final doneSteps = steps.indexOf(steps.whereType<WorkStep>().toList()[21 - 1]) + 1;
      expect(completedRounds(steps, doneSteps, exercisesPerRound: 3), 7);
    });

    test('una ronda a medias no cuenta', () {
      final steps = buildScript(circuitDay(rounds: 8));
      final doneSteps = steps.indexOf(steps.whereType<WorkStep>().toList()[22 - 1]) + 1;
      expect(completedRounds(steps, doneSteps, exercisesPerRound: 3), 7);
    });

    test('en bloques no se reportan rondas', () {
      final steps = buildScript(blockDay());
      expect(completedRounds(steps, steps.length, exercisesPerRound: 3), 0,
          reason: 'las series de bloques nunca son rondas de circuito');
    });
  });
}
