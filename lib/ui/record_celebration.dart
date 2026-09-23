import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Celebración al superar el máximo de rondas. Es el momento más motivante de
/// la semana y antes pasaba desapercibido.
Future<void> showRecordCelebration(
  BuildContext context, {
  required int rounds,
  int? previous,
}) {
  unawaited(HapticFeedback.mediumImpact());
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _RecordDialog(rounds: rounds, previous: previous),
  );
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.rounds, this.previous});

  final int rounds;
  final int? previous;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOutBack.transform(_controller.value.clamp(0.0, 1.0));
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(320, 320),
                painter: _BurstPainter(progress: _controller.value, color: scheme.primary),
              ),
              Transform.scale(
                scale: 0.6 + 0.4 * t,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events, size: 56, color: scheme.primary),
                      const SizedBox(height: 8),
                      Text('RÉCORD',
                          style: text.titleMedium?.copyWith(letterSpacing: 3, color: scheme.primary)),
                      const SizedBox(height: 4),
                      Text('${widget.rounds}',
                          style: text.displayLarge?.copyWith(fontWeight: FontWeight.w900, height: 1)),
                      Text('rondas', style: text.titleMedium),
                      const SizedBox(height: 10),
                      Text(
                        widget.previous == null
                            ? 'Primera marca registrada'
                            : 'Tu máximo anterior era ${widget.previous}',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Seguir así'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Destello de rayos: barato de pintar y suficiente para que se note.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color.withOpacity((1 - progress).clamp(0, 1) * 0.8)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const rays = 12;
    final radius = size.width / 2 * Curves.easeOut.transform(progress);
    for (var i = 0; i < rays; i++) {
      final angle = (math.pi * 2 / rays) * i;
      final from = center + Offset(math.cos(angle), math.sin(angle)) * (radius * 0.55);
      final to = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}
