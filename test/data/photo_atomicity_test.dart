import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/photo_repository.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/plan027_path_provider.dart';
import '../support/sqlite_host.dart';

/// Plan 027: los archivos de fotos viven fuera de SQLite. Un fallo de la base
/// no puede dejar una fila apuntando a un archivo ya borrado.
void main() {
  late AppDatabase db;
  late PhotoRepository repo;
  late Directory docs;
  late Directory scratch;

  setUpAll(useHostSqlite);
  setUp(() {
    docs = FakePathProvider.install();
    scratch = Directory.systemTemp.createTempSync('seguimiento_027_src');
    db = openInMemoryDatabase();
    repo = PhotoRepository(db);
  });
  tearDown(() async {
    await db.close();
    for (final d in [docs, scratch]) {
      try {
        d.deleteSync(recursive: true);
      } on FileSystemException {/* Windows retiene el handle un instante. */}
    }
  });

  File source(String name, List<int> bytes) => File(p.join(scratch.path, name))..writeAsBytesSync(bytes);

  /// Foto ya guardada con archivo real en la carpeta de documentos.
  Future<ProgressPhotoRow> stored(String date, PhotoAngle angle, List<int> bytes, {String ext = 'jpg'}) async {
    final rel = p.join(PhotoRepository.folder, '$date-${angle.name}-seed.$ext');
    final f = File(p.join(docs.path, rel))..createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    final id = await db
        .into(db.progressPhotos)
        .insert(ProgressPhotosCompanion.insert(date: date, angle: angle, relativePath: rel));
    return (db.select(db.progressPhotos)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> failOn(String op) => db.customStatement(
      "CREATE TRIGGER falla_$op BEFORE $op ON progress_photos BEGIN SELECT RAISE(ABORT, 'falla inyectada'); END");

  List<int> bytesOf(ProgressPhotoRow r) => File(p.join(docs.path, r.relativePath)).readAsBytesSync();

  group('add', () {
    test('éxito sin ocupante: copia el archivo y registra la fila', () async {
      await repo.add(source: source('a.jpg', [1, 2, 3]), date: DateTime(2026, 10, 3), angle: PhotoAngle.frente);
      final row = await db.select(db.progressPhotos).getSingle();
      expect(bytesOf(row), [1, 2, 3]);
    });

    test('éxito con ocupante: reemplaza fila y archivo, sin huérfano', () async {
      final old = await stored('2026-10-03', PhotoAngle.frente, [9, 9]);
      await repo.add(source: source('a.jpg', [1, 2, 3]), date: DateTime(2026, 10, 3), angle: PhotoAngle.frente);
      final rows = await db.select(db.progressPhotos).get();
      expect(rows, hasLength(1));
      expect(rows.single.relativePath, isNot(old.relativePath));
      expect(bytesOf(rows.single), [1, 2, 3]);
      expect(File(p.join(docs.path, old.relativePath)).existsSync(), isFalse);
      expect(Directory(p.join(docs.path, 'fotos')).listSync(), hasLength(1));
    });

    test('INSERT fallido: conserva fila y bytes previos y no deja el archivo nuevo', () async {
      final old = await stored('2026-10-03', PhotoAngle.frente, [9, 9]);
      await failOn('INSERT');
      await expectLater(
          repo.add(source: source('a.jpg', [1, 2, 3]), date: DateTime(2026, 10, 3), angle: PhotoAngle.frente),
          throwsA(anything));
      final rows = await db.select(db.progressPhotos).get();
      expect(rows.map((r) => r.id), [old.id]);
      expect(bytesOf(rows.single), [9, 9]);
      expect(Directory(p.join(docs.path, 'fotos')).listSync(), hasLength(1));
    });

    test('origen inexistente: falla la copia y no cambia nada', () async {
      final old = await stored('2026-10-03', PhotoAngle.frente, [9, 9]);
      await expectLater(
          repo.add(source: File(p.join(scratch.path, 'no.jpg')), date: DateTime(2026, 10, 3), angle: PhotoAngle.frente),
          throwsA(isA<FileSystemException>()));
      expect(bytesOf(await db.select(db.progressPhotos).getSingle()), [9, 9]);
      expect(File(p.join(docs.path, old.relativePath)).existsSync(), isTrue);
      expect(Directory(p.join(docs.path, 'fotos')).listSync(), hasLength(1));
    });

    test('dos altas del mismo día y ángulo no pisan el archivo de la otra', () async {
      final a = source('a.jpg', [1]);
      final b = source('b.jpg', [2]);
      // Ambas deben completar: las transacciones se serializan y la segunda
      // reemplaza a la primera.
      await Future.wait([
        repo.add(source: a, date: DateTime(2026, 10, 4), angle: PhotoAngle.perfil),
        repo.add(source: b, date: DateTime(2026, 10, 4), angle: PhotoAngle.perfil),
      ]);
      final rows = await db.select(db.progressPhotos).get();
      expect(rows, hasLength(1));
      expect(bytesOf(rows.single).single, isIn([1, 2]));
      // La perdedora se purga: ni huérfanos ni archivo compartido.
      expect(Directory(p.join(docs.path, 'fotos')).listSync(), hasLength(1));
    });
  });

  group('reclassify', () {
    test('éxito: la ocupante se reemplaza y su archivo se purga tras el commit', () async {
      final taken = await stored('2026-10-03', PhotoAngle.espalda, [7]);
      final moved = await stored('2026-10-03', PhotoAngle.perfil, [8]);
      await repo.reclassify(moved, angle: PhotoAngle.espalda);
      final rows = await db.select(db.progressPhotos).get();
      expect(rows.map((r) => (r.id, r.angle)), [(moved.id, PhotoAngle.espalda)]);
      expect(bytesOf(rows.single), [8]);
      expect(File(p.join(docs.path, taken.relativePath)).existsSync(), isFalse);
    });

    test('UPDATE fallido: la ocupante conserva fila y bytes', () async {
      final taken = await stored('2026-10-03', PhotoAngle.espalda, [7]);
      final moved = await stored('2026-10-03', PhotoAngle.perfil, [8]);
      await failOn('UPDATE');
      await expectLater(repo.reclassify(moved, angle: PhotoAngle.espalda), throwsA(anything));
      final rows = await db.select(db.progressPhotos).get();
      expect(
          rows.map((r) => (r.id, r.angle)).toSet(), {(taken.id, PhotoAngle.espalda), (moved.id, PhotoAngle.perfil)});
      expect(bytesOf(taken), [7]);
      expect(bytesOf(moved), [8]);
    });

    test('sin ocupante: solo mueve', () async {
      final moved = await stored('2026-10-03', PhotoAngle.perfil, [8]);
      await repo.reclassify(moved, date: DateTime(2026, 9, 29));
      expect((await db.select(db.progressPhotos).getSingle()).date, '2026-09-29');
      expect(bytesOf(moved), [8]);
    });
  });

  group('quitar, deshacer y purga', () {
    test('quitar conserva el archivo; restore devuelve la foto; purga lo borra', () async {
      final p1 = await stored('2026-10-03', PhotoAngle.frente, [5]);
      await repo.remove(p1);
      expect(bytesOf(p1), [5]);
      await repo.restore(p1);
      expect((await db.select(db.progressPhotos).getSingle()).id, p1.id);
      await repo.remove(p1);
      await repo.purgeFile(p1);
      expect(File(p.join(docs.path, p1.relativePath)).existsSync(), isFalse);
    });

    test('delete confinado: una ruta con .. no borra fuera de fotos', () async {
      final outside = File(p.join(docs.path, 'seguimiento.sqlite'))..writeAsBytesSync([4]);
      final id = await db.into(db.progressPhotos).insert(ProgressPhotosCompanion.insert(
          date: '2026-10-03', angle: PhotoAngle.frente, relativePath: 'fotos/../seguimiento.sqlite'));
      final row = await (db.select(db.progressPhotos)..where((t) => t.id.equals(id))).getSingle();
      await repo.delete(row);
      expect(outside.existsSync(), isTrue);
      expect(await db.select(db.progressPhotos).get(), isEmpty);
    });

    test('delete con fallo SQL conserva el archivo', () async {
      final p1 = await stored('2026-10-03', PhotoAngle.frente, [5]);
      await failOn('DELETE');
      await expectLater(repo.delete(p1), throwsA(anything));
      expect(bytesOf(p1), [5]);
    });
  });
}
