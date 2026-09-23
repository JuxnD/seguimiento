import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database_host.dart';
import '../domain/dates.dart';
import '../ui/theme.dart';

/// Pantalla de último recurso cuando la app no logra arrancar. Dice qué pasó
/// y, si la base alcanzó a abrir, permite exportarla antes de tocar nada más.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error, this.host});

  final Object error;
  final DatabaseHost? host;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildGymTheme(),
        home: _StartupErrorScreen(error: error, host: host),
      );
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error, this.host});

  final Object error;
  final DatabaseHost? host;

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'seguimiento-rescate-${dayKey(DateTime.now())}.sqlite');
      final file = await host!.exportTo(path);
      await Share.shareXFiles([XFile(file.path)], subject: 'Respaldo Seguimiento (rescate)');
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Seguimiento no pudo arrancar')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Algo falló al abrir la app. Tus datos no se han borrado.'),
            const SizedBox(height: 12),
            SelectableText('$error', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (host != null) ...[
              const Text('La base sí abrió: expórtala antes de reinstalar o actualizar.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _export(context),
                icon: const Icon(Icons.save_alt),
                label: const Text('Exportar base de datos'),
              ),
            ] else
              const Text('La base no abrió. Actualiza la app o restaura un respaldo desde Ajustes '
                  'cuando vuelva a abrir.'),
          ],
        ),
      );
}
