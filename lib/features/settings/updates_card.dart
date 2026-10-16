import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../config.dart';
import '../../data/update_service.dart';
import '../../ui/widgets.dart';

/// Actualizaciones por GitHub Releases. Plan 058 (ADR 0018): «Actualizar»
/// descarga el APK dentro de la app, comprueba su SHA-256 y abre el
/// instalador del sistema; sin manifiesto, abre la descarga como antes.
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
            if (release == null) return const Text('No hay una actualización más nueva disponible.');
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
                if (release.apkUrl != null && release.manifestUrl != null) ...[
                  FilledButton.icon(
                    key: const ValueKey('actualizar'),
                    onPressed: () => _update(context, release),
                    icon: const Icon(Icons.system_update),
                    label: const Text('Actualizar'),
                  ),
                  TextButton(
                    onPressed: () => _download(context, release.apkUrl!),
                    child: const Text('Descargar con el navegador'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: () => release.apkUrl == null
                        ? _open(context, release.pageUrl)
                        : _download(context, release.apkUrl!),
                    icon: const Icon(Icons.download),
                    label: Text(release.apkUrl == null ? 'Ver la versión en GitHub' : 'Descargar APK'),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Al instalar encima, los datos se conservan. Aun así, exporta un respaldo antes. Android te pide confirmar la instalación.'),
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

  /// Plan 058: descarga, verifica y abre el instalador sin salir de la app.
  Future<void> _update(BuildContext context, AppRelease release) async {
    if (!await UpdateInstaller.canInstall()) {
      if (!context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Permite instalar la actualización'),
          content: const Text(
              'Una sola vez: Android te va a mostrar «Instalar apps desconocidas». '
              'Activa «Permitir de esta fuente» para My Prime, vuelve y toca «Actualizar» otra vez.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Abrir el ajuste')),
          ],
        ),
      );
      if (go == true) await UpdateInstaller.openInstallPermission();
      return;
    }
    if (!context.mounted) return;
    final file = await showDialog<File?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(release: release),
    );
    if (file == null || !context.mounted) return;
    if (!await UpdateInstaller.install(file) && context.mounted) {
      showSnack(context, 'No se pudo abrir el instalador. Usa «Descargar con el navegador».');
    }
  }

  /// La descarga va en su propia tarea y la app se cierra: así, tras instalar,
  /// en recientes queda un solo "Seguimiento" (§16.13). Si el canal nativo no
  /// pudo, se abre como antes para no dejar al usuario sin actualizar.
  Future<void> _download(BuildContext context, Uri url) async {
    if (await const UpdateLauncher().openApkDownload(url)) return;
    if (context.mounted) await _open(context, url);
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

/// Plan 058: la descarga con su progreso; devuelve el APK verificado o null.
class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog({required this.release});
  final AppRelease release;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  int _received = 0;
  int? _total;
  String? _error;
  UpdateInstaller? _installer;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final cache = await getTemporaryDirectory();
      final installer = _installer = UpdateInstaller(cacheDir: cache);
      final file = await installer.download(widget.release,
          onProgress: (r, t) {
        if (mounted) {
          setState(() {
            _received = r;
            _total = t;
          });
        }
      });
      if (mounted) Navigator.pop(context, file);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _installer?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mb = (_received / 1e6).toStringAsFixed(1);
    final total = _total == null ? null : (_total! / 1e6).toStringAsFixed(1);
    return AlertDialog(
      title: Text(_error == null ? 'Descargando ${widget.release.version}' : 'No se pudo actualizar'),
      content: _error != null
          ? Text(_error!)
          : Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(
                  value: _total == null || _total == 0 ? null : _received / _total!),
              const SizedBox(height: 8),
              Text(total == null ? '$mb MB' : '$mb de $total MB'),
              const SizedBox(height: 4),
              const Text('Después se comprueba que sea el archivo publicado.'),
            ]),
      actions: [
        if (_error != null)
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    );
  }
}
