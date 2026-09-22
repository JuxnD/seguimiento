import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/session_math.dart';
import '../../ui/widgets.dart';
import '../plan/plan_screen.dart';
import 'football_form_screen.dart';
import 'round_counter_screen.dart';
import 'session_form_screen.dart';

/// Abre el contador y, al terminar, el formulario con todo prellenado.
Future<void> startCircuitFlow(BuildContext context, WidgetRef ref, {DateTime? date}) async {
  final result = await Navigator.push<CounterResult>(
    context,
    MaterialPageRoute(builder: (_) => const RoundCounterScreen()),
  );
  if (result == null || !context.mounted) return;
  final draft = SessionDraft(
    date: date ?? dateOnly(DateTime.now()),
    startTime: result.startTime,
    totalSec: result.totalSec,
    warmupSec: result.warmupSec,
    cooldownSec: result.cooldownSec,
    roundsDone: result.rounds,
    roundMarksSec: result.roundMarksSec,
  );
  await openSessionForm(context, draft);
}

Future<void> openSessionForm(BuildContext context, SessionDraft draft) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => SessionFormScreen(draft: draft)));

class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final football = ref.watch(footballProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entreno'),
        actions: [
          IconButton(
            tooltip: 'Plan',
            icon: const Icon(Icons.calendar_view_week),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          AppCard(
            children: [
              FilledButton.icon(
                onPressed: () => startCircuitFlow(context, ref),
                icon: const Icon(Icons.timer),
                label: const Text('Empezar circuito con contador'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openSessionForm(context, SessionDraft(date: dateOnly(DateTime.now()))),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Registrar a mano'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const FootballFormScreen())),
                      icon: const Icon(Icons.sports_soccer),
                      label: const Text('Fútbol'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppCard(
            title: 'Sesiones',
            children: [
              sessions.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? const EmptyHint('Aún no hay sesiones.')
                    : Column(children: [for (final s in list) _SessionTile(summary: s)]),
              ),
            ],
          ),
          AppCard(
            title: 'Fútbol',
            children: [
              football.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? const EmptyHint('Sin partidos registrados.')
                    : Column(children: [for (final g in list) _FootballTile(game: g)]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary.row;
    final date = parseDay(s.date);
    final net = circuitNetSec(totalSec: s.totalSec, warmupSec: s.warmupSec, cooldownSec: s.cooldownSec);
    final rounds = s.roundsDone == null ? '—' : '${s.roundsEstimated ? '~' : ''}${s.roundsDone}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${weekdayShort(date.weekday)} ${formatShort(date)}'
          '${s.startTime == null ? '' : ' · ${s.startTime}'} · ${s.type.label}'),
      subtitle: Text('Total ${formatDuration(s.totalSec)} · neto ${formatDuration(net)} · '
          'rondas $rounds${s.rpe == null ? '' : ' · RPE ${s.rpe}'}'
          '${summary.splitSets > 0 ? ' · ${summary.splitSets} partidas' : ''}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final draft = await ref.read(trainingRepositoryProvider).load(s.id);
        if (context.mounted) await openSessionForm(context, draft);
      },
    );
  }
}

class _FootballTile extends StatelessWidget {
  const _FootballTile({required this.game});

  final FootballGameRow game;

  @override
  Widget build(BuildContext context) {
    final date = parseDay(game.date);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${weekdayShort(date.weekday)} ${formatShort(date)} · Fútbol ${game.format}'),
      subtitle: Text('${game.minutes} min'
          '${game.steps == null ? '' : ' · ${game.steps} pasos'}'
          '${game.intensity == null ? '' : ' · intensidad ${game.intensity}'}'
          '${game.fatigueAfter == null ? '' : ' · fatiga ${game.fatigueAfter}'}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => FootballFormScreen(existing: game))),
    );
  }
}
