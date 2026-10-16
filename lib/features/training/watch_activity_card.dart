import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../data/database.dart' show WatchActivityRow;
import '../../data/watch_ocr.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/watch_capture.dart';
import '../../ui/widgets.dart';

/// Plan 058 (§16.17): elige una captura del reloj, la lee en el teléfono y
/// devuelve lo leído para confirmarlo. null si se canceló.
Future<WatchReading?> readWatchCapture(BuildContext context, WidgetRef ref,
    {bool vitals = false}) async {
  final picked = await ImagePicker()
      .pickImage(source: ImageSource.gallery, maxWidth: 2200);
  if (picked == null || !context.mounted) return null;
  String text;
  try {
    text = await ref.read(watchTextReaderProvider).read(picked.path);
  } on Object {
    if (context.mounted) {
      showSnack(context, 'No se pudo leer la captura: escribe los datos a mano');
    }
    text = '';
  }
  if (!context.mounted) return null;
  final read = parseWatchText(text);
  if (read.isEmpty && context.mounted) {
    showSnack(context, 'No se reconoció ningún dato: escríbelos a mano');
  }
  return editWatchReading(context, initial: read, vitals: vitals);
}

/// El formulario para confirmar o escribir los datos del reloj.
Future<WatchReading?> editWatchReading(BuildContext context,
        {WatchReading? initial, bool vitals = false}) =>
    showDialog<WatchReading>(
      context: context,
      builder: (_) => _WatchReadingDialog(
          initial: initial ?? WatchReading(), vitals: vitals),
    );

class _WatchReadingDialog extends StatefulWidget {
  const _WatchReadingDialog({required this.initial, required this.vitals});

  final WatchReading initial;

  /// Sólo presión y SpO₂ (desde Cuerpo).
  final bool vitals;

  @override
  State<_WatchReadingDialog> createState() => _WatchReadingDialogState();
}

class _WatchReadingDialogState extends State<_WatchReadingDialog> {
  late final r = widget.initial;
  late final _fields = <String, TextEditingController>{
    'kind': TextEditingController(text: r.kind ?? ''),
    'start': TextEditingController(text: r.startTime ?? ''),
    'duration': TextEditingController(
        text: r.durationSec == null ? '' : formatDuration(r.durationSec!)),
    'avg': TextEditingController(text: r.avgHr?.toString() ?? ''),
    'max': TextEditingController(text: r.maxHr?.toString() ?? ''),
    'kcal': TextEditingController(text: r.kcal?.toString() ?? ''),
    'steps': TextEditingController(text: r.steps?.toString() ?? ''),
    'km': TextEditingController(
        text: r.distanceM == null ? '' : fmtDec(r.distanceM! / 1000)),
    'sys': TextEditingController(text: r.systolic?.toString() ?? ''),
    'dia': TextEditingController(text: r.diastolic?.toString() ?? ''),
    'spo2': TextEditingController(text: r.spo2?.toString() ?? ''),
  };
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(String key) => int.tryParse(_fields[key]!.text.trim());

  int? _duration() {
    final t = _fields['duration']!.text.trim();
    if (t.isEmpty) return null;
    final parts = t.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return -1;
    return switch (parts.length) {
      1 => parts[0]! * 60,
      2 => parts[0]! * 60 + parts[1]!,
      3 => parts[0]! * 3600 + parts[1]! * 60 + parts[2]!,
      _ => -1,
    };
  }

  void _save() {
    final km = double.tryParse(_fields['km']!.text.trim().replaceAll(',', '.'));
    final start = _fields['start']!.text.trim();
    final out = WatchReading(
      kind: _fields['kind']!.text.trim().isEmpty ? null : _fields['kind']!.text.trim(),
      startTime: RegExp(r'^\d{1,2}:\d{2}$').hasMatch(start)
          ? start.padLeft(5, '0')
          : null,
      durationSec: _duration(),
      avgHr: _int('avg'),
      maxHr: _int('max'),
      kcal: _int('kcal'),
      steps: _int('steps'),
      distanceM: km == null ? null : (km * 1000).round(),
      systolic: _int('sys'),
      diastolic: _int('dia'),
      spo2: _int('spo2'),
    );
    final problem = out.durationSec == -1
        ? 'Duración: usa mm:ss o h:mm:ss'
        : watchReadingProblem(out);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (out.isEmpty || (widget.vitals && !out.hasVitals)) {
      setState(() => _error = 'No hay ningún dato para guardar');
      return;
    }
    Navigator.pop(context, out);
  }

  Widget _field(String key, String label, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: _fields[key],
          keyboardType: type ?? TextInputType.number,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.vitals ? 'Presión y SpO₂ del reloj' : 'Datos del reloj'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Revisa lo leído y corrige lo que haga falta. Lo vacío no se guarda.',
              style: text.bodySmall),
          const SizedBox(height: 8),
          if (!widget.vitals) ...[
            _field('kind', 'Actividad (como la nombra el reloj)',
                type: TextInputType.text),
            _field('start', 'Hora de inicio (HH:mm)', type: TextInputType.datetime),
            _field('duration', 'Duración (mm:ss o h:mm:ss)',
                type: TextInputType.datetime),
            _field('avg', 'Pulso medio (lpm)'),
            _field('max', 'Pulso máximo (lpm)'),
            _field('kcal', 'kcal del reloj (informativas)'),
            _field('steps', 'Pasos'),
            _field('km', 'Distancia (km)',
                type: const TextInputType.numberWithOptions(decimal: true)),
          ],
          Text('Presión y SpO₂: estimación del reloj, no es una medida clínica.',
              style: text.bodySmall),
          const SizedBox(height: 4),
          _field('sys', 'Presión alta (mmHg)'),
          _field('dia', 'Presión baja (mmHg)'),
          _field('spo2', 'SpO₂ (%)'),
          if (_error case final e?)
            Text(e,
                style: text.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

/// Resumen de una actividad del reloj con zona y carga por pulso.
String watchActivityLine(WatchActivityRow a,
    {int? maxHrEstimate, int? restHr}) {
  final zone = hrZone(a.avgHr, maxHrEstimate);
  final trimp = banisterTrimp(
      durationSec: a.durationSec,
      avgHr: a.avgHr,
      restHr: restHr,
      maxHr: a.maxHr == null || maxHrEstimate == null
          ? maxHrEstimate
          : (a.maxHr! > maxHrEstimate ? a.maxHr : maxHrEstimate));
  return [
    if (a.kind != null) a.kind!,
    if (a.startTime != null) a.startTime!,
    if (a.durationSec != null) formatDuration(a.durationSec!),
    if (a.avgHr != null || a.maxHr != null)
      'pulso ${a.avgHr ?? '—'} / ${a.maxHr ?? '—'} lpm',
    if (zone != null) 'zona $zone',
    if (a.kcal != null) '${a.kcal} kcal (informativas)',
    if (a.steps != null) '${fmtInt(a.steps!)} pasos',
    if (a.distanceM != null) '${fmtDec(a.distanceM! / 1000)} km',
    if (trimp != null) 'carga por pulso ${trimp.round()}',
  ].join(' · ');
}

/// En la sesión guardada: lo del reloj para esa sesión.
class WatchActivityCard extends ConsumerWidget {
  const WatchActivityCard(
      {super.key, required this.sessionId, required this.date});

  final int sessionId;
  final DateTime date;

  Future<void> _add(BuildContext context, WidgetRef ref, {required bool capture}) async {
    final WatchReading? read;
    if (capture) {
      read = await readWatchCapture(context, ref);
    } else {
      read = await editWatchReading(context);
    }
    if (read == null || !context.mounted) return;
    final reading = read;
    await guarded(
        context,
        () => ref.read(watchRepositoryProvider).saveReading(reading,
            date: date, sessionId: sessionId, source: capture ? 'captura' : 'manual'),
        ok: 'Datos del reloj guardados');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final repo = ref.watch(watchRepositoryProvider);
    final birth = ref.watch(profileProvider).valueOrNull?.birthDate;
    final maxHr = estimatedMaxHr(
        birth == null ? null : DateTime.tryParse(birth), dateOnly(date));
    return AppCard(
      title: 'Datos del reloj',
      children: [
        StreamBuilder<List<WatchActivityRow>>(
          stream: repo.watchForSession(sessionId),
          builder: (context, snap) {
            final list = snap.data ?? const <WatchActivityRow>[];
            if (list.isEmpty) {
              return Text(
                  'INNOVA sólo pasa los pasos a Health Connect. Importa la captura de la actividad o escribe pulso, kcal y duración.',
                  style: text.bodySmall);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in list)
                  FutureBuilder<int?>(
                    future: ref.read(recoveryRepositoryProvider).restingHrOn(date),
                    builder: (context, rest) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(watchActivityLine(a,
                          maxHrEstimate: maxHr, restHr: rest.data)),
                      subtitle: Text(a.source == 'captura'
                          ? 'Leído de la captura'
                          : 'Escrito a mano'),
                      trailing: IconButton(
                        tooltip: 'Quitar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (!await confirmAction(context,
                              title: '¿Quitar estos datos del reloj?',
                              body: 'La sesión no cambia.',
                              confirm: 'Quitar')) {
                            return;
                          }
                          await repo.deleteActivity(a.id);
                        },
                      ),
                    ),
                  ),
                if (maxHr == null)
                  Text('Para ver la zona, anota tu fecha de nacimiento en Ajustes.',
                      style: text.bodySmall),
              ],
            );
          },
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('reloj-captura'),
              onPressed: () => _add(context, ref, capture: true),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Importar captura del reloj'),
            ),
            TextButton(
              key: const ValueKey('reloj-mano'),
              onPressed: () => _add(context, ref, capture: false),
              child: const Text('Escribir a mano'),
            ),
          ],
        ),
      ],
    );
  }
}
