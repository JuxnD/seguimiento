import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/habits.dart';
import 'package:seguimiento/domain/progress.dart';
import 'package:seguimiento/domain/recovery.dart';

void main() {
  final today = DateTime(2026, 10, 27);
  test('una sesión moderada registrada hoy corta la racha intensa previa', () {
    final items = [
      for (var i = 1; i <= 10; i++) LoadItem(date: addDays(today, -i), minutes: 30, effort: 8),
      LoadItem(date: today, minutes: 20, effort: 4)
    ];
    expect(loadReading(items, today).intenseStreak, 0);
    expect(loadReading(items, today).threeIntense, isFalse);
  });
  test('un pesaje aislado por semana no justifica ajustar comida o pasos', () {
    final reading = twoWeekRule(
        weeks: [WeekAverage(addDays(today, -22), 80, 1), WeekAverage(addDays(today, -8), 78, 1)],
        abdomen: const [],
        today: today);
    expect(reading.action, KcalAction.faltanDatos);
  });
  test('cintura de enero no produce reducción con pesos de octubre', () {
    final reading = twoWeekRule(
        weeks: [WeekAverage(addDays(today, -22), 80, 3), WeekAverage(addDays(today, -8), 80, 3)],
        abdomen: [(DateTime(2026, 1, 1), 92), (DateTime(2026, 1, 22), 92)],
        today: today);
    expect(reading.action, isNot(KcalAction.bajar));
    expect(reading.message, contains('reciente'));
  });
}
