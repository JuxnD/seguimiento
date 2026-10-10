import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/goal_repository.dart';
import '../../domain/adaptive_coach.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../ui/widgets.dart';

/// Acompañamiento en Hoy (plan 009): qué se lee hoy, con qué evidencia y
/// cuándo se revisa. Una propuesta se acepta (editable), se pospone o se
/// rechaza; nunca se aplica sola.
class CoachCard extends ConsumerWidget {
  const CoachCard({super.key, required this.reading});

  final CoachReading reading;

  Future<void> _decide(BuildContext context, WidgetRef ref, ProposalStatus status, {int? value}) async {
    final p = reading.proposal!;
    await GoalRepository(ref.read(databaseProvider)).decideSteps(
      p,
      status,
      today: reading.evaluatedOn,
      acceptedValue: value,
      evidence: reading.evidence.join(' · '),
    );
    ref.invalidate(dashboardProvider);
    if (!context.mounted) return;
    showSnack(
      context,
      switch (status) {
        ProposalStatus.aceptada => 'Meta de ${fmtInt(value ?? p.to)} pasos desde mañana. Se revisa en $coachReviewDays días.',
        ProposalStatus.pospuesta => 'Se vuelve a mirar en $coachPostponeDays días.',
        ProposalStatus.rechazada => 'Se mantiene ${fmtInt(p.from)}. No vuelve a proponerse con esta evidencia.',
        ProposalStatus.pendiente => '',
      },
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final p = reading.proposal!;
    final value = await showDialog<int>(context: context, builder: (_) => _AcceptDialog(proposal: p));
    if (value == null || !context.mounted) return;
    await _decide(context, ref, ProposalStatus.aceptada, value: value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final r = reading;
    final compact = r.state == CoachState.observar || r.state == CoachState.faltanDatos;
    return AppCard(
      key: const ValueKey('coach-card'),
      title: 'Acompañamiento · ${r.state.label}',
      children: [
        Text(r.reason, style: compact ? text.bodySmall : text.bodyMedium),
        if (!compact && r.action != null) ...[
          const SizedBox(height: 4),
          Text(r.action!, style: text.titleSmall),
        ],
        if (!compact && r.evidence.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(r.evidence.join(' · '), style: text.bodySmall),
        ],
        if (r.nextReview != null && !compact)
          Text('Próxima revisión: ${formatShort(r.nextReview!)}', style: text.bodySmall),
        if (r.proposal != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton(onPressed: () => _accept(context, ref), child: Text('Subir a ${fmtInt(r.proposal!.to)}…')),
              OutlinedButton(
                onPressed: () => _decide(context, ref, ProposalStatus.pospuesta),
                child: const Text('En $coachPostponeDays días'),
              ),
              TextButton(
                onPressed: () => _decide(context, ref, ProposalStatus.rechazada),
                child: Text('Mantener ${fmtInt(r.proposal!.from)}'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AcceptDialog extends StatefulWidget {
  const _AcceptDialog({required this.proposal});

  final StepsProposal proposal;

  @override
  State<_AcceptDialog> createState() => _AcceptDialogState();
}

class _AcceptDialogState extends State<_AcceptDialog> {
  late final _field = TextEditingController(text: '${widget.proposal.to}');
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _ok() {
    final v = int.tryParse(_field.text.trim().replaceAll('.', ''));
    if (v == null || v < 1000 || v > 30000) {
      setState(() => _error = 'Entre 1.000 y 30.000 pasos');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nueva meta de pasos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tu promedio fue ${fmtInt(widget.proposal.average)}. Rige desde mañana; el pasado se sigue '
                'midiendo con ${fmtInt(widget.proposal.from)}.'),
            const SizedBox(height: 8),
            TextField(
              controller: _field,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Pasos entre semana', errorText: _error, border: const OutlineInputBorder()),
              onSubmitted: (_) => _ok(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _ok, child: const Text('Aceptar')),
        ],
      );
}
