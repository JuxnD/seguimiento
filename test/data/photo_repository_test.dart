import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/photo_repository.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

/// Fotos de progreso: reclasificar y borrar con deshacer (§16.11). Solo la
/// base: los archivos los resuelve path_provider, que aquí no existe.
void main() {
  late AppDatabase db;
  late PhotoRepository repo;

  setUpAll(useHostSqlite);
  setUp(() {
    db = openInMemoryDatabase();
    repo = PhotoRepository(db);
  });
  tearDown(() => db.close());

  Future<ProgressPhotoRow> photo(String date, PhotoAngle angle) async {
    final id = await db.into(db.progressPhotos).insert(
        ProgressPhotosCompanion.insert(date: date, angle: angle, relativePath: 'fotos/$date-${angle.name}.jpg'));
    return (db.select(db.progressPhotos)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<List<(String, PhotoAngle)>> all() async =>
      [for (final r in await db.select(db.progressPhotos).get()) (r.date, r.angle)];

  test('una espalda subida como perfil se pasa a espalda', () async {
    final wrong = await photo('2026-10-03', PhotoAngle.perfil);
    await repo.reclassify(wrong, angle: PhotoAngle.espalda);
    expect(await all(), [('2026-10-03', PhotoAngle.espalda)]);
  });

  test('cambiar la fecha la mueve de toma', () async {
    final p = await photo('2026-10-03', PhotoAngle.frente);
    await repo.reclassify(p, date: DateTime(2026, 9, 29));
    expect(await all(), [('2026-09-29', PhotoAngle.frente)]);
  });

  test('detecta la foto que ya ocupa el destino y mueve la nueva allí', () async {
    final other = await photo('2026-10-03', PhotoAngle.espalda);
    final moved = await photo('2026-10-03', PhotoAngle.perfil);
    expect((await repo.occupant(DateTime(2026, 10, 3), PhotoAngle.espalda, except: moved.id))!.id, other.id);
    // Borrar el archivo de la reemplazada pide path_provider, que en la
    // prueba no existe: se quita a mano y se prueba el movimiento.
    await db.delete(db.progressPhotos).delete(other);
    await repo.reclassify(moved, angle: PhotoAngle.espalda);
    expect(await all(), [('2026-10-03', PhotoAngle.espalda)]);
  });

  test('quitar y deshacer devuelve la misma foto', () async {
    final p = await photo('2026-10-03', PhotoAngle.perfil);
    await repo.remove(p);
    expect(await all(), isEmpty);
    await repo.restore(p);
    final back = await db.select(db.progressPhotos).getSingle();
    expect((back.id, back.date, back.angle, back.relativePath), (p.id, p.date, p.angle, p.relativePath));
  });
}
