import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'repositories/reminder_repository.dart';

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

  static Future<DatabaseHost> open() async {
    final file = await databaseFile();
    await recoverPendingRestore(file);
    return DatabaseHost(file, (f) => AppDatabase(NativeDatabase.createInBackground(f)));
  }

  final File file;

  /// Cómo se abre la base. Las pruebas la abren en el mismo isolate.
  final AppDatabase Function(File) opener;
  AppDatabase _db;
  bool _restoring = false;

  AppDatabase get db => _db;

  /// Copia consistente de la base actual.
  Future<File> exportTo(String path) => _db.exportTo(path);

  /// Reemplaza la base por el respaldo. Valida antes de tocar nada y, si algo
  /// falla al reabrir, deja la base anterior tal como estaba.
  /// [stagedPhotos], si existe, es una carpeta ya verificada del paquete ZIP.
  /// Base y fotos comparten una reversión; SQLite antiguo solo cambia la base.
  Future<void> restoreFrom(File backup, {Directory? stagedPhotos}) async {
    if (_restoring) throw RestoreException('Ya hay una restauración en curso.');
    _restoring = true;
    try {
      await _restoreFrom(backup, stagedPhotos: stagedPhotos);
    } finally {
      _restoring = false;
    }
  }

  Future<void> validateBackup(File backup) async {
    await _validate(backup);
    await _trialOpen(backup);
  }

  Future<void> _restoreFrom(File backup, {Directory? stagedPhotos}) async {
    await validateBackup(backup);
    final photos = Directory(p.join(file.parent.path, 'fotos'));
    final oldPhotos = Directory('${file.path}.pre-restore-fotos');
    final journal = File('${file.path}.restore-state.json');
    if (journal.existsSync()) {
      throw RestoreException('Hay una restauración pendiente de recuperar. Cierra y vuelve a abrir la app.');
    }
    final hadPhotos = photos.existsSync();
    if (stagedPhotos != null) {
      final photosType = FileSystemEntity.typeSync(photos.path, followLinks: false);
      if (!p.isWithin(file.parent.absolute.path, stagedPhotos.absolute.path) ||
          p.equals(photos.absolute.path, stagedPhotos.absolute.path) ||
          p.isWithin(photos.absolute.path, stagedPhotos.absolute.path) ||
          FileSystemEntity.typeSync(stagedPhotos.path, followLinks: false) != FileSystemEntityType.directory ||
          (photosType != FileSystemEntityType.notFound && photosType != FileSystemEntityType.directory) ||
          FileSystemEntity.typeSync(oldPhotos.path, followLinks: false) != FileSystemEntityType.notFound) {
        throw RestoreException('La carpeta de fotos no se puede reemplazar de forma segura.');
      }
    }

    // Copia consistente hecha por SQLite con la conexión aún abierta: no
    // depende de que no haya una escritura a medias en ese instante.
    final safetyCopy = File('${file.path}.pre-restore');
    if (safetyCopy.existsSync()) safetyCopy.deleteSync();
    await _db.exportTo(safetyCopy.path);
    final state = <String, Object>{
      'version': 1,
      'photos': stagedPhotos != null,
      'hadPhotos': hadPhotos,
      'committed': false
    };
    await _writeJournal(journal, state);
    try {
      await _db.close();
      _deleteSidecars();
      if (stagedPhotos != null) {
        if (hadPhotos) await photos.rename(oldPhotos.path);
        await stagedPhotos.rename(photos.path);
      }
      await backup.copy(file.path);
      _db = opener(file);
      // Consulta real a cada tabla: si el archivo no sirve, falla aquí y no
      // en la UI, y la copia previa todavía existe para volver atrás.
      await checkComplete(_db);
      // Un respaldo viejo puede llegar sin recordatorios (anterior al esquema 5,
      // o reiniciados por la migración al 9): se recrean con sus valores.
      await ReminderRepository(_db).ensureDefaults();
      state['committed'] = true;
      await _writeJournal(journal, state);
    } on Object catch (e) {
      try {
        await _rollback(safetyCopy);
        if (stagedPhotos != null) await _restorePhotos(file, hadPhotos: hadPhotos);
        await checkComplete(_db);
        state['committed'] = true;
        await _writeJournal(journal, state);
        await _cleanRestore(file);
      } on Object catch (rollbackError) {
        throw RestoreException('No se pudo completar la restauración ni su reversión: $rollbackError. '
            'Se conservaron las copias previas; cierra y vuelve a abrir la app para recuperarlas.');
      }
      throw RestoreException('No se pudo restaurar: $e. Se dejó la base anterior sin cambios.');
    }
    // La operación ya quedó confirmada. Un fallo al limpiar copias sobrantes
    // no debe intentar revertir un estado cuya copia ya se empezó a borrar.
    await _cleanRestore(file);
  }

  static Future<void> _writeJournal(File journal, Map<String, Object> state) async {
    final pending = File('${journal.path}.tmp');
    await pending.writeAsString(jsonEncode(state), flush: true);
    await pending.rename(journal.path);
  }

  /// Recuperación antes de abrir SQLite si Android cerró el proceso a mitad
  /// del reemplazo. Las rutas de recuperación son fijas, nunca vienen del ZIP.
  static Future<void> recoverPendingRestore(File file) async {
    final journal = File('${file.path}.restore-state.json');
    if (!journal.existsSync()) return;
    final Object? decoded = jsonDecode(await journal.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['photos'] is! bool ||
        decoded['hadPhotos'] is! bool ||
        decoded['committed'] is! bool) {
      throw RestoreException('No se pudo leer la recuperación pendiente. Se conservaron sus copias previas.');
    }
    if (decoded['committed'] == false) {
      final safety = File('${file.path}.pre-restore');
      if (!safety.existsSync()) throw RestoreException('Falta la base previa de la restauración pendiente.');
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = File('${file.path}$suffix');
        if (sidecar.existsSync()) await sidecar.delete();
      }
      await safety.copy(file.path);
      if (decoded['photos'] == true) await _restorePhotos(file, hadPhotos: decoded['hadPhotos'] as bool);
      await _writeJournal(journal, {
        'version': 1,
        'photos': decoded['photos'] as bool,
        'hadPhotos': decoded['hadPhotos'] as bool,
        'committed': true
      });
    }
    await _cleanRestore(file);
  }

  static Future<void> _restorePhotos(File file, {required bool hadPhotos}) async {
    final photos = Directory(p.join(file.parent.path, 'fotos'));
    final previous = Directory('${file.path}.pre-restore-fotos');
    if (previous.existsSync() || !hadPhotos) {
      if (photos.existsSync()) await photos.delete(recursive: true);
      if (previous.existsSync()) await previous.rename(photos.path);
    }
  }

  static Future<void> _cleanRestore(File file) async {
    try {
      final previous = Directory('${file.path}.pre-restore-fotos');
      if (previous.existsSync()) await previous.delete(recursive: true);
      final safety = File('${file.path}.pre-restore');
      if (safety.existsSync()) await safety.delete();
      final journal = File('${file.path}.restore-state.json');
      if (journal.existsSync()) await journal.delete();
    } on FileSystemException {
      // La próxima apertura termina la limpieza usando el diario confirmado.
    }
  }

  /// Abre una copia del respaldo con la app (corre las migraciones) y
  /// consulta todas las tablas. Un respaldo de esquema 16 al que le falte
  /// `foods` pasaba la validación por tablas mínimas, se daba por bueno y se
  /// borraba la copia anterior (auditoría del 5 oct).
  Future<void> _trialOpen(File backup) async {
    final trial = File('${file.path}.restore-check');
    void clean() {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('${trial.path}$suffix');
        if (f.existsSync()) f.deleteSync();
      }
    }

    clean();
    await backup.copy(trial.path);
    AppDatabase? db;
    try {
      db = opener(trial);
      await checkComplete(db);
    } on RestoreException {
      rethrow;
    } on Object catch (e) {
      throw RestoreException('El respaldo está incompleto o dañado: $e');
    } finally {
      await db?.close();
      clean();
    }
  }

  /// Consulta cada tabla del esquema actual. Lanza [RestoreException] con las
  /// que falten.
  static Future<void> checkComplete(AppDatabase db) async {
    final missing = <String>[];
    for (final table in db.allTables) {
      try {
        final columns = table.$columns.map((c) => '"${table.actualTableName}"."${c.name}"').join(', ');
        await db.customSelect('select $columns from "${table.actualTableName}" limit 1').get();
      } on Object {
        missing.add(table.actualTableName);
      }
    }
    if (missing.isNotEmpty) {
      throw RestoreException('El respaldo está incompleto (faltan tablas: ${missing.join(', ')}).');
    }
    final integrity = await db.customSelect('pragma quick_check').get();
    if (integrity.length != 1 || integrity.single.data.values.single != 'ok') {
      throw RestoreException('El respaldo está dañado (integridad SQLite).');
    }
    if ((await db.customSelect('pragma foreign_key_check').get()).isNotEmpty) {
      throw RestoreException('El respaldo contiene referencias incompletas.');
    }
    final profile = await db.customSelect('select id from profiles').get();
    if (profile.length != 1 || profile.single.data['id'] != 1) {
      throw RestoreException('El respaldo no contiene un perfil válido.');
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
      final tables =
          probe.select("select name from sqlite_master where type = 'table'").map((r) => r['name'] as String).toSet();
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
