import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart';
import '../../domain/recovery.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

/// Hoja de ruta de habilidades (§19.8): cada una con su criterio, la ventana
/// estimada desde octubre de 2026 y lo que conviene tener antes. Se marca a
/// mano cuando se cumple el criterio. Se entrenan en el bloque inicial de
/// 10 min, nunca más de 2 a la vez.
class SkillsScreen extends ConsumerWidget {
  const SkillsScreen({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, Skill s, DateTime? achieved) async {
    final repo = ref.read(recoveryRepositoryProvider);
    if (achieved != null) {
      final undo = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.name),
          content: Text('Lograda el ${formatLong(achieved)}. ¿Quitar el logro?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Dejarla')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitar')),
          ],
        ),
      );
      if (undo == true) await repo.setSkill(s.id, null);
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: dateOnly(DateTime.now()),
      firstDate: DateTime(2026, 9, 1),
      lastDate: dateOnly(DateTime.now()),
      helpText: '${s.name}: ${s.criterion}',
    );
    if (picked != null) await repo.setSkill(s.id, dateOnly(picked));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(skillsProvider).valueOrNull ?? const {};
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Habilidades')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AppCard(
            children: [
              Text('Hoja de ruta de 2 años desde octubre de 2026. Las fechas son orientativas y se recalculan '
                  'con el progreso. Se entrenan en el bloque inicial de 10 min, rotando cada 4–6 semanas y '
                  'nunca más de 2 a la vez.', style: text.bodyMedium),
              const SizedBox(height: 6),
              Text('${done.length} de ${skillRoadmap.length} logradas', style: text.titleSmall),
            ],
          ),
          AppCard(
            children: [
              for (final s in skillRoadmap)
                Builder(builder: (context) {
                  final achieved = done[s.id];
                  final (from, to) = skillWindow(s);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      achieved != null ? Icons.emoji_events : Icons.emoji_events_outlined,
                      color: achieved != null ? AppColors.record : null,
                    ),
                    title: Text('${s.name} · ${s.criterion}'),
                    subtitle: Text([
                      achieved != null
                          ? 'Lograda el ${formatLong(achieved)}'
                          : 'Estimada: ${_monthYear(from)} – ${_monthYear(to)} (${s.window})',
                      if (s.prereq != null && achieved == null) 'Antes: ${s.prereq}',
                    ].join('\n')),
                    isThreeLine: s.prereq != null && achieved == null,
                    onTap: () => _toggle(context, ref, s, achieved),
                  );
                }),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Élite, fuera del plan: maltese y victorian.', style: text.bodySmall),
          ),
        ],
      ),
    );
  }
}
