import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Anillo de progreso: el dato se ve antes de leerse. Se anima al cambiar
/// para que registrar una comida se note.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.value,
    required this.label,
    this.sublabel,
    this.color,
    this.size = 92,
    this.stroke = 9,
  });

  /// 0 a 1. null = sin referencia: sólo pista neutral, no cumplimiento0%.
  final double? progress;

  /// Número grande dentro del anillo.
  final String value;
  final String label;
  final String? sublabel;
  final Color? color;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ringColor = color ?? scheme.primary;
    // Auditoría 053, P1-4: en los anillos chicos la meta («de 2.100–2.200»)
    // se encogía a ~3 sp dentro del FittedBox; va debajo, con letra normal
    // que sí crece con la del sistema.
    final small = size < 160;
    final inside = small ? null : sublabel;
    return Semantics(
      // TalkBack anuncia el dato y la meta, no sólo el dibujo.
      label: [label, value, if (sublabel != null) sublabel!]
          .where((x) => x.isNotEmpty)
          .join(', '),
      excludeSemantics: true,
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress?.clamp(0, 1) ?? 0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => CustomPaint(
              painter: _RingPainter(
                progress: animated,
                color: ringColor,
                track: scheme.surfaceContainerHighest,
                stroke: stroke,
              ),
              child: Center(
                // En anillos pequeños (cuatro en Hoy) el texto se encoge en vez
                // de desbordar el anillo.
                child: Padding(
                  padding: EdgeInsets.all(stroke + 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          value,
                          // En anillos grandes (cronómetro) el número manda.
                          style: (size >= 160
                                  ? Theme.of(context).textTheme.displayMedium
                                  : Theme.of(context).textTheme.titleLarge)
                              ?.copyWith(fontWeight: FontWeight.w800, height: 1.1),
                        ),
                        if (inside != null)
                          Text(inside,
                              style: Theme.of(context).textTheme.titleSmall),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
        if (small && sublabel != null)
          SizedBox(
            width: size + 24,
            child: Text(sublabel!,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color, required this.track, required this.stroke});

  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..color = track
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);

    if (progress <= 0) return;
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [color.withOpacity(0.65), color],
      ).createShader(rect)
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color || old.track != track;
}

/// Barra fina para metas secundarias.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.progress, required this.label, required this.value, this.color});

  final double progress;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
            Text(value, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0, 1)),
            duration: const Duration(milliseconds: 500),
            builder: (context, animated, _) => LinearProgressIndicator(
              value: animated,
              minHeight: 8,
              color: c,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ],
    );
  }
}
