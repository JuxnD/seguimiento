import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart' show WatchVitalRow;
import '../../domain/dates.dart';
import '../../domain/watch_capture.dart' show WatchReading;
import '../../ui/widgets.dart';
import '../training/watch_activity_card.dart';

/// Plan 058 (§16.17): presión y SpO₂. Las del reloj son una estimación (sin
/// manguito no están validadas): sólo tendencia en reposo; nunca deciden
/// carga, alertas ni plan. Una medida con tensiómetro de brazo va marcada.
class WatchVitalsCard extends ConsumerWidget {
  const WatchVitalsCard({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref,
      {required bool capture, String source = 'reloj'}) async {
    final WatchReading? read;
    if (capture) {
      read = await readWatchCapture(context, ref, vitals: true);
    } else {
      read = await editWatchReading(context, vitals: true);
    }
    if (read == null || !context.mounted) return;
    final r = read;
    final now = DateTime.now();
    await guarded(
        context,
        () => ref.read(watchRepositoryProvider).saveVital(
            date: now,
            time: r.startTime ??
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            systolic: r.systolic,
            diastolic: r.diastolic,
            spo2: r.spo2,
            source: source),
        ok: 'Lectura guardada');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final repo = ref.watch(watchRepositoryProvider);
    return AppCard(
      title: 'Presión y SpO₂',
      children: [
        Text('Estimación del reloj, no es una medida clínica.',
            key: const ValueKey('vitales-aviso'),
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
        Text(
            'Sólo cuenta la tendencia de lecturas en reposo, sentado y a la misma hora. '
            'No decide carga, alertas ni el plan.',
            style: text.bodySmall),
        StreamBuilder<List<WatchVitalRow>>(
          stream: repo.watchVitals(),
          builder: (context, snap) {
            final list = snap.data ?? const <WatchVitalRow>[];
            if (list.isEmpty) return const SizedBox.shrink();
            final rest = list.where((v) => v.atRest).toList();
            final bp = rest.where((v) => v.systolic != null).take(7).toList();
            final ox = rest.where((v) => v.spo2 != null).take(7).toList();
            int avg(Iterable<int> xs) =>
                (xs.reduce((a, b) => a + b) / xs.length).round();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                if (bp.isNotEmpty)
                  Text(
                      'Presión, promedio de ${bp.length} en reposo: '
                      '${avg(bp.map((v) => v.systolic!))}/${avg(bp.map((v) => v.diastolic!))} mmHg',
                      style: text.bodyMedium),
                if (ox.isNotEmpty)
                  Text('SpO₂, promedio de ${ox.length} en reposo: ${avg(ox.map((v) => v.spo2!))} %',
                      style: text.bodyMedium),
                for (final v in list.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text([
                      if (v.systolic != null) '${v.systolic}/${v.diastolic} mmHg',
                      if (v.spo2 != null) 'SpO₂ ${v.spo2} %',
                    ].join(' · ')),
                    subtitle: Text(
                        '${weekdayShort(parseDay(v.date).weekday)} ${formatShort(parseDay(v.date))}'
                        '${v.time == null ? '' : ' · ${v.time}'} · '
                        '${v.source == 'tensiometro' ? 'Tensiómetro' : 'Reloj'}'),
                    trailing: IconButton(
                      tooltip: 'Quitar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirmAction(context,
                            title: '¿Quitar esta lectura?',
                            body: 'No se puede deshacer.',
                            confirm: 'Quitar')) {
                          await repo.deleteVital(v.id);
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _add(context, ref, capture: true),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Importar captura'),
            ),
            TextButton(
              onPressed: () => _add(context, ref, capture: false),
              child: const Text('Reloj a mano'),
            ),
            TextButton(
              onPressed: () =>
                  _add(context, ref, capture: false, source: 'tensiometro'),
              child: const Text('Tensiómetro'),
            ),
          ],
        ),
      ],
    );
  }
}
