import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/custom_reminder_repository.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/reminders.dart';

import '../support/sqlite_host.dart';

/// Recordatorios propios: "Ejercicios de cuello cada 3 días a las 19:00".
void main() {
  CustomReminder neck({DateTime? lastDone, bool enabled = true}) => CustomReminder(
        id: 7,
        title: 'Ejercicios de cuello',
        note: 'Retracción de mentón 2×10',
        intervalDays: 3,
        hour: 19,
        minute: 0,
        startDate: DateTime(2026, 9, 28),
        lastDone: lastDone,
        enabled: enabled,
      );

  test('se cuenta desde la última vez hecho, o desde el inicio', () {
    expect(neck().nextDue, DateTime(2026, 9, 28));
    expect(neck().dueOn(DateTime(2026, 9, 28)), isTrue);
    expect(neck().dueOn(DateTime(2026, 9, 27)), isFalse);

    final done = neck(lastDone: DateTime(2026, 9, 28));
    expect(done.dueOn(DateTime(2026, 9, 28)), isFalse, reason: 'ya se hizo hoy');
    expect(done.dueOn(DateTime(2026, 9, 30)), isFalse);
    expect(done.nextDue, DateTime(2026, 10, 1));
    expect(done.dueOn(DateTime(2026, 10, 1)), isTrue);
    expect(done.dueOn(DateTime(2026, 10, 3)), isTrue, reason: 'sin marcar sigue pendiente');
    expect(neck(enabled: false).dueOn(DateTime(2026, 9, 28)), isFalse);
    expect(neck().frequencyLabel, 'cada 3 días');
  });

  test('avisa el día que toca y cada día después hasta marcarlo', () {
    final planned = planReminders(ReminderContext(
      now: DateTime(2026, 9, 29, 8),
      days: [
        for (var i = 0; i < 5; i++) ReminderDay(date: DateTime(2026, 9, 29 + i), type: DayType.descanso),
      ],
      settings: const {},
      custom: [neck(lastDone: DateTime(2026, 9, 28))],
    )).where((n) => n.kind == ReminderKind.personalizado).toList();

    expect(planned.map((n) => n.when), [
      DateTime(2026, 10, 1, 19),
      DateTime(2026, 10, 2, 19),
      DateTime(2026, 10, 3, 19),
    ]);
    expect(planned.first.title, 'Ejercicios de cuello');
    expect(planned.first.body, contains('Retracción de mentón 2×10'));
    expect(planned.first.body, contains('cada 3 días'));
    expect(planned[1].body, contains('Pendiente desde el'));
    expect(planned.map((n) => n.id).toSet(), hasLength(3), reason: 'un id por día');
    expect(planned.first.id, greaterThan(20000), reason: 'lejos de los ids de los avisos fijos');
  });

  group('repositorio', () {
    setUpAll(useHostSqlite);

    test('crear, marcar hecho, deshacer, apagar y borrar', () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final repo = CustomReminderRepository(db);
      final id = await repo.save(
        title: '  Ejercicios de cuello ',
        note: '',
        intervalDays: 3,
        hour: 19,
        minute: 30,
        startDate: DateTime(2026, 9, 28),
      );
      var r = (await repo.all()).single;
      expect((r.title, r.note, r.timeLabel), ('Ejercicios de cuello', null, '19:30'));

      await repo.markDone(id, DateTime(2026, 9, 28));
      r = (await repo.all()).single;
      expect(r.nextDue, DateTime(2026, 10, 1));

      await repo.setLastDone(id, null);
      expect((await repo.all()).single.lastDone, isNull);

      await repo.setEnabled(id, false);
      expect((await repo.all()).single.enabled, isFalse);

      await repo.delete(id);
      expect(await repo.all(), isEmpty);
    });
  });
}
