import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../domain/ai_context.dart';
import '../ai/ai_conversation_screen.dart';
import '../../data/exercise_details.dart';
import '../../data/repositories/exercise_photo_repository.dart';
import '../../domain/band_guide.dart';
import '../../domain/search.dart';
import '../../ui/exercise_figure_3d_view.dart';
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
  String? anchor,
  String? grip,
  bool? loaded,
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
          anchor: anchor,
          grip: grip,
          loaded: loaded,
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
    this.anchor,
    this.grip,
    this.loaded,
  });

  final String exercise;
  final List<String> cues;
  final String? progressionNote;
  final String? mediaUrl;
  final ScrollController? controller;

  /// Anclaje de la banda ('alto', 'medio', 'bajo', 'manos'); null sin banda.
  final String? anchor;

  /// Variante que pide la sesión: agarre ('supina') y si lleva carga
  /// externa. null = sin contexto (desde el catálogo): la guía completa.
  final String? grip;
  final bool? loaded;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final url = mediaUrl == null ? null : Uri.tryParse(mediaUrl!);
    // La guía fija y las claves personales se complementan. No se oculta
    // lo que conserva el catálogo, ni se repite una clave idéntica.
    final detail = exerciseDetail(exercise);
    final steps = _uniqueCues(detail?.stepsFor(loaded: loaded) ?? cues);
    final personal =
        detail == null ? const <String>[] : _uniqueCues(cues, excluding: steps);
    final easier = detail?.easierFor(loaded: loaded);
    return SafeArea(
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(exercise,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (detail != null) Text(detail.muscles, style: text.bodyMedium),
          const SizedBox(height: 14),
          ExerciseFigureView(exercise: exercise, grip: grip, loaded: loaded),
          const SizedBox(height: 16),
          if (detail != null) Text('Cómo hacerlo', style: text.titleSmall),
          if (detail != null) const SizedBox(height: 6),
          for (final (i, cue) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 24,
                      child: Text('${i + 1}.', style: text.titleMedium)),
                  Expanded(child: Text(cue, style: text.bodyLarge)),
                ],
              ),
            ),
          if (personal.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Claves personales', style: text.titleSmall),
            const SizedBox(height: 6),
            for (final cue in personal)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(cue, style: text.bodyLarge)),
          ],
          if (detail?.note case final note?) ...[
            const SizedBox(height: 4),
            Text(note,
                style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          if (detail != null && detail.mistakes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Errores comunes', style: text.titleSmall),
            for (final m in detail.mistakes)
              Text('• $m', style: text.bodyMedium),
          ],
          if (easier != null || detail?.harder != null) ...[
            const SizedBox(height: 12),
            if (easier case final easy?)
              _Scale(title: 'Más fácil', body: easy, icon: Icons.south),
            if (easier != null && detail?.harder != null)
              const SizedBox(height: 8),
            if (detail?.harder case final hard?)
              _Scale(title: 'Más difícil', body: hard, icon: Icons.north),
          ],
          if (progressionNote != null) ...[
            const SizedBox(height: 12),
            Text('Progresión', style: text.labelLarge),
            Text(progressionNote!, style: text.bodyMedium),
          ],
          if (bandAnchors[anchor] case (final title, final how)) ...[
            const SizedBox(height: 12),
            Text('Banda: $title', style: text.labelLarge),
            Text(how, style: text.bodyMedium),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showBandGuide(context),
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('Guía completa de la banda'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Consumer(builder: (context, ref, _) {
            final guideText = _guideSnapshotText(
              exercise: exercise,
              muscles: detail?.muscles,
              steps: steps,
              personal: personal,
              note: detail?.note,
              mistakes: detail?.mistakes ?? const [],
              easier: easier,
              harder: detail?.harder,
              progression: progressionNote,
              anchor: anchor,
              grip: grip,
              loaded: loaded,
            );
            return OutlinedButton.icon(
              onPressed: () {
                late final AiConversationSnapshot snapshot;
                try {
                  snapshot = AiConversationSnapshot(
                    kind: AiConversationKind.exerciseQuestion,
                    title: 'Guía · $exercise',
                    sources: [
                      AiContextSource(
                          id: 'exercise_guide:${nameKey(exercise)}',
                          title: 'Guía seleccionada · $exercise',
                          text: guideText)
                    ],
                    model: aiQuestionModel,
                    contractVersion: aiQuestionContractVersion,
                  );
                } on FormatException {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Esta guía supera el límite de consulta. Puedes seguir usando la guía sin IA.')));
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AiConversationScreen.forQuestion(
                      repository: ref.read(aiConversationRepositoryProvider),
                      snapshot: snapshot,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.question_answer_outlined),
              label: const Text('Preguntar sobre esta guía'),
            );
          }),
          const SizedBox(height: 16),
          ExerciseReferencePhoto(exercise: exercise),
          if (url != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  launchUrl(url, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.play_circle_outline),
              label: Text(url.queryParameters.containsKey('search_query') ||
                      url.path == '/search'
                  ? 'Buscar demostración'
                  : 'Ver video de referencia'),
            ),
          ],
        ],
      ),
    );
  }
}

String _guideSnapshotText({
  required String exercise,
  required String? muscles,
  required List<String> steps,
  required List<String> personal,
  required String? note,
  required List<String> mistakes,
  required String? easier,
  required String? harder,
  required String? progression,
  required String? anchor,
  required String? grip,
  required bool? loaded,
}) =>
    [
      'Ejercicio: $exercise.',
      if (muscles != null) 'Músculos: $muscles.',
      'Figura: $exercise${grip == null ? '' : ', agarre $grip'}${loaded == null ? '' : loaded ? ', con carga' : ', sin carga'}.',
      if (steps.isNotEmpty)
        'Cómo hacerlo:\n${steps.indexed.map((entry) => '${entry.$1 + 1}. ${entry.$2}').join('\n')}',
      if (personal.isNotEmpty) 'Claves personales:\n${personal.join('\n')}',
      if (note != null) 'Nota: $note',
      if (mistakes.isNotEmpty)
        'Errores comunes:\n${mistakes.map((text) => '• $text').join('\n')}',
      if (easier != null) 'Más fácil: $easier',
      if (harder != null) 'Más difícil: $harder',
      if (progression != null) 'Progresión: $progression',
      if (bandAnchors[anchor] case (final title, final how))
        'Banda: $title. $how',
    ].join('\n\n');

List<String> _uniqueCues(List<String> cues,
    {List<String> excluding = const []}) {
  String key(String cue) => nameKey(cue.trim().replaceAll(RegExp(r'\s+'), ' '));
  final seen = excluding.map(key).toSet();
  return [
    for (final cue in cues)
      if (cue.trim().isNotEmpty && seen.add(key(cue))) cue.trim()
  ];
}

/// "Más fácil" / "Más difícil" de la guía v3.1.
class _Scale extends StatelessWidget {
  const _Scale({required this.title, required this.body, required this.icon});

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Expanded(child: Text(title, style: text.labelLarge))
          ]),
          const SizedBox(height: 4),
          Text(body, style: text.bodySmall),
        ],
      ),
    );
  }
}

/// Guía de la banda elástica (§18.7): los tres anclajes, la tensión y la
/// seguridad.
Future<void> showBandGuide(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('La banda elástica',
                  style:
                      text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final (title, how) in bandAnchors.values) ...[
                Text(title, style: text.titleSmall),
                Text(how, style: text.bodyMedium),
                const SizedBox(height: 10),
              ],
              Text('Tensión', style: text.titleSmall),
              Text(bandTension, style: text.bodyMedium),
              const SizedBox(height: 10),
              Text('Seguridad', style: text.titleSmall),
              for (final s in bandSafety) Text('• $s', style: text.bodyMedium),
            ],
          ),
        );
      },
    );

/// Foto de referencia de un ejercicio (null si no hay).
final exercisePhotoProvider = StreamProvider.family(
  (ref, String exercise) =>
      ref.watch(exercisePhotoRepositoryProvider).watch(exercise),
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
    final file = row == null || base == null
        ? null
        : ExercisePhotoRepository.fileIn(base, row);

    final header = Row(
      children: [
        Expanded(
            child: Text('TU FOTO DE REFERENCIA',
                style: text.labelMedium?.copyWith(letterSpacing: 0.6))),
        if (file != null) ...[
          TextButton(
              onPressed: () => _pick(context, ref),
              child: const Text('Cambiar')),
          IconButton(
            tooltip: 'Quitar foto',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDelete(context, 'la foto de referencia')) {
                if (!context.mounted) return;
                await guarded(
                    context,
                    () => ref
                        .read(exercisePhotoRepositoryProvider)
                        .remove(exercise));
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
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
                      Text('Una captura de un video o una foto tuya bien hecha',
                          style: text.bodySmall),
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
              title: const Text(
                  'Elegir de la galería (una captura de video sirve)'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? picked;
    try {
      picked = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    } on Object catch (e) {
      // Permiso negado o sin cámara: se dice, no se revienta.
      if (context.mounted) {
        showSnack(context, 'No se pudo abrir la cámara o la galería: $e');
      }
      return;
    }
    if (picked == null || !context.mounted) return;
    await guarded(
      context,
      () => ref
          .read(exercisePhotoRepositoryProvider)
          .save(exercise, File(picked!.path)),
      ok: 'Foto guardada',
    );
  }

  void _open(BuildContext context, File file) => showDialog<void>(
        context: context,
        builder: (c) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                  child: InteractiveViewer(
                      maxScale: 5, child: Center(child: Image.file(file)))),
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
