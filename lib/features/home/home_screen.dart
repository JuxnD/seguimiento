import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/meal_slots.dart';
import '../../ui/progress_ring.dart';
import '../../ui/session_style.dart';
import '../../ui/widgets.dart';
import '../meals/meal_form_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/updates_card.dart';
import '../training/active_session_banner.dart';
import '../training/football_form_screen.dart';
import '../training/training_screen.dart';

/// Pantalla de entrada: qué toca hoy, cómo voy y cómo registrarlo rápido.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const ActiveSessionBanner(),
            UpdateBanner(
              onOpenSettings: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
            _PlanHero(dashboard: d),
            _RingsCard(dashboard: d),
            _ActionsCard(date: today, dayType: d.dayType),
            if (d.daysToMeasurement != null) _MeasurementCard(days: d.daysToMeasurement!),
          ],
        ),
      ),
    );
  }
}

/// Lo primero que se ve: qué toca hoy, con color e icono del tipo.
class _PlanHero extends StatelessWidget {
  const _PlanHero({required this.dashboard});

  final TodayDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final style = styleForDay(dashboard.dayType);
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [style.color.withOpacity(0.22), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${weekdayLong(dashboard.date.weekday)} ${formatShort(dashboard.date)}'.toUpperCase(),
                    style: text.labelSmall?.copyWith(letterSpacing: 1)),
                const Spacer(),
                _Chip(
                  icon: Icons.local_fire_department,
                  label: dashboard.streak == 0 ? 'Sin racha' : '${dashboard.streak} ${dashboard.streak == 1 ? 'día' : 'días'}',
                  color: dashboard.streak >= 3 ? style.color : null,
                ),
                const SizedBox(width: 6),
                _Chip(icon: Icons.calendar_today_outlined, label: 'Sem ${dashboard.weekIndex}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: style.color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(style.icon, size: 30, color: style.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dashboard.dayType.label.toUpperCase(),
                        style: text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: style.color,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (dashboard.targetRounds != null)
                        Text('Meta: ${dashboard.targetRounds} rondas', style: text.titleSmall),
                      if (dashboard.planVersion != null)
                        Text('Plan v${dashboard.planVersion}', style: text.bodySmall),
                    ],
                  ),
                ),
                if (dashboard.trained)
                  Icon(Icons.check_circle, color: style.color, size: 28),
              ],
            ),
            if (dashboard.mainExercises.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final e in dashboard.mainExercises)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('• $e', style: text.bodyMedium),
                ),
            ],
            if (dashboard.dayType == DayType.descanso)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Día de descanso. La racha no se rompe.', style: text.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}

/// Anillos: proteína, kcal y rondas. El progreso se ve, no se lee.
class _RingsCard extends StatelessWidget {
  const _RingsCard({required this.dashboard});

  final TodayDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final d = dashboard;
    final style = styleForDay(d.dayType);
    final showRounds = d.targetRounds != null;
    return AppCard(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ProgressRing(
              progress: d.proteinProgress,
              value: fmtInt(d.macros.protein),
              sublabel: 'de ${d.proteinMin}',
              label: 'Proteína',
              color: const Color(0xFF4EA8FF),
            ),
            ProgressRing(
              progress: d.kcalProgress,
              value: fmtInt(d.macros.kcal),
              sublabel: 'de ${fmtInt(d.kcalTarget)}',
              label: 'kcal',
              color: const Color(0xFFFFB067),
            ),
            if (showRounds)
              ProgressRing(
                progress: d.roundsProgress,
                value: '${d.roundsDone ?? 0}',
                sublabel: 'de ${d.targetRounds}',
                label: 'Rondas',
                color: style.color,
              )
            else
              ProgressRing(
                progress: d.trained ? 1 : 0,
                value: d.trained ? '✓' : '—',
                label: 'Sesión',
                color: style.color,
              ),
          ],
        ),
        if (d.roundsRecord != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined, size: 18),
              const SizedBox(width: 8),
              Text('Récord de rondas: ${d.roundsRecord}',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActionsCard extends ConsumerWidget {
  const _ActionsCard({required this.date, required this.dayType});

  final DateTime date;
  final DayType dayType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = styleForDay(dayType);
    return AppCard(
      title: 'Registrar',
      children: [
        FilledButton.icon(
          onPressed: () => startGuidedSession(context, ref),
          style: FilledButton.styleFrom(backgroundColor: style.color),
          icon: Icon(dayType.isTraining ? Icons.play_arrow : Icons.timer),
          label: Text(dayType.isTraining ? 'Empezar ${dayType.label.toLowerCase()}' : 'Empezar sesión'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ActionButton(
                icon: Icons.edit_note,
                label: 'Sesión',
                onPressed: () => openSessionForm(context, SessionDraft(date: date)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.sports_soccer,
                label: 'Fútbol',
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const FootballFormScreen())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActionButton(
                icon: Icons.restaurant,
                label: 'Comida',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MealFormScreen(
                      draft: _mealNow(date),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Comida de ahora: la franja sale de la hora, igual que en la pestaña
/// Comidas, para no tener que corregirla a las 8 p. m.
MealDraft _mealNow(DateTime date) {
  final now = DateTime.now();
  return MealDraft(date: date, slot: slotForTime(now.hour, now.minute), time: timeKey(now.hour, now.minute));
}

class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) => AppCard(
        children: [
          Row(
            children: [
              const Icon(Icons.straighten, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(days > 0
                    ? 'Próxima medición en $days ${days == 1 ? 'día' : 'días'}'
                    : 'Toca medir: ya pasó el intervalo'),
              ),
            ],
          ),
        ],
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
        ],
      ),
    );
  }
}
