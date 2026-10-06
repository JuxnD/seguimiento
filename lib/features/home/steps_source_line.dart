import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/steps.dart';

/// "INNOVA S-WATCH · 3:06 p. m.": quién escribió el último registro de pasos
/// en Health Connect y a qué hora. Esa hora es la de la última sincronización
/// del reloj, que es lo que decide si los pasos de Hoy están al día; la hora
/// en que esta app leyó no dice nada (lee cada 2 min). Si pasaron más de 6 h,
/// pide abrir la app del reloj (§16.14). Nada si Health Connect no está
/// conectado.
class StepsSourceLine extends ConsumerWidget {
  const StepsSourceLine({super.key, this.now, this.activityToday = false});

  /// Solo para pruebas.
  final DateTime? now;

  /// Hubo sesión o partido hoy: los pasos del reloj se vuelven viejos antes.
  final bool activityToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(stepsSyncInfoProvider);
    if (!info.enabled) return const SizedBox.shrink();
    final now = this.now ?? DateTime.now();
    final origin = info.origin;
    final small = Theme.of(context).textTheme.bodySmall;
    final warn = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.watch_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  origin == null ? 'Pasos del reloj · aún sin registros en Health Connect' : stepsOriginLine(origin, now),
                  style: small,
                ),
              ),
            ],
          ),
          if (watchSyncStale(origin?.at, now, activityToday: activityToday))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.sync_problem, size: 18, color: warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Abre la app del reloj para sincronizar', style: small?.copyWith(color: warn)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
