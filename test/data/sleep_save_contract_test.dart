import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/sleep_repository.dart';
import 'package:seguimiento/domain/sleep_entry.dart';

import '../support/sqlite_host.dart';

/// Observación previa a R1 de 040: las horas no pueden contradecir la hora de
/// acostarse y de despertar, y una noche de 0 h (permitida por la tabla) se
/// conserva. Fechas ficticias.
void main() {
  late AppDatabase db;
  late SleepRepository repo;
  final mon = DateTime(2030, 3, 4);

  setUpAll(useHostSqlite);
  setUp(() {
    db = openInMemoryDatabase();
    repo = SleepRepository(db);
  });
  tearDown(() => db.close());

  test('horas que no cuadran con acostarse y despertar se rechazan sin escribir', () async {
    final w = sleepWindow(mon, (23, 0), (7, 0)); // 8 h
    await expectLater(repo.save(mon, hours: 1, start: w.start, wake: w.wake, source: sleepSourceManual),
        throwsArgumentError);
    expect(await repo.detail(mon), isNull);
    // Dentro del redondeo a dos decimales sí.
    await repo.save(mon, hours: 7.995, start: w.start, wake: w.wake, source: sleepSourceManual);
    expect((await repo.detail(mon))!.hours, 7.995);
  });

  test('una noche de 0 h se puede guardar (editar sólo nota o procedencia)', () async {
    await db.customStatement("insert into sleep_logs (date, hours) values ('2030-03-04', 0)");
    await repo.save(mon, hours: 0, source: sleepSourceManual, note: 'no dormí');
    final d = (await repo.detail(mon))!;
    expect((d.hours, d.note), (0.0, 'no dormí'));
    await expectLater(repo.save(mon, hours: double.nan, source: sleepSourceManual), throwsArgumentError);
    await expectLater(repo.save(mon, hours: 17, source: sleepSourceManual), throwsArgumentError);
    await expectLater(repo.save(mon, hours: -1, source: sleepSourceManual), throwsArgumentError);
    expect((await repo.detail(mon))!.hours, 0, reason: 'los rechazos no escriben');
  });
}
