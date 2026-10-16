import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/readiness_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/fitness_test.dart' show TestPart;
import '../../domain/test_protocol.dart';
import '../../ui/widgets.dart';
import 'readiness_card.dart' show readinessRepositoryProvider;

String _dayLabel(DateTime d) =>
    '${weekdayShort(d.weekday).toLowerCase()} ${formatShort(d)}';

String _partLabel(TestPart part) =>
    part == TestPart.torso ? 'torso' : 'piernas';

/// Plan 054 (§16.28.1): elegir el día del test, para el test de hoy o uno
/// que se pasó sin hacer. Lista los próximos 14 días con lo que toca; el
/// fútbol no se ofrece y, para piernas, propone primero un día de piernas.
/// Las reglas de piernas (2 días tras el torso, 48 h tras un partido,
/// escaleras) se aplican igual: el aviso final dice la fecha que quedó.
Future<void> pickTestDay(BuildContext context, WidgetRef ref,
    {required DateTime from,
    required DateTime start,
    required TestScheduleKey key}) async {
  final plan = ref.read(planRepositoryProvider);
  final today = dateOnly(clock.now());
  final options = <({DateTime day, String label})>[];
  for (var i = 1; i <= 14; i++) {
    final d = addDays(today, i);
    final type = (await plan.dayFor(d))?.day.type;
    if (type == DayType.futbol) continue;
    options.add((day: d, label: type?.label ?? 'Sin plan'));
  }
  if (options.isEmpty || !context.mounted) return;
  final preferred = key.part == TestPart.piernas
      ? options.where((o) => o.label == DayType.piernas.label).firstOrNull
      : null;
  final chosen = await showDialog<DateTime>(
    context: context,
    builder: (_) => _TestDayDialog(
        title:
            '¿Qué día haces el Test ${key.round} de ${_partLabel(key.part)}?',
        options: options,
        initial: preferred?.day ?? options.first.day),
  );
  if (chosen == null || !context.mounted) return;
  final repo = ref.read(readinessRepositoryProvider);
  DateTime? result;
  final ok = await guarded(context, () async {
    await repo.moveTest(
        start: start,
        round: key.round,
        part: key.part,
        from: from,
        to: chosen,
        reasons: const ['Elegido por el owner'],
        now: clock.now(),
        key: key.protocolId == TestProtocolId.v31_12 ? null : key);
    result = await repo.currentTestDate(start, key.round, key.part,
        key: key.protocolId == TestProtocolId.v31_12 ? null : key);
  });
  if (!ok || !context.mounted) return;
  ref.invalidate(dashboardProvider);
  final landed = result ?? chosen;
  showSnack(
      context,
      landed == chosen
          ? 'Test ${key.round} de ${_partLabel(key.part)}: ${_dayLabel(landed)}'
          : 'Test ${key.round} de ${_partLabel(key.part)}: quedó el ${_dayLabel(landed)} '
              '(piernas descansadas tras el torso o el partido)');
}

class _TestDayDialog extends StatefulWidget {
  const _TestDayDialog(
      {required this.title, required this.options, required this.initial});

  final String title;
  final List<({DateTime day, String label})> options;
  final DateTime initial;

  @override
  State<_TestDayDialog> createState() => _TestDayDialogState();
}

class _TestDayDialogState extends State<_TestDayDialog> {
  late DateTime _day = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'El test reemplaza o acorta la sesión de ese día. Los días de fútbol no se ofrecen.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in widget.options)
                ChoiceChip(
                  label: Text('${_dayLabel(o.day)} · ${o.label.toLowerCase()}'),
                  selected: o.day == _day,
                  onSelected: (_) => setState(() => _day = o.day),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _day),
            child: const Text('Mover el test')),
      ],
    );
  }
}

/// Plan 054: un test cuya fecha pasó sin hacerse (el 15 oct se hizo la sesión
/// de piernas en vez del test). Hoy lo dice y deja elegir el día.
class OverdueTestRow extends ConsumerWidget {
  const OverdueTestRow({super.key, required this.test});

  final EffectiveTest test;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              'Test ${test.round} de ${_partLabel(test.part)} pendiente: era el '
              '${_dayLabel(test.date)} y no quedó hecho.',
              style: text.bodyMedium),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            key: const ValueKey('test-vencido-elegir-dia'),
            onPressed: () => pickTestDay(context, ref,
                from: test.date, start: test.key.blockStart, key: test.key),
            icon: const Icon(Icons.event),
            label: const Text('Elegir el día del test'),
          ),
        ],
      ),
    );
  }
}
