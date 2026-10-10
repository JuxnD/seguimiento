import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart' show HomeShell;
import '../../app/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../ui/widgets.dart';
import '../settings/restore_access.dart';
import 'onboarding_screen.dart';

/// Barrera de entrada (plan 022): el estado del alta vive en SQLite y decide
/// qué se monta. Mientras esté pendiente no existe HomeShell, así que no hay
/// permisos, pasos, respaldos ni avisos. Se reconsulta con cada generación de
/// la base (restaurar, incluido el rollback).
class AppEntry extends ConsumerWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listo → pendiente o inválido con la app abierta (restaurar desde
    // Ajustes): los avisos del perfil anterior se retiran y las rutas abiertas
    // sobre el shell (Ajustes, editores) se cierran, para que el alta o el
    // error queden visibles (plan 024). Listo → listo no toca la navegación.
    ref.listen<AsyncValue<SetupStatus>>(setupStatusProvider, (prev, next) {
      final wasReady = prev?.valueOrNull?.ready == true;
      final leftReady = next is AsyncError || (next is AsyncData<SetupStatus> && !next.value.ready);
      if (!wasReady || !leftReady) return;
      if (next is AsyncData<SetupStatus>) ref.read(rescheduleRemindersProvider)();
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
    return ref.watch(setupStatusProvider).when(
          // Al cambiar de base se conserva lo que había hasta saber el nuevo
          // estado: Ajustes no se desmonta por recargar.
          skipLoadingOnReload: true,
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => SetupErrorScreen(error: e),
          data: (s) => s.ready ? const HomeShell() : const OnboardingScreen(),
        );
  }
}

/// Alta con origen/estado inválidos: no se adivina, se explica y se ofrece
/// restaurar un respaldo válido.
class SetupErrorScreen extends ConsumerWidget {
  const SetupErrorScreen({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('No se puede abrir el perfil')),
        body: ListView(
          children: [
            AppCard(
              children: [
                Text('El estado del perfil guardado no es válido y la app no lo corrige sola.',
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 8),
                Text('$error'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => pickAndRestoreBackup(context, ref),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restaurar desde un respaldo'),
                ),
              ],
            ),
          ],
        ),
      );
}
