import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/report/missing_data_actions.dart';
import '../../data/repositories/nutrition_repository.dart' show MealDraft;
import '../body/body_screen.dart' show addWeightDialog;
import '../home/home_screen.dart' show editStepsDialog;
import '../meals/meal_form_screen.dart';

/// Acciones tipadas derivadas de los registros actuales del rango.
/// Abrir un formulario no escribe hasta que el usuario confirme.
class MissingDataActionsCard extends ConsumerWidget {
  const MissingDataActionsCard({super.key, required this.range});

  final (String, String) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input = ref.watch(reportInputProvider(range));
    return input.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (value) {
        final actions = missingDataActions(value);
        if (actions.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Registros que puedes completar',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                  'Estos accesos se recalculan con tus registros actuales del rango. Los comentarios y citas guardados conservan la fuente original.'),
              for (final action in actions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      switch (action.kind) {
                        case ReportActionKind.weighIn:
                          await addWeightDialog(context, ref,
                              date: action.date);
                        case ReportActionKind.stepsForDay:
                          await editStepsDialog(
                              context, ref, action.date, null);
                        case ReportActionKind.mealForDay:
                          final slot = action.mealSlot ?? MealSlot.desayuno;
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => MealFormScreen(
                                    draft: MealDraft(
                                        date: action.date, slot: slot))),
                          );
                      }
                    },
                    icon: Icon(switch (action.kind) {
                      ReportActionKind.weighIn => Icons.monitor_weight_outlined,
                      ReportActionKind.mealForDay => Icons.restaurant_outlined,
                      ReportActionKind.stepsForDay =>
                        Icons.directions_walk_outlined,
                    }),
                    label: Text(switch (action.kind) {
                      ReportActionKind.weighIn =>
                        'Registrar pesaje · ${formatLong(action.date)}',
                      ReportActionKind.mealForDay =>
                        'Registrar ${action.mealSlot!.name} · ${formatLong(action.date)}',
                      ReportActionKind.stepsForDay =>
                        'Registrar pasos · ${formatLong(action.date)}',
                    }),
                  ),
                ),
              const Text(
                  'Abrir una acción no guarda nada; revisa el día y confirma en el formulario.'),
            ],
          ),
        );
      },
    );
  }
}
