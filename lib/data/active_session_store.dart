import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/active_session.dart';

/// Guarda la sesión en curso en un archivo, fuera de la base: se escribe en
/// cada paso del cronómetro y no debe competir con el historial ni viajar en
/// los respaldos.
class ActiveSessionStore {
  ActiveSessionStore(this.file);

  static Future<ActiveSessionStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return ActiveSessionStore(File(p.join(dir.path, 'sesion-en-curso.json')));
  }

  final File file;

  /// null si no hay sesión o el archivo no se entiende (se descarta).
  Future<ActiveSession?> load() async {
    try {
      if (!file.existsSync()) return null;
      return ActiveSession.fromJson(jsonDecode(await file.readAsString()));
    } on Object {
      return null;
    }
  }

  ActiveSession? _pending;
  Future<void> _queue = Future.value();

  /// Guarda la foto. Las escrituras van en fila y cada una escribe la foto
  /// **más reciente**: si llegan muchas seguidas, nunca queda una vieja encima
  /// de una nueva. Nunca lanza: perder una foto intermedia es mejor que tumbar
  /// el cronómetro.
  Future<void> save(ActiveSession session) {
    _pending = _sanitized(session);
    return _enqueue();
  }

  /// Identidad (fecha + inicio) de la sesión que una restauración desvinculó:
  /// un guardado tardío de esa misma sesión no puede reponer el id viejo.
  (String, DateTime)? _unlinked;

  ActiveSession _sanitized(ActiveSession session) {
    final u = _unlinked;
    if (u != null && session is GuidedSnapshot && session.planDayId >= 0) {
      if (session.date == u.$1 && session.startedAt == u.$2) return session.unlinkedAfterRestore();
    }
    return session;
  }

  /// Borra la sesión en curso (se guardó o se descartó).
  Future<void> clear() {
    _unlinked = null;
    _pending = null;
    return _enqueue();
  }

  /// Operación crítica: corre en la misma fila que los guardados y, a
  /// diferencia de ellos, propaga su fallo.
  Future<T> _exclusive<T>(Future<T> Function() op) {
    final done = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await op());
      } on Object catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Escritura que NO absorbe errores (tmp + rename). Lanza si no quedó escrita.
  Future<void> _writeStrict(List<int> bytes) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    if (!file.existsSync() || !_same(await file.readAsBytes(), bytes)) {
      throw FileSystemException('La sesión en curso no quedó escrita', file.path);
    }
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Protege el cronómetro en curso alrededor de una restauración de la base.
  ///
  /// 1. Espera los guardados pendientes y toma lo más reciente en disco.
  /// 2. Persiste la desvinculación con escritura estricta ANTES de llamar a
  ///    [restore]; si no se puede, lanza [SessionProtectionException] y [restore]
  ///    no corre (la base no cambia).
  /// 3. Si [restore] falla, devuelve el archivo original byte a byte; si esa
  ///    recuperación también falla, lanza [SessionRecoveryException].
  /// Tras un éxito, los guardados tardíos de esa sesión no reponen el id viejo.
  Future<T> protectedRestore<T>(Future<T> Function() restore) async {
    List<int>? original;
    try {
      original = await _exclusive<List<int>?>(() async {
        final current = await load();
        if (current is! GuidedSnapshot || current.planDayId < 0) return null;
        final bytes = await file.readAsBytes();
        _unlinked = (current.date, current.startedAt);
        await _writeStrict(utf8.encode(jsonEncode(current.unlinkedAfterRestore().toJson())));
        return bytes;
      });
    } on Object catch (e) {
      _unlinked = null;
      throw SessionProtectionException('$e');
    }
    try {
      return await restore();
    } on Object {
      _unlinked = null;
      if (original != null) {
        try {
          await _exclusive(() => _writeStrict(original!));
        } on Object catch (e) {
          throw SessionRecoveryException('$e');
        }
      }
      rethrow;
    }
  }

  Future<void> _enqueue() => _queue = _queue.then((_) => _flush());

  Future<void> _flush() async {
    try {
      final session = _pending;
      if (session == null) {
        if (file.existsSync()) await file.delete();
        return;
      }
      await file.parent.create(recursive: true);
      // Escribe aparte y renombra: un cierre a mitad no deja el archivo cortado.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(session.toJson()), flush: true);
      await tmp.rename(file.path);
    } on Object {
      // Sin espacio o sin permiso: el cronómetro sigue igual.
    }
  }
}

/// No se pudo dejar el cronómetro en curso protegido: la restauración no corrió.
class SessionProtectionException implements Exception {
  SessionProtectionException(this.cause);
  final String cause;
  @override
  String toString() => 'No se pudo proteger el cronómetro en curso ($cause). La base no cambió.';
}

/// La restauración falló y el cronómetro en curso tampoco se pudo devolver a su
/// estado anterior.
class SessionRecoveryException implements Exception {
  SessionRecoveryException(this.cause);
  final String cause;
  @override
  String toString() => 'La restauración falló y no se pudo devolver el cronómetro en curso a su estado anterior ($cause).';
}
