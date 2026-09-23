import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/reminders.dart';

ReminderSetting on_(ReminderKind kind, int hour, [int minute = 0, int? threshold]) =>
    ReminderSetting(kind: kind, enabled: true, hour: hour, minute: minute, threshold: threshold);

Map<ReminderKind, ReminderSetting> defaults() => {
      for (final s in [
        on_(ReminderKind.sesion, 15),
        on_(ReminderKind.sesionSinRegistrar, 21),
        on_(ReminderKind.comidaMerienda, 16, 30),
        on_(ReminderKind.comidaCena, 20),
        on_(ReminderKind.proteina, 20, 0, 100),
        on_(ReminderKind.medicion, 7),
      ])
        s.kind: s,
    };

ReminderContext ctx({
  DateTime? now,
  List<ReminderDay>? days,
  Map<ReminderKind, ReminderSetting>? settings,
  double proteinToday = 0,
  DateTime? lastMeasurement,
  DateTime? nextMeasurementDate,
}) =>
    ReminderContext(
      now: now ?? DateTime(2026, 9, 23, 8),
      days: days ??
          [
            ReminderDay(
              date: DateTime(2026, 9, 23),
              type: DayType.circuito,
              planSummary: 'Circuito 6 rondas: Dominadas 5 · Flexiones 10 · Sentadillas 15',
            ),
          ],
      settings: settings ?? defaults(),
      proteinToday: proteinToday,
      lastMeasurement: lastMeasurement,
      nextMeasurementDate: nextMeasurementDate,
    );

void main() {
  group('sesión', () {
    test('avisa 15 minutos antes y dice qué toca', () {
      final n = planReminders(ctx()).firstWhere((x) => x.kind == ReminderKind.sesion);
      expect(n.when, DateTime(2026, 9, 23, 14, 45));
      expect(n.title, 'En 15 min: Circuito');
      expect(n.body, contains('6 rondas'));
    });

    test('un día de bloques nombra el trabajo del día', () {
      final n = planReminders(ctx(days: [
        ReminderDay(
          date: DateTime(2026, 9, 23),
          type: DayType.bloques,
          planSummary: 'Bloques — Dominadas 4×6–8 · Flexiones 4×14–16',
        ),
      ])).firstWhere((x) => x.kind == ReminderKind.sesion);
      expect(n.title, 'En 15 min: Bloques');
      expect(n.body, contains('4×6–8'));
    });

    test('no avisa en día de fútbol ni de descanso', () {
      for (final type in [DayType.futbol, DayType.descanso]) {
        final plan = planReminders(ctx(days: [ReminderDay(date: DateTime(2026, 9, 23), type: type)]));
        expect(plan.where((x) => x.kind == ReminderKind.sesion), isEmpty);
        expect(plan.where((x) => x.kind == ReminderKind.sesionSinRegistrar), isEmpty);
      }
    });

    test('si la sesión ya está registrada, callado', () {
      final plan = planReminders(ctx(days: [
        ReminderDay(date: DateTime(2026, 9, 23), type: DayType.circuito, hasSession: true),
      ]));
      expect(plan.where((x) => x.kind == ReminderKind.sesion), isEmpty);
      expect(plan.where((x) => x.kind == ReminderKind.sesionSinRegistrar), isEmpty);
    });

    test('el aviso de sesión sin registrar va a su hora', () {
      final n = planReminders(ctx()).firstWhere((x) => x.kind == ReminderKind.sesionSinRegistrar);
      expect(n.when, DateTime(2026, 9, 23, 21));
      expect(n.body, contains('circuito'));
    });
  });

  group('proteína', () {
    test('avisa con lo que llevas y lo que falta', () {
      final n = planReminders(ctx(proteinToday: 68)).firstWhere((x) => x.kind == ReminderKind.proteina);
      expect(n.when, DateTime(2026, 9, 23, 20));
      expect(n.title, 'Proteína: 68 g');
      expect(n.body, 'Faltan 62 g para el mínimo de 130 g.');
    });

    test('por encima del umbral no molesta', () {
      expect(
        planReminders(ctx(proteinToday: 105)).where((x) => x.kind == ReminderKind.proteina),
        isEmpty,
      );
    });
  });

  group('comidas', () {
    test('programa las franjas activadas', () {
      final plan = planReminders(ctx());
      expect(plan.firstWhere((x) => x.kind == ReminderKind.comidaMerienda).when,
          DateTime(2026, 9, 23, 16, 30));
      expect(plan.firstWhere((x) => x.kind == ReminderKind.comidaCena).when, DateTime(2026, 9, 23, 20));
      expect(plan.where((x) => x.kind == ReminderKind.comidaDesayuno), isEmpty,
          reason: 'el desayuno viene apagado por defecto');
    });

    test('lo apagado no se programa', () {
      final settings = defaults()
        ..[ReminderKind.comidaCena] =
            const ReminderSetting(kind: ReminderKind.comidaCena, enabled: false, hour: 20);
      expect(planReminders(ctx(settings: settings)).where((x) => x.kind == ReminderKind.comidaCena), isEmpty);
    });
  });

  group('medición', () {
    test('usa la fecha acordada si existe', () {
      final n = planReminders(ctx(nextMeasurementDate: DateTime(2026, 10, 2)))
          .firstWhere((x) => x.kind == ReminderKind.medicion);
      expect(n.when, DateTime(2026, 10, 2, 7));
      expect(n.body, contains('ayunas'));
    });

    test('si no, cuenta el intervalo desde la última toma', () {
      final n = planReminders(ctx(lastMeasurement: DateTime(2026, 9, 20)))
          .firstWhere((x) => x.kind == ReminderKind.medicion);
      expect(n.when, DateTime(2026, 10, 11, 7), reason: '20 sep + 21 días');
      expect(n.body, contains('21 días'));
    });

    test('una medición vencida se recuerda a la mañana siguiente', () {
      final n = planReminders(ctx(lastMeasurement: DateTime(2026, 8, 1)))
          .firstWhere((x) => x.kind == ReminderKind.medicion);
      expect(n.when, DateTime(2026, 9, 24, 7));
    });

    test('sin línea base no inventa un aviso', () {
      expect(planReminders(ctx()).where((x) => x.kind == ReminderKind.medicion), isEmpty);
    });
  });

  group('reglas generales', () {
    test('nada se programa en el pasado', () {
      final plan = planReminders(ctx(now: DateTime(2026, 9, 23, 22)));
      expect(plan.where((x) => x.when.isBefore(DateTime(2026, 9, 23, 22))), isEmpty);
    });

    test('los avisos salen ordenados por hora', () {
      final plan = planReminders(ctx(proteinToday: 40));
      final times = plan.map((x) => x.when).toList();
      expect(times, orderedEquals(List.of(times)..sort()));
    });

    test('cada aviso tiene un id estable por tipo y día', () {
      final first = planReminders(ctx(proteinToday: 40));
      final second = planReminders(ctx(proteinToday: 40));
      expect(first.map((x) => x.id), second.map((x) => x.id));
      expect(first.map((x) => x.id).toSet().length, first.length, reason: 'sin ids repetidos');
    });

    test('programa varios días por adelantado', () {
      final plan = planReminders(ctx(days: [
        ReminderDay(date: DateTime(2026, 9, 23), type: DayType.circuito, planSummary: 'Circuito'),
        ReminderDay(date: DateTime(2026, 9, 24), type: DayType.bloques, planSummary: 'Bloques'),
        ReminderDay(date: DateTime(2026, 9, 25), type: DayType.futbol),
      ]));
      final sesiones = plan.where((x) => x.kind == ReminderKind.sesion).toList();
      expect(sesiones.length, 2, reason: 'el fútbol no lleva aviso de sesión');
      expect(sesiones.last.when, DateTime(2026, 9, 24, 14, 45));
    });
  });
}
