import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminders.dart';

/// Canales de Android. El de descanso suena aunque la app esté en segundo
/// plano; los recordatorios son avisos normales.
const _reminderChannel = AndroidNotificationChannel(
  'recordatorios',
  'Recordatorios',
  description: 'Sesión, comidas, proteína y medición',
  importance: Importance.defaultImportance,
);

const _restChannel = AndroidNotificationChannel(
  'descanso',
  'Fin del descanso',
  description: 'Avisa cuando termina el descanso entre series o rondas',
  importance: Importance.max,
  enableVibration: true,
);

/// Lo que el planificador necesita del sistema de notificaciones. Existe para
/// poder probar la programación sin plataforma de por medio.
abstract interface class NotificationSink {
  Future<void> applySchedule(List<PlannedNotification> planned);
}

/// Envoltorio de `flutter_local_notifications`: inicializa, pide permiso y
/// programa. No decide qué avisar — eso es `domain/reminders.dart`.
class NotificationService implements NotificationSink {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// Id fijo para el aviso de fin de descanso: siempre hay uno solo.
  static const restNotificationId = 90001;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } on Object {
      // Si el sistema no da una zona reconocible, se queda en UTC: los avisos
      // seguirían saliendo, solo que hay que revisar la hora.
    }

    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_reminderChannel);
    await android?.createNotificationChannel(_restChannel);
    _ready = true;
  }

  /// Android 13+ exige permiso explícito. Devuelve false si el usuario dijo
  /// que no: la app sigue funcionando, solo sin avisos.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> hasPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  /// Reemplaza todos los recordatorios programados por los de la lista.
  /// Cancelar y volver a programar es más simple —y más fácil de razonar—
  /// que llevar un diff incremental.
  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async {
    await init();
    await cancelScheduled();
    for (final n in planned) {
      await _schedule(n);
    }
  }

  Future<void> cancelScheduled() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id != restNotificationId) await _plugin.cancel(p.id);
    }
  }

  Future<void> _schedule(PlannedNotification n) async {
    final when = tz.TZDateTime.from(n.when, tz.local);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      n.id,
      n.title,
      n.body,
      when,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannel.id,
          _reminderChannel.name,
          channelDescription: _reminderChannel.description,
          styleInformation: BigTextStyleInformation(n.body),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Aviso de fin de descanso: exacto, porque 30 s tarde no sirve de nada.
  Future<void> scheduleRestEnd({required Duration inSeconds, required String nextLabel}) async {
    await init();
    await cancelRestEnd();
    final when = tz.TZDateTime.now(tz.local).add(inSeconds);
    await _plugin.zonedSchedule(
      restNotificationId,
      'Se acabó el descanso',
      nextLabel,
      when,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _restChannel.id,
          _restChannel.name,
          channelDescription: _restChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: false,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelRestEnd() => _plugin.cancel(restNotificationId);

  Future<List<PendingNotificationRequest>> pending() => _plugin.pendingNotificationRequests();
}
