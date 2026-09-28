import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../data/repositories/exercise_photo_repository.dart';
import '../../ui/exercise_figure.dart';
import '../../ui/widgets.dart';

/// Técnica de un ejercicio en el momento de hacerlo: la figura con los
/// momentos clave, el músculo que trabaja, las claves, la progresión, la foto
/// de referencia del usuario y el enlace al video.
Future<void> showTechniqueSheet(
  BuildContext context, {
  required String exercise,
  List<String> cues = const [],
  String? progressionNote,
  String? mediaUrl,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) => TechniqueContent(
          exercise: exercise,
          cues: cues,
          progressionNote: progressionNote,
          mediaUrl: mediaUrl,
          controller: controller,
        ),
      ),
    );

class TechniqueContent extends StatelessWidget {
  const TechniqueContent({
    super.key,
    required this.exercise,
    this.cues = const [],
    this.progressionNote,
    this.mediaUrl,
    this.controller,
  });

  final String exercise;
  final List<String> cues;
  final String? progressionNote;
  final String? mediaUrl;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final url = mediaUrl == null ? null : Uri.tryParse(mediaUrl!);
    return SafeArea(
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(exercise, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          ExerciseArtView(exercise: exercise),
          const SizedBox(height: 16),
          for (final (i, cue) in cues.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 24, child: Text('${i + 1}.', style: text.titleMedium)),
                  Expanded(child: Text(cue, style: text.bodyLarge)),
                ],
              ),
            ),
          if (progressionNote != null) ...[
            const SizedBox(height: 4),
            Text('Progresión', style: text.labelLarge),
            Text(progressionNote!, style: text.bodyMedium),
          ],
          const SizedBox(height: 16),
          ExerciseReferencePhoto(exercise: exercise),
          if (url != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => launchUrl(url, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Ver video de referencia'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Foto de referencia de un ejercicio (null si no hay).
final exercisePhotoProvider = StreamProvider.family(
  (ref, String exercise) => ref.watch(exercisePhotoRepositoryProvider).watch(exercise),
);

/// La foto que el usuario guardó para este ejercicio, o el botón para
/// añadirla (cámara o galería). Tocarla la abre completa y con zoom.
class ExerciseReferencePhoto extends ConsumerWidget {
  const ExerciseReferencePhoto({super.key, required this.exercise});

  final String exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final row = ref.watch(exercisePhotoProvider(exercise)).valueOrNull;
    final base = ref.watch(documentsDirProvider).valueOrNull;
    final file = row == null || base == null ? null : ExercisePhotoRepository.fileIn(base, row);

    final header = Row(
      children: [
        Expanded(child: Text('TU FOTO DE REFERENCIA', style: text.labelMedium?.copyWith(letterSpacing: 0.6))),
        if (file != null) ...[
          TextButton(onPressed: () => _pick(context, ref), child: const Text('Cambiar')),
          IconButton(
            tooltip: 'Quitar foto',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDelete(context, 'la foto de referencia')) {
                if (!context.mounted) return;
                await guarded(context, () => ref.read(exercisePhotoRepositoryProvider).remove(exercise));
              }
            },
          ),
        ],
      ],
    );

    if (file == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => _pick(context, ref),
            child: Row(
              children: [
                Icon(Icons.add_a_photo_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Añadir foto', style: text.titleSmall),
                      Text('Una captura de un video o una foto tuya bien hecha', style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _open(context, file),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              file,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 90,
                alignment: Alignment.center,
                color: scheme.surfaceContainerHighest,
                child: const Text('No se encontró la foto: vuelve a añadirla'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería (una captura de video sirve)'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    } on Object catch (e) {
      // Permiso negado o sin cámara: se dice, no se revienta.
      if (context.mounted) showSnack(context, 'No se pudo abrir la cámara o la galería: $e');
      return;
    }
    if (picked == null || !context.mounted) return;
    await guarded(
      context,
      () => ref.read(exercisePhotoRepositoryProvider).save(exercise, File(picked!.path)),
      ok: 'Foto guardada',
    );
  }

  void _open(BuildContext context, File file) => showDialog<void>(
        context: context,
        builder: (c) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(child: InteractiveViewer(maxScale: 5, child: Center(child: Image.file(file)))),
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(c),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
