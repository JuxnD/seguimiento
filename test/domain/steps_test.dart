import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/dates.dart';
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

  group('de dónde vienen los pasos (§16.14)', () {
    final innova = StepsOrigin(at: DateTime(2026, 10, 3, 15, 6), package: 'com.moyoung.innov', label: 'INNOVA S-WATCH');

    test('hora de 12 horas', () {
      expect(formatTime12(DateTime(2026, 10, 3, 15, 6)), '3:06 p. m.');
      expect(formatTime12(DateTime(2026, 10, 3, 0, 5)), '12:05 a. m.');
      expect(formatTime12(DateTime(2026, 10, 3, 12, 0)), '12:00 p. m.');
      expect(formatTime12(DateTime(2026, 10, 3, 9, 30)), '9:30 a. m.');
    });

    test('la línea dice la app y la hora; ayer u otro día, con el día', () {
      expect(stepsOriginLine(innova, DateTime(2026, 10, 3, 20)), 'INNOVA S-WATCH · 3:06 p. m.');
      expect(stepsOriginLine(innova, DateTime(2026, 10, 4, 8)), 'INNOVA S-WATCH · ayer 3:06 p. m.');
      expect(stepsOriginLine(innova, DateTime(2026, 10, 5, 8)), 'INNOVA S-WATCH · sáb 3 oct 3:06 p. m.');
    });

    test('sin nombre visible usa uno conocido o el paquete', () {
      StepsOrigin o(String pkg, String label) => StepsOrigin(at: innova.at, package: pkg, label: label);
      expect(stepsAppName(o('com.moyoung.innov', 'com.moyoung.innov')), 'INNOVA S-WATCH');
      expect(stepsAppName(o('com.moyoung.innov', 'Innova')), 'Innova', reason: 'manda el de Android');
      expect(stepsAppName(o('com.otra.app', '')), 'com.otra.app');
    });

    test('más de 6 h sin registros pide abrir la app del reloj', () {
      expect(watchSyncStale(null, DateTime(2026, 10, 3, 16)), isTrue, reason: 'nunca escribió');
      expect(watchSyncStale(innova.at, DateTime(2026, 10, 3, 21, 6)), isFalse, reason: 'justo 6 h');
      expect(watchSyncStale(innova.at, DateTime(2026, 10, 3, 21, 7)), isTrue);
    });

    test('se guarda y se lee igual en las banderas', () {
      final back = StepsOrigin.fromJson(innova.toJson())!;
      expect([back.at, back.package, back.label], [innova.at, innova.package, innova.label]);
      expect(StepsOrigin.fromJson('basura'), isNull);
      expect(StepsOrigin.fromJson({'at': 'no-es-fecha', 'package': 'x'}), isNull);
    });
  });
}
