import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/corrections_29sep.dart';
import '../../data/history_import.dart' show corrections7Oct;
import '../../data/local_flags.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Estado de las correcciones del 29 sep. Se recalcula al aplicar.
final correctionsProvider = FutureProvider<Map<String, CorrectionState>>(
    (ref) => checkCorrections(ref.watch(databaseProvider)));

/// Cuántas faltan por aplicar, sin contar los grupos que el usuario dijo que
/// no quiere.
final pendingCorrectionsProvider = Provider<int>((ref) {
  final flags = ref.watch(localFlagsProvider);
  final states = ref.watch(correctionsProvider).valueOrNull ?? const {};
  int pending(List<DataCorrection> list, String dismissedKey) => flags.get<bool>(dismissedKey) == true
      ? 0
      : list.where((c) => states[c.id] == CorrectionState.pending).length;
  return pending(corrections29Sep, FlagKeys.corrections29SepDismissed) +
      pending(corrections5Oct, FlagKeys.corrections5OctDismissed) +
      pending(corrections7Oct, FlagKeys.corrections7OctDismissed);
});

Future<void> openCorrections(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CorrectionsScreen()));

/// Las correcciones de datos del traspaso del 29 sep (§17), una por una, con
/// qué se encontró. Nada se toca hasta confirmar, y antes se hace un respaldo.
class CorrectionsScreen extends ConsumerWidget {
  const CorrectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = ref.watch(correctionsProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Correcciones del traspaso')),
      body: states.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (map) {
          final pending = map.values.where((s) => s == CorrectionState.pending).length;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              AppCard(
                children: [
                  Text(
                    'Registros que el traspaso pidió corregir. Cada uno se aplica solo si sigue tal cual lo '
                    'describe: si ya lo corregiste a mano o no existe, no se toca.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Antes de aplicar se guarda un respaldo automático (Ajustes › Respaldo).',
                      style: text.bodySmall),
                ],
              ),
              AppCard(
                children: [
                  for (final c in allCorrections)
                    _CorrectionTile(correction: c, state: map[c.id] ?? CorrectionState.missing),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: pending == 0 ? null : () => _apply(context, ref, pending),
                  icon: const Icon(Icons.done_all),
                  label: Text(pending == 0
                      ? 'Nada pendiente'
                      : 'Aplicar $pending ${pending == 1 ? 'corrección' : 'correcciones'}'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref, int pending) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Aplicar las correcciones?'),
        content: Text('Se cambian $pending ${pending == 1 ? 'registro' : 'registros'} de sesiones, comidas, peso y pasos. '
            'Antes se guarda un respaldo para poder volver atrás.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    var applied = 0;
    final done = await guarded(context, () async {
      final backup = await ref.read(autoBackupProvider.future);
      if (await backup.runNow() == null) throw StateError('No se pudo guardar el respaldo: no se aplicó nada.');
      applied = await applyPendingCorrections(ref.read(databaseProvider));
    });
    ref.invalidate(correctionsProvider);
    ref.invalidate(dashboardProvider);
    if (done && context.mounted) {
      showSnack(context, '$applied ${applied == 1 ? 'corrección aplicada' : 'correcciones aplicadas'}');
    }
  }
}

class _CorrectionTile extends StatelessWidget {
  const _CorrectionTile({required this.correction, required this.state});

  final DataCorrection correction;
  final CorrectionState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (state) {
      CorrectionState.pending => (Icons.edit_note, scheme.primary, 'Por aplicar'),
      CorrectionState.done => (Icons.check_circle, AppColors.body, 'Ya está'),
      CorrectionState.missing => (Icons.help_outline, scheme.onSurfaceVariant, 'No se encontró tal cual: no se toca'),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text('${correction.date} · ${correction.title}'),
      subtitle: Text('${correction.change}\n$label'),
      isThreeLine: true,
    );
  }
}
