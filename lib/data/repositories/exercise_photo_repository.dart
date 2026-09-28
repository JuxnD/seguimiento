import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/search.dart';
import '../database.dart';

/// Fotos de referencia por ejercicio. El archivo vive en el directorio de la
/// app (`fotos/ejercicios/`) y la base guarda la ruta relativa. Como las fotos
/// de progreso, no entran en los respaldos.
class ExercisePhotoRepository {
  ExercisePhotoRepository(this.db, this.documents);

  final AppDatabase db;

  /// Directorio de documentos de la app (inyectado para poder probarlo).
  final Future<Directory> Function() documents;

  static const folder = 'fotos/ejercicios';

  Stream<ExercisePhotoRow?> watch(String exercise) =>
      (db.select(db.exercisePhotos)..where((t) => t.nameKey.equals(nameKey(exercise)))).watchSingleOrNull();

  /// Copia la imagen y la registra; si el ejercicio ya tenía una, la reemplaza
  /// y borra el archivo anterior.
  Future<void> save(String exercise, File source) async {
    final base = await documents();
    final dir = Directory(p.join(base.path, folder));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final key = nameKey(exercise);
    // Nombre nuevo en cada foto: un archivo con el nombre de siempre quedaría
    // en la caché de imágenes y la pantalla seguiría mostrando la vieja.
    final name = '${_slug(key)}-${DateTime.now().millisecondsSinceEpoch}${p.extension(source.path).toLowerCase()}';
    final relative = p.join(folder, name);
    await source.copy(p.join(base.path, relative));

    final previous = await (db.select(db.exercisePhotos)..where((t) => t.nameKey.equals(key))).getSingleOrNull();
    await db.into(db.exercisePhotos).insertOnConflictUpdate(
          ExercisePhotosCompanion.insert(nameKey: key, relativePath: relative),
        );
    if (previous != null && previous.relativePath != relative) _deleteFile(base, previous.relativePath);
  }

  Future<void> remove(String exercise) async {
    final key = nameKey(exercise);
    final row = await (db.select(db.exercisePhotos)..where((t) => t.nameKey.equals(key))).getSingleOrNull();
    if (row == null) return;
    await (db.delete(db.exercisePhotos)..where((t) => t.nameKey.equals(key))).go();
    _deleteFile(await documents(), row.relativePath);
  }

  static File fileIn(Directory base, ExercisePhotoRow row) => File(p.join(base.path, row.relativePath));

  void _deleteFile(Directory base, String relative) {
    // La ruta sale de la base, que puede venir de un respaldo restaurado:
    // solo se borra lo que está dentro de la carpeta de fotos de ejercicios.
    final full = p.normalize(p.join(base.path, relative));
    if (!p.isWithin(p.join(base.path, folder), full)) return;
    try {
      final f = File(full);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // Un archivo huérfano no rompe nada.
    }
  }

  static String _slug(String key) => key.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}
