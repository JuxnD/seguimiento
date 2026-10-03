import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/photo_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../ui/widgets.dart';

/// Fotos de progreso y comparador lado a lado. Es lo que más motiva a largo
/// plazo: la báscula se mueve poco, la foto no miente.
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  @override
  void initState() {
    super.initState();
    _recoverLostPhoto();
  }

  PhotoAngle _angle = PhotoAngle.frente;

  @override
  Widget build(BuildContext context) {
    final checkIns = ref.watch(photoCheckInsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Fotos de progreso')),
      body: checkIns.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            AppCard(
              children: [
                SegmentedButton<PhotoAngle>(
                  segments: [
                    for (final a in PhotoAngle.values) ButtonSegment(value: a, label: Text(a.label)),
                  ],
                  selected: {_angle},
                  onSelectionChanged: (s) => setState(() => _angle = s.first),
                ),
              ],
            ),
            if (list.where((c) => c.byAngle.containsKey(_angle)).length >= 2)
              _Comparator(
                checkIns: list.where((c) => c.byAngle.containsKey(_angle)).toList(),
                angle: _angle,
              ),
            AppCard(
              title: 'Tomas',
              children: [
                if (list.isEmpty)
                  const EmptyHint('Sin fotos todavía. La primera es la línea base.')
                else
                  for (final c in list) _CheckInRow(checkIn: c),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _capture,
        icon: const Icon(Icons.add_a_photo),
        label: Text(_angle.label),
      ),
    );
  }

  Future<void> _capture() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text('Tomar foto de ${_angle.label.toLowerCase()}'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
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
      // Permiso de cámara negado o sin cámara: se dice, no se revienta.
      if (mounted) showSnack(context, 'No se pudo abrir la cámara o la galería: $e');
      return;
    }
    if (picked == null || !mounted) return;
    await _save(File(picked.path));
  }

  Future<void> _save(File file) => guarded(
        context,
        () => ref.read(photoRepositoryProvider).add(source: file, date: dateOnly(DateTime.now()), angle: _angle),
        ok: 'Foto de ${_angle.label.toLowerCase()} guardada',
      );

  /// Si Android cerró la app mientras la cámara estaba abierta, la foto no se
  /// pierde: al volver se recupera y se guarda.
  Future<void> _recoverLostPhoto() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      final file = lost.file;
      if (lost.isEmpty || file == null || !mounted) return;
      await _save(File(file.path));
    } on Object {
      // Nada que recuperar.
    }
  }
}

/// Dos fechas, el mismo ángulo, lado a lado.
class _Comparator extends ConsumerStatefulWidget {
  const _Comparator({required this.checkIns, required this.angle});

  final List<PhotoCheckIn> checkIns;
  final PhotoAngle angle;

  @override
  ConsumerState<_Comparator> createState() => _ComparatorState();
}

class _ComparatorState extends ConsumerState<_Comparator> {
  late DateTime _left = widget.checkIns.last.date;
  late DateTime _right = widget.checkIns.first.date;

  @override
  void didUpdateWidget(_Comparator old) {
    super.didUpdateWidget(old);
    if (old.angle != widget.angle) {
      _left = widget.checkIns.last.date;
      _right = widget.checkIns.first.date;
    }
  }

  /// La foto de ese ángulo en esa fecha, o null: nunca se muestra otra en
  /// su lugar (§16.11).
  ProgressPhotoRow? _photo(DateTime date) {
    for (final c in widget.checkIns) {
      if (dayKey(c.date) == dayKey(date)) return c.byAngle[widget.angle];
    }
    return null;
  }

  bool _exists(DateTime date) => widget.checkIns.any((c) => dayKey(c.date) == dayKey(date));

  @override
  Widget build(BuildContext context) {
    // Si se borró la toma elegida, el desplegable quedaría con un valor que
    // no está en la lista (assertion en debug, vacío en release).
    if (!_exists(_left)) _left = widget.checkIns.last.date;
    if (!_exists(_right)) _right = widget.checkIns.first.date;
    final days = daysBetween(_left, _right);
    return AppCard(
      title: 'Comparar',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _side(_left, (d) => setState(() => _left = d))),
            const SizedBox(width: 8),
            Expanded(child: _side(_right, (d) => setState(() => _right = d))),
          ],
        ),
        if (days != 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('${days.abs()} días entre las dos',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _side(DateTime date, ValueChanged<DateTime> onChanged) {
    final photo = _photo(date);
    return Column(
      children: [
        DropdownButton<String>(
          isExpanded: true,
          value: dayKey(date),
          items: [
            for (final c in widget.checkIns)
              DropdownMenuItem(value: dayKey(c.date), child: Text(formatLong(c.date))),
          ],
          onChanged: (v) => v == null ? null : onChanged(parseDay(v)),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: photo == null
              ? ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: Text('Sin foto de ${widget.angle.label.toLowerCase()} ese día',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  ),
                )
              : GestureDetector(onTap: () => openPhoto(context, photo), child: _PhotoView(row: photo)),
        ),
      ],
    );
  }
}

class _CheckInRow extends ConsumerWidget {
  const _CheckInRow({required this.checkIn});

  final PhotoCheckIn checkIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatLong(checkIn.date), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final angle in PhotoAngle.values)
                  if (checkIn.byAngle[angle] != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => openPhoto(context, checkIn.byAngle[angle]!),
                        onLongPress: () => openPhoto(context, checkIn.byAngle[angle]!),
                        child: Semantics(
                          label: 'Foto de ${angle.label.toLowerCase()} del ${formatLong(checkIn.date)}. '
                              'Tócala para verla, borrarla o cambiar su tipo o fecha.',
                          image: true,
                          child: AspectRatio(
                            aspectRatio: 3 / 4,
                            child: _PhotoView(row: checkIn.byAngle[angle]!, caption: angle.label),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openPhoto(BuildContext context, ProgressPhotoRow row) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => _PhotoScreen(row: row)));

/// Una foto en grande, con su menú: eliminar, cambiar tipo, cambiar fecha
/// (§16.11). Caso real: una espalda subida como perfil arruinaba la
/// comparación de perfil.
class _PhotoScreen extends ConsumerWidget {
  const _PhotoScreen({required this.row});

  final ProgressPhotoRow row;

  String get _what => '${row.angle.label} del ${formatShort(parseDay(row.date))}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_what),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            onSelected: (v) => switch (v) {
              'tipo' => _changeAngle(context, ref),
              'fecha' => _changeDate(context, ref),
              _ => _delete(context, ref),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'tipo', child: Text('Cambiar tipo')),
              PopupMenuItem(value: 'fecha', child: Text('Cambiar fecha')),
              PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
            ],
          ),
        ],
      ),
      body: Center(child: InteractiveViewer(child: _PhotoView(row: row))),
    );
  }

  /// Si el destino ya tiene foto, pregunta antes de reemplazarla.
  Future<bool> _confirmReplace(BuildContext context, WidgetRef ref, PhotoAngle angle, DateTime date) async {
    final taken = await ref.read(photoRepositoryProvider).occupant(date, angle, except: row.id);
    if (taken == null || !context.mounted) return taken == null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ya hay foto de ${angle.label.toLowerCase()} el ${formatShort(date)}'),
        content: const Text('Si sigues, esta la reemplaza y la otra se borra.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reemplazar')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _changeAngle(BuildContext context, WidgetRef ref) async {
    final angle = await showDialog<PhotoAngle>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Tipo de foto'),
        children: [
          for (final a in PhotoAngle.values)
            RadioListTile<PhotoAngle>(
              value: a,
              groupValue: row.angle,
              title: Text(a.label),
              onChanged: (v) => Navigator.pop(c, v),
            ),
        ],
      ),
    );
    if (angle == null || angle == row.angle || !context.mounted) return;
    final replace = await _confirmReplace(context, ref, angle, parseDay(row.date));
    if (!replace || !context.mounted) return;
    final ok = await guarded(context, () => ref.read(photoRepositoryProvider).reclassify(row, angle: angle),
        ok: 'Ahora es de ${angle.label.toLowerCase()}');
    if (ok && context.mounted) Navigator.pop(context);
  }

  Future<void> _changeDate(BuildContext context, WidgetRef ref) async {
    final date = await showDatePicker(
      context: context,
      initialDate: parseDay(row.date),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Fecha de la foto',
    );
    if (date == null || dayKey(date) == row.date || !context.mounted) return;
    final replace = await _confirmReplace(context, ref, row.angle, date);
    if (!replace || !context.mounted) return;
    final ok = await guarded(context, () => ref.read(photoRepositoryProvider).reclassify(row, date: dateOnly(date)),
        ok: 'Movida al ${formatShort(date)}');
    if (ok && context.mounted) Navigator.pop(context);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Eliminar foto de $_what?'),
        content: const Text('Se puede deshacer durante 5 segundos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final repo = ref.read(photoRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final removed = await guarded(context, () => repo.remove(row), failure: 'No se pudo borrar');
    if (!removed || !context.mounted) return;
    Navigator.pop(context);
    var undone = false;
    // El archivo se borra cuando el aviso se va sin "Deshacer".
    messenger.hideCurrentSnackBar();
    unawaited(messenger.showSnackBar(SnackBar(
        content: Text('Foto de $_what eliminada'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            undone = true;
            repo.restore(row);
          },
        ),
      )).closed.then((_) {
        if (!undone) repo.purgeFile(row);
      }));
  }
}

class _PhotoView extends ConsumerWidget {
  const _PhotoView({required this.row, this.caption});

  final ProgressPhotoRow row;
  final String? caption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El directorio se resuelve una vez para toda la app: antes cada rebuild
    // creaba un Future nuevo y la foto parpadeaba en negro.
    final base = ref.watch(documentsDirProvider).valueOrNull;
    if (base == null) return const ColoredBox(color: Colors.black26);
    final file = PhotoRepository.fileIn(base, row);
    return Builder(
      builder: (context) {
        if (!file.existsSync()) {
          return const ColoredBox(
            color: Colors.black26,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(file, fit: BoxFit.cover),
              if (caption != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(caption!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
