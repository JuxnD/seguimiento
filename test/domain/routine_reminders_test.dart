import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/domain/daily_routines.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/reminders.dart';

/// Avisos de 032: rutina de mañana y de noche, y la noche antes de un día de
/// recuperación (§19.14, §19.15, §19.17).
void main() {
  ReminderSetting on_(ReminderKind kind, int hour, int minute) =>
      ReminderSetting(kind: kind, enabled: true, hour: hour, minute: minute);

  final settings = {
    ReminderKind.rutinaManana: on_(ReminderKind.rutinaManana, 7, 15),
    ReminderKind.rutinaNoche: on_(ReminderKind.rutinaNoche, 21, 30),
    ReminderKind.recuperacionManana: on_(ReminderKind.recuperacionManana, 22, 0),
  };
  final today = DateTime(2030, 3, 3);
  final days = [
    ReminderDay(date: today, type: DayType.descanso),
    ReminderDay(date: DateTime(2030, 3, 4), type: DayType.trenSuperior),
  ];

  List<(ReminderKind, DateTime)> plan({DateTime? now, Set<String> done = const {}, String? notice}) => [
        for (final n in planReminders(ReminderContext(
          now: now ?? DateTime(2030, 3, 3, 6),
          days: days,
          settings: settings,
          routinesDoneToday: done,
          recoveryNoticeTonight: notice,
        )))
          (n.kind, n.when),
      ];

  test('cada día, mañana y noche a su hora', () {
    expect(plan(), [
      (ReminderKind.rutinaManana, DateTime(2030, 3, 3, 7, 15)),
      (ReminderKind.rutinaNoche, DateTime(2030, 3, 3, 21, 30)),
      (ReminderKind.rutinaManana, DateTime(2030, 3, 4, 7, 15)),
      (ReminderKind.rutinaNoche, DateTime(2030, 3, 4, 21, 30)),
    ]);
  });

  test('lo terminado hoy no suena; la recuperación cubre las dos', () {
    expect(plan(done: {morningActivaId}).where((p) => p.$2.day == 3).map((p) => p.$1), [ReminderKind.rutinaNoche]);
    expect(plan(done: {recoveryActiveId}).where((p) => p.$2.day == 3), isEmpty);
    expect(plan(done: {recoveryActiveId}).where((p) => p.$2.day == 4), hasLength(2), reason: 'mañana vuelve a sonar');
  });

  test('la noche anterior: sólo con la carga alta, a las 22:00', () {
    expect(plan().map((p) => p.$1), isNot(contains(ReminderKind.recuperacionManana)));
    final withNotice = plan(notice: 'Carga de ayer y hoy: 1.110.');
    expect(withNotice, contains((ReminderKind.recuperacionManana, DateTime(2030, 3, 3, 22))));
    expect(plan(now: DateTime(2030, 3, 3, 22, 30), notice: 'x').map((p) => p.$1),
        isNot(contains(ReminderKind.recuperacionManana)), reason: 'nunca en el pasado');
  });

  test('los tipos nuevos van al final: los ids de los avisos de antes no cambian', () {
    expect(ReminderKind.values.indexOf(ReminderKind.pasos), 10);
    expect(ReminderKind.values.indexOf(ReminderKind.personalizado), 11);
    expect(ReminderKind.values.sublist(12),
        [ReminderKind.recuperacionManana, ReminderKind.rutinaManana, ReminderKind.rutinaNoche]);
    for (final k in [ReminderKind.recuperacionManana, ReminderKind.rutinaManana, ReminderKind.rutinaNoche]) {
      expect(defaultReminders[k]?.$1, isTrue, reason: '$k activo por defecto');
      expect(k.label, isNotEmpty);
      expect(k.description, isNotEmpty);
    }
  });
}
