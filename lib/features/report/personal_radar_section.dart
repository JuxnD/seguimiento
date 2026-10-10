import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/personal_radar_repository.dart';
import '../../domain/fitness_test.dart';
import '../../domain/dates.dart';
import '../../domain/progress_metrics.dart';
import '../../ui/widgets.dart';
import '../body/test_results_screen.dart';
import '../training/training_screen.dart';
import 'personal_radar_widget.dart';
import 'radar_reference_dialog.dart';

class PersonalRadarSection extends ConsumerWidget {
  const PersonalRadarSection({super.key, required this.end});
  final String end;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(personalRadarProvider(end)).when(
      skipLoadingOnReload: true,
      loading: () => const AppCard(children: [LinearProgressIndicator()]),
      error: (_, __) =>
          const AppCard(children: [Text('No se pudieron leer tus pruebas. Vuelve a abrir este período.')]),
      data: (radar) => PersonalRadarWidget(
          radar: radar,
          compact: true,
          onConfigure: (axis) => _configure(context, ref, axis, radar),
          onRegister: (axis) async {
            if (axis == RadarAxis.circuit) {
              final start = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                          title: const Text('Registrar Cindy de 20 min'),
                          content: const Text(
                              'Abre la prueba de hoy con su preparación y revisión habitual. Puedes cancelar antes de empezar.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Abrir prueba'))
                          ]));
              if (start == true && context.mounted) {
                await startCindyTest(context, ref);
              }
            } else {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => TestResultsScreen(
                          focusPart:
                              axis == RadarAxis.legs || axis == RadarAxis.jump ? TestPart.piernas : TestPart.torso)));
            }
          }));

  Future<void> _configure(BuildContext context, WidgetRef ref, RadarAxis axis, PersonalRadar radar) async {
    final clock = ref.read(decisionClockProvider);
    final repository = GoalRepository(ref.read(databaseProvider));
    final decision = clock();
    final current = ref.read(goalHistoryProvider).valueOrNull?.on(radarMetric(axis), decision);
    final result = await showDialog<({double? value})>(
        context: context,
        builder: (_) => RadarReferenceDialog(
            axis: axis, decision: decision, cutoff: radar.asOf, value: current?.known == true ? current?.value : null));
    if (result == null) return;
    try {
      final confirmed = clock();
      await repository.setReference(radarMetric(axis), result.value, now: confirmed);
      if (context.mounted) showSnack(context, 'Referencia guardada desde ${formatLong(confirmed)}.');
    } on Object {
      if (context.mounted) showSnack(context, 'No se pudo guardar la referencia. Inténtalo de nuevo.');
    }
  }
}
