import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/equipment_repository.dart';
import '../../domain/fitness_test.dart' show TestPart, recordedTestDate;
import '../../domain/test_protocol.dart';
import '../../ui/widgets.dart';
import '../training/test_mode_screen.dart';

/// Plan 052 (§16.27.4): una prueba que quedó sin hacer por falta de material
/// vuelve a Hoy cuando ese material ya está, hasta medirla en otro intento.
class PendingEquipmentTestCard extends ConsumerWidget {
  const PendingEquipmentTestCard({super.key});

  /// La identidad del intento original; null si no se puede reconstruir
  /// (entonces el botón queda apagado en lugar de abrir otro protocolo).
  static ({TestPart part, TestScheduleKey? key})? _identity(
      PendingEquipmentTest p) {
    final part = p.part;
    final protocol = TestProtocolId.values
        .where((v) => v.name == p.attempt.protocolId)
        .firstOrNull;
    if (part == null || protocol == null) return null;
    final raw = p.attempt.blockStart;
    if (raw == null) {
      // Sin bloque sólo existe el protocolo anterior de 12 pruebas.
      return protocol == TestProtocolId.v31_12 ? (part: part, key: null) : null;
    }
    final blockStart = recordedTestDate(raw);
    if (blockStart == null) return null;
    return (
      part: part,
      key: TestScheduleKey(
          scheme: p.attempt.scheme,
          blockStart: blockStart,
          protocolId: protocol,
          round: p.attempt.round,
          part: part)
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready =
        ref.watch(pendingEquipmentTestsProvider).valueOrNull ?? const [];
    if (ready.isEmpty) return const SizedBox.shrink();
    return AppCard(children: [
      for (final p in ready) ...[
        Text(
            'Test pendiente: ${p.itemName} — ya tienes ${p.requiresLabel}; hazlo al inicio de tu próxima '
            'sesión de ${p.part == TestPart.piernas ? 'piernas' : 'torso'}.'),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Builder(builder: (context) {
            final identity = _identity(p);
            return OutlinedButton.icon(
              key: ValueKey('pending-test:${p.pending.id}'),
              onPressed: identity == null
                  ? null
                  // Intento nuevo con las condiciones del anterior: así la
                  // prueba queda medida y la pendiente se cierra sola.
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TestModeScreen(
                              date: clock.now(),
                              round: p.attempt.round,
                              part: identity.part,
                              scheduleKey: identity.key,
                              attemptId: p.attempt.id,
                              newAttempt: true))),
              icon: const Icon(Icons.timer_outlined),
              label: Text('Abrir test ${p.attempt.round}'),
            );
          }),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }
}
