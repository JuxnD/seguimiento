import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/sleep_repository.dart';
import 'package:seguimiento/domain/sleep_entry.dart';

import '../support/sqlite_host.dart';

/// Plan 040: la noche guarda inicio, despertar, procedencia y nota sin romper
/// a los lectores de horas (readiness, informe, registro de la mañana).
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

  test('noche completa: se relee igual y las horas siguen para los demás', () async {
    final w = sleepWindow(mon, (23, 38), (11, 0));
    await repo.save(mon,
        hours: hoursBetween(w.start, w.wake)!, start: w.start, wake: w.wake, source: sleepSourceEditManual, note: ' reloj descargado ');
    final d = (await repo.detail(mon))!;
    expect((d.start, d.wake, d.source, d.note), (w.start, w.wake, sleepSourceEditManual, 'reloj descargado'));
    expect(d.hours, closeTo(11.37, 0.01));
    expect((await repo.range(mon, mon))['2030-03-04'], closeTo(11.37, 0.01));
    expect(await repo.watchDay(mon).first, closeTo(11.37, 0.01));
  });

  test('una noche de antes sólo tiene horas: lo demás queda sin dato', () async {
    await db.customStatement("insert into sleep_logs (date, hours) values ('2030-03-04', 7.5)");
    final d = (await repo.detail(mon))!;
    expect((d.hours, d.start, d.wake, d.source, d.note), (7.5, null, null, null, null));
  });

  test('los botones de horas: mismas horas no tocan nada; otras borran los tiempos y conservan la nota', () async {
    final w = sleepWindow(mon, (23, 0), (7, 0));
    await repo.save(mon, hours: 8, start: w.start, wake: w.wake, source: sleepSourceClock, note: 'n');
    await repo.set(mon, 8); // el registro de la mañana guarda lo que ya había
    var d = (await repo.detail(mon))!;
    expect((d.start, d.source, d.note), (w.start, sleepSourceClock, 'n'));
    await repo.set(mon, 7);
    d = (await repo.detail(mon))!;
    expect((d.hours, d.start, d.wake, d.source, d.note), (7.0, null, null, sleepSourceEditManual, 'n'),
        reason: 'los tiempos ya no cuadran con 7 h; lo del reloj quedó corregido a mano');
  });

  test('datos imposibles se rechazan sin escribir', () async {
    final w = sleepWindow(mon, (23, 0), (7, 0));
    await expectLater(repo.save(mon, hours: double.nan, source: sleepSourceManual), throwsArgumentError);
    await expectLater(repo.save(mon, hours: 17, source: sleepSourceManual), throwsArgumentError);
    await expectLater(repo.save(mon, hours: 8, start: w.wake, wake: w.start, source: sleepSourceManual), throwsArgumentError);
    await expectLater(repo.save(mon, hours: 8, start: w.start, source: sleepSourceManual), throwsArgumentError);
    expect(await repo.detail(mon), isNull);
  });
}
