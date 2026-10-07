import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/core_ladders.dart';
import 'package:seguimiento/domain/fitness_test.dart';

/// Escaleras de core (§19.10) y test de condición (§19.11).
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);
  LadderSession session(DateTime date, {int reps = 12, int hollow = 40}) => LadderSession(date: date, sets: {
        'Encogimiento inverso': [reps, reps, reps],
        hollowHold: [hollow, hollow, hollow],
      });

  group('escaleras', () {
    test('empiezan en el peldaño 1: dragon flag el lunes, V-up el jueves', () {
      expect(dragonFlagLadder.stepAt(1).exercise, 'Encogimiento inverso');
      expect(dragonFlagLadder.weekday, DateTime.monday);
      expect(vUpLadder.stepAt(1).exercise, 'Tuck-up');
      expect(vUpLadder.weekday, DateTime.thursday);
      expect(dragonFlagLadder.top, 6);
      expect(vUpLadder.top, 4);
    });

    test('sube con el criterio en 2 sesiones seguidas y 2 semanas en el peldaño', () {
      final a = ladderAdvice(dragonFlagLadder, 1, d(10, 12), [session(d(10, 19)), session(d(10, 26))], d(10, 26));
      expect(a.cleanInARow, 2);
      expect(a.canStepUp, isTrue);
    });

    test('nunca antes de 2 semanas en el peldaño', () {
      final a = ladderAdvice(dragonFlagLadder, 1, d(10, 12), [session(d(10, 12)), session(d(10, 19))], d(10, 19));
      expect(a.cleanInARow, 2);
      expect(a.canStepUp, isFalse);
      expect(a.status, contains('7 días para poder subir'));
    });

    test('la última sesión sin el criterio corta la racha; el hollow también cuenta', () {
      expect(
          ladderAdvice(dragonFlagLadder, 1, d(10, 12), [session(d(10, 19)), session(d(10, 26), reps: 11)], d(10, 26))
              .cleanInARow,
          0);
      expect(
          ladderAdvice(dragonFlagLadder, 1, d(10, 12), [session(d(10, 19)), session(d(10, 26), hollow: 35)], d(10, 26))
              .canStepUp,
          isFalse,
          reason: 'el dragon flag pide hollow 3 × 40 s');
    });

    test('por lado: 3 × 8 en cada lado', () {
      const goal = LadderGoal('V-up a una pierna', 3, 8, perSide: true);
      expect(goal.metBy([8, 8, 8, 8, 8, 8]), isTrue);
      expect(goal.metBy([8, 8, 8, 8, 8, 7]), isFalse);
    });

    test('el último peldaño no propone subir', () {
      final a = ladderAdvice(vUpLadder, 4, d(10, 12), const [], d(12, 1));
      expect(a.canStepUp, isFalse);
      expect(a.status, 'Último peldaño.');
    });

    test('el hollow no es de ninguna escalera; los peldaños sí', () {
      expect(ladderOf(hollowHold), isNull);
      expect(ladderOf('Vela'), dragonFlagLadder);
      expect(ladderOf('V-up a una pierna'), vUpLadder);
      expect(ladderOf('Dominadas'), isNull);
    });
  });

  group('test de condición', () {
    final start = d(10, 12);

    test('Test 1 el lun 12 y el mié 14; Test 2 en la descarga; Test 3 con las pruebas del 11 dic', () {
      expect(scheduledTest(start, d(10, 12)), (round: 1, part: TestPart.torso));
      expect(scheduledTest(start, d(10, 14)), (round: 1, part: TestPart.piernas));
      expect(scheduledTest(start, d(10, 13)), isNull);
      expect(scheduledTest(start, d(11, 16)), (round: 2, part: TestPart.torso));
      expect(scheduledTest(start, d(11, 18)), (round: 2, part: TestPart.piernas));
      expect(scheduledTest(start, d(12, 11)), (round: 3, part: TestPart.torso));
      expect(scheduledTest(start, d(12, 9)), (round: 3, part: TestPart.piernas));
      expect(scheduledTest(start, d(12, 7)), isNull, reason: 'el lunes de la semana 9 entrena normal');
    });

    test('12 pruebas de torso y 4 de piernas', () {
      expect(torsoTests, hasLength(12));
      expect(legTests, hasLength(4));
      expect({for (final t in allTests) t.id}, hasLength(16));
    });

    test('dosis inicial: reps al 70–75 %, aguantes al 50–60 %', () {
      expect(initialDose(testItem('pullup')!, 12), 'Tope del rango: 8–9 reps');
      expect(initialDose(testItem('hollow_hold')!, 60), 'Series de 30–36 s');
      expect(initialDose(testItem('broad_jump')!, 220), isNull);
    });

    test('por lado cuenta el más débil; mejora contra el Test 1', () {
      const results = [
        TestResult(round: 1, item: 'one_arm_pushup', side: 'I', value: 5),
        TestResult(round: 1, item: 'one_arm_pushup', side: 'D', value: 4),
        TestResult(round: 2, item: 'one_arm_pushup', side: 'I', value: 6),
        TestResult(round: 2, item: 'one_arm_pushup', side: 'D', value: 6),
      ];
      expect(testValue(results, 1, 'one_arm_pushup'), 4);
      expect(improvement(testValue(results, 1, 'one_arm_pushup'), testValue(results, 2, 'one_arm_pushup')), 50);
      expect(testValue(results, 3, 'one_arm_pushup'), isNull);
    });
  });
}
