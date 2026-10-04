import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Preferencias del dispositivo que **no** son datos del usuario: si ya se
/// pidió un permiso, cuándo fue el último respaldo automático, cuándo se
/// consultó GitHub. Viven fuera de la base a propósito: restaurar un respaldo
/// no debe hacer que la app vuelva a pedir permisos ni borre respaldos.
class LocalFlags {
  LocalFlags(this.file);

  static Future<LocalFlags> open() async {
    final dir = await getApplicationSupportDirectory();
    return LocalFlags(File(p.join(dir.path, 'flags.json')));
  }

  final File file;

  Map<String, Object?> _read() {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, Object?> ? decoded : {};
    } on Object {
      // Sin archivo o archivo dañado: se empieza de cero, nunca se falla.
      return {};
    }
  }

  T? get<T>(String key) {
    final value = _read()[key];
    return value is T ? value : null;
  }

  DateTime? getDate(String key) {
    final raw = get<String>(key);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> set(String key, Object? value) async {
    final data = _read()..[key] = value is DateTime ? value.toIso8601String() : value;
    await file.parent.create(recursive: true);
    // Escribe aparte y renombra: un cierre a mitad no deja el archivo cortado.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}

/// Claves conocidas, en un solo sitio.
abstract final class FlagKeys {
  static const notificationsAsked = 'notificationsAsked';
  static const lastUpdateCheck = 'lastUpdateCheck';
  static const lastAutoBackup = 'lastAutoBackup';

  /// El usuario conectó Health Connect en Ajustes: los pasos se sincronizan.
  static const healthConnectEnabled = 'healthConnectEnabled';
  static const lastStepsSync = 'lastStepsSync';

  /// El usuario decidió no aplicar las correcciones del 29 sep: Hoy deja de
  /// ofrecerlas (siguen en Ajustes).
  static const corrections29SepDismissed = 'corrections29SepDismissed';

  /// Día (`YYYY-MM-DD`) en que se respondió "está bien así" a "¿Te faltó
  /// registrar algo de ayer?": no se vuelve a preguntar por ese día.
  static const yesterdayCheckDismissed = 'yesterdayCheckDismissed';
}
