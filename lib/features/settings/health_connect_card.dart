import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/health_connect.dart';
import '../../data/local_flags.dart';
import '../../domain/dates.dart';
import '../../ui/widgets.dart';

/// Estado de la conexión, para la tarjeta. Se refresca con invalidate.
class HealthConnectState {
  const HealthConnectState({
    required this.status,
    required this.permitted,
    required this.enabled,
    this.lastSync,
    this.sourcesToday = const [],
  });

  final HealthConnectStatus status;
  final bool permitted;
  final bool enabled;
  final DateTime? lastSync;

  /// Apps que escribieron pasos hoy: así se ve si llegan del reloj.
  final List<String> sourcesToday;

  bool get connected => status == HealthConnectStatus.disponible && permitted && enabled;
}

final healthConnectStateProvider = FutureProvider.autoDispose<HealthConnectState>((ref) async {
  final health = ref.watch(healthConnectProvider);
  final sync = ref.watch(stepsSyncProvider);
  final status = await health.status();
  final permitted = status == HealthConnectStatus.disponible && await _safe(health.hasPermission, false);
  final today = dateOnly(DateTime.now());
  return HealthConnectState(
    status: status,
    permitted: permitted,
    enabled: sync.enabled,
    lastSync: sync.lastSync,
    sourcesToday: permitted ? await _safe(() => health.sources(today, today), const <String>[]) : const [],
  );
});

Future<T> _safe<T>(Future<T> Function() f, T fallback) async {
  try {
    return await f();
  } on Object {
    return fallback;
  }
}

/// Pasos del reloj: Innova S-Watch los escribe en Health Connect y la app los
/// trae solos al abrirla. Lo anotado a mano se respeta si es mayor.
class HealthConnectCard extends ConsumerWidget {
  const HealthConnectCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(healthConnectStateProvider);
    final text = Theme.of(context).textTheme;
    return AppCard(
      title: 'Pasos del reloj (Health Connect)',
      children: [
        state.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('No se pudo consultar Health Connect: $e'),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_describe(s), style: text.bodyMedium),
              if (s.connected && s.sourcesToday.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Hoy escribieron pasos: ${s.sourcesToday.join(', ')}', style: text.bodySmall),
              ],
              if (s.connected && s.sourcesToday.isEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Hoy todavía no hay pasos en Health Connect. Abre la app del reloj para que sincronice.',
                  style: text.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              ..._actions(context, ref, s),
            ],
          ),
        ),
      ],
    );
  }

  String _describe(HealthConnectState s) {
    switch (s.status) {
      case HealthConnectStatus.noInstalado:
        return 'Health Connect no está instalado. Instálalo y conecta en él la app del reloj.';
      case HealthConnectStatus.actualizar:
        return 'Health Connect necesita actualizarse antes de poder leer los pasos.';
      case HealthConnectStatus.noSoportado:
      case HealthConnectStatus.desconocido:
        return 'Este teléfono no ofrece Health Connect: los pasos se anotan a mano en Hoy.';
      case HealthConnectStatus.disponible:
        if (!s.connected) {
          return 'Conecta para que los pasos del reloj lleguen solos al anillo de Hoy y al informe. '
              'Solo se leen los pasos; nada se escribe ni sale del teléfono.';
        }
        final last = s.lastSync;
        return 'Conectado. Los pasos se traen al abrir la app'
            '${last == null ? '' : ' · última vez ${weekdayLong(last.weekday).toLowerCase()} ${timeKey(last.hour, last.minute)}'}. '
            'Si anotas a mano una cifra mayor, se queda la tuya.';
    }
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref, HealthConnectState s) {
    final health = ref.read(healthConnectProvider);
    switch (s.status) {
      case HealthConnectStatus.noInstalado:
      case HealthConnectStatus.actualizar:
        return [
          FilledButton.icon(
            onPressed: () async {
              await health.installProvider();
              ref.invalidate(healthConnectStateProvider);
            },
            icon: const Icon(Icons.download),
            label: Text(s.status == HealthConnectStatus.actualizar ? 'Actualizar Health Connect' : 'Instalar Health Connect'),
          ),
        ];
      case HealthConnectStatus.noSoportado:
      case HealthConnectStatus.desconocido:
        return const [];
      case HealthConnectStatus.disponible:
        if (!s.connected) {
          return [
            FilledButton.icon(
              onPressed: () => _connect(context, ref),
              icon: const Icon(Icons.link),
              label: const Text('Conectar'),
            ),
          ];
        }
        return [
          FilledButton.icon(
            onPressed: () => _syncNow(context, ref),
            icon: const Icon(Icons.sync),
            label: const Text('Traer pasos ahora'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => health.openSettings(),
                  child: const Text('Abrir Health Connect'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _disconnect(context, ref),
                  child: const Text('Desconectar'),
                ),
              ),
            ],
          ),
        ];
    }
  }

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final health = ref.read(healthConnectProvider);
    bool granted;
    try {
      granted = await health.hasPermission() || await health.requestPermission();
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'Health Connect no respondió: $e');
      return;
    }
    if (!granted) {
      if (context.mounted) {
        showSnack(context, 'Sin permiso no se pueden leer los pasos. Puedes darlo en Health Connect → Permisos de apps.');
      }
      ref.invalidate(healthConnectStateProvider);
      return;
    }
    await ref.read(localFlagsProvider).set(FlagKeys.healthConnectEnabled, true);
    if (!context.mounted) return;
    await _syncNow(context, ref);
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(stepsSyncProvider).run();
    ref.invalidate(healthConnectStateProvider);
    if (!context.mounted) return;
    showSnack(context, switch (result.outcome) {
      StepsSyncOutcome.hecho => result.updatedDays == 0
          ? 'Pasos al día: nada que cambiar'
          : 'Pasos traídos: ${result.updatedDays} ${result.updatedDays == 1 ? 'día actualizado' : 'días actualizados'}',
      StepsSyncOutcome.sinPermiso => 'Falta el permiso de pasos en Health Connect',
      StepsSyncOutcome.noDisponible => 'Health Connect no está disponible',
      StepsSyncOutcome.apagado => 'Health Connect no está conectado',
      StepsSyncOutcome.error => 'No se pudieron traer los pasos: ${result.message ?? 'error desconocido'}',
    });
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    await ref.read(localFlagsProvider).set(FlagKeys.healthConnectEnabled, false);
    ref.invalidate(healthConnectStateProvider);
    if (context.mounted) {
      showSnack(context, 'Desconectado. Los pasos ya traídos se quedan; el permiso se quita en Health Connect.');
    }
  }
}
