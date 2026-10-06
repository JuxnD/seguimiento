import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/catalog_updates.dart' show applyExerciseGuides;
import '../../data/local_flags.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/plan_v3.dart';
import '../../ui/widgets.dart';
import 'plan_edit_screen.dart';
import 'v3_activation.dart';

/// Activar el Plan v3 a mano: la app lo propone en Hoy tras 10 rondas
/// limpias, pero el arranque también se puede elegir aquí (§18: si el 9 oct no
/// salen, arranca el lunes después de la primera sesión de 10 limpias).
class _V3ActivationCard extends ConsumerWidget {
  const _V3ActivationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monday = nextMonday(addDays(dateOnly(DateTime.now()), 1));
    return AppCard(
      title: 'Plan v3.1',
      children: [
        const Text('Tirón + hombro, empuje + brazos, piernas + potencia el miércoles, torso B y el viernes de '
            'referencia (circuito hasta las 10 limpias; luego Cindy y Tabata). 9 semanas: bloque 1 de 5, '
            'descarga, bloque 2 de 3 y pruebas. Arranca un lunes.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: () => activateV31(context, ref, monday),
              child: Text('Activar desde el ${formatShort(monday)}'),
            ),
            OutlinedButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: monday,
                  firstDate: dateOnly(DateTime.now()),
                  lastDate: DateTime(2027, 12, 31),
                  selectableDayPredicate: (d) => d.weekday == DateTime.monday,
                  helpText: 'Lunes de inicio',
                );
                if (picked != null && context.mounted) await activateV31(context, ref, dateOnly(picked));
              },
              child: const Text('Otro lunes'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Bloque de planche (§19.7): empieza cuando lleguen las mini paralelas.
class _PlancheCard extends ConsumerStatefulWidget {
  const _PlancheCard();

  @override
  ConsumerState<_PlancheCard> createState() => _PlancheCardState();
}

class _PlancheCardState extends ConsumerState<_PlancheCard> {
  late bool _on = ref.read(localFlagsProvider).get<bool>(FlagKeys.hasParallettes) == true;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'Bloque de planche',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tengo las mini paralelas'),
          subtitle: const Text('Martes, jueves y viernes, ~10 min al inicio: muñecas, inclinación de planche y, el '
              'martes, flexiones pseudo-planche. El tuck entra con 3 × 30 s de inclinación. En descarga, solo '
              'inclinaciones. Con dolor de muñeca o codo, una semana solo inclinaciones suaves.'),
          value: _on,
          onChanged: (v) async {
            setState(() => _on = v);
            await ref.read(localFlagsProvider).set(FlagKeys.hasParallettes, v);
            if (v) await applyExerciseGuides(ref.read(databaseProvider));
            ref.invalidate(dashboardProvider);
          },
        ),
      ],
    );
  }
}

/// Historial de versiones del plan. Las versiones no se editan: se crean.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = ref.watch(planVersionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Plan semanal')),
      body: versions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const AppCard(children: [EmptyHint('Sin plan. Crea la versión 1.')]);
          }
          final hasV3 = list.any((v) => v.scheme == v31Scheme);
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (!hasV3) const _V3ActivationCard(),
              if (hasV3) const _PlancheCard(),
              for (var i = list.length - 1; i >= 0; i--)
                _VersionCard(versionId: list[i].id, number: i + 1, validFrom: parseDay(list[i].validFrom), notes: list[i].notes),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final list = ref.read(planVersionsProvider).value ?? [];
          final draft = list.isEmpty
              ? PlanDraft.empty(dateOnly(DateTime.now()))
              : (await ref.read(planRepositoryProvider).load(list.last.id)
                ..validFrom = dateOnly(DateTime.now()));
          if (context.mounted) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => PlanEditScreen(draft: draft)));
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva versión'),
      ),
    );
  }
}

class _VersionCard extends ConsumerWidget {
  const _VersionCard({required this.versionId, required this.number, required this.validFrom, this.notes});

  final int versionId;
  final int number;
  final DateTime validFrom;
  final String? notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      title: 'v$number · desde ${formatLong(validFrom)}',
      trailing: IconButton(
        tooltip: 'Duplicar y editar',
        icon: const Icon(Icons.edit_note),
        onPressed: () async {
          final draft = await ref.read(planRepositoryProvider).load(versionId)
            ..validFrom = dateOnly(DateTime.now());
          if (context.mounted) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => PlanEditScreen(draft: draft)));
          }
        },
      ),
      children: [
        if (notes != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(notes!)),
        ref.watch(planDraftProvider(versionId)).when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (plan) {
            return Column(
              children: [
                for (final day in plan.days)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('${weekdayLong(day.weekday)} · ${day.type.label}'
                        '${day.targetRounds == null ? '' : ' · meta ${day.targetRounds} rondas'}'),
                    subtitle: day.exercises.isEmpty
                        ? null
                        : Text(day.exercises.map((e) => '${e.name} ${e.targetLabel}'.trim()).join(' · ')),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
