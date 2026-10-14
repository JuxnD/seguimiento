import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart' show rayitoWidgetBridgeProvider;
export '../../app/providers.dart' show rayitoWidgetBridgeProvider;

import '../../data/rayito_widget_bridge.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../domain/dates.dart';
import '../../ui/mascot.dart';
import 'rayito_state.dart';
import 'readiness_card.dart';

/// Puente al widget de inicio; reemplazable en pruebas.

/// Rayito en Hoy (planes 049 y 052): nivel y avance de la racha; la frase del
/// día la dice el compañero flotante. Lee la misma racha que el chip de Hoy y
/// el mismo readiness de 032; no guarda nada en la base. Cuando cambia lo que muestra,
/// refresca el widget de inicio con los mismos datos.
class MascotCard extends ConsumerStatefulWidget {
  const MascotCard({super.key, required this.dashboard});

  final TodayDashboard dashboard;

  @override
  ConsumerState<MascotCard> createState() => _MascotCardState();
}

class _MascotCardState extends ConsumerState<MascotCard> {
  RayitoWidgetData? _sent;
  RayitoWidgetData? _pending;

  void _syncWidget(RayitoWidgetData data) {
    if (data == _sent || data == _pending) return;
    _pending = data;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ok = await ref.read(rayitoWidgetBridgeProvider).update(data);
      if (!mounted) return;
      if (ok) _sent = data;
      if (_pending == data) _pending = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboard;
    final view = ref
        .watch(
            readinessViewProvider((day: dayKey(dashboard.date), test: false)))
        .valueOrNull;
    final rayito = rayitoView(dashboard, view);
    _syncWidget(RayitoWidgetData(
        phase: rayito.phase,
        mood: rayito.mood,
        streak: rayito.streak,
        today: rayito.todayLabel,
        date: dashboard.date));
    final text = Theme.of(context).textTheme;
    final phase = rayito.phase;
    final next = phase.next;
    final progress = next == null
        ? 1.0
        : ((rayito.streak - phase.fromDays) / (next.fromDays - phase.fromDays))
            .clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Rayito(
              phase: phase,
              mood: rayito.mood,
              size: 56,
              semanticLabel: rayito.semanticLabel,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rayito', style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text('${rayito.levelLine} · ${rayito.streakLine}',
                      style: text.bodyMedium),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      color: mascotLime,
                      semanticsLabel: 'Avance al nivel siguiente',
                    ),
                  ),
                  if (rayito.progressLine case final line?) ...[
                    const SizedBox(height: 6),
                    Text(line, style: text.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
