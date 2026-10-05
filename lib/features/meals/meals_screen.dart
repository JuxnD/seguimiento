import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/nutrition_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/meal_slots.dart';
import '../../domain/nutrition.dart';
import '../../domain/progress.dart';
import '../../ui/hero.dart';
import '../../ui/progress_ring.dart';
import '../../ui/widgets.dart';
import 'foods_screen.dart';
import 'meal_form_screen.dart';
import '../../ui/theme.dart';

class MealsScreen extends ConsumerStatefulWidget {
  const MealsScreen({super.key});

  @override
  ConsumerState<MealsScreen> createState() => _MealsScreenState();
}

/// Color de la sección de comidas: el mismo naranja claro del anillo de kcal.
const _mealColor = AppColors.kcal;

class _MealsScreenState extends ConsumerState<MealsScreen> {
  late DateTime _day = ref.read(todayProvider);

  @override
  Widget build(BuildContext context) {
    // Si estaba en "hoy" y cambia el día, sigue en hoy: los atajos de un toque
    // registran en la fecha visible, y quedarse en ayer sería un error mudo.
    ref.listen(todayProvider, (previous, next) {
      if (previous != null && _day == previous) setState(() => _day = next);
    });
    final today = ref.watch(todayProvider);
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
          HeroCard(
            color: _mealColor,
            children: [
              Row(
                children: [
                  IconButton(tooltip: 'Día anterior', 
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _day = addDays(_day, -1)),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _day = dateOnly(picked));
                      },
                      child: Column(
                        children: [
                          Text(
                            _day == today ? 'HOY' : weekdayLong(_day.weekday).toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1),
                          ),
                          Text(formatLong(_day),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800, color: _mealColor)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(tooltip: 'Día siguiente', 
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _day = addDays(_day, 1)),
                  ),
                ],
              ),
              if (_day != today)
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _day = today),
                    icon: const Icon(Icons.today, size: 18),
                    label: const Text('Volver a hoy'),
                  ),
                ),
              const SizedBox(height: 12),
              meals.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) {
                  final total = Macros.sum(list.map((m) => m.macros));
                  final kcalTarget = dailyKcalTarget(
                      day: _day, weekdayTarget: profile?.kcalTarget ?? 2400, footballTarget: profile?.kcalTargetFootball);
                  final proteinMin = profile?.proteinMin ?? 130;
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ProgressRing(
                            progress: goalProgress(total.protein, proteinMin),
                            value: fmtInt(total.protein),
                            sublabel: 'de $proteinMin',
                            label: 'Proteína (g)',
                            color: AppColors.protein,
                            size: 104,
                          ),
                          ProgressRing(
                            progress: goalProgress(total.kcal, kcalTarget),
                            value: fmtInt(total.kcal),
                            sublabel: 'de ${fmtInt(kcalTarget)}',
                            label: 'kcal',
                            color: AppColors.kcal,
                            size: 104,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Carbos ${fmtInt(total.carbs)} g · Grasa ${fmtInt(total.fat)} g',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (!_day.isAfter(today) && list.isNotEmpty)
                        _DayStatus(
                          day: _day,
                          slots: {for (final m in list) m.meal.slot},
                          mealCount: list.length,
                          kcal: total.kcal,
                        ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _newMeal,
                        style: FilledButton.styleFrom(
                          backgroundColor: _mealColor,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Armar comida'),
                      ),
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
                ? const AppCard(children: [
                    EmptyState(
                      icon: Icons.restaurant_outlined,
                      text: 'Sin comidas este día. Usa un atajo o arma una comida.',
                    ),
                  ])
                : Column(
                    children: [
                      for (final m in list) _MealCard(meal: m, today: today, onChanged: () => setState(() {})),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _newMeal() {
    final now = DateTime.now();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MealFormScreen(
          draft: MealDraft(
            date: _day,
            slot: slotForTime(now.hour, now.minute),
            time: timeKey(now.hour, now.minute),
          ),
        ),
      ),
    );
  }
}

class _MealCard extends ConsumerWidget {
  const _MealCard({required this.meal, required this.today, required this.onChanged});

  final MealWithItems meal;
  final DateTime today;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = meal.macros;
    final date = parseDay(meal.meal.date);
    // La fecha va en la tarjeta si no es de hoy: así nunca hay duda de a qué
    // día pertenece (§16.7).
    final when = date == today ? '' : ' · ${weekdayShort(date.weekday)} ${formatShort(date)}';
    return AppCard(
      title: '${meal.meal.slot.label}${meal.meal.time == null ? '' : ' · ${meal.meal.time}'}$when',
      trailing: PopupMenuButton<String>(
        tooltip: 'Opciones',
        onSelected: (v) async {
          final repo = ref.read(nutritionRepositoryProvider);
          if (v == 'editar') {
            final draft = await repo.loadMeal(meal.meal.id);
            if (context.mounted) {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => MealFormScreen(draft: draft)));
            }
          } else if (v == 'tipo') {
            final slot = await _pickSlot(context, meal.meal.slot);
            if (slot != null && slot != meal.meal.slot && context.mounted) {
              await guarded(context, () => repo.updateMealHeader(meal.meal.id, slot: slot), ok: 'Ahora es ${slot.label}');
            }
          } else if (v == 'fecha') {
            await _moveMeal(context, ref, meal);
          } else if (v == 'hoy') {
            await addMealCopyToDay(context, ref, meal, today);
          } else if (v == 'borrar') {
            // Sin diálogo: se borra y se puede deshacer. Corregir debe costar
            // un toque, no dos.
            late MealDraft backup;
            final ok = await guarded(context, () async {
              backup = await repo.loadMeal(meal.meal.id);
              await repo.deleteMeal(meal.meal.id);
            }, failure: 'No se pudo borrar');
            if (ok && context.mounted) {
              showUndoSnack(context, '${meal.meal.slot.label} borrada', () => repo.saveMeal(backup..id = null));
            }
          }
          onChanged();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'editar', child: Text('Editar')),
          PopupMenuItem(value: 'tipo', child: Text('Cambiar tipo')),
          PopupMenuItem(value: 'fecha', child: Text('Cambiar fecha/hora')),
          PopupMenuItem(value: 'hoy', child: Text('Duplicar en hoy')),
          PopupMenuItem(value: 'borrar', child: Text('Eliminar')),
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
    final today = ref.watch(todayProvider);
    // "De ayer" solo tiene sentido mirando hoy: mirando otro día, "repetir"
    // registraría en una fecha que no es la que el usuario cree.
    final yesterday = ref.watch(mealsForDayProvider(dayKey(addDays(today, -1))));
    return AppCard(
      title: 'Atajos',
      children: [
        templates.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  icon: Icons.bolt,
                  text: 'Sin combos. Arma una comida y guárdala con el icono de marcador.',
                )
              : Column(
                  children: [
                    for (final t in list)
                      TypedTile(
                        icon: Icons.bolt,
                        color: _mealColor,
                        title: t.name,
                        subtitle: 'P ${fmtInt(t.macros.protein)} g · toca para registrar',
                        value: fmtInt(t.macros.kcal),
                        valueLabel: 'kcal',
                        onTap: () => _logTemplate(context, ref, t),
                        trailing: IconButton(
                          tooltip: 'Ajustar o borrar',
                          icon: const Icon(Icons.tune),
                          onPressed: () => _templateMenu(context, ref, t),
                        ),
                      ),
                  ],
                ),
        ),
        yesterday.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (meals) => meals.isEmpty || day != today
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text('De ayer', style: Theme.of(context).textTheme.labelLarge),
                    Text('Toca para ver o corregir; "Repetir hoy" la registra otra vez hoy.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    for (final m in meals)
                      Row(
                        children: [
                          Expanded(
                            child: TypedTile(
                              icon: Icons.history,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              title: '${m.meal.slot.label} de ayer${m.meal.time == null ? '' : ' · ${m.meal.time}'}',
                              subtitle: '${m.items.map((i) => i.label).join(', ')} · ${fmtInt(m.macros.kcal)} kcal',
                              onTap: () => _edit(context, ref, m),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => addMealCopyToDay(context, ref, m, today),
                            icon: const Icon(Icons.replay, size: 18),
                            label: const Text('Repetir hoy'),
                          ),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _logTemplate(BuildContext context, WidgetRef ref, MealTemplate template) async {
    final repo = ref.read(nutritionRepositoryProvider);
    final now = DateTime.now();
    final slot = await confirmOneTapMeal(
      context,
      ref,
      day: day,
      slot: template.row.slot ?? slotForTime(now.hour, now.minute),
      time: _now(),
    );
    if (slot == null || !context.mounted) return;
    final id = await repo.logTemplate(template, day, slot: slot, time: _now());
    if (!context.mounted) return;
    showUndoSnack(
        context,
        '${template.name}: ${fmtInt(template.macros.kcal)} kcal · '
        'P ${fmtInt(template.macros.protein)} g',
        () => repo.deleteMeal(id),
        duration: const Duration(seconds: 5));
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, MealWithItems meal) async {
    final draft = await ref.read(nutritionRepositoryProvider).loadMeal(meal.meal.id);
    if (context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => MealFormScreen(draft: draft)));
    }
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
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Editar combo'),
              onTap: () => Navigator.pop(context, 'editar'),
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
    } else if (action == 'editar') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MealFormScreen(
            template: template,
            draft: MealDraft(date: day, slot: template.row.slot ?? MealSlot.otro, items: template.toDrafts()),
          ),
        ),
      );
    } else if (action == 'borrar') {
      if (await confirmDelete(context, 'el combo "${template.name}"') && context.mounted) {
        await guarded(context, () => repo.deleteTemplate(template.row.id), failure: 'No se pudo borrar');
      }
    }
  }
}

String _now() => timeKey(DateTime.now().hour, DateTime.now().minute);

/// Copia una comida a `day` con la hora de ahora, después de los avisos de
/// hora y de duplicado. "Añadido a hoy · Deshacer" durante 5 s.
Future<void> addMealCopyToDay(BuildContext context, WidgetRef ref, MealWithItems meal, DateTime day) async {
  final repo = ref.read(nutritionRepositoryProvider);
  final time = _now();
  final slot = await confirmOneTapMeal(context, ref, day: day, slot: meal.meal.slot, time: time);
  if (slot == null || !context.mounted) return;
  late int id;
  final ok = await guarded(context, () async {
    id = await repo.copyMeal(meal.meal.id, day, time: time);
    if (slot != meal.meal.slot) await repo.updateMealHeader(id, slot: slot);
  });
  if (!ok || !context.mounted) return;
  final isToday = day == dateOnly(DateTime.now());
  showUndoSnack(context, isToday ? 'Añadido a hoy' : 'Añadido al ${formatShort(day)}', () => repo.deleteMeal(id),
      duration: const Duration(seconds: 5));
}

/// Avisos de los registros de un toque (repetir, duplicar, combo): si la hora
/// no cuadra con el tipo (§9) y si ya hay una comida principal de ese tipo en
/// el día (§16.7). Devuelve el tipo con el que registrar, o null si se canceló.
Future<MealSlot?> confirmOneTapMeal(
  BuildContext context,
  WidgetRef ref, {
  required DateTime day,
  required MealSlot slot,
  required String time,
}) async {
  var chosen = slot;
  final fits = slotMismatch(slot, time);
  if (fits != null) {
    final pick = await showDialog<MealSlot>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿${slot.label} a las $time?'),
        content: Text('A esta hora suele ser ${fits.label.toLowerCase()}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, slot), child: Text('Dejar ${slot.label.toLowerCase()}')),
          FilledButton(onPressed: () => Navigator.pop(c, fits), child: Text('Como ${fits.label.toLowerCase()}')),
        ],
      ),
    );
    if (pick == null || !context.mounted) return null;
    chosen = pick;
  }

  const main = {MealSlot.desayuno, MealSlot.almuerzo, MealSlot.cena};
  if (main.contains(chosen)) {
    final existing = (await ref.read(nutritionRepositoryProvider).range(day, day))
        .where((m) => m.meal.slot == chosen)
        .toList();
    if (existing.isNotEmpty && context.mounted) {
      final isToday = day == dateOnly(DateTime.now());
      final kcal = existing.fold(0.0, (a, m) => a + m.macros.kcal);
      final more = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Ya tienes ${_article(chosen)} ${chosen.label.toLowerCase()} ${isToday ? 'hoy' : 'ese día'}'),
          content: Text('${fmtInt(kcal)} kcal registradas'
              '${existing.first.meal.time == null ? '' : ' a las ${existing.first.meal.time}'}. ¿Añadir ${_other(chosen)}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Añadir ${_other(chosen)}')),
          ],
        ),
      );
      if (more != true) return null;
    }
  }
  return chosen;
}

String _article(MealSlot slot) => slot == MealSlot.cena ? 'una' : 'un';
String _other(MealSlot slot) => slot == MealSlot.cena ? 'otra' : 'otro';

Future<MealSlot?> _pickSlot(BuildContext context, MealSlot current) => showDialog<MealSlot>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Tipo de comida'),
        children: [
          for (final s in MealSlot.values)
            RadioListTile<MealSlot>(
              value: s,
              groupValue: current,
              title: Text(s.label),
              onChanged: (v) => Navigator.pop(c, v),
            ),
        ],
      ),
    );

/// Cambia la fecha y la hora de una comida (para lo registrado en el día
/// equivocado). Avisa si la hora no cuadra con el tipo.
Future<void> _moveMeal(BuildContext context, WidgetRef ref, MealWithItems meal) async {
  final current = parseDay(meal.meal.date);
  final date = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    helpText: 'Fecha de la comida',
  );
  if (date == null || !context.mounted) return;
  final parts = (meal.meal.time ?? '12:00').split(':');
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 12, minute: int.tryParse(parts.last) ?? 0),
    helpText: 'Hora de la comida',
  );
  if (!context.mounted) return;
  final time = picked == null ? meal.meal.time : timeKey(picked.hour, picked.minute);
  var slot = meal.meal.slot;
  final fits = slotMismatch(slot, time);
  if (fits != null) {
    final change = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿${slot.label} a las $time?'),
        content: Text('A esa hora suele ser ${fits.label.toLowerCase()}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Dejar ${slot.label.toLowerCase()}')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('Cambiar a ${fits.label.toLowerCase()}')),
        ],
      ),
    );
    if (!context.mounted) return;
    if (change == true) slot = fits;
  }
  await guarded(
    context,
    () => ref.read(nutritionRepositoryProvider).updateMealHeader(meal.meal.id,
        date: dateOnly(date), time: time, slot: slot == meal.meal.slot ? null : slot),
    ok: 'Movida al ${weekdayShort(date.weekday)} ${formatShort(date)}${time == null ? '' : ' a las $time'}',
  );
}

/// Si el día cuenta para promedios y alertas: con desayuno, almuerzo y cena,
/// o cerrado a mano. Cerrar es decir "hoy no hubo más", no inventar comidas.
class _DayStatus extends ConsumerWidget {
  const _DayStatus({required this.day, required this.slots, required this.mealCount, required this.kcal});

  final DateTime day;
  final Set<MealSlot> slots;
  final int mealCount;
  final double kcal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manual = ref.watch(dayClosedProvider(dayKey(day))).value ?? false;
    final missing = missingMainMeals(slots);
    final text = Theme.of(context).textTheme;
    final repo = ref.read(nutritionRepositoryProvider);
    if (missing.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Día completo: cuenta para los promedios', style: text.bodySmall),
      );
    }
    final labels = missing.map((m) => m.label.toLowerCase()).toList();
    final names = labels.length == 1 ? labels.first : '${labels.take(labels.length - 1).join(', ')} y ${labels.last}';
    // Regla alternativa (§16.6.3): 3 comidas o 1.800 kcal cierran el día.
    if (!manual && isDayClosed(slots, mealCount: mealCount, kcal: kcal)) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Cuenta para los promedios: ${mealCount >= closeByMealCount ? '$mealCount comidas' : '${fmtInt(kcal)} kcal'} '
          '(aunque falte $names)',
          style: text.bodySmall,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              manual
                  ? 'Día cerrado a mano (sin $names)'
                  : '${labels.length == 1 ? 'Falta' : 'Faltan'} $names: no entra a los promedios',
              style: text.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => guarded(context, () => repo.setClosed(day, !manual)),
            child: Text(manual ? 'Reabrir' : 'Cerrar día'),
          ),
        ],
      ),
    );
  }
}
