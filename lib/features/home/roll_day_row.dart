import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';

/// Corrimientos vigentes de la semana del día (clave `dayKey`).
final weekRollsProvider = StreamProvider.family<List<DateTime>, String>(
    (ref, day) =>
        ref.watch(planRepositoryProvider).watchShiftsInWeek(parseDay(day)));

String _day(DateTime d) =>
    '${weekdayShort(d.weekday).toLowerCase()} ${formatShort(d)}';

/// Plan 053: rodar la programación un día desde Hoy. El día elegido queda
/// libre y las sesiones siguientes de la semana (con sus tests) van un día
/// más tarde; el fútbol no se mueve. Se puede rodar desde un día anterior de
/// esta semana (si en la práctica ya se corrió) y deshacer el último.
class RollDayRow extends ConsumerWidget {
  const RollDayRow({super.key, required this.date, required this.trained});

  final DateTime date;
  final bool trained;

  Future<void> _roll(BuildContext context, WidgetRef ref) async {
    final plan = ref.read(planRepositoryProvider);
    final today = dateOnly(date);
    final options = <DateTime, List<DateTime>>{};
    for (var d = weekAnchor(today); !d.isAfter(today); d = addDays(d, 1)) {
      if (await plan.canRollDay(d)) options[d] = await plan.droppedIfRolled(d);
    }
    if (!context.mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Esta semana no queda una sesión que rodar.')));
      return;
    }
    final already = await plan.shiftsInWeek(today);
    if (!context.mounted) return;
    final from = await showDialog<DateTime>(
      context: context,
      builder: (_) =>
          _RollDialog(today: today, options: options, already: already),
    );
    if (from == null) return;
    await plan.rollDay(from, now: clock.now());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(planDayProvider(dayKey(date))).valueOrNull;
    if (view == null || dateOnly(date) != dateOnly(clock.now())) {
      return const SizedBox.shrink();
    }
    final rolls =
        ref.watch(weekRollsProvider(dayKey(date))).valueOrNull ?? const [];
    final earlier = rolls.where((r) => r.isBefore(dateOnly(date))).toList();
    final text = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (view.vacated) ...[
            if (view.day.notes case final notes?) Text(notes, style: text),
            TextButton.icon(
              key: const ValueKey('deshacer-rodar'),
              onPressed: () => ref.read(planRepositoryProvider).undoRoll(date),
              icon: const Icon(Icons.undo),
              label: const Text('Deshacer: volver a lo de hoy'),
            ),
          ] else if (!trained && view.day.type.isTraining)
            TextButton.icon(
              key: const ValueKey('rodar-dia'),
              onPressed: () => _roll(context, ref),
              icon: const Icon(Icons.event_repeat),
              label: const Text('Rodar 1 día'),
            ),
          // Todos los días rodados de la semana: cada uno corre un día más.
          if (rolls.isNotEmpty) ...[
            Text(
                rolls.length == 1
                    ? 'Programación rodada 1 día: desde el ${_day(rolls.single)}.'
                    : 'Programación rodada ${rolls.length} días esta semana '
                        '(desde ${rolls.map(_day).join(', ')}).',
                style: Theme.of(context).textTheme.bodySmall),
            if (!view.vacated && earlier.isNotEmpty)
              TextButton.icon(
                key: const ValueKey('deshacer-rodar-anterior'),
                onPressed: () =>
                    ref.read(planRepositoryProvider).undoRoll(earlier.last),
                icon: const Icon(Icons.undo),
                label: Text('Deshacer el del ${_day(earlier.last)}'),
              ),
            if (rolls.length > 1)
              TextButton.icon(
                key: const ValueKey('deshacer-rodar-todo'),
                onPressed: () =>
                    ref.read(planRepositoryProvider).undoWeekRolls(date),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Deshacer todos: volver a la semana normal'),
              ),
          ],
        ],
      ),
    );
  }
}

/// Confirmación con el día desde el que se rueda (hoy por defecto) y lo que
/// se pierde esa semana.
class _RollDialog extends StatefulWidget {
  const _RollDialog(
      {required this.today, required this.options, this.already = const []});

  final DateTime today;
  final Map<DateTime, List<DateTime>> options;

  /// Corrimientos que ya tiene la semana.
  final List<DateTime> already;

  @override
  State<_RollDialog> createState() => _RollDialogState();
}

class _RollDialogState extends State<_RollDialog> {
  late DateTime _from = widget.options.containsKey(widget.today)
      ? widget.today
      : widget.options.keys.last;

  @override
  Widget build(BuildContext context) {
    final dropped = widget.options[_from]!;
    final isToday = _from == widget.today;
    return AlertDialog(
      title: const Text('¿Rodar la programación un día?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.options.length > 1) ...[
              const Text('¿Desde qué día?'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in widget.options.keys)
                    ChoiceChip(
                      label: Text(d == widget.today ? 'Hoy' : _day(d)),
                      selected: d == _from,
                      onSelected: (_) => setState(() => _from = d),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text([
              if (widget.already.isNotEmpty)
                'Esta semana ya está rodada desde el '
                    '${widget.already.map(_day).join(', ')}: rodar otra vez la '
                    'corre un día más. Si sólo querías corregir el día, usa '
                    '«Deshacer» en Hoy.',
              isToday
                  ? 'Hoy queda libre y lo de hoy pasa a mañana; el resto de la '
                      'semana también va un día más tarde, con sus tests.'
                  : 'El ${_day(_from)} cuenta como libre y desde ahí todo va un '
                      'día más tarde, con sus tests: úsalo si en la práctica ya '
                      'lo corriste.',
              'El fútbol no se mueve.',
              if (dropped.isNotEmpty)
                'Esta semana no hay descanso que lo absorba: se pierde la '
                    'sesión del ${dropped.map(_day).join(' y ')}.',
              'Puedes deshacerlo desde Hoy.',
            ].join('\n\n')),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _from),
            child: const Text('Rodar 1 día')),
      ],
    );
  }
}
