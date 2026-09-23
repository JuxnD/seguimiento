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
    _pending = session;
    return _enqueue();
  }

  /// Borra la sesión en curso (se guardó o se descartó).
  Future<void> clear() {
    _pending = null;
    return _enqueue();
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
