import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'exercise_art.dart';
import 'theme.dart';

/// Catálogo de figuras, leído una vez del asset.
final exerciseArtProvider = FutureProvider<ExerciseArtCatalog>(
  (ref) async => ExerciseArtCatalog.fromJsonString(await rootBundle.loadString(ExerciseArtCatalog.asset)),
);

/// Colores por rol, tomados de la paleta del tema.
const _roleColors = <ArtRole, Color>{
  ArtRole.ink: Color(0xFFFFF6EC),
  ArtRole.ghost: Color(0xFFFFF6EC),
  ArtRole.muscle: Color(0xFFF08A34),
  ArtRole.prop: Color(0xFF7A6150),
  ArtRole.propFill: Color(0xFF241A13),
  ArtRole.floor: Color(0xFF4A3526),
  ArtRole.arrow: AppColors.steps,
  ArtRole.guide: Color(0xFFFFC271),
  ArtRole.label: Color(0xFFC9B8A8),
  ArtRole.wrong: Color(0xFFFF6B5B),
  ArtRole.bg: Color(0xFF0B0806),
};

/// La silueta de la posición anterior va muy tenue: se intuye, no compite.
const _roleOpacity = <ArtRole, double>{ArtRole.ghost: 0.16};

Color _color(ArtRole role, double opacity) =>
    _roleColors[role]!.withOpacity((opacity * (_roleOpacity[role] ?? 1)).clamp(0, 1));

/// Pinta un cuadro de una figura dentro de su recuadro común, sin deformar.
class ExerciseFramePainter extends CustomPainter {
  ExerciseFramePainter(this.art, this.frame);

  final ExerciseArt art;
  final ArtFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / art.boxWidth, size.height / art.boxHeight);
    final dx = (size.width - art.boxWidth * scale) / 2 - art.box.left * scale;
    final dy = (size.height - art.boxHeight * scale) / 2 - art.box.top * scale;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    for (final item in frame.items) {
      _draw(canvas, item);
    }
    canvas.restore();
  }

  void _draw(Canvas canvas, ArtItem item) {
    switch (item) {
      case ArtLine(:final a, :final b, :final role, :final width, :final opacity, :final dashed):
        final paint = Paint()
          ..color = _color(role, opacity)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round;
        if (!dashed) {
          canvas.drawLine(a, b, paint);
          return;
        }
        final total = (b - a).distance;
        if (total == 0) return;
        final dir = (b - a) / total;
        const dash = 1.6, gap = 1.3;
        for (var t = 0.0; t < total; t += dash + gap) {
          canvas.drawLine(a + dir * t, a + dir * math.min(t + dash, total), paint..strokeCap = StrokeCap.butt);
        }
      case ArtCircle(:final center, :final radius, :final role, :final opacity, :final filled, :final stroke):
        if (filled) canvas.drawCircle(center, radius, Paint()..color = _color(role, opacity));
        if (stroke != null) {
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = item.strokeWidth
              ..color = _color(stroke, item.strokeOpacity),
          );
        }
      case ArtEllipse(:final center, :final rx, :final ry, :final rotationDeg, :final role, :final opacity, :final stroke):
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(rotationDeg * math.pi / 180);
        final rect = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
        canvas.drawOval(rect, Paint()..color = _color(role, opacity));
        if (stroke != null) {
          canvas.drawOval(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = item.strokeWidth
              ..color = _color(stroke, item.strokeOpacity),
          );
        }
        canvas.restore();
      case ArtRect(:final x, :final y, :final width, :final height, :final role, :final stroke, :final strokeWidth):
        final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, width, height), const Radius.circular(0.8));
        canvas.drawRRect(rect, Paint()..color = _color(role, 1));
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..color = _color(stroke, 1),
        );
      case ArtPolygon(:final points, :final role):
        if (points.isEmpty) return;
        final path = Path()..addPolygon(points, true);
        canvas.drawPath(path, Paint()..color = _color(role, 1));
      case ArtArc(:final center, :final radius, :final startDeg, :final sweepDeg, :final role, :final width):
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startDeg * math.pi / 180,
          sweepDeg * math.pi / 180,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = _color(role, 1),
        );
      case ArtText(:final at, :final text, :final size, :final role, :final anchor):
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: _color(role, 1), height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        final x = switch (anchor) {
          'middle' => at.dx - painter.width / 2,
          'end' => at.dx - painter.width,
          _ => at.dx,
        };
        painter.paint(canvas, Offset(x, at.dy - baseline));
    }
  }

  @override
  bool shouldRepaint(ExerciseFramePainter oldDelegate) => oldDelegate.art != art || oldDelegate.frame != frame;
}

/// Los cuadros de un ejercicio (dos por fila) con su pie y el músculo que
/// trabaja. Si el ejercicio no tiene figura, no ocupa espacio.
class ExerciseArtView extends ConsumerWidget {
  const ExerciseArtView({super.key, required this.exercise, this.frameHeight = 140});

  final String exercise;
  final double frameHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(exerciseArtProvider).valueOrNull?.forExercise(exercise);
    if (art == null) return const SizedBox.shrink();
    return ExerciseArtFrames(art: art, frameHeight: frameHeight);
  }
}

class ExerciseArtFrames extends StatelessWidget {
  const ExerciseArtFrames({super.key, required this.art, this.frameHeight = 140});

  final ExerciseArt art;
  final double frameHeight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 10.0;
      final columns = art.frames.length == 1 ? 1 : 2;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: gap,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final frame in art.frames)
                SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Container(
                        height: frameHeight,
                        width: width,
                        decoration: BoxDecoration(
                          color: _roleColors[ArtRole.bg],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: frame.wrong ? _roleColors[ArtRole.wrong]!.withOpacity(0.45) : Colors.transparent),
                        ),
                        child: Semantics(
                          image: true,
                          label: '${art.name}: ${frame.caption}',
                          child: CustomPaint(painter: ExerciseFramePainter(art, frame)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        frame.caption,
                        textAlign: TextAlign.center,
                        style: text.labelMedium?.copyWith(
                          color: frame.wrong ? _roleColors[ArtRole.wrong] : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: _roleColors[ArtRole.muscle], shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Trabaja: '),
                    TextSpan(text: art.muscles, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}
