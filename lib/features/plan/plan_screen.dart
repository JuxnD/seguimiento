import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../ui/widgets.dart';
import 'plan_edit_screen.dart';

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
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
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
