import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/progress.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/domain/session_math.dart';

ReminderSetting _on(ReminderKind kind, int hour, {int? threshold}) =>
    ReminderSetting(kind: kind, enabled: true, hour: hour, minute: 0, threshold: threshold);

ReminderContext _ctx({double kcal = 0, List<MealSlot> missing = const []}) => ReminderContext(
      now: DateTime(2026, 9, 25, 12),
      days: [ReminderDay(date: DateTime(2026, 9, 25), type: DayType.progresion)],
      settings: {
        ReminderKind.calorias: _on(ReminderKind.calorias, 20, threshold: 1800),
        ReminderKind.comidasSinRegistrar: _on(ReminderKind.comidasSinRegistrar, 22),
      },
      kcalToday: kcal,
      kcalTarget: 2400,
      missingMealsToday: missing,
    );

void main() {
  group('trabajo por ronda', () {
    test('cada vuelta pierde el descanso que la precede', () {
      // Sesión del 25 sep: vueltas 0:50 · 1:22 · 1:22 … con 30 s de descanso.
      final marks = [50, 132, 214, 295, 376, 462, 543, 602];
      final rests = [30, 30, 30, 30, 30, 30, 30, 0];
      expect(roundWork(marks, rests), [50, 52, 52, 51, 51, 56, 51, 29]);
      expect(firstToLastDelta([50, 52, 52, 51, 51, 56, 51, 59]), 9);
    });

    test('sin descansos medidos no inventa el trabajo', () {
      expect(roundWork([50, 132], const []), isNull);
      expect(firstToLastDelta([50]), isNull);
    });
  });

  group('día cerrado', () {
    test('con desayuno, almuerzo y cena, o cerrado a mano', () {
      expect(isDayClosed({MealSlot.desayuno, MealSlot.almuerzo, MealSlot.cena}), isTrue);
      expect(isDayClosed({MealSlot.desayuno}), isFalse);
      expect(isDayClosed({MealSlot.almuerzo, MealSlot.cena}, manuallyClosed: true), isTrue);
      expect(missingMainMeals({MealSlot.almuerzo, MealSlot.merienda}), [MealSlot.desayuno, MealSlot.cena]);
    });
  });

  group('propuesta de progresión', () {
    test('con los cinco criterios cumplidos propone una ronda más', () {
      final p = proposeProgression(
        lastRounds: 8,
        lastPlanned: 8,
        anySplit: false,
        anyFailure: false,
        techniqueOk: true,
        fullRange: true,
        recoveryOk: true,
      )!;
      expect(p.canProgress, isTrue);
      expect(p.rounds, 9);
    });

    test('si algo falla mantiene la meta y dice qué', () {
      final p = proposeProgression(
        lastRounds: 8,
        lastPlanned: 8,
        anySplit: true,
        anyFailure: false,
        techniqueOk: true,
        fullRange: null,
        recoveryOk: true,
      )!;
      expect(p.rounds, 8);
      expect(p.unmet, ['series partidas', 'rango completo sin registrar']);
    });

    test('sin completar la meta no sube', () {
      final p = proposeProgression(
        lastRounds: 7,
        lastPlanned: 8,
        anySplit: false,
        anyFailure: false,
        techniqueOk: true,
        fullRange: true,
        recoveryOk: true,
      )!;
      expect(p.rounds, 7);
      expect(p.unmet.single, 'no completó la meta de 8');
    });
  });

  group('avisos nuevos', () {
    test('calorías a las 20:00 si va por debajo del umbral', () {
      final n = planReminders(_ctx(kcal: 1200)).where((x) => x.kind == ReminderKind.calorias).single;
      expect(n.when, DateTime(2026, 9, 25, 20));
      expect(n.title, 'Calorías: 1200 kcal');
      expect(n.body, contains('Faltan 1200 kcal para la meta de 2400'));
      expect(planReminders(_ctx(kcal: 1900)).where((x) => x.kind == ReminderKind.calorias), isEmpty);
    });

    test('comidas sin registrar a las 22:00 nombra las que faltan', () {
      final n = planReminders(_ctx(missing: [MealSlot.desayuno, MealSlot.cena]))
          .where((x) => x.kind == ReminderKind.comidasSinRegistrar)
          .single;
      expect(n.when, DateTime(2026, 9, 25, 22));
      expect(n.title, 'Falta registrar: desayuno y cena');
      expect(planReminders(_ctx()).where((x) => x.kind == ReminderKind.comidasSinRegistrar), isEmpty,
          reason: 'día completo o cerrado a mano: no hay nada que recordar');
    });
  });

  test('la escala RPE dice cuántas quedaban', () {
    expect(rpeMeaning(10), 'no quedaba ninguna');
    expect(rpeMeaning(8), 'quedaban 2');
    expect(rpeScale.first, ('10', 'No podía hacer ni una repetición más'));
  });
}
