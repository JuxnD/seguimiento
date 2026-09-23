import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/meal_slots.dart';
import '../../domain/nutrition.dart';
import '../../ui/widgets.dart';
import 'foods_screen.dart';
import 'meal_form_screen.dart';

class MealsScreen extends ConsumerStatefulWidget {
  const MealsScreen({super.key});

  @override
  ConsumerState<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends ConsumerState<MealsScreen> {
  DateTime _day = dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final meals = ref.watch(mealsForDayProvider(dayKey(_day)));
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comidas'),
        actions: [
          IconButton(
            tooltip: 'Catálogo',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoodsScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          AppCard(
            children: [
              Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(() => _day = addDays(_day, -1))),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _day = dateOnly(picked));
                      },
                      child: Text('${weekdayLong(_day.weekday)} ${formatLong(_day)}'),
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(() => _day = addDays(_day, 1))),
                ],
              ),
              meals.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) {
                  final total = Macros.sum(list.map((m) => m.macros));
                  final kcalTarget = profile?.kcalTarget ?? 2400;
                  final proteinMin = profile?.proteinMin ?? 130;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${fmtInt(total.kcal)} kcal de ${fmtInt(kcalTarget)} · '
                          'P ${fmtInt(total.protein)} g de $proteinMin g'),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: (total.protein / proteinMin).clamp(0, 1).toDouble()),
                      const SizedBox(height: 4),
                      Text('C ${fmtInt(total.carbs)} g · G ${fmtInt(total.fat)} g',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  );
                },
              ),
            ],
          ),
          _Shortcuts(day: _day),
          meals.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) => list.isEmpty
                ? const AppCard(children: [EmptyHint('Sin comidas este día.')])
                : Column(
                    children: [
                      for (final m in list) _MealCard(meal: m, onChanged: () => setState(() {})),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MealFormScreen(
              draft: MealDraft(
                date: _day,
                slot: slotForTime(DateTime.now().hour, DateTime.now().minute),
                time: timeKey(DateTime.now().hour, DateTime.now().minute),
              ),
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Comida'),
      ),
    );
  }
}

class _MealCard extends ConsumerWidget {
  const _MealCard({required this.meal, required this.onChanged});

  final MealWithItems meal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = meal.macros;
    return AppCard(
      title: '${meal.meal.slot.label}${meal.meal.time == null ? '' : ' · ${meal.meal.time}'}',
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          final repo = ref.read(nutritionRepositoryProvider);
          if (v == 'editar') {
            final draft = await repo.loadMeal(meal.meal.id);
            if (context.mounted) {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => MealFormScreen(draft: draft)));
            }
          } else if (v == 'hoy') {
            await repo.copyMeal(meal.meal.id, dateOnly(DateTime.now()));
            if (context.mounted) showSnack(context, 'Copiada a hoy');
          } else if (v == 'borrar') {
            if (await confirmDelete(context, 'la comida')) await repo.deleteMeal(meal.meal.id);
          }
          onChanged();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'editar', child: Text('Editar')),
          PopupMenuItem(value: 'hoy', child: Text('Copiar a hoy')),
          PopupMenuItem(value: 'borrar', child: Text('Borrar')),
        ],
      ),
      children: [
        for (final i in meal.items)
          Text('• ${i.label}'
              '${i.quantity == null ? '' : ' ${fmtDec(i.quantity!)} ${i.quantityUnit ?? ''}'.trimRight()}'
              ' — ${fmtInt(i.kcal)} kcal · P ${fmtDec(i.protein)} g'),
        const SizedBox(height: 6),
        Text('${fmtInt(m.kcal)} kcal · P ${fmtInt(m.protein)} g',
            style: Theme.of(context).textTheme.titleSmall),
        if (meal.meal.notes != null) Text(meal.meal.notes!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Registro en un toque: combos guardados y lo que comiste ayer.
class _Shortcuts extends ConsumerWidget {
  const _Shortcuts({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(mealTemplatesProvider);
    final yesterday = ref.watch(mealsForDayProvider(dayKey(addDays(day, -1))));
    return AppCard(
      title: 'Atajos',
      children: [
        templates.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (list) => list.isEmpty
              ? const EmptyHint('Sin combos. Arma una comida y guárdala con el icono de marcador.')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in list)
                      GestureDetector(
                        onLongPress: () => _templateMenu(context, ref, t),
                        child: ActionChip(
                          avatar: const Icon(Icons.bolt, size: 18),
                          label: Text('${t.name} · ${fmtInt(t.macros.kcal)} kcal'),
                          onPressed: () => _logTemplate(context, ref, t),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 4),
        Text('Toque: registra tal cual. Mantener: ajustar cantidades o borrar.',
            style: Theme.of(context).textTheme.bodySmall),
        yesterday.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (meals) => meals.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text('Repetir de ayer', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in meals)
                          ActionChip(
                            avatar: const Icon(Icons.replay, size: 18),
                            label: Text('${m.meal.slot.label} · ${fmtInt(m.macros.kcal)} kcal'),
                            onPressed: () => _repeat(context, ref, m),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  String _now() => timeKey(DateTime.now().hour, DateTime.now().minute);

  Future<void> _logTemplate(BuildContext context, WidgetRef ref, MealTemplate template) async {
    final repo = ref.read(nutritionRepositoryProvider);
    final now = DateTime.now();
    final id = await repo.logTemplate(
      template,
      day,
      slot: template.row.slot ?? slotForTime(now.hour, now.minute),
      time: _now(),
    );
    if (!context.mounted) return;
    _undoable(
        context,
        '${template.name}: ${fmtInt(template.macros.kcal)} kcal · '
        'P ${fmtInt(template.macros.protein)} g',
        () => repo.deleteMeal(id));
  }

  /// Copia una comida de ayer al día mostrado, con la hora de ahora.
  Future<void> _repeat(BuildContext context, WidgetRef ref, MealWithItems meal) async {
    final repo = ref.read(nutritionRepositoryProvider);
    final id = await repo.copyMeal(meal.meal.id, day, time: _now());
    if (!context.mounted) return;
    _undoable(context, '${meal.meal.slot.label} de ayer repetido', () => repo.deleteMeal(id));
  }

  Future<void> _templateMenu(BuildContext context, WidgetRef ref, MealTemplate template) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: Text(template.name), subtitle: Text(template.items.map((i) => i.$1.name).join(', '))),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Ajustar cantidades y registrar'),
              onTap: () => Navigator.pop(context, 'ajustar'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Borrar combo'),
              onTap: () => Navigator.pop(context, 'borrar'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final repo = ref.read(nutritionRepositoryProvider);
    if (action == 'ajustar') {
      final now = DateTime.now();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MealFormScreen(
            draft: MealDraft(
              date: day,
              slot: template.row.slot ?? slotForTime(now.hour, now.minute),
              time: _now(),
              items: template.toDrafts(),
            ),
          ),
        ),
      );
    } else if (action == 'borrar') {
      if (await confirmDelete(context, 'el combo "${template.name}"')) {
        await repo.deleteTemplate(template.row.id);
      }
    }
  }

  void _undoable(BuildContext context, String message, Future<void> Function() undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Deshacer', onPressed: () => undo()),
      ));
  }
}
