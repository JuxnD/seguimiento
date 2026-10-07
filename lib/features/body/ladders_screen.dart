import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/core_ladders.dart';
import '../../domain/dates.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Escaleras de core (§19.10): el peldaño actual, el criterio para subir y
/// cuánto falta. Subir lo confirma el usuario; la molestia lumbar baja uno.
class LaddersScreen extends ConsumerWidget {
  const LaddersScreen({super.key});

  Future<void> _change(BuildContext context, WidgetRef ref, CoreLadder ladder, int current) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Escalera del ${ladder.name}'),
        children: [
          for (final s in ladder.steps)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, s.step),
              child: Text('${s.step}. ${s.exercise}${s.step == current ? ' (actual)' : ''}'),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await ref.read(ladderRepositoryProvider).setStep(ladder, picked, ref.read(todayProvider));
    ref.invalidate(ladderAdviceProvider);
    ref.invalidate(dashboardProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advice = ref.watch(ladderAdviceProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Escaleras de core')),
      body: advice.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (byId) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            AppCard(
              children: [
                Text(
                  'Se sube un peldaño cuando el criterio sale en $ladderCleanSessions sesiones seguidas, y nunca antes '
                  'de 2–3 semanas en el peldaño. Si la lumbar se arquea o molesta, se baja uno: márcalo en el '
                  'descanso de la serie con "Molestia lumbar".',
                  style: text.bodyMedium,
                ),
              ],
            ),
            for (final l in coreLadders)
              if (byId[l.id] case final a?)
                AppCard(
                  title: '${l.name} · ${weekdayLong(l.weekday).toLowerCase()}',
                  trailing: TextButton(onPressed: () => _change(context, ref, l, a.step.step), child: const Text('Cambiar')),
                  children: [
                    Text('Peldaño ${a.step.step} de ${l.top}: ${a.step.exercise}', style: text.titleSmall),
                    Text(a.step.prescription, style: text.bodySmall),
                    const SizedBox(height: 6),
                    if (a.step.goals.isNotEmpty) Text('Para subir: ${a.step.criterion}', style: text.bodyMedium),
                    Text(a.status,
                        style: text.bodySmall?.copyWith(color: a.canStepUp ? AppColors.record : null)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (a.canStepUp)
                          FilledButton.tonal(
                            onPressed: () async {
                              await ref.read(ladderRepositoryProvider).stepUp(l, ref.read(todayProvider));
                              ref.invalidate(ladderAdviceProvider);
                              ref.invalidate(dashboardProvider);
                            },
                            child: Text('Subir a ${l.stepAt(a.step.step + 1).exercise}'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final step = await ref.read(ladderRepositoryProvider).lumbar(l, ref.read(todayProvider));
                            ref.invalidate(ladderAdviceProvider);
                            ref.invalidate(dashboardProvider);
                            if (context.mounted) {
                              showSnack(context, '${l.name}: peldaño $step, ${l.stepAt(step).exercise}.');
                            }
                          },
                          icon: const Icon(Icons.healing_outlined),
                          label: const Text('Molestia lumbar'),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    for (final s in l.steps)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              s.step < a.step.step
                                  ? Icons.check_circle
                                  : s.step == a.step.step
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                              size: 18,
                              color: s.step <= a.step.step ? AppColors.record : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('${s.step}. ${s.exercise} · ${s.prescription}', style: text.bodySmall),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}
