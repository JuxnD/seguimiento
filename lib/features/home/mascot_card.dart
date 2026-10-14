import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart' show rayitoWidgetBridgeProvider;
export '../../app/providers.dart' show rayitoWidgetBridgeProvider;

import '../../data/rayito_widget_bridge.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/mascot.dart';
import '../../domain/mascot_message.dart';
import '../../domain/readiness.dart';
import '../../ui/mascot.dart';
import 'readiness_card.dart';

/// Puente al widget de inicio; reemplazable en pruebas.

/// Rayito en Hoy (plan 049): crece con la racha de constancia y su cara dice
/// cómo va el día. Lee la misma racha que el chip de Hoy y el mismo
/// readiness de 032; no guarda nada en la base. Cuando cambia lo que muestra,
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
    final restAdvised = view != null &&
        !view.trainedAnyway &&
        view.advice.action != SuggestedAction.trainAsPlanned;
    final plannedRest =
        dashboard.planVersion != null && dashboard.dayType == DayType.descanso;
    final restOnly = view != null &&
        !view.trainedAnyway &&
        view.advice.action == SuggestedAction.restOnly;
    final todayLabel = dashboard.planVersion == null
        ? 'Configura tu rutina'
        : view == null
            ? 'Abre Hoy para revisar tu agenda'
            : restOnly
                ? 'Descanso'
                : restAdvised
                    ? 'Recuperación activa'
                    : dashboard.planB
                        ? 'Plan B: solo torso'
                        : dashboard.dayType.label;
    final streak = dashboard.streak;
    final phase = mascotPhase(streak);
    final mood = mascotMood(
        streak: streak,
        activeToday: dashboard.activeToday,
        restAdvised: restAdvised || plannedRest);
    final toNext = daysToNextPhase(streak);
    _syncWidget(RayitoWidgetData(
        phase: phase,
        mood: mood,
        streak: streak,
        today: todayLabel,
        date: dashboard.date));
    final text = Theme.of(context).textTheme;
    final days = streak == 1 ? '1 día' : '$streak días';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Rayito(
              phase: phase,
              mood: mood,
              size: 76,
              semanticLabel:
                  'Rayito, fase ${phase.label}, estado ${mood.name}, $days de racha',
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rayito · ${phase.label}', style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    streak == 0 ? 'Sin racha todavía' : '$days de racha',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mascotMessage(
                        streak: streak,
                        activeToday: dashboard.activeToday,
                        restAdvised: restAdvised || plannedRest,
                        restOnly: restOnly),
                    style:
                        text.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                  ),
                  if (toNext != null && !restAdvised && !plannedRest) ...[
                    const SizedBox(height: 2),
                    Text(
                      toNext == 1
                          ? 'Un día más y llega a ${phase.next!.label}.'
                          : 'Faltan $toNext días para ${phase.next!.label}.',
                      style: text.bodySmall,
                    ),
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
