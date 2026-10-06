import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/ai_context.dart';
import '../../domain/ai_report_sources.dart';
import '../../domain/report/period_summary.dart';
import '../../ui/widgets.dart';
import '../../ui/hero.dart';
import 'charts_section.dart';
import 'summary_screen.dart';
import 'weekly_ai_screen.dart';
import '../ai/ai_conversation_screen.dart';
import '../ai/ai_history_screen.dart';
import 'missing_data_actions_card.dart';

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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (p) {
        final start = p.programStart;
        final currentWeek = weekIndexFor(start, ref.watch(todayProvider));
        final week = _weekIndex ?? currentWeek;
        final range = _customRange == null
            ? weekRange(start, week)
            : WeekRange(week, dateOnly(_customRange!.start),
                dateOnly(_customRange!.end));
        final key = (dayKey(range.start), dayKey(range.end));
        final report = ref.watch(reportProvider(key));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Informe'),
            actions: [
              IconButton(
                tooltip: 'Tu progreso en números',
                icon: const Icon(Icons.insights),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SummaryScreen())),
              ),
              IconButton(
                tooltip: 'Rango personalizado',
                icon: const Icon(Icons.date_range),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDateRange:
                        DateTimeRange(start: range.start, end: range.end),
                  );
                  if (picked != null) setState(() => _customRange = picked);
                },
              ),
              IconButton(
                tooltip: 'Historial de IA',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AiHistoryScreen())),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              HeroCard(
                color: Theme.of(context).colorScheme.primary,
                overline: _customRange == null
                    ? 'Informe semanal'
                    : 'Rango personalizado',
                pills: [
                  if (_customRange == null && week == currentWeek)
                    const StatPill(icon: Icons.today, label: 'Semana en curso'),
                ],
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Semana anterior',
                        icon: const Icon(Icons.chevron_left),
                        // Antes de la semana 1 no hay programa: no hay qué informar.
                        onPressed: week <= 1 && _customRange == null
                            ? null
                            : () => setState(() {
                                  _customRange = null;
                                  _weekIndex = week <= 1 ? 1 : week - 1;
                                }),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _customRange == null ? 'SEMANA $week' : 'RANGO',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                            Text(
                                '${formatShort(range.start)} – ${formatLong(range.end)}',
                                style: Theme.of(context).textTheme.titleSmall),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Semana siguiente',
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
              _SummaryLink(range: key),
              MissingDataActionsCard(range: key),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Analizar este informe con IA'),
                  onPressed: report.value == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => WeeklyAiScreen(
                                    report: report.value!,
                                    repository: ref
                                        .read(aiConversationRepositoryProvider),
                                    rangeStart: range.start,
                                    rangeEnd: range.end,
                                  ))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.question_answer_outlined),
                  label: const Text('Preguntar sobre este informe'),
                  onPressed: report.value == null
                      ? null
                      : () => _askAboutReport(
                          context, ref, key, range.start, range.end),
                ),
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
                              await Clipboard.setData(
                                  ClipboardData(text: report.value!));
                              if (context.mounted) {
                                showSnack(context, 'Informe copiado');
                              }
                            },
                    ),
                    IconButton(
                      tooltip: 'Compartir',
                      icon: const Icon(Icons.ios_share),
                      onPressed: report.value == null
                          ? null
                          : () => Share.share(report.value!),
                    ),
                  ],
                ),
                children: [
                  report.when(
                    loading: () => const Center(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator())),
                    error: (e, _) => Text('Error: $e'),
                    data: (md) => SelectableText(
                      md,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12, height: 1.35),
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

  Future<void> _askAboutReport(
    BuildContext context,
    WidgetRef ref,
    (String, String) rangeKey,
    DateTime from,
    DateTime to,
  ) async {
    try {
      final input = await ref.read(reportInputProvider(rangeKey).future);
      final reportText = await ref.read(reportProvider(rangeKey).future);
      if (!context.mounted) return;
      var includePrevious = false;
      if (input.previous != null) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('¿Incluir comparación anterior?'),
            content: const Text(
                'Puedes enviar el informe actual solo o añadir una comparación calculada localmente con el periodo anterior.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Solo informe actual'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Añadir comparación'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        includePrevious = choice;
      }
      if (!context.mounted) return;
      final sources = reportQuestionSources(
        input: input,
        report: reportText,
        includePrevious: includePrevious,
      );
      final snapshot = AiConversationSnapshot(
        kind: AiConversationKind.reportQuestion,
        title: 'Informe · ${dayKey(from)} – ${dayKey(to)}',
        rangeStart: from,
        rangeEnd: to,
        sources: sources,
        model: aiQuestionModel,
        contractVersion: aiQuestionContractVersion,
      );
      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => AiConversationScreen.forQuestion(
            snapshot: snapshot,
            repository: ref.read(aiConversationRepositoryProvider),
          ),
        ),
      );
    } on FormatException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } on Object {
      if (context.mounted) {
        showSnack(context, 'No se pudo preparar el contexto del informe.');
      }
    }
  }
}

/// Los números grandes del rango y la entrada al resumen por semana o mes.
class _SummaryLink extends ConsumerWidget {
  const _SummaryLink({required this.range});

  final (String, String) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(periodSummaryProvider(range)).valueOrNull;
    final text = Theme.of(context).textTheme;
    final top = s == null
        ? const <ExerciseTotal>[]
        : s.exercises.where((e) => !e.isHold).take(3).toList();
    return AppCard(
      title: 'En números',
      trailing: TextButton(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const SummaryScreen())),
        child: const Text('Semana y mes'),
      ),
      children: [
        if (s == null)
          const LinearProgressIndicator()
        else if (s.isEmpty)
          Text('Nada registrado en este rango todavía.', style: text.bodyLarge)
        else
          Text(
            [
              for (final e in top)
                '${fmtInt(e.amount)} ${e.name.toLowerCase()}',
              if (s.stepsTotal > 0) '${fmtInt(s.stepsTotal)} pasos',
              if (s.kcalBurned case final k?)
                '≈ ${fmtInt(k)} kcal en actividad',
            ].join(' · '),
            style: text.bodyLarge,
          ),
      ],
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
          decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Lo que el dato no cuenta'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () async {
              await ref
                  .read(profileRepositoryProvider)
                  .saveWeekNote(widget.weekIndex, _controller.text);
              if (context.mounted) showSnack(context, 'Notas guardadas');
            },
            child: const Text('Guardar notas'),
          ),
        ),
      ],
    );
  }
}
