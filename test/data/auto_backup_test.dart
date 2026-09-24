import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/auto_backup.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';

import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);

  late Directory dir;
  late DatabaseHost host;
  late AutoBackup backup;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_auto');
    host = DatabaseHost(File('${dir.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
    backup = AutoBackup(
      host: host,
      flags: LocalFlags(File('${dir.path}/flags.json')),
      dir: Directory('${dir.path}/respaldos'),
      keep: 3,
    );
  });

  tearDown(() async {
    await host.db.close();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows el archivo puede seguir tomado.
    }
  });

  test('el primer arranque respalda; hasta la semana siguiente no repite', () async {
    await BodyRepository(host.db).addWeight(DateTime(2026, 9, 1), 72);
    expect(await backup.runIfDue(now: DateTime(2026, 9, 1)), isNotNull);
    expect(await backup.runIfDue(now: DateTime(2026, 9, 7)), isNull);
    expect(await backup.runIfDue(now: DateTime(2026, 9, 8)), isNotNull);
    expect((await backup.list()).map((b) => b.date), [DateTime(2026, 9, 8), DateTime(2026, 9, 1)]);
  });

  test('se queda solo con los más recientes', () async {
    for (var week = 0; week < 5; week++) {
      await backup.runIfDue(now: DateTime(2026, 8, 1).add(Duration(days: 7 * week)));
    }
    final dates = (await backup.list()).map((b) => b.date).toList();
    expect(dates, [DateTime(2026, 8, 29), DateTime(2026, 8, 22), DateTime(2026, 8, 15)]);
  });

  test('el respaldo se puede restaurar y trae los datos de ese día', () async {
    final body = BodyRepository(host.db);
    await body.addWeight(DateTime(2026, 9, 1), 72);
    final file = await backup.runIfDue(now: DateTime(2026, 9, 1));
    await body.addWeight(DateTime(2026, 9, 2), 71);

    await host.restoreFrom(file!);
    final weights = await BodyRepository(host.db).watchWeights().first;
    expect(weights.map((w) => w.kg), [72]);
  });

  test('archivos ajenos en la carpeta no se listan ni se borran', () async {
    final stranger = File('${dir.path}/respaldos/notas.txt')..createSync(recursive: true);
    await backup.runIfDue(now: DateTime(2026, 9, 1));
    expect((await backup.list()).length, 1);
    expect(stranger.existsSync(), isTrue);
  });
}
