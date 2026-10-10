import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../data/backup_archive.dart';
import '../../data/database_host.dart';
import '../../ui/widgets.dart';

/// Acceso común a la restauración (plan 022): Ajustes y el alta usan el mismo
/// parser (BackupArchive), la misma validación previa (DatabaseHost, también
/// del alta) y la misma reversión. Aquí sólo viven el selector, la
/// confirmación y el progreso.

/// Elige un archivo y lo restaura. true si la base quedó reemplazada.
Future<bool> pickAndRestoreBackup(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.platform.pickFiles(withData: false);
  final path = picked?.files.single.path;
  if (path == null || !context.mounted) return false;
  return restoreBackupFile(context, ref, File(path), p.basename(path));
}

/// Verifica, pide confirmación explícita (borra lo registrado desde ese
/// respaldo) y restaura. true si la base quedó reemplazada.
Future<bool> restoreBackupFile(BuildContext context, WidgetRef ref, File file, String label) async {
  PreparedBackup? prepared;
  var replaced = false;
  var restored = false;
  try {
    final archive =
        BackupArchive(host: ref.read(databaseHostProvider), documents: await ref.read(documentsDirProvider.future));
    if (!context.mounted) return false;
    final ready = await _progress(context, 'Verificando respaldo', () => archive.prepare(file));
    prepared = ready;
    if (!context.mounted) return false;
    final legacy = ready.legacy;
    final missing = ready.missingPhotos.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('¿Restaurar este respaldo?'),
        content: Text('Respaldo: $label\n\n'
            'Se reemplaza la base actual: perfil, plan, sesiones, comidas, medidas, catálogos e historial de IA '
            '(preguntas, respuestas y contexto) por lo guardado en el respaldo. '
            'Pueden reaparecer conversaciones que borraste después de esa copia. '
            '${legacy ? 'Es un respaldo antiguo: NO contiene fotos. Las fotos actuales se conservan.' : 'Se reemplazan también las fotos actuales por las ${ready.photoCount} fotos del ZIP.'}\n\n'
            '${missing == 0 ? '' : 'RESPALDO INCOMPLETO: $missing fotos ya faltaban al exportarlo y no se pueden recuperar.\n\n'}'
            'El cronómetro en curso, los permisos y la licencia no cambian. '
            'El respaldo es un archivo sin cifrar.\n\n'
            'Esto no se puede deshacer.\n\n'
            'Si lo de ahora te sirve, exporta primero.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    replaced = true;
    await _progress(context, 'Restaurando respaldo', () => archive.restore(ready, allowMissingPhotos: true));
    restored = true;
    if (context.mounted) {
      showSnack(
          context,
          legacy
              ? 'Registros restaurados; fotos actuales conservadas'
              : 'Registros y ${ready.photoCount} fotos restaurados${missing == 0 ? '' : '; $missing fotos faltantes'}');
    }
  } on RestoreException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  } on Object catch (e) {
    if (context.mounted) showSnack(context, 'No se pudo restaurar: $e');
  } finally {
    // Siempre: aunque falle, la conexión pudo cerrarse y reabrirse en el
    // rollback. Sin esto, repositorios y streams quedan sobre la vieja.
    if (replaced) ref.read(databaseGenerationProvider.notifier).state++;
    await prepared?.dispose();
  }
  return restored;
}

Future<T> _progress<T>(BuildContext context, String title, Future<T> Function() action) async {
  final navigator = Navigator.of(context);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: const Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Espera mientras verificamos los archivos.'))
        ]),
      ),
    ),
  ));
  try {
    return await action();
  } finally {
    navigator.pop();
  }
}
