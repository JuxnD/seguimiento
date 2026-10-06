import 'package:flutter/material.dart';

import '../../data/ai_gateway.dart';

/// Presenta la última cuota informada por el gateway v2.
/// API: `AiBudget(quota: client.lastQuota)`; no consulta ni modifica datos.
class AiBudget extends StatelessWidget {
  const AiBudget({super.key, required this.quota});

  final AiQuota? quota;

  @override
  Widget build(BuildContext context) {
    final value = quota;
    if (value == null) {
      return const Text('El límite diario se mostrará al consultar la IA.');
    }
    final reset = value.resetAt;
    final resetText = reset == null
        ? ''
        : ' · Reinicia ${reset.toLocal().toString().substring(0, 16)}';
    return Semantics(
      label:
          '${value.remaining} de ${value.limit} consultas disponibles$resetText',
      child: Text(
          'Consultas disponibles: ${value.remaining}/${value.limit}$resetText'),
    );
  }
}

class AiStatusPanel extends StatelessWidget {
  const AiStatusPanel({super.key, required this.status, required this.quota});

  final String? status;
  final AiQuota? quota;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status != null) Text(status!),
          AiBudget(quota: quota),
        ],
      );
}
