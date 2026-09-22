import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../config.dart';
import '../../data/update_service.dart';
import '../../ui/widgets.dart';

/// Actualizaciones por GitHub Releases: la app avisa y abre la descarga en el
/// navegador. No instala nada por su cuenta.
class UpdatesCard extends ConsumerWidget {
  const UpdatesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider);
    final check = ref.watch(updateCheckProvider);

    return AppCard(
      title: 'Actualizaciones',
      trailing: IconButton(
        tooltip: 'Buscar ahora',
        icon: const Icon(Icons.refresh),
        onPressed: () => ref.invalidate(updateCheckProvider),
      ),
      children: [
        Text('Versión instalada: ${version.value ?? '…'}'),
        const SizedBox(height: 8),
        check.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('No se pudo consultar: $e'),
          data: (result) {
            if (result.error != null) return Text(result.error!);
            final release = result.release;
            if (release == null) return const Text('Estás en la última versión publicada.');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Hay una versión nueva: ${release.version}',
                    style: Theme.of(context).textTheme.titleSmall),
                if (release.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(release.notes),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _open(context, release.apkUrl ?? release.pageUrl),
                  icon: const Icon(Icons.download),
                  label: Text(release.apkUrl == null ? 'Ver la versión en GitHub' : 'Descargar APK'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Al instalar encima, los datos se conservan. Aun así, exporta un respaldo antes.'),
                ),
              ],
            );
          },
        ),
        if (!updatesConfigured)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Compilada sin repositorio de GitHub configurado.'),
          ),
      ],
    );
  }

  Future<void> _open(BuildContext context, Uri url) async {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'No se pudo abrir $url');
  }
}

/// Aviso discreto en la pantalla Hoy. Silencioso si no hay novedad o falla.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(updateCheckProvider);
    final UpdateCheck? result = check.value;
    if (result == null || !result.hasUpdate) return const SizedBox.shrink();
    return AppCard(
      children: [
        Row(
          children: [
            const Icon(Icons.system_update),
            const SizedBox(width: 12),
            Expanded(child: Text('Versión ${result.release!.version} disponible')),
            TextButton(onPressed: onOpenSettings, child: const Text('Ver')),
          ],
        ),
      ],
    );
  }
}
