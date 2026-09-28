import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/domain/steps.dart';

/// Traspaso §14: pasos diarios.
void main() {
  test('la meta es solo entre semana', () {
    expect(stepsGoalFor(DateTime(2026, 9, 28), 7500), 7500, reason: 'lunes');
    expect(stepsGoalFor(DateTime(2026, 10, 2), 7500), 7500, reason: 'viernes');
    expect(stepsGoalFor(DateTime(2026, 9, 26), 7500), isNull, reason: 'sábado');
    expect(stepsGoalFor(DateTime(2026, 9, 27), 7500), isNull, reason: 'domingo');
  });

  test('el resumen promedia solo los días registrados', () {
    final s = summarizeSteps({
      DateTime(2026, 9, 21): 1935, // lunes de oficina
      DateTime(2026, 9, 22): 8000,
      DateTime(2026, 9, 27): 12000, // domingo de fútbol
    }, 7500)!;
    expect(s.days, 3);
    expect(s.average, 7312);
    expect(s.weekdayDays, 2);
    expect(s.weekdayAverage, 4968);
    expect(s.weekdaysAtGoal, 1);
    expect(summarizeSteps({}, 7500), isNull);
  });

  group('aviso de las 18:00', () {
    ReminderContext ctx(DateTime now, {int? steps}) => ReminderContext(
          now: now,
          days: [ReminderDay(date: DateTime(now.year, now.month, now.day), type: DayType.bloques)],
          settings: const {
            ReminderKind.pasos: ReminderSetting(kind: ReminderKind.pasos, enabled: true, hour: 18, minute: 0, threshold: 4000),
          },
          stepsToday: steps,
        );

    List<PlannedNotification> steps(ReminderContext c) =>
        planReminders(c).where((n) => n.kind == ReminderKind.pasos).toList();

    test('entre semana suena si va por debajo o si no se anotaron', () {
      final low = steps(ctx(DateTime(2026, 9, 29, 12), steps: 1935));
      expect(low.single.when, DateTime(2026, 9, 29, 18));
      expect(low.single.body, contains('Faltan 5.565'));
      expect(steps(ctx(DateTime(2026, 9, 29, 12))).single.title, 'Pasos: sin anotar hoy');
    });

    test('no suena si ya pasó el umbral ni el fin de semana', () {
      expect(steps(ctx(DateTime(2026, 9, 29, 12), steps: 4500)), isEmpty);
      expect(steps(ctx(DateTime(2026, 9, 27, 12), steps: 100)), isEmpty);
      expect(steps(ctx(DateTime(2026, 9, 29, 19), steps: 100)), isEmpty, reason: 'ya pasó la hora');
    });
  });
}
