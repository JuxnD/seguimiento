import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/widgets.dart';
import 'training_screen.dart';

/// Aviso de sesión sin terminar: Android cerró la app a mitad del cronómetro.
/// Un toque la retoma donde iba; nada se pierde.
class ActiveSessionBanner extends ConsumerWidget {
  const ActiveSessionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSessionProvider).valueOrNull;
    if (session == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // Fondo oscuro con borde de acento: sobre el contenedor naranja,
    // "Descartar" (texto naranja) y "Retomar" (botón naranja) no se veían.
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sesión sin terminar: empezó ${describeActiveSession(session)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    if (!await confirmDelete(context, 'la sesión sin terminar')) return;
                    await ref.read(activeSessionStoreProvider).clear();
                    ref.invalidate(activeSessionProvider);
                  },
                  child: const Text('Descartar'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => resumeActiveSession(context, ref, session),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Retomar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
