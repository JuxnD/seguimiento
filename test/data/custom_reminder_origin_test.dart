import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/custom_reminder_repository.dart';

import '../support/sqlite_host.dart';

/// Plan 040: lo que se crea desde Ajustes es del usuario; lo viejo queda sin
/// origen registrado, nunca atribuido a la IA. Editar no reescribe el origen.
void main() {
  late AppDatabase db;
  setUpAll(useHostSqlite);
  setUp(() => db = openInMemoryDatabase());
  tearDown(() => db.close());

  test('crear desde Ajustes guarda origen usuario; editar no lo cambia', () async {
    final repo = CustomReminderRepository(db);
    final id = await repo.save(
        title: 'Estirar cuello', intervalDays: 1, hour: 9, minute: 0, startDate: DateTime(2030, 3, 4));
    expect((await (db.select(db.customReminders)..where((t) => t.id.equals(id))).getSingle()).origin, 'usuario');
    await repo.save(
        id: id, title: 'Estirar cuello 2', intervalDays: 2, hour: 10, minute: 0, startDate: DateTime(2030, 3, 4));
    expect((await (db.select(db.customReminders)..where((t) => t.id.equals(id))).getSingle()).origin, 'usuario');
  });

  test('un recordatorio viejo sin origen sigue sin origen al editarlo', () async {
    await db.customStatement(
        "insert into custom_reminders (title, interval_days, hour, minute, start_date, enabled) values ('Ejercicio de prueba', 1, 8, 0, '2030-03-01', 1)");
    final row = await db.select(db.customReminders).getSingle();
    expect(row.origin, isNull);
    await CustomReminderRepository(db)
        .save(id: row.id, title: 'Ejercicio de prueba', intervalDays: 3, hour: 8, minute: 0, startDate: DateTime(2030, 3, 1));
    expect((await db.select(db.customReminders).getSingle()).origin, isNull, reason: 'no se inventa procedencia');
  });
}
