import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

/// Error de restauración con mensaje listo para mostrar.
class RestoreException implements Exception {
  RestoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dueño de la conexión a la base. Existe para poder **reemplazar el archivo**
/// (restaurar un respaldo) sin reiniciar la app: cierra, cambia el archivo y
/// vuelve a abrir. Los providers se recrean después con la instancia nueva.
class DatabaseHost {
  /// `initial` permite adoptar una conexión ya abierta (pruebas).
  DatabaseHost(this.file, this.opener, {AppDatabase? initial}) : _db = initial ?? opener(file);

  static Future<DatabaseHost> open() async =>
      DatabaseHost(await databaseFile(), (f) => AppDatabase(NativeDatabase.createInBackground(f)));

  final File file;

  /// Cómo se abre la base. Las pruebas la abren en el mismo isolate.
  final AppDatabase Function(File) opener;
  AppDatabase _db;

  AppDatabase get db => _db;

  /// Copia consistente de la base actual.
  Future<File> exportTo(String path) => _db.exportTo(path);

  /// Reemplaza la base por el respaldo. Valida antes de tocar nada y, si algo
  /// falla al reabrir, deja la base anterior tal como estaba.
  Future<void> restoreFrom(File backup) async {
    await _validate(backup);

    // Copia consistente hecha por SQLite con la conexión aún abierta: no
    // depende de que no haya una escritura a medias en ese instante.
    final safetyCopy = File('${file.path}.pre-restore');
    if (safetyCopy.existsSync()) safetyCopy.deleteSync();
    await _db.exportTo(safetyCopy.path);

    await _db.close();
    try {
      _deleteSidecars();
      await backup.copy(file.path);
      _db = opener(file);
      // Consulta real: si el archivo no sirve, falla aquí y no en la UI.
      await _db.customSelect('select count(*) as n from profiles').getSingle();
      if (safetyCopy.existsSync()) safetyCopy.deleteSync();
    } on Object catch (e) {
      await _rollback(safetyCopy);
      throw RestoreException('No se pudo restaurar: $e. Se dejó la base anterior sin cambios.');
    }
  }

  Future<void> _rollback(File safetyCopy) async {
    try {
      await _db.close();
    } on Object {
      // La conexión ya podía estar rota; seguir con el rollback del archivo.
    }
    _deleteSidecars();
    if (safetyCopy.existsSync()) {
      await safetyCopy.copy(file.path);
      safetyCopy.deleteSync();
    }
    _db = opener(file);
  }

  /// Los `-wal` y `-shm` pertenecen al archivo anterior: mezclarlos con una
  /// base restaurada corrompe los datos.
  void _deleteSidecars() {
    for (final suffix in ['-wal', '-shm']) {
      final f = File('${file.path}$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }

  Future<void> _validate(File backup) async {
    if (!backup.existsSync()) throw RestoreException('El archivo no existe.');
    if (await backup.length() < 512) throw RestoreException('El archivo está vacío o no es una base de datos.');

    Database? probe;
    try {
      probe = sqlite3.open(backup.path, mode: OpenMode.readOnly);
      final tables = probe
          .select("select name from sqlite_master where type = 'table'")
          .map((r) => r['name'] as String)
          .toSet();
      const required = {'profiles', 'sessions', 'meals', 'measurements'};
      final missing = required.difference(tables);
      if (missing.isNotEmpty) {
        throw RestoreException('El archivo no es un respaldo de Seguimiento '
            '(faltan tablas: ${missing.join(', ')}).');
      }
      final version = probe.select('pragma user_version').first.values.first as int;
      if (version > _db.schemaVersion) {
        throw RestoreException('El respaldo viene de una versión más nueva de la app '
            '(esquema $version, esta app usa ${_db.schemaVersion}). Actualiza la app y vuelve a intentarlo.');
      }
    } on SqliteException catch (e) {
      throw RestoreException('El archivo no se puede leer como base de datos: ${e.message}');
    } finally {
      probe?.dispose();
    }
  }
}
