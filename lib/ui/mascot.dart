import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/mascot.dart';

/// Colores de la marca 036 (assets/icon/LEEME.md): carbón, lima y marfil.
const mascotLime = Color(0xFFC1FF45);
const mascotCarbon = Color(0xFF171A1B);
const mascotIvory = Color(0xFFF8F7F0);

/// Rayito dibujado en vector (plan 049, acabado v5 elegido por el owner): el
/// rayo de la marca, blandito, con volumen, cara y brillo. Escala desde un
/// ícono de 24 px hasta la tarjeta de Hoy. Sin imágenes ni dependencias.
class Rayito extends StatelessWidget {
  const Rayito({
    super.key,
    required this.phase,
    required this.mood,
    this.size = 72,
    this.semanticLabel,
  });

  final MascotPhase phase;
  final MascotMood mood;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: semanticLabel ?? 'Rayito, ${phase.label}',
        image: true,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: RayitoPainter(phase: phase, mood: mood)),
        ),
      );
}

class RayitoPainter extends CustomPainter {
  RayitoPainter({required this.phase, required this.mood});

  final MascotPhase phase;
  final MascotMood mood;

  bool get _prime => phase.index >= MascotPhase.prime.index;
  bool get _asleep =>
      phase == MascotPhase.dormido && mood != MascotMood.contento;

  // Silueta del rayo en un cuadro de diseño de 160 × 160 centrado en (0, 0).
  static const _bolt = [
    Offset(-6, -56),
    Offset(28, -56),
    Offset(11, -12),
    Offset(34, -12),
    Offset(-14, 56),
    Offset(-2, 8),
    Offset(-28, 8),
  ];
  static const _bodyRect = Rect.fromLTRB(-42, -66, 44, 66);

  List<Color> get _bodyColors => _asleep
      ? const [Color(0xFF8A9091), Color(0xFF454A4B)]
      : _prime
          ? const [Color(0xFF3A4042), mascotCarbon, Color(0xFF0A0B0B)]
          : const [Color(0xFFEDFFB0), mascotLime, Color(0xFF7FC21A)];

  Color get _rim => _asleep
      ? const Color(0xFF3B3F40)
      : _prime
          ? mascotLime
          : const Color(0xFF6AA80F);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 160;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale);

    // Sombra en el piso.
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(2, 72), width: 80, height: 16),
        Paint()
          ..shader = ui.Gradient.radial(const Offset(2, 72), 40,
              [Colors.black.withOpacity(0.55), Colors.black.withOpacity(0)]));

    if (phase.index >= MascotPhase.energizado.index) {
      final r = phase.index >= MascotPhase.super_.index ? 70.0 : 62.0;
      canvas.drawCircle(
          Offset.zero,
          r,
          Paint()
            ..shader = ui.Gradient.radial(
                Offset.zero,
                r,
                _prime
                    ? [
                        const Color(0xE6E6FF9C),
                        mascotLime.withOpacity(0.35),
                        mascotLime.withOpacity(0)
                      ]
                    : [
                        mascotLime.withOpacity(0.55),
                        mascotLime.withOpacity(0.18),
                        mascotLime.withOpacity(0)
                      ],
                const [0, 0.58, 1]));
    }
    if (phase.index >= MascotPhase.tormenta.index) {
      final color = _prime ? const Color(0xFFE6FF9C) : mascotIvory;
      for (final (a, r) in const [
        (-2.4, 7.0),
        (-1.0, 5.0),
        (0.4, 6.0),
        (1.6, 4.5),
        (2.7, 5.5)
      ]) {
        _star(canvas, Offset(math.cos(a) * 64, math.sin(a) * 60), r, color);
      }
    }
    if (phase == MascotPhase.leyenda) {
      for (var k = 0; k < 6; k++) {
        final a = -math.pi / 2 + k * 2 * math.pi / 6;
        final at = Offset(math.cos(a) * 66, math.sin(a) * 62);
        final mini = Path()
          ..addPolygon([for (final o in _bolt) at + o * 0.12], true);
        canvas
          ..drawPath(mini, Paint()..color = mascotLime)
          ..drawPath(
              mini,
              Paint()
                ..color = const Color(0xFF7FC21A)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1);
      }
    }
    if (phase.index >= MascotPhase.cargado.index && !_prime) {
      _star(canvas, const Offset(44, -52), 6, const Color(0xFFE6FF9C));
      _star(canvas, const Offset(-44, 38), 4.5, const Color(0xFFE6FF9C));
    }

    // Cuerpo con volumen: borde, relleno degradado y brillo lateral.
    final body = Path()..addPolygon(_bolt, true);
    final gradient = ui.Gradient.linear(
        _bodyRect.topLeft,
        _bodyRect.bottomRight,
        _bodyColors,
        _bodyColors.length == 3 ? const [0, 0.45, 1] : null);
    canvas
      ..drawPath(
          body,
          Paint()
            ..color = _rim
            ..style = PaintingStyle.stroke
            ..strokeWidth = 20
            ..strokeJoin = StrokeJoin.round)
      ..drawPath(
          body,
          Paint()
            ..shader = gradient
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..strokeJoin = StrokeJoin.round)
      ..drawPath(body, Paint()..shader = gradient)
      ..drawPath(
          Path()
            ..addPolygon(const [
              Offset(-2, -54),
              Offset(6, -54),
              Offset(-10, -6),
              Offset(-20, -6)
            ], true),
          Paint()
            ..color = Colors.white.withOpacity(0.32)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));

    _face(canvas);
    canvas.restore();
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final k = r * 0.28;
    canvas.drawPath(
        Path()
          ..addPolygon([
            c + Offset(0, -r),
            c + Offset(k, -k),
            c + Offset(r, 0),
            c + Offset(k, k),
            c + Offset(0, r),
            c + Offset(-k, k),
            c + Offset(-r, 0),
            c + Offset(-k, -k),
          ], true),
        Paint()..color = color.withOpacity(0.95));
  }

  void _face(Canvas canvas) {
    const center = Offset(6, -30);
    final ink = (_prime || _asleep) ? mascotIvory : mascotCarbon;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    final closed = _asleep || mood == MascotMood.sereno;
    for (final dx in const [-11.0, 11.0]) {
      final eye = center + Offset(dx, 0);
      if (closed) {
        // Dormido: rayitas; sereno: arcos tranquilos.
        final depth = mood == MascotMood.sereno ? 5.0 : 3.0;
        canvas.drawPath(
            Path()
              ..moveTo(eye.dx - 6, eye.dy)
              ..quadraticBezierTo(eye.dx, eye.dy + depth, eye.dx + 6, eye.dy),
            line);
        continue;
      }
      canvas
        ..drawOval(Rect.fromCenter(center: eye, width: 14, height: 18),
            Paint()..color = Colors.white)
        ..drawOval(
            Rect.fromCenter(
                center: eye + const Offset(1, 1.5), width: 9.6, height: 12.4),
            Paint()..color = mascotCarbon)
        ..drawCircle(
            eye + const Offset(2.6, -1.6), 2, Paint()..color = Colors.white)
        ..drawCircle(
            eye + const Offset(-0.6, 4), 1, Paint()..color = Colors.white);
    }
    if (!_asleep) {
      final cheek = Paint()..color = const Color(0xFFFF8FA3).withOpacity(0.55);
      canvas
        ..drawOval(
            Rect.fromCenter(
                center: center + const Offset(-17, 9), width: 10, height: 6),
            cheek)
        ..drawOval(
            Rect.fromCenter(
                center: center + const Offset(18, 9), width: 10, height: 6),
            cheek);
    }
    if (phase.index >= MascotPhase.energizado.index && !closed) {
      // Cejas arriba: con ganas, no enojado.
      for (final dx in const [-11.0, 11.0]) {
        canvas.drawPath(
            Path()
              ..moveTo(center.dx + dx - 5, center.dy - 13)
              ..quadraticBezierTo(center.dx + dx, center.dy - 17,
                  center.dx + dx + 5, center.dy - 13),
            line..strokeWidth = 3);
      }
    }
    switch (mood) {
      case MascotMood.contento:
        canvas
          ..drawPath(
              Path()
                ..moveTo(center.dx - 7, center.dy + 12)
                ..quadraticBezierTo(
                    center.dx, center.dy + 22, center.dx + 7, center.dy + 12)
                ..close(),
              Paint()..color = _prime ? mascotIvory : mascotCarbon)
          ..drawPath(
              Path()
                ..moveTo(center.dx - 3, center.dy + 17)
                ..quadraticBezierTo(
                    center.dx, center.dy + 19, center.dx + 3, center.dy + 17)
                ..close(),
              Paint()..color = const Color(0xFFFF6B81));
      case MascotMood.sereno:
        canvas.drawPath(
            Path()
              ..moveTo(center.dx - 4, center.dy + 14)
              ..quadraticBezierTo(
                  center.dx, center.dy + 17, center.dx + 4, center.dy + 14),
            line..strokeWidth = 3);
      case MascotMood.atento:
        canvas.drawOval(
            Rect.fromCenter(
                center: center + const Offset(0, 15), width: 6, height: 7.2),
            Paint()..color = ink);
      case MascotMood.dormido:
        break;
    }
  }

  @override
  bool shouldRepaint(RayitoPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.mood != mood;
}
