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
  Future<void> add({
    required File source,
    required DateTime date,
    required PhotoAngle angle,
    bool fasted = true,
  }) async {
    final dir = await _dir();
    final name = '${dayKey(date)}-${angle.name}${p.extension(source.path)}';
    final target = File(p.join(dir.path, name));
    await source.copy(target.path);

    final existing = await (db.select(db.progressPhotos)
          ..where((t) => t.date.equals(dayKey(date)) & t.angle.equalsValue(angle)))
        .getSingleOrNull();
    // Si la anterior tenía otra extensión (.png → .jpg), su archivo no fue
    // sobrescrito: se borra para no dejar huérfanos.
    if (existing != null) await delete(existing, keepFile: existing.relativePath == p.join(folder, name));

    await db.into(db.progressPhotos).insert(ProgressPhotosCompanion.insert(
          date: dayKey(date),
          angle: angle,
          relativePath: p.join(folder, name),
          fasted: Value(fasted),
        ));
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

  Future<void> delete(ProgressPhotoRow row, {bool keepFile = false}) async {
    if (!keepFile) {
      final file = await fileOf(row);
      if (file.existsSync()) file.deleteSync();
    }
    await (db.delete(db.progressPhotos)..where((t) => t.id.equals(row.id))).go();
  }
}
