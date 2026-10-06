import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart' hide ZLibDecoder;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'database_host.dart';

/// ZIP v1: manifiesto, snapshot SQLite y carpeta fotos (incluye ejercicios).
/// Se procesan archivos por streams; nunca se descomprime el paquete en RAM.
class BackupArchive {
  BackupArchive({required this.host, required this.documents}) {
    if (!p.equals(host.file.parent.absolute.path, documents.absolute.path)) {
      throw ArgumentError('La base y las fotos deben compartir el directorio de documentos.');
    }
  }

  static const format = 'seguimiento-backup';
  static const formatVersion = 1;
  static const databaseName = 'seguimiento.sqlite';
  static const manifestName = 'manifest.json';
  static const maxFileBytes = 64 * 1024 * 1024;
  static const maxTotalBytes = 256 * 1024 * 1024;
  static const maxPackageBytes = maxTotalBytes + 4 * 1024 * 1024;
  static const maxFiles = 4096;
  static const maxManifestBytes = 1024 * 1024;

  final DatabaseHost host;
  final Directory documents;

  Future<BackupExport> exportTo(String path) async {
    final target = File(path);
    if (p.isWithin(documents.absolute.path, target.absolute.path) ||
        p.equals(documents.absolute.path, target.absolute.path)) {
      throw RestoreException('Guarda el paquete fuera del directorio de datos de la app.');
    }
    final stage = await documents.createTemp('.backup-export-');
    final temporary = File('$path.partial-${DateTime.now().microsecondsSinceEpoch}');
    try {
      final snapshot = await host.exportTo(p.join(stage.path, databaseName));
      final references = _photoReferences(snapshot, canonicalize: true);
      final job = _ExportJob(snapshot.path, documents.path, temporary.path, references, host.db.schemaVersion,
          DateTime.now().toUtc().toIso8601String());
      final result = await compute(_writePackage, job);
      await temporary.rename(target.path);
      return BackupExport(target, photoCount: result.photoCount, missingPhotos: result.missingPhotos);
    } on RestoreException {
      rethrow;
    } on Object catch (e) {
      throw RestoreException('No se pudo crear el respaldo: $e');
    } finally {
      if (temporary.existsSync()) await temporary.delete();
      if (stage.existsSync()) await stage.delete(recursive: true);
    }
  }

  /// Prepara y valida sin modificar ni la base ni las fotos actuales. El caller
  /// debe liberar [PreparedBackup] incluso si el usuario cancela el diálogo.
  Future<PreparedBackup> prepare(File source) async {
    if (!source.existsSync()) throw RestoreException('El archivo no existe.');
    final length = await source.length();
    if (length < 16 || length > maxPackageBytes) {
      throw RestoreException('El respaldo está vacío o supera el límite de 260 MiB.');
    }
    final input = await source.open();
    late final List<int> signature;
    try {
      signature = await input.read(16);
    } finally {
      await input.close();
    }
    final legacy = ascii.decode(signature, allowInvalid: true) == 'SQLite format 3\u0000';
    final stage = await documents.createTemp('.backup-import-');
    try {
      _PackageInfo? info;
      final database = File(p.join(stage.path, databaseName));
      if (legacy) {
        if (length > maxFileBytes) throw RestoreException('La base supera el límite de 64 MiB por archivo.');
        await source.copy(database.path);
      } else {
        info = await compute(_unpackPackage, _ImportJob(source.path, stage.path));
      }
      await host.validateBackup(database);
      final references = _photoReferences(database, canonicalize: legacy);
      if (info != null) {
        final raw = sqlite3.open(database.path, mode: OpenMode.readOnly);
        try {
          final version = raw.select('pragma user_version').first.values.first;
          if (version != info.schemaVersion) throw RestoreException('El esquema no coincide con el manifiesto.');
        } finally {
          raw.dispose();
        }
        final paths = info.paths;
        final absent = references.where((path) => !paths.contains(path)).toSet();
        if (!_setEquals(absent, info.missingPhotos.toSet())) {
          throw RestoreException('El paquete no contiene todas las fotos que declara su base.');
        }
      }
      return PreparedBackup._(stage, database,
          legacy: legacy,
          photos: legacy ? null : Directory(p.join(stage.path, 'fotos')),
          missingPhotos: info?.missingPhotos ?? const [],
          photoCount: info?.photoCount ?? 0);
    } on RestoreException {
      await stage.delete(recursive: true);
      rethrow;
    } on Object catch (e) {
      await stage.delete(recursive: true);
      throw RestoreException('El respaldo es inválido o está dañado: $e');
    }
  }

  Future<void> restore(PreparedBackup prepared, {bool allowMissingPhotos = false}) async {
    if (!prepared.legacy && prepared.missingPhotos.isNotEmpty && !allowMissingPhotos) {
      throw RestoreException('El respaldo declara ${prepared.missingPhotos.length} fotos faltantes. '
          'Confirma explícitamente que quieres restaurarlo incompleto.');
    }
    await host.restoreFrom(prepared.database, stagedPhotos: prepared.photos);
  }

  Future<void> restoreFrom(File source, {bool allowMissingPhotos = false}) async {
    final prepared = await prepare(source);
    try {
      await restore(prepared, allowMissingPhotos: allowMissingPhotos);
    } finally {
      await prepared.dispose();
    }
  }
}

class BackupExport {
  const BackupExport(this.file, {required this.photoCount, required this.missingPhotos});
  final File file;
  final int photoCount;
  final List<String> missingPhotos;
  bool get complete => missingPhotos.isEmpty;
}

class PreparedBackup {
  PreparedBackup._(this.stage, this.database,
      {required this.legacy, required this.photos, required this.missingPhotos, required this.photoCount});
  final Directory stage;
  final File database;
  final Directory? photos;
  final bool legacy;
  final List<String> missingPhotos;
  final int photoCount;

  Future<void> dispose() async {
    if (stage.existsSync()) await stage.delete(recursive: true);
  }
}

class _ExportJob {
  const _ExportJob(this.database, this.documents, this.output, this.references, this.schemaVersion, this.createdAt);
  final String database, documents, output, createdAt;
  final List<String> references;
  final int schemaVersion;
}

class _ImportJob {
  const _ImportJob(this.source, this.stage);
  final String source, stage;
}

class _PackageInfo {
  const _PackageInfo(this.paths, this.missingPhotos, this.schemaVersion);
  final Set<String> paths;
  final List<String> missingPhotos;
  final int schemaVersion;
  int get photoCount => paths.where((path) => path.startsWith('fotos/')).length;
}

class _ExportInfo {
  const _ExportInfo(this.photoCount, this.missingPhotos);
  final int photoCount;
  final List<String> missingPhotos;
}

List<String> _photoReferences(File snapshot, {bool canonicalize = false}) {
  final raw = sqlite3.open(snapshot.path, mode: canonicalize ? OpenMode.readWrite : OpenMode.readOnly);
  try {
    final tables = raw.select("select name from sqlite_master where type='table'").map((r) => r['name']).toSet();
    final out = <String>{};
    for (final table in ['progress_photos', 'exercise_photos']) {
      // Una base legacy puede ser anterior a la función de fotos.
      if (!tables.contains(table)) continue;
      for (final row in raw.select('select relative_path from $table')) {
        final original = row['relative_path'];
        if (original is! String) throw RestoreException('El respaldo contiene una ruta de foto inválida.');
        final path = canonicalize ? original.replaceAll('\\', '/') : original;
        _checkPhotoPath(path);
        if (table == 'exercise_photos' && !path.startsWith('fotos/ejercicios/')) {
          throw RestoreException('Una foto de ejercicio apunta fuera de su carpeta.');
        }
        out.add(path);
        if (canonicalize && original != path) {
          raw.execute('update $table set relative_path = ? where relative_path = ?', [path, original]);
        }
      }
    }
    return out.toList()..sort();
  } finally {
    raw.dispose();
  }
}

void _checkPath(String path) {
  if (path.isEmpty || path.length > 240 || path.contains(RegExp(r'[\\:\x00-\x1f<>"|?*]'))) {
    throw RestoreException('El respaldo contiene una ruta no permitida.');
  }
  for (final part in path.split('/')) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)', caseSensitive: false).hasMatch(part)) {
      throw RestoreException('El respaldo contiene una ruta no permitida.');
    }
  }
}

void _checkPhotoPath(String path) {
  _checkPath(path);
  if (!path.startsWith('fotos/') || path == 'fotos/ejercicios') {
    throw RestoreException('El respaldo contiene un archivo fuera de las carpetas de fotos.');
  }
}

Future<_ExportInfo> _writePackage(_ExportJob job) async {
  final sources = <String, File>{BackupArchive.databaseName: File(job.database)};
  final folder = Directory(p.join(job.documents, 'fotos'));
  final folderType = FileSystemEntity.typeSync(folder.path, followLinks: false);
  if (folderType != FileSystemEntityType.notFound && folderType != FileSystemEntityType.directory) {
    throw RestoreException('La carpeta de fotos no es una carpeta normal.');
  }
  final folded = <String>{BackupArchive.databaseName};
  if (folder.existsSync()) {
    await for (final entity in folder.list(recursive: true, followLinks: false)) {
      if (entity is Link) throw RestoreException('Las fotos contienen enlaces; no se exportó el paquete.');
      if (entity is! File) continue;
      final path = p.relative(entity.path, from: job.documents).replaceAll('\\', '/');
      _checkPhotoPath(path);
      if (!folded.add(path.toLowerCase())) throw RestoreException('Las fotos contienen rutas duplicadas.');
      sources[path] = entity;
      if (sources.length > BackupArchive.maxFiles) {
        throw RestoreException('El respaldo supera el límite de 4096 archivos.');
      }
    }
  }
  final missing = job.references.where((path) => !sources.containsKey(path)).toList();
  final descriptors = <Map<String, Object>>[];
  var total = 0;
  final encoder = ZipFileEncoder();
  encoder.create(job.output, level: ZipFileEncoder.STORE);
  try {
    final names = sources.keys.toList()..sort();
    for (final name in names) {
      final file = sources[name]!;
      final bytes = await file.length();
      total += bytes;
      if (bytes > BackupArchive.maxFileBytes || total > BackupArchive.maxTotalBytes) {
        throw RestoreException('El respaldo supera los límites: 64 MiB por archivo y 256 MiB en total.');
      }
      final digest = await sha256.bind(file.openRead()).first;
      descriptors.add({'path': name, 'bytes': bytes, 'sha256': digest.toString()});
      await encoder.addFile(file, name, ZipFileEncoder.STORE);
    }
    final manifest = utf8.encode(jsonEncode({
      'format': BackupArchive.format,
      'version': BackupArchive.formatVersion,
      'schemaVersion': job.schemaVersion,
      'createdAt': job.createdAt,
      'complete': missing.isEmpty,
      'missingPhotos': missing,
      'files': descriptors,
    }));
    if (manifest.length > BackupArchive.maxManifestBytes) throw RestoreException('El manifiesto es demasiado grande.');
    encoder.addArchiveFile(ArchiveFile.noCompress(BackupArchive.manifestName, manifest.length, manifest));
  } finally {
    await encoder.close();
  }
  // Releer el archivo que viajará detecta cambios de fotos entre hash y copia.
  final verification = Directory(p.dirname(job.output)).createTempSync('.backup-verify-');
  try {
    await _unpackPackage(_ImportJob(job.output, verification.path));
  } finally {
    await verification.delete(recursive: true);
  }
  return _ExportInfo(sources.length - 1, missing);
}

/// Se valida el EOCD antes de que archive materialice el directorio central.
/// No se aceptan ZIP64 ni multi-volumen: el formato propio no los necesita.
void _checkDirectory(InputFileStream input) {
  final endStart = max(0, input.length - 65557);
  final tail = input.subset(endStart, input.length - endStart).toUint8List();
  final data = ByteData.sublistView(tail);
  for (var at = tail.length - 22; at >= 0; at--) {
    if (data.getUint32(at, Endian.little) != 0x06054b50) continue;
    final comments = data.getUint16(at + 20, Endian.little);
    if (at + 22 + comments != tail.length) continue;
    final entries = data.getUint16(at + 10, Endian.little);
    final size = data.getUint32(at + 12, Endian.little);
    final offset = data.getUint32(at + 16, Endian.little);
    if (data.getUint16(at + 4, Endian.little) != 0 ||
        data.getUint16(at + 6, Endian.little) != 0 ||
        data.getUint16(at + 8, Endian.little) != entries ||
        entries < 2 ||
        entries > BackupArchive.maxFiles + 3 ||
        size > 2 * 1024 * 1024 ||
        offset + size != endStart + at) {
      throw RestoreException('El directorio ZIP es inválido o supera los límites.');
    }
    return;
  }
  throw RestoreException('El archivo no es un ZIP de respaldo válido.');
}

Future<_PackageInfo> _unpackPackage(_ImportJob job) async {
  if (File(job.source).lengthSync() > BackupArchive.maxPackageBytes) {
    throw RestoreException('El respaldo supera el límite de 260 MiB.');
  }
  final input = InputFileStream(job.source);
  try {
    _checkDirectory(input);
    final zip = ZipDirectory.read(input);
    if (zip.fileHeaders.length != zip.totalCentralDirectoryEntries) {
      throw RestoreException('El directorio ZIP está incompleto.');
    }
    final files = <String, ZipFileHeader>{};
    final seen = <String>{};
    var total = 0;
    for (final header in zip.fileHeaders) {
      final name = header.filename;
      final mode = ((header.externalFileAttributes ?? 0) >> 16) & 0xf000;
      if (mode != 0 && mode != 0x8000 && mode != 0x4000) {
        throw RestoreException('El paquete contiene enlaces o archivos especiales.');
      }
      final directory = name.endsWith('/');
      final path = directory ? name.substring(0, name.length - 1) : name;
      _checkPath(path);
      if (!seen.add(path.toLowerCase())) throw RestoreException('El paquete contiene rutas duplicadas.');
      if (header.generalPurposeBitFlag & 1 != 0 ||
          header.file!.flags & 1 != 0 ||
          header.versionNeededToExtract > 20 ||
          header.file!.version > 20 ||
          header.diskNumberStart != 0 ||
          header.file!.compressionMethod != header.compressionMethod ||
          (header.compressionMethod != 0 && header.compressionMethod != 8)) {
        throw RestoreException('El paquete usa cifrado, ZIP64 o compresión no admitidos.');
      }
      final bytes = header.uncompressedSize ?? -1;
      if (bytes < 0 || bytes > BackupArchive.maxFileBytes || header.file!.uncompressedSize != bytes) {
        throw RestoreException('El paquete supera el límite por archivo o declara un tamaño inválido.');
      }
      total += bytes;
      if (total > BackupArchive.maxTotalBytes + BackupArchive.maxManifestBytes) {
        throw RestoreException('El paquete supera el límite de 256 MiB.');
      }
      if (directory) {
        if ((path != 'fotos' && path != 'fotos/ejercicios') || bytes != 0) {
          throw RestoreException('El paquete contiene una carpeta no permitida.');
        }
        continue;
      }
      if (mode == 0x4000) throw RestoreException('El paquete contiene un tipo de archivo inválido.');
      if (path != BackupArchive.databaseName && path != BackupArchive.manifestName) _checkPhotoPath(path);
      files[path] = header;
    }
    final manifestHeader = files.remove(BackupArchive.manifestName);
    if (manifestHeader == null ||
        !files.containsKey(BackupArchive.databaseName) ||
        files.length > BackupArchive.maxFiles ||
        manifestHeader.uncompressedSize! > BackupArchive.maxManifestBytes) {
      throw RestoreException('Falta la base o el manifiesto del respaldo, o el paquete es demasiado grande.');
    }
    final manifestFile = File(p.join(job.stage, BackupArchive.manifestName));
    await _extractFile(manifestHeader, manifestFile);
    final Object? decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != BackupArchive.format ||
        decoded['version'] != BackupArchive.formatVersion ||
        decoded['schemaVersion'] is! int ||
        decoded['schemaVersion'] as int <= 0 ||
        decoded['complete'] is! bool ||
        decoded['missingPhotos'] is! List ||
        decoded['files'] is! List ||
        decoded['createdAt'] is! String ||
        DateTime.tryParse(decoded['createdAt'] as String) == null) {
      throw RestoreException('El manifiesto no es una versión de respaldo admitida.');
    }
    final expected = <String, (int, String)>{};
    final missing = <String>[];
    for (final entry in decoded['files'] as List) {
      if (entry is! Map<String, dynamic> ||
          entry['path'] is! String ||
          entry['bytes'] is! int ||
          entry['sha256'] is! String) {
        throw RestoreException('El manifiesto contiene una entrada inválida.');
      }
      final name = entry['path'] as String;
      _checkPath(name);
      final bytes = entry['bytes'] as int;
      final hash = entry['sha256'] as String;
      if (bytes < 0 ||
          bytes > BackupArchive.maxFileBytes ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
          expected.containsKey(name)) {
        throw RestoreException('El manifiesto contiene tamaños, hashes o rutas inválidos.');
      }
      expected[name] = (bytes, hash);
    }
    for (final entry in decoded['missingPhotos'] as List) {
      if (entry is! String) throw RestoreException('La lista de fotos faltantes es inválida.');
      _checkPhotoPath(entry);
      if (missing.contains(entry) || files.containsKey(entry)) {
        throw RestoreException('La lista de faltantes es incoherente.');
      }
      missing.add(entry);
    }
    if ((decoded['complete'] as bool) != missing.isEmpty || !_setEquals(expected.keys.toSet(), files.keys.toSet())) {
      throw RestoreException('El paquete está incompleto o su manifiesto no coincide.');
    }
    for (final entry in files.entries) {
      final spec = expected[entry.key]!;
      if (entry.value.uncompressedSize != spec.$1) throw RestoreException('El tamaño de ${entry.key} no coincide.');
      final file = File(p.join(job.stage, p.posix.joinAll(entry.key.split('/'))));
      final hash = await _extractFile(entry.value, file);
      if (hash != spec.$2) throw RestoreException('El archivo ${entry.key} está dañado (SHA-256).');
    }
    await Directory(p.join(job.stage, 'fotos')).create(recursive: true);
    return _PackageInfo(files.keys.toSet(), missing, decoded['schemaVersion'] as int);
  } finally {
    await input.close();
  }
}

// Extraer a mano evita el extractor general de archive y los buffers inflados.
// También detecta un DEFLATE cuyo tamaño real exceda el declarado en el ZIP.
Future<String> _extractFile(ZipFileHeader header, File target) async {
  await target.parent.create(recursive: true);
  final output = await target.open(mode: FileMode.write);
  final digestSink = _DigestSink();
  final hash = sha256.startChunkedConversion(digestSink);
  var bytes = 0;
  var crc = 0;
  final raw = header.file!.rawContent!;
  Stream<List<int>> chunks() async* {
    while (!raw.isEOS) {
      yield raw.readBytes(min(64 * 1024, raw.length)).toUint8List();
    }
  }

  final stream = header.compressionMethod == 8 ? ZLibDecoder(raw: true).bind(chunks()) : chunks();
  try {
    await for (final chunk in stream) {
      bytes += chunk.length;
      if (bytes > header.uncompressedSize! || bytes > BackupArchive.maxFileBytes) {
        throw RestoreException('Un archivo descomprimido excede el tamaño declarado.');
      }
      hash.add(chunk);
      crc = getCrc32(chunk, crc);
      await output.writeFrom(chunk);
    }
    hash.close();
    if (bytes != header.uncompressedSize || crc != header.crc32) {
      throw RestoreException('El archivo ${header.filename} está truncado o dañado (CRC/tamaño).');
    }
    return digestSink.value.toString();
  } finally {
    await output.close();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

bool _setEquals<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
