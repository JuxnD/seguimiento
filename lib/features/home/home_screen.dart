import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/nutrition.dart';
import '../../ui/widgets.dart';
import '../meals/meal_form_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/updates_card.dart';
import '../training/football_form_screen.dart';
import '../training/training_screen.dart';

/// Pantalla de entrada: qué toca hoy y cómo registrarlo en menos de 30 s.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateOnly(DateTime.now());
    final profile = ref.watch(profileProvider);
    final planDay = ref.watch(planDayProvider(dayKey(today)));
    final meals = ref.watch(mealsForDayProvider(dayKey(today)));
    final checkIns = ref.watch(checkInsProvider);

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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          UpdateBanner(
            onOpenSettings: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          AppCard(
            children: [
              Text('${weekdayLong(today.weekday)} ${formatLong(today)}',
                  style: Theme.of(context).textTheme.titleMedium),
              profile.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Text('Error: $e'),
                data: (p) => Text('Semana ${weekIndexFor(p.programStart, today)} desde el inicio '
                    '(${formatShort(p.programStart)})'),
              ),
              const SizedBox(height: 8),
              planDay.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (view) {
                  if (view == null) {
                    return const Text('Sin plan para hoy. Créalo en Entreno → Plan.');
                  }
                  final day = view.day;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Plan v${view.versionNumber}: ${day.type.label}'
                          '${day.targetRounds == null ? '' : ' · meta ${day.targetRounds} rondas'}'),
                      if (day.exercises.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(day.exercises.map((e) => '${e.name} ${e.targetLabel}'.trim()).join(' · ')),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          AppCard(
            title: 'Registrar',
            children: [
              FilledButton.icon(
                onPressed: () => startCircuitFlow(context, ref),
                icon: const Icon(Icons.timer),
                label: const Text('Empezar circuito'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openSessionForm(context, SessionDraft(date: today)),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Sesión'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const FootballFormScreen())),
                      icon: const Icon(Icons.sports_soccer),
                      label: const Text('Fútbol'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MealFormScreen(
                            draft: MealDraft(
                              date: today,
                              slot: MealSlot.desayuno,
                              time: timeKey(DateTime.now().hour, DateTime.now().minute),
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.restaurant),
                      label: const Text('Comida'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppCard(
            title: 'Nutrición de hoy',
            children: [
              meals.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) {
                  final total = Macros.sum(list.map((m) => m.macros));
                  final p = profile.value;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${fmtInt(total.kcal)} kcal · P ${fmtInt(total.protein)} g'
                          '${p == null ? '' : ' (meta ${fmtInt(p.kcalTarget)} kcal · ${p.proteinMin}–${p.proteinMax} g)'}'),
                      if (list.isEmpty) const Text('Sin comidas registradas todavía.'),
                      for (final m in list)
                        Text('• ${m.meal.slot.label}: ${fmtInt(m.macros.kcal)} kcal · '
                            'P ${fmtInt(m.macros.protein)} g'),
                    ],
                  );
                },
              ),
            ],
          ),
          checkIns.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) {
              final p = profile.value;
              if (p == null) return const SizedBox.shrink();
              if (list.isEmpty) {
                return const AppCard(children: [Text('Aún no hay una línea base de medidas. Tómala en Cuerpo.')]);
              }
              final days = daysBetween(list.first.date, dateOnly(DateTime.now()));
              final left = p.measureIntervalDays - days;
              return AppCard(children: [
                Text(left > 0
                    ? 'Próxima medición en $left días (última: ${formatShort(list.first.date)})'
                    : 'Toca medir: han pasado $days días desde la última'),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
