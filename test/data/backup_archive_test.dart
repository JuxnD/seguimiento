import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';

import '../support/sqlite_host.dart';

void main() {
  setUpAll(() {
    useHostSqlite();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  late Directory root;
  late DatabaseHost a;
  late DatabaseHost b;
  late BackupArchive archiveA;
  late BackupArchive archiveB;
  final photos = {
    'fotos/frente.jpg': <int>[1, 3, 5, 7],
    'fotos/ejercicios/flexion.jpg': <int>[2, 4, 6, 8],
  };

  setUp(() async {
    root = Directory.systemTemp.createTempSync('seguimiento_backup_test_');
    final dirA = Directory('${root.path}/A')..createSync();
    final dirB = Directory('${root.path}/B')..createSync();
    a = DatabaseHost(File('${dirA.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
    b = DatabaseHost(File('${dirB.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
    archiveA = BackupArchive(host: a, documents: dirA);
    archiveB = BackupArchive(host: b, documents: dirB);
    await BodyRepository(a.db).addWeight(DateTime(2026, 10, 1), 72);
    await BodyRepository(b.db).addWeight(DateTime(2026, 10, 2), 73);
    for (final e in photos.entries) {
      final file = File('${dirA.path}/${e.key}')..createSync(recursive: true);
      file.writeAsBytesSync(e.value);
    }
    await a.db.customStatement(
        "INSERT INTO progress_photos (date, angle, relative_path) VALUES ('2026-10-01', 'frente', 'fotos/frente.jpg')");
    await a.db.customStatement(
        "INSERT INTO exercise_photos (name_key, relative_path) VALUES ('flexion', 'fotos/ejercicios/flexion.jpg')");
    File('${dirB.path}/fotos/vieja.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([99]);
    File('${dirB.path}/flags.json').writeAsStringSync('flags-B');
    File('${dirB.path}/sesion-en-curso.json').writeAsStringSync('cronometro-B');
  });

  tearDown(() async {
    await a.db.close();
    await b.db.close();
    root.deleteSync(recursive: true);
  });

  String logicalDbB() {
    final raw = sqlite3.open(b.file.path, mode: OpenMode.readOnly);
    try {
      final content = {
        for (final table in b.db.allTables)
          table.actualTableName: raw
              .select('select * from "${table.actualTableName}" order by rowid')
              .map((row) => Map<String, Object?>.from(row))
              .toList()
      };
      return sha256.convert(utf8.encode(jsonEncode(content))).toString();
    } finally {
      raw.dispose();
    }
  }

  Map<String, String> stateB() => {
        'db': sha256.convert(b.file.readAsBytesSync()).toString(),
        'records': logicalDbB(),
        'photo': sha256.convert(File('${b.file.parent.path}/fotos/vieja.jpg').readAsBytesSync()).toString(),
        'flags': File('${b.file.parent.path}/flags.json').readAsStringSync(),
        'timer': File('${b.file.parent.path}/sesion-en-curso.json').readAsStringSync(),
      };

  Future<void> expectBUnchanged(Map<String, String> before, {bool requireDbBytes = true}) async {
    final actual = stateB();
    if (!requireDbBytes) {
      // VACUUM reconstruye páginas: el rollback exige mismos datos, no layout.
      actual.remove('db');
      before = Map.of(before)..remove('db');
    }
    expect(actual, before, reason: 'el rechazo no puede cambiar DB, fotos ni archivos fuera del respaldo');
    expect((await BodyRepository(b.db).watchWeights().first).map((w) => w.kg), [73]);
  }

  Future<List<ArchiveFile>> entries() async {
    final exported = await archiveA.exportTo('${root.path}/source.zip');
    return ZipDecoder()
        .decodeBytes(exported.file.readAsBytesSync())
        .files
        .map((f) => ArchiveFile(f.name, f.size, (f.content as List<int>).toList())..mode = f.mode)
        .toList();
  }

  Future<File> altered(List<ArchiveFile> files, {bool compress = false}) async {
    final file = File('${root.path}/altered.zip');
    final encoder = ZipFileEncoder()..create(file.path);
    try {
      for (final entry in files) {
        entry.compress = compress;
        encoder.addArchiveFile(entry);
      }
    } finally {
      await encoder.close();
    }
    return file;
  }

  void describeAddedFile(List<ArchiveFile> files, String name, List<int> payload) {
    final old = files.firstWhere((f) => f.name == 'manifest.json');
    final manifest = jsonDecode(utf8.decode(old.content as List<int>)) as Map<String, dynamic>;
    (manifest['files'] as List)
        .add({'path': name, 'bytes': payload.length, 'sha256': sha256.convert(payload).toString()});
    files.remove(old);
    final bytes = utf8.encode(jsonEncode(manifest));
    files.add(ArchiveFile('manifest.json', bytes.length, bytes));
  }

  test('el respaldo manual es ZIP y transporta DB y ambas clases de fotos de A a B', () async {
    final exported = await archiveA.exportTo('${root.path}/portable.zip');
    expect(exported.file.readAsBytesSync().take(4), [80, 75, 3, 4],
        reason: 'el archivo que viaja debe ser ZIP, no SQLite renombrado');
    await archiveB.restoreFrom(exported.file);
    expect((await BodyRepository(b.db).watchWeights().first).map((w) => w.kg), [72]);
    for (final e in photos.entries) {
      final restored = File('${b.file.parent.path}/${e.key}');
      expect(restored.existsSync(), isTrue, reason: 'la foto ${e.key} debe viajar');
      expect(sha256.convert(restored.readAsBytesSync()), sha256.convert(e.value));
    }
    expect(File('${b.file.parent.path}/fotos/vieja.jpg').existsSync(), isFalse);
    expect(File('${b.file.parent.path}/flags.json').readAsStringSync(), 'flags-B');
    expect(File('${b.file.parent.path}/sesion-en-curso.json').readAsStringSync(), 'cronometro-B');
    final dbPhotos = await b.db
        .customSelect('select relative_path from progress_photos union all select relative_path from exercise_photos')
        .get();
    expect(dbPhotos.map((r) => r.data['relative_path']).toSet(), photos.keys.toSet());
    expect(exported.complete, isTrue);
    expect(exported.photoCount, 2);
  });

  test('SQLite legacy sigue restaurando solo los registros y conserva las fotos locales', () async {
    final legacy = await a.exportTo('${root.path}/legacy.sqlite');
    await archiveB.restoreFrom(legacy);
    expect((await BodyRepository(b.db).watchWeights().first).map((w) => w.kg), [72]);
    expect(File('${b.file.parent.path}/fotos/vieja.jpg').readAsBytesSync(), [99]);
  });

  test('el manifiesto declara esquema, bytes y SHA-256 del archivo que viaja', () async {
    final files = await entries();
    final manifest = jsonDecode(utf8.decode(files.firstWhere((f) => f.name == 'manifest.json').content as List<int>))
        as Map<String, dynamic>;
    expect(manifest['format'], 'seguimiento-backup');
    expect(manifest['version'], 1);
    expect(manifest['schemaVersion'], a.db.schemaVersion);
    expect(manifest['complete'], true);
    expect(manifest['missingPhotos'], isEmpty);
    final specs = manifest['files'] as List;
    expect(specs.length, 3);
    for (final spec in specs.cast<Map<String, dynamic>>()) {
      final bytes = files.firstWhere((f) => f.name == spec['path']).content as List<int>;
      expect(spec['bytes'], bytes.length);
      expect(spec['sha256'], sha256.convert(bytes).toString());
    }
  });

  for (final name in [
    'fotos/../flags.json',
    '../escape.jpg',
    '/fotos/absolute.jpg',
    'C:/fotos/absolute.jpg',
    'fotos/a/../../escape.jpg',
    'fotos/a\\..\\escape.jpg',
    'flags.json'
  ]) {
    test('ruta rechazada sin cambiar B: $name', () async {
      final before = stateB();
      final files = await entries();
      files.add(ArchiveFile(name, 1, [7]));
      // Manifiesto consistente: el rechazo debe venir de la ruta insegura,
      // no de que el fixture olvide declarar el archivo añadido.
      describeAddedFile(files, name.replaceAll('\\', '/'), [7]);
      await expectLater(archiveB.restoreFrom(await altered(files)), throwsA(isA<RestoreException>()));
      await expectBUnchanged(before);
      expect(File('${root.path}/escape.jpg').existsSync(), isFalse);
    });
  }

  test('duplicados exactos y por mayúsculas se rechazan antes de extraer', () async {
    for (final name in ['fotos/frente.jpg', 'fotos/FRENTE.jpg']) {
      final before = stateB();
      final files = await entries();
      final payload = photos['fotos/frente.jpg']!;
      files.add(ArchiveFile(name, payload.length, payload));
      if (name != 'fotos/frente.jpg') describeAddedFile(files, name, payload);
      await expectLater(archiveB.restoreFrom(await altered(files)), throwsA(isA<RestoreException>()));
      await expectBUnchanged(before);
    }
  });

  test('una entrada symlink se rechaza sin escribir su destino', () async {
    final before = stateB();
    final files = await entries();
    final payload = utf8.encode('../flags.json');
    files.add(ArchiveFile('fotos/enlace.jpg', payload.length, payload)..mode = 0xa1ff);
    describeAddedFile(files, 'fotos/enlace.jpg', payload);
    await expectLater(archiveB.restoreFrom(await altered(files)), throwsA(isA<RestoreException>()));
    await expectBUnchanged(before);
  });

  for (final missing in ['manifest.json', 'seguimiento.sqlite', 'fotos/frente.jpg']) {
    test('paquete sin $missing se rechaza y conserva B', () async {
      final before = stateB();
      final files = await entries()
        ..removeWhere((f) => f.name == missing);
      await expectLater(archiveB.restoreFrom(await altered(files)), throwsA(isA<RestoreException>()));
      await expectBUnchanged(before);
    });
  }

  test('foto con CRC válido pero SHA-256 distinto se rechaza', () async {
    final before = stateB();
    final files = await entries()
      ..removeWhere((f) => f.name == 'fotos/frente.jpg');
    files.add(ArchiveFile('fotos/frente.jpg', 4, [9, 9, 9, 9]));
    await expectLater(archiveB.restoreFrom(await altered(files)), throwsA(isA<RestoreException>()));
    await expectBUnchanged(before);
  });

  test('quitar foto y descriptor no oculta la referencia pendiente de la base', () async {
    final before = stateB();
    final files = await entries();
    files.removeWhere((f) => f.name == 'fotos/frente.jpg');
    final old = files.firstWhere((f) => f.name == 'manifest.json');
    final manifest = jsonDecode(utf8.decode(old.content as List<int>)) as Map<String, dynamic>;
    (manifest['files'] as List).removeWhere((Object? f) => (f as Map<String, dynamic>)['path'] == 'fotos/frente.jpg');
    files.remove(old);
    final bytes = utf8.encode(jsonEncode(manifest));
    files.add(ArchiveFile('manifest.json', bytes.length, bytes));
    await expectLater(archiveB.restoreFrom(await altered(files)), throwsA(isA<RestoreException>()));
    await expectBUnchanged(before);
  });

  test('DB incompleta con hashes correctos en ZIP se rechaza sin tocar B', () async {
    final before = stateB();
    final files = await entries();
    final dbEntry = files.firstWhere((f) => f.name == 'seguimiento.sqlite');
    final copy = File('${root.path}/broken.sqlite')..writeAsBytesSync(dbEntry.content as List<int>);
    final raw = sqlite3.open(copy.path);
    raw.execute('drop table daily_steps');
    raw.dispose();
    final dbBytes = copy.readAsBytesSync();
    files.remove(dbEntry);
    files.add(ArchiveFile('seguimiento.sqlite', dbBytes.length, dbBytes));
    final old = files.firstWhere((f) => f.name == 'manifest.json');
    final manifest = jsonDecode(utf8.decode(old.content as List<int>)) as Map<String, dynamic>;
    final spec =
        (manifest['files'] as List).cast<Map<String, dynamic>>().firstWhere((f) => f['path'] == 'seguimiento.sqlite');
    spec['bytes'] = dbBytes.length;
    spec['sha256'] = sha256.convert(dbBytes).toString();
    files.remove(old);
    final bytes = utf8.encode(jsonEncode(manifest));
    files.add(ArchiveFile('manifest.json', bytes.length, bytes));
    await expectLater(archiveB.restoreFrom(await altered(files)), throwsA(isA<RestoreException>()));
    await expectBUnchanged(before);
  });

  test('un esquema futuro y un manifiesto incoherente se rechazan', () async {
    for (final field in ['version', 'schemaVersion', 'complete']) {
      final before = stateB();
      final files = await entries();
      final old = files.firstWhere((f) => f.name == 'manifest.json');
      final manifest = jsonDecode(utf8.decode(old.content as List<int>)) as Map<String, dynamic>;
      manifest[field] = field == 'complete' ? false : 999;
      files.remove(old);
      final bytes = utf8.encode(jsonEncode(manifest));
      files.add(ArchiveFile('manifest.json', bytes.length, bytes));
      await expectLater(archiveB.restoreFrom(await altered(files)), throwsA(isA<RestoreException>()));
      await expectBUnchanged(before);
    }
  });

  test('archivo ZIP truncado se rechaza sin cambiar B', () async {
    final before = stateB();
    final exported = await archiveA.exportTo('${root.path}/source.zip');
    final bytes = exported.file.readAsBytesSync();
    final broken = File('${root.path}/truncated.zip')..writeAsBytesSync(bytes.sublist(0, bytes.length - 30));
    await expectLater(archiveB.restoreFrom(broken), throwsA(isA<RestoreException>()));
    await expectBUnchanged(before);
  });

  test('tamaños declarados excesivos y DEFLATE con tamaño falso se rechazan', () async {
    for (final bomb in [false, true]) {
      final before = stateB();
      final files = await entries();
      if (bomb) {
        files.removeWhere((f) => f.name == 'fotos/frente.jpg');
        files.add(ArchiveFile('fotos/frente.jpg', 1024 * 1024, List<int>.filled(1024 * 1024, 0)));
      }
      final zip = await altered(files, compress: bomb);
      final bytes = zip.readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      final decoded = ZipDecoder()..decodeBytes(bytes);
      final header = decoded.directory.fileHeaders.firstWhere((h) => h.filename == 'fotos/frente.jpg');
      final size = bomb ? 4 : BackupArchive.maxFileBytes + 1;
      data.setUint32(header.localHeaderOffset! + 22, size, Endian.little);
      // Ubicar su cabecera central sin asumir posiciones propias del encoder.
      var at = decoded.directory.centralDirectoryOffset;
      while (data.getUint32(at, Endian.little) == 0x02014b50) {
        final nameLength = data.getUint16(at + 28, Endian.little);
        final name = utf8.decode(bytes.sublist(at + 46, at + 46 + nameLength));
        if (name == 'fotos/frente.jpg') {
          data.setUint32(at + 24, size, Endian.little);
          break;
        }
        at += 46 + nameLength + data.getUint16(at + 30, Endian.little) + data.getUint16(at + 32, Endian.little);
      }
      zip.writeAsBytesSync(bytes);
      await expectLater(archiveB.restoreFrom(zip), throwsA(isA<RestoreException>()));
      await expectBUnchanged(before);
    }
  });

  test('exportar fotos previamente ausentes declara incompleto; restaurarlo requiere confirmación', () async {
    File('${a.file.parent.path}/fotos/frente.jpg').deleteSync();
    final exported = await archiveA.exportTo('${root.path}/partial.zip');
    expect(exported.complete, isFalse);
    expect(exported.missingPhotos, ['fotos/frente.jpg']);
    expect(exported.photoCount, 1);
    final before = stateB();
    await expectLater(archiveB.restoreFrom(exported.file), throwsA(isA<RestoreException>()));
    await expectBUnchanged(before);
    await archiveB.restoreFrom(exported.file, allowMissingPhotos: true);
    expect((await BodyRepository(b.db).watchWeights().first).map((w) => w.kg), [72]);
    expect(File('${b.file.parent.path}/fotos/frente.jpg').existsSync(), isFalse);
    expect(File('${b.file.parent.path}/fotos/ejercicios/flexion.jpg').readAsBytesSync(),
        photos['fotos/ejercicios/flexion.jpg']);
  });

  test('sin fotos todavía exporta y restaura un paquete completo', () async {
    await a.db.customStatement('delete from progress_photos');
    await a.db.customStatement('delete from exercise_photos');
    Directory('${a.file.parent.path}/fotos').deleteSync(recursive: true);
    final exported = await archiveA.exportTo('${root.path}/empty-photos.zip');
    expect(exported.complete, isTrue);
    expect(exported.photoCount, 0);
    await archiveB.restoreFrom(exported.file);
    expect((await BodyRepository(b.db).watchWeights().first).map((w) => w.kg), [72]);
    expect(Directory('${b.file.parent.path}/fotos').listSync(), isEmpty);
  });

  test('fallo al reabrir después de reemplazar fotos revierte DB y todas las fotos de B', () async {
    final exported = await archiveA.exportTo('${root.path}/source.zip');
    final before = stateB();
    var fail = true;
    final initial = b.db;
    final file = b.file;
    b = DatabaseHost(file, (f) {
      if (f.path == file.path && fail) {
        fail = false;
        expect(File('${file.parent.path}/fotos/frente.jpg').readAsBytesSync(), photos['fotos/frente.jpg'],
            reason: 'el fallo inyectado ocurre después de reemplazar las fotos');
        throw StateError('fallo tardío sintético');
      }
      return AppDatabase(NativeDatabase(f));
    }, initial: initial);
    archiveB = BackupArchive(host: b, documents: b.file.parent);
    await expectLater(archiveB.restoreFrom(exported.file), throwsA(isA<RestoreException>()));
    await expectBUnchanged(before, requireDbBytes: false);
    expect(File('${b.file.parent.path}/fotos/frente.jpg').existsSync(), isFalse);
    expect(File('${b.file.path}.pre-restore').existsSync(), isFalse);
    expect(Directory('${b.file.path}.pre-restore-fotos').existsSync(), isFalse);
    expect(File('${b.file.path}.restore-state.json').existsSync(), isFalse);
  });

  for (final committed in [false, true]) {
    test('recuperación tras cierre del proceso, committed=$committed', () async {
      final safety = await b.exportTo('${b.file.path}.pre-restore');
      final source = await a.exportTo('${root.path}/source.sqlite');
      final file = b.file;
      await b.db.close();
      Directory('${file.parent.path}/fotos').renameSync('${file.path}.pre-restore-fotos');
      for (final e in photos.entries) {
        File('${file.parent.path}/${e.key}')
          ..createSync(recursive: true)
          ..writeAsBytesSync(e.value);
      }
      await source.copy(file.path);
      File('${file.path}.restore-state.json').writeAsStringSync(jsonEncode({
        'version': 1,
        'photos': true,
        'hadPhotos': true,
        'committed': committed,
      }));
      await DatabaseHost.recoverPendingRestore(file);
      b = DatabaseHost(file, (f) => AppDatabase(NativeDatabase(f)));
      expect((await BodyRepository(b.db).watchWeights().first).map((w) => w.kg), [committed ? 72 : 73]);
      expect(File('${file.parent.path}/fotos/vieja.jpg').existsSync(), !committed);
      expect(File('${file.parent.path}/fotos/frente.jpg').existsSync(), committed);
      expect(safety.existsSync(), isFalse);
      expect(File('${file.path}.restore-state.json').existsSync(), isFalse);
    });
  }
}
