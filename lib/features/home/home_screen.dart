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
                  final rounds = day.targetRounds;
                  final scheme = Theme.of(context).colorScheme;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              day.type.label.toUpperCase(),
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: scheme.primary,
                                    letterSpacing: 0.6,
                                  ),
                            ),
                          ),
                          if (rounds != null)
                            Text('meta $rounds rondas', style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(width: 8),
                          Text('v${view.versionNumber}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      for (final e in day.main)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• ${e.name} ${e.targetLabel}'.trimRight()),
                        ),
                      if (day.restBetweenRoundsSec != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Descanso entre rondas: ${day.restBetweenRoundsSec} s',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      for (final block in day.blocks.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text('Bloque ${block.key}'.toUpperCase(),
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 0.6)),
                        ),
                        for (final e in block.value)
                          Text('• ${e.variantPrefix}${e.name} ${e.targetLabel}'.trimRight()),
                      ],
                      if (day.notes != null && day.notes!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(day.notes!, style: Theme.of(context).textTheme.bodySmall),
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
                    child: ActionButton(
                      icon: Icons.edit_note,
                      label: 'Sesión',
                      onPressed: () => openSessionForm(context, SessionDraft(date: today)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ActionButton(
                      icon: Icons.sports_soccer,
                      label: 'Fútbol',
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const FootballFormScreen())),
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
                            draft: MealDraft(
                              date: today,
                              slot: MealSlot.desayuno,
                              time: timeKey(DateTime.now().hour, DateTime.now().minute),
                            ),
                          ),
                        ),
                      ),
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
