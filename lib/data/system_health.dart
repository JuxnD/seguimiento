import 'package:flutter/services.dart';

/// Ajustes del sistema que pueden callar los recordatorios aunque el permiso
/// de notificaciones esté dado. Los lee `MainActivity.kt`.
class SystemHealth {
  const SystemHealth();

  static const _channel = MethodChannel('seguimiento/sistema');

  /// true si la app está bajo optimización de batería. null si no se pudo
  /// saber (fuera de Android o en pruebas).
  Future<bool?> batteryOptimized() => _ask('batteryOptimized');

  /// true si "Pausar la actividad de la app si no se usa" está activo. null
  /// si el ajuste no existe (Android < 11) o no se pudo saber.
  Future<bool?> pausedIfUnused() => _ask('pausedIfUnused');

  Future<bool> openBatterySettings() async => await _ask('openBatterySettings') ?? false;
  Future<bool> openUnusedAppSettings() async => await _ask('openUnusedAppSettings') ?? false;

  Future<bool?> _ask(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
