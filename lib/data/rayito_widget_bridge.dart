import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/mascot.dart';
import '../ui/mascot.dart';

/// Lo que muestra el widget de inicio de Rayito (plan 049). Sólo lo que Hoy ya
/// calculó; nada de salud ni de comidas.
@immutable
class RayitoWidgetData {
  const RayitoWidgetData({
    required this.phase,
    required this.mood,
    required this.streak,
    required this.today,
    this.date,
  });

  final MascotPhase phase;
  final MascotMood mood;
  final int streak;

  /// Lo que toca hoy, ya en palabras ("Tren superior", "Descanso").
  final String today;

  /// Fecha local de la lectura; el widget nunca presenta ayer como hoy.
  final DateTime? date;

  String get title => 'Rayito · ${phase.label}';
  String get streakLine => streak == 0
      ? 'Sin racha todavía'
      : '$streak ${streak == 1 ? 'día' : 'días'} de racha';
  String get todayLine => 'Hoy: $today';

  @override
  bool operator ==(Object other) =>
      other is RayitoWidgetData &&
      other.phase == phase &&
      other.mood == mood &&
      other.streak == streak &&
      other.today == today &&
      other.date == date;

  @override
  int get hashCode => Object.hash(phase, mood, streak, today, date);
}

/// Envía los datos al widget nativo (canal "seguimiento/widget"). En otras
/// plataformas, o sin el canal (pruebas), no hace nada.
class RayitoWidgetBridge {
  static final shared = RayitoWidgetBridge();
  RayitoWidgetBridge({MethodChannel? channel, bool? android})
      : _channel = channel ?? const MethodChannel('seguimiento/widget'),
        _android = android ?? (!kIsWeb && Platform.isAndroid);

  final MethodChannel _channel;
  final bool _android;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _enabled = true;

  void enable() {
    _enabled = true;
  }

  Future<bool> clear() {
    _enabled = false;
    _generation++;
    final result = _tail.then((_) async {
      if (!_android) return true;
      try {
        await _channel.invokeMethod<int>('clear');
        return true;
      } on MissingPluginException {
        return false;
      } on PlatformException {
        return false;
      }
    });
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> update(RayitoWidgetData data) {
    if (!_enabled) return Future<bool>.value(false);
    final generation = _generation;
    final result = _tail.then((_) => generation == _generation && _enabled
        ? _update(data, generation)
        : Future<bool>.value(false));
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> _update(RayitoWidgetData data, int generation) async {
    if (!_android) return true;
    try {
      final png = await renderRayitoPng(data.phase, data.mood);
      if (!_enabled || generation != _generation) return false;
      await _channel.invokeMethod<int>('update', {
        'title': data.title,
        'streak': data.streakLine,
        'today': data.todayLine,
        'date': _dayKey(data.date ?? DateTime.now()),
        'semanticLabel':
            '${data.title}, estado ${data.mood.name}, ${data.streakLine}, ${data.todayLine}',
        'png': png,
      });
      return true;
    } on MissingPluginException {
      // Sin la parte nativa (pruebas o plataforma sin widget).
    } on PlatformException {
      // Un widget que no se refresca no debe romper Hoy.
    }
    return false;
  }
}

String _dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Rayito como PNG cuadrado, con el mismo painter de la app.
Future<Uint8List> renderRayitoPng(MascotPhase phase, MascotMood mood,
    {int size = 192}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  RayitoPainter(phase: phase, mood: mood)
      .paint(canvas, Size.square(size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
