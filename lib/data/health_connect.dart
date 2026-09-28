import 'package:flutter/services.dart';

import '../domain/dates.dart';
import '../domain/steps.dart';
import 'local_flags.dart';
import 'repositories/steps_repository.dart';

enum HealthConnectStatus { disponible, actualizar, noInstalado, noSoportado, desconocido }

/// Pasos desde Health Connect. La app del reloj (Innova S-Watch) los escribe
/// ahí; esta app solo los lee. Lo implementa `HealthConnectBridge.kt`.
class HealthConnect {
  const HealthConnect();

  static const _channel = MethodChannel('seguimiento/salud');

  Future<HealthConnectStatus> status() async {
    final raw = await _call<String>('status');
    return switch (raw) {
      'disponible' => HealthConnectStatus.disponible,
      'actualizar' => HealthConnectStatus.actualizar,
      'no_instalado' => HealthConnectStatus.noInstalado,
      'no_soportado' => HealthConnectStatus.noSoportado,
      _ => HealthConnectStatus.desconocido,
    };
  }

  Future<bool> hasPermission() async => await _call<bool>('hasPermission') ?? false;

  /// Abre el diálogo de Health Connect. true si el usuario dio el permiso.
  Future<bool> requestPermission() async => await _call<bool>('requestPermission') ?? false;

  /// Pasos por día (`YYYY-MM-DD`), días sin datos incluidos con 0.
  Future<Map<String, int>> stepsByDay(DateTime from, DateTime to) async {
    final raw = await _channel.invokeMapMethod<String, int>('stepsByDay', {'from': dayKey(from), 'to': dayKey(to)});
    return raw ?? const {};
  }

  /// Apps que escribieron pasos en el rango (por nombre visible).
  Future<List<String>> sources(DateTime from, DateTime to) async =>
      await _channel.invokeListMethod<String>('sources', {'from': dayKey(from), 'to': dayKey(to)}) ?? const [];

  Future<bool> openSettings() async => await _call<bool>('openSettings') ?? false;
  Future<bool> installProvider() async => await _call<bool>('installProvider') ?? false;

  Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      // Fuera de Android o en pruebas.
      return null;
    }
  }
}

enum StepsSyncOutcome { apagado, noDisponible, sinPermiso, hecho, error }

class StepsSyncResult {
  const StepsSyncResult(this.outcome, {this.updatedDays = 0, this.message});

  final StepsSyncOutcome outcome;
  final int updatedDays;
  final String? message;
}

/// Trae los pasos de los últimos días a `daily_steps`. Solo corre si el
/// usuario conectó Health Connect en Ajustes. Nunca lanza.
class StepsSync {
  StepsSync({required this.health, required this.steps, required this.flags});

  final HealthConnect health;
  final StepsRepository steps;
  final LocalFlags flags;

  static const source = 'health_connect';

  bool get enabled => flags.get<bool>(FlagKeys.healthConnectEnabled) == true;
  DateTime? get lastSync => flags.getDate(FlagKeys.lastStepsSync);

  Future<StepsSyncResult> run({int days = 14, DateTime? now}) async {
    if (!enabled) return const StepsSyncResult(StepsSyncOutcome.apagado);
    try {
      if (await health.status() != HealthConnectStatus.disponible) {
        return const StepsSyncResult(StepsSyncOutcome.noDisponible);
      }
      if (!await health.hasPermission()) return const StepsSyncResult(StepsSyncOutcome.sinPermiso);
      final today = dateOnly(now ?? DateTime.now());
      final synced = await health.stepsByDay(addDays(today, -(days - 1)), today);
      var updated = 0;
      for (final e in synced.entries) {
        final day = parseDay(e.key);
        final row = await steps.row(day);
        final value = mergeSyncedSteps(current: row?.steps, currentSource: row?.source, synced: e.value);
        if (value == null) continue;
        await steps.setSteps(day, value, source: source);
        updated++;
      }
      await flags.set(FlagKeys.lastStepsSync, now ?? DateTime.now());
      return StepsSyncResult(StepsSyncOutcome.hecho, updatedDays: updated);
    } on PlatformException catch (e) {
      if (e.code == 'sin_permiso') return const StepsSyncResult(StepsSyncOutcome.sinPermiso);
      return StepsSyncResult(StepsSyncOutcome.error, message: e.message);
    } on Object catch (e) {
      return StepsSyncResult(StepsSyncOutcome.error, message: '$e');
    }
  }
}
