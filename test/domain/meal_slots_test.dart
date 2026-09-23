import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/meal_slots.dart';

void main() {
  group('franja por hora', () {
    test('cada hora cae en su franja', () {
      expect(slotForTime(7, 30), MealSlot.desayuno);
      expect(slotForTime(12, 45), MealSlot.almuerzo);
      expect(slotForTime(16, 30), MealSlot.merienda);
      expect(slotForTime(20, 0), MealSlot.cena);
    });

    test('la madrugada sigue siendo cena', () {
      expect(slotForTime(0, 30), MealSlot.cena);
      expect(slotForTime(4, 59), MealSlot.cena);
      expect(slotForTime(5, 0), MealSlot.desayuno);
    });

    test('los bordes caen en la franja que empieza', () {
      expect(slotForTime(11, 0), MealSlot.almuerzo);
      expect(slotForTime(15, 30), MealSlot.merienda);
      expect(slotForTime(19, 0), MealSlot.cena);
    });
  });

  group('aviso de hora que no cuadra', () {
    test('un desayuno a las 14:57 sugiere almuerzo', () {
      expect(slotMismatch(MealSlot.desayuno, '14:57'), MealSlot.almuerzo);
    });

    test('una cena a las 13:00 sugiere almuerzo', () {
      expect(slotMismatch(MealSlot.cena, '13:00'), MealSlot.almuerzo);
    });

    test('dentro de la franja no avisa', () {
      expect(slotMismatch(MealSlot.desayuno, '07:40'), isNull);
      expect(slotMismatch(MealSlot.cena, '23:30'), isNull);
      expect(slotMismatch(MealSlot.cena, '00:40'), isNull, reason: 'cena de madrugada');
    });

    test('media hora de margen en los bordes', () {
      expect(slotMismatch(MealSlot.desayuno, '11:20'), isNull, reason: 'desayuno tardío');
      expect(slotMismatch(MealSlot.desayuno, '11:45'), MealSlot.almuerzo);
      expect(slotMismatch(MealSlot.merienda, '19:15'), isNull);
    });

    test('"otro" y sin hora nunca avisan', () {
      expect(slotMismatch(MealSlot.otro, '03:00'), isNull);
      expect(slotMismatch(MealSlot.desayuno, null), isNull);
      expect(slotMismatch(MealSlot.desayuno, 'basura'), isNull);
    });
  });
}
