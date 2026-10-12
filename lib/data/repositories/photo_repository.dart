import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../database.dart';

/// Una toma: todas las fotos de una misma fecha.
class PhotoCheckIn {
  PhotoCheckIn(this.date, this.byAngle);

  final DateTime date;
  final Map<PhotoAngle, ProgressPhotoRow> byAngle;
}

/// Fotos de progreso. El archivo vive en el directorio de la app y la base
/// guarda solo la ruta relativa.
class PhotoRepository {
  PhotoRepository(this.db);

  final AppDatabase db;
  static const folder = 'fotos';

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, folder));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Ruta absoluta de una foto guardada.
  Future<File> fileOf(ProgressPhotoRow row) async => fileIn(await getApplicationDocumentsDirectory(), row);

  /// Igual, con el directorio ya resuelto (para pintar sin esperar).
  static File fileIn(Directory base, ProgressPhotoRow row) => File(p.join(base.path, row.relativePath));

  /// Copia la imagen al directorio de la app y la registra. Si ya había una
  /// foto de ese ángulo ese día, la reemplaza.
  ///
  /// Orden: archivo nuevo, fila en una transacción y, solo con la fila ya
  /// confirmada, el archivo anterior. Si algo falla antes del commit, el
  /// archivo nuevo se limpia y la foto previa queda intacta.
  Future<void> add({
    required File source,
    required DateTime date,
    required PhotoAngle angle,
    bool fasted = true,
  }) async {
    final dir = await _dir();
    final target = await _claim(dir, '${dayKey(date)}-${angle.name}-${DateTime.now().millisecondsSinceEpoch}',
        p.extension(source.path));
    final relative = p.join(folder, p.basename(target.path));
    ProgressPhotoRow? replaced;
    try {
      await source.copy(target.path);
      replaced = await db.transaction(() async {
        final existing = await occupant(date, angle);
        if (existing != null) await _deleteRow(existing);
        await db.into(db.progressPhotos).insert(ProgressPhotosCompanion.insert(
              date: dayKey(date),
              angle: angle,
              relativePath: relative,
              fasted: Value(fasted),
            ));
        return existing;
      });
    } on Object {
      try {
        if (target.existsSync()) target.deleteSync();
      } on FileSystemException {
        // Queda un huérfano en fotos/; nunca una foto referenciada sin archivo.
      }
      rethrow;
    }
    if (replaced != null && replaced.relativePath != relative) _deleteFile(dir.parent, replaced);
  }

  /// Reserva un nombre libre creando el archivo de forma exclusiva: otra alta
  /// del mismo día y ángulo en el mismo milisegundo no puede pisarlo.
  Future<File> _claim(Directory dir, String stem, String ext) async {
    for (var n = 0;; n++) {
      final file = File(p.join(dir.path, n == 0 ? '$stem$ext' : '$stem-$n$ext'));
      try {
        await file.create(exclusive: true);
        return file;
      } on PathExistsException {
        continue;
      }
    }
  }

  Stream<List<PhotoCheckIn>> watchCheckIns() => (db.select(db.progressPhotos)
        ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
      .watch()
      .map(_group);

  List<PhotoCheckIn> _group(List<ProgressPhotoRow> rows) {
    final byDate = <String, Map<PhotoAngle, ProgressPhotoRow>>{};
    for (final r in rows) {
      byDate.putIfAbsent(r.date, () => {})[r.angle] = r;
    }
    final keys = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys) PhotoCheckIn(parseDay(k), byDate[k]!)];
  }

  /// La foto que ya ocupa ese día y ángulo (otra que no sea `except`).
  Future<ProgressPhotoRow?> occupant(DateTime date, PhotoAngle angle, {int? except}) async {
    final rows = await (db.select(db.progressPhotos)
          ..where((t) => t.date.equals(dayKey(date)) & t.angle.equalsValue(angle)))
        .get();
    return rows.where((r) => r.id != except).firstOrNull;
  }

  /// Reclasifica una foto: otro tipo u otra fecha (§16.11). Si ya había una
  /// foto en ese lugar, se reemplaza: su fila sale en la misma transacción y su
  /// archivo se borra solo después del commit.
  Future<void> reclassify(ProgressPhotoRow row, {PhotoAngle? angle, DateTime? date}) async {
    final taken = await db.transaction(() async {
      final newAngle = angle ?? row.angle;
      final newDate = date == null ? row.date : dayKey(date);
      final taken = await occupant(parseDay(newDate), newAngle, except: row.id);
      if (taken != null) await _deleteRow(taken);
      await (db.update(db.progressPhotos)..where((t) => t.id.equals(row.id))).write(ProgressPhotosCompanion(
        angle: Value(newAngle),
        date: Value(newDate),
      ));
      return taken;
    });
    if (taken != null && taken.relativePath != row.relativePath) {
      _deleteFile(await getApplicationDocumentsDirectory(), taken);
    }
  }

  /// Quita la foto de la lista sin borrar el archivo: así se puede deshacer.
  /// El archivo se borra después con [purgeFile].
  Future<void> remove(ProgressPhotoRow row) => (db.delete(db.progressPhotos)..where((t) => t.id.equals(row.id))).go();

  /// Vuelve a poner una foto quitada con [remove].
  Future<void> restore(ProgressPhotoRow row) => db.into(db.progressPhotos).insert(row.toCompanion(true));

  /// Borra el archivo de una foto ya quitada de la lista.
  Future<void> purgeFile(ProgressPhotoRow row) async => _deleteFile(await getApplicationDocumentsDirectory(), row);

  /// Borra la fila y después el archivo: si el DELETE falla, la foto sigue
  /// completa. Un crash entre ambos pasos deja un huérfano, no una foto rota.
  Future<void> delete(ProgressPhotoRow row, {bool keepFile = false}) async {
    await _deleteRow(row);
    if (!keepFile) _deleteFile(await getApplicationDocumentsDirectory(), row);
  }

  Future<void> _deleteRow(ProgressPhotoRow row) =>
      (db.delete(db.progressPhotos)..where((t) => t.id.equals(row.id))).go();

  /// La ruta sale de la base, que puede venir de un respaldo restaurado: solo
  /// se borra lo que está dentro de la carpeta de fotos. Una ruta con `..`
  /// podía borrar otro archivo de la app.
  static void _deleteFile(Directory base, ProgressPhotoRow row) {
    final full = confinedPath(base, row.relativePath);
    if (full == null) return;
    try {
      final f = File(full);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // Un archivo que ya no está no rompe nada.
    }
  }

  /// Ruta absoluta si `relative` cae dentro de la carpeta de fotos; si no,
  /// null.
  static String? confinedPath(Directory base, String relative) {
    final full = p.normalize(p.join(base.path, relative));
    return p.isWithin(p.join(base.path, folder), full) ? full : null;
  }
}
