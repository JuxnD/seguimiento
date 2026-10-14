import 'dart:io' show Platform;
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
        label: semanticLabel ?? 'Rayito, nivel ${phase.level} de ${MascotPhase.levels}',
        image: true,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: RayitoPainter(phase: phase, mood: mood)),
        ),
      );
}

/// Rayito se mueve en la app y queda quieto en `flutter test`, donde un ciclo
/// infinito no dejaría asentar las pantallas. Las pruebas de la animación lo
/// encienden a mano.
bool rayitoAnimationsEnabled = () {
  try {
    return !Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return true;
  }
}();

/// Rayito vivo (plan 052): flota, respira, parpadea, el halo late y las
/// estrellas titilan; dormido, sube sus Z. Cada vez que [hop] cambia da un
/// salto con estirón. Con «quitar animaciones» del sistema queda quieto.
class RayitoAlive extends StatefulWidget {
  const RayitoAlive({
    super.key,
    required this.phase,
    required this.mood,
    this.size = 72,
    this.semanticLabel,
    this.hop = 0,
  });

  final MascotPhase phase;
  final MascotMood mood;
  final double size;
  final String? semanticLabel;
  final int hop;

  @override
  State<RayitoAlive> createState() => _RayitoAliveState();
}

class _RayitoAliveState extends State<RayitoAlive>
    with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));
  late final AnimationController _hop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  bool _still = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = !rayitoAnimationsEnabled ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (_still) {
      _loop.stop();
      _loop.value = 0;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void didUpdateWidget(RayitoAlive old) {
    super.didUpdateWidget(old);
    if (old.hop != widget.hop && !_still) _hop.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    _hop.dispose();
    super.dispose();
  }

  /// Parpadeo breve dos veces por vuelta, el segundo doble.
  static double _blink(double t) {
    double pulse(double at) {
      final d = (t - at).abs();
      return d > 0.018 ? 0 : 1 - d / 0.018;
    }

    return math.max(pulse(0.31), math.max(pulse(0.81), pulse(0.86)));
  }

  @override
  Widget build(BuildContext context) {
    final asleep =
        widget.phase == MascotPhase.dormido && widget.mood != MascotMood.contento;
    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Rayito',
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_loop, _hop]),
          builder: (context, _) {
            final t = _still ? 0.0 : _loop.value;
            final wave = math.sin(2 * math.pi * t * 2);
            final float = asleep ? 0.012 * wave : 0.035 * wave;
            final breathe = 1 + (asleep ? 0.035 : 0.02) * math.cos(2 * math.pi * t * 2);
            final h = _hop.value;
            final jump = -0.22 * math.sin(math.pi * h);
            final squash = 0.09 * math.sin(2 * math.pi * h);
            return Transform.translate(
              offset: Offset(0, widget.size * (float + jump)),
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(
                    breathe * (1 + squash), breathe * (1 - squash), 1),
                child: CustomPaint(
                  size: Size.square(widget.size),
                  painter: RayitoPainter(
                    phase: widget.phase,
                    mood: widget.mood,
                    blink: _still || asleep ? 0 : _blink(t),
                    glow: _still ? 1 : 0.75 + 0.25 * math.sin(2 * math.pi * t * 3),
                    twinkle: _still ? 0 : t,
                    look: _still || widget.mood != MascotMood.atento
                        ? 0
                        : 0.6 * math.sin(2 * math.pi * t),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class RayitoPainter extends CustomPainter {
  RayitoPainter({
    required this.phase,
    required this.mood,
    this.blink = 0,
    this.glow = 1,
    this.twinkle = 0,
    this.look = 0,
  });

  final MascotPhase phase;
  final MascotMood mood;

  /// Animación (plan 052): 0 ojos abiertos, 1 cerrados en un parpadeo.
  final double blink;

  /// Intensidad del halo, 0–1; late suave cuando Rayito está vivo.
  final double glow;

  /// Vuelta de 0 a 1 que hace titilar las estrellas y subir las Z al dormir.
  final double twinkle;

  /// Hacia dónde mira, −1 izquierda a 1 derecha.
  final double look;

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
                        const Color(0xFFE6FF9C).withOpacity(0.9 * glow),
                        mascotLime.withOpacity(0.35 * glow),
                        mascotLime.withOpacity(0)
                      ]
                    : [
                        mascotLime.withOpacity(0.55 * glow),
                        mascotLime.withOpacity(0.18 * glow),
                        mascotLime.withOpacity(0)
                      ],
                const [0, 0.58, 1]));
    }
    if (phase.index >= MascotPhase.tormenta.index) {
      final color = _prime ? const Color(0xFFE6FF9C) : mascotIvory;
      for (final (i, (a, r)) in const [
        (-2.4, 7.0),
        (-1.0, 5.0),
        (0.4, 6.0),
        (1.6, 4.5),
        (2.7, 5.5)
      ].indexed) {
        _star(canvas, Offset(math.cos(a) * 64, math.sin(a) * 60),
            r * _twinkleScale(i), color);
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
      _star(canvas, const Offset(44, -52), 6 * _twinkleScale(0),
          const Color(0xFFE6FF9C));
      _star(canvas, const Offset(-44, 38), 4.5 * _twinkleScale(3),
          const Color(0xFFE6FF9C));
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
    if (_asleep && twinkle > 0) _sleepyZ(canvas);
    canvas.restore();
  }

  /// Cada estrella titila con su propio desfase; quieta si no hay animación.
  double _twinkleScale(int i) => twinkle == 0
      ? 1
      : 0.7 + 0.3 * (0.5 + 0.5 * math.sin(2 * math.pi * (twinkle + i / 5)));

  /// Dormido: dos Z suben y se desvanecen.
  void _sleepyZ(Canvas canvas) {
    for (final k in const [0.0, 0.5]) {
      final t = (twinkle + k) % 1;
      final size = 9 + 7 * t;
      final at = Offset(30 + 18 * t, -58 - 34 * t);
      final paint = Paint()
        ..color = mascotIvory.withOpacity(0.9 * (1 - t))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(
          Path()
            ..moveTo(at.dx, at.dy)
            ..lineTo(at.dx + size, at.dy)
            ..lineTo(at.dx, at.dy + size)
            ..lineTo(at.dx + size, at.dy + size),
          paint);
    }
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
      if (blink > 0.85) {
        // Parpadeo: el ojo se vuelve una rayita un instante.
        canvas.drawLine(eye - const Offset(6, 0), eye + const Offset(6, 0), line);
        continue;
      }
      final open = 1 - blink;
      final pupil = eye + Offset(1 + 2.2 * look, 1.5 * open);
      canvas
        ..drawOval(Rect.fromCenter(center: eye, width: 14, height: 18 * open),
            Paint()..color = Colors.white)
        ..drawOval(
            Rect.fromCenter(center: pupil, width: 9.6, height: 12.4 * open),
            Paint()..color = mascotCarbon)
        ..drawCircle(pupil + const Offset(1.6, -3.1) * open, 2 * open,
            Paint()..color = Colors.white)
        ..drawCircle(pupil + const Offset(-1.6, 2.5) * open, 1 * open,
            Paint()..color = Colors.white);
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
      oldDelegate.phase != phase ||
      oldDelegate.mood != mood ||
      oldDelegate.blink != blink ||
      oldDelegate.glow != glow ||
      oldDelegate.twinkle != twinkle ||
      oldDelegate.look != look;
}
