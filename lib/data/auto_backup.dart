import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/dates.dart';
import 'database_host.dart';
import 'local_flags.dart';

/// Un respaldo automático ya guardado.
class AutoBackupFile {
  AutoBackupFile(this.file, this.date, this.bytes);

  final File file;
  final DateTime date;
  final int bytes;
}

/// Respaldo automático: una copia de la base cada [everyDays] días, guardada
/// dentro de la app y rotada para quedarse con las [keep] más recientes.
///
/// Protege de lo que más pasa: un borrado o una restauración equivocada, una
/// base dañada. No protege de perder el teléfono: para eso sigue el exportar
/// a mano (o la copia de Android, si está activa; ver docs/actualizaciones.md).
class AutoBackup {
  AutoBackup({required this.host, required this.flags, required this.dir, this.everyDays = 7, this.keep = 4});

  static Future<AutoBackup> open(DatabaseHost host, LocalFlags flags) async {
    final docs = await getApplicationDocumentsDirectory();
    return AutoBackup(host: host, flags: flags, dir: Directory(p.join(docs.path, folder)));
  }

  static const folder = 'respaldos';
  static final _name = RegExp(r'^respaldo-(\d{4}-\d{2}-\d{2})\.sqlite$');

  final DatabaseHost host;
  final LocalFlags flags;
  final Directory dir;
  final int everyDays;
  final int keep;

  /// Hace el respaldo si ya toca. Devuelve el archivo creado o null. Nunca
  /// lanza: un respaldo fallido no puede impedir usar la app.
  Future<File?> runIfDue({DateTime? now}) async {
    try {
      final today = dateOnly(now ?? DateTime.now());
      final last = flags.getDate(FlagKeys.lastAutoBackup);
      if (last != null && daysBetween(last, today) < everyDays) return null;

      await dir.create(recursive: true);
      final file = await host.exportTo(p.join(dir.path, 'respaldo-${dayKey(today)}.sqlite'));
      await flags.set(FlagKeys.lastAutoBackup, today);
      await _prune();
      return file;
    } on Object {
      return null;
    }
  }

  /// Respaldos guardados, del más nuevo al más viejo.
  Future<List<AutoBackupFile>> list() async {
    if (!dir.existsSync()) return [];
    final out = <AutoBackupFile>[];
    for (final entity in dir.listSync().whereType<File>()) {
      final match = _name.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      out.add(AutoBackupFile(entity, parseDay(match.group(1)!), entity.lengthSync()));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  Future<void> _prune() async {
    final all = await list();
    for (final old in all.skip(keep)) {
      try {
        await old.file.delete();
      } on Object {
        // Tomado o ya borrado: se intenta la próxima vez.
      }
    }
  }
}
