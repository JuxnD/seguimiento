import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/dates.dart';
import '../../ui/widgets.dart';
import '../../ui/hero.dart';
import 'charts_section.dart';

/// El informe es el producto: se genera, se copia y se pega en el chat.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  int? _weekIndex;
  DateTimeRange? _customRange;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return profile.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (p) {
        final start = p.programStart;
        final currentWeek = weekIndexFor(start, dateOnly(DateTime.now()));
        final week = _weekIndex ?? currentWeek;
        final range = _customRange == null
            ? weekRange(start, week)
            : WeekRange(week, dateOnly(_customRange!.start), dateOnly(_customRange!.end));
        final key = (dayKey(range.start), dayKey(range.end));
        final report = ref.watch(reportProvider(key));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Informe'),
            actions: [
              IconButton(
                tooltip: 'Rango personalizado',
                icon: const Icon(Icons.date_range),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDateRange: DateTimeRange(start: range.start, end: range.end),
                  );
                  if (picked != null) setState(() => _customRange = picked);
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              HeroCard(
                color: Theme.of(context).colorScheme.primary,
                overline: _customRange == null ? 'Informe semanal' : 'Rango personalizado',
                pills: [
                  if (_customRange == null && week == currentWeek)
                    const StatPill(icon: Icons.today, label: 'Semana en curso'),
                ],
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() {
                          _customRange = null;
                          _weekIndex = week - 1;
                        }),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _customRange == null ? 'SEMANA $week' : 'RANGO',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                            Text('${formatShort(range.start)} – ${formatLong(range.end)}',
                                style: Theme.of(context).textTheme.titleSmall),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: week >= currentWeek && _customRange == null
                            ? null
                            : () => setState(() {
                                  _customRange = null;
                                  _weekIndex = week + 1;
                                }),
                      ),
                    ],
                  ),
                  if (_customRange != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _customRange = null;
                        _weekIndex = currentWeek;
                      }),
                      child: const Text('Volver a la semana actual'),
                    ),
                ],
              ),
              ChartsSection(range: key),
              if (_customRange == null) _WeekNotes(weekIndex: week),
              AppCard(
                title: 'Markdown',
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy),
                      onPressed: report.value == null
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: report.value!));
                              if (context.mounted) showSnack(context, 'Informe copiado');
                            },
                    ),
                    IconButton(
                      tooltip: 'Compartir',
                      icon: const Icon(Icons.ios_share),
                      onPressed: report.value == null ? null : () => Share.share(report.value!),
                    ),
                  ],
                ),
                children: [
                  report.when(
                    loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                    error: (e, _) => Text('Error: $e'),
                    data: (md) => SelectableText(
                      md,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeekNotes extends ConsumerStatefulWidget {
  const _WeekNotes({required this.weekIndex});

  final int weekIndex;

  @override
  ConsumerState<_WeekNotes> createState() => _WeekNotesState();
}

class _WeekNotesState extends ConsumerState<_WeekNotes> {
  final _controller = TextEditingController();
  int? _loadedFor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(weekNoteProvider(widget.weekIndex));
    if (_loadedFor != widget.weekIndex && note.hasValue) {
      _loadedFor = widget.weekIndex;
      _controller.text = note.value ?? '';
    }
    return AppCard(
      title: 'Notas de la semana',
      children: [
        TextField(
          controller: _controller,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Lo que el dato no cuenta'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () async {
              await ref.read(profileRepositoryProvider).saveWeekNote(widget.weekIndex, _controller.text);
              if (context.mounted) showSnack(context, 'Notas guardadas');
            },
            child: const Text('Guardar notas'),
          ),
        ),
      ],
    );
  }
}
