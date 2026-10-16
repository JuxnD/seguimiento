import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/mobility_benchmark_repository.dart';
import '../../data/repositories/readiness_repository.dart';
import '../../domain/daily_routines.dart';
import '../../domain/dates.dart';
import '../../domain/fitness_test.dart';
import '../../domain/test_protocol.dart';
import '../../domain/format.dart';
import '../../domain/readiness.dart';
import '../../ui/widgets.dart';
import '../body/mobility_benchmarks_screen.dart';
import '../training/mobility_screen.dart';

/// Lo que Hoy necesita de la recuperación (§19.17) y de las rutinas diarias.
class ReadinessView {
  const ReadinessView({
    required this.advice,
    required this.trainedAnyway,
    required this.recoveryDone,
    required this.routines,
    required this.mobilityStreak,
  });

  final ReadinessAdvice advice;
  final bool trainedAnyway;
  final bool recoveryDone;

  /// Ids de las rutinas diarias guardadas hoy.
  final Set<String> routines;
  final int mobilityStreak;

  /// La tarjeta de recuperación reemplaza a la sesión del día.
  bool get proposesRecovery =>
      advice.level != ReadinessLevel.green && !trainedAnyway && !recoveryDone;
}

final _readinessSignalsProvider = StreamProvider<void>((ref) {
  final db = ref.watch(databaseProvider);
  return db.tableUpdates(TableUpdateQuery.onAllTables([
    db.sessions,
    db.footballGames,
    db.morningChecks,
    db.sorenessLogs,
    db.sleepLogs,
    db.coachProposals
  ]));
});

final readinessRepositoryProvider =
    Provider((ref) => ReadinessRepository(ref.watch(databaseProvider)));

/// Lo que Hoy lee de la base para la recuperación de `day`. `test`: hoy toca
/// test o intento.
Future<ReadinessView> loadReadinessView(ReadinessRepository repo, DateTime day,
        {bool test = false}) async =>
    ReadinessView(
      advice: await repo.readinessOn(day, testOrAttemptToday: test),
      trainedAnyway: await repo.trainedAnyway(day),
      recoveryDone: await repo.recoveryDone(day),
      routines: await repo.routinesOn(day),
      mobilityStreak: await repo.mobilityStreak(day),
    );

final readinessViewProvider =
    FutureProvider.family<ReadinessView, ({String day, bool test})>(
        (ref, args) {
  ref.watch(_readinessSignalsProvider);
  return loadReadinessView(
      ref.watch(readinessRepositoryProvider), parseDay(args.day),
      test: args.test);
});

Color readinessColor(ReadinessLevel level) => switch (level) {
      ReadinessLevel.green => const Color(0xFF4CAF50),
      ReadinessLevel.yellow => const Color(0xFFF2B233),
      ReadinessLevel.red => const Color(0xFFE5533D),
    };

/// "Hoy: recuperación activa" en lugar de la sesión del día, con el porqué.
/// `test`: el test de hoy, si lo hay (para "Mover test a mañana").
class RecoveryProposalCard extends ConsumerWidget {
  const RecoveryProposalCard(
      {super.key,
      required this.date,
      required this.view,
      this.test,
      this.scheduleKey});

  final DateTime date;
  final ReadinessView view;
  final ({DateTime start, int round, TestPart part})? test;
  final TestScheduleKey? scheduleKey;

  Future<void> _trainAnyway(BuildContext context, WidgetRef ref) async {
    final a = view.advice;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Entrenar igual?'),
        content: Text(a.load3Days > 0
            ? 'La carga de anteayer y ayer está en ${fmtInt(a.load3Days)}. ${a.reasons.first}. ¿Seguro?'
            : '${a.reasons.first}. ¿Seguro?'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Mejor recupero')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Entrenar igual')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await guarded(context,
        () => ref.read(readinessRepositoryProvider).trainAnyway(date, a),
        ok: 'Anotado: entrenas igual. Queda en el informe.');
  }

  Future<void> _moveTest(BuildContext context, WidgetRef ref) async {
    final t = test!;
    DateTime? to;
    final ok = await guarded(context, () async {
      to = await ref.read(readinessRepositoryProvider).moveTest(
          start: t.start,
          round: t.round,
          part: t.part,
          from: date,
          reasons: view.advice.reasons,
          key: scheduleKey?.protocolId == TestProtocolId.v31_12
              ? null
              : scheduleKey);
    });
    if (!ok || !context.mounted) return;
    if (to == null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Este test ya se movió 2 veces'),
          content: const Text(
              'No se mueve otra vez a mañana. Si sigues sin recuperarte, '
              'elige el día con «Mover el test» en la tarjeta del día.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Entendido'))
          ],
        ),
      );
      return;
    }
    ref.invalidate(dashboardProvider);
    showSnack(context,
        'Test movido al ${weekdayLong(to!.weekday).toLowerCase()} ${formatShort(to!)}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = view.advice;
    final color = readinessColor(a.level);
    final text = Theme.of(context).textTheme;
    final red = a.level == ReadinessLevel.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.title,
                  style: text.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              Text(a.advice, style: text.bodyMedium),
              const SizedBox(height: 6),
              for (final r in a.reasons) Text('• $r', style: text.bodyMedium),
              if (a.missing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      'Sin dato: ${a.missing.map((m) => m.split(':').first).join(', ').toLowerCase()}',
                      style: text.bodySmall),
                ),
              if (a.level == ReadinessLevel.yellow)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      // Plan 057 (auditoría 053, P1-9): la misma meta que Hoy
                      // y Comidas, no un número escrito a mano.
                      switch (ref.watch(kcalGoalOnProvider(dayKey(date))).valueOrNull) {
                        (target: final t?, max: final m, day: _) =>
                          'Comida: ${fmtInt(t)}${m == null ? '' : '–${fmtInt(m)}'} kcal y proteína ≥ 130 g, carbohidratos moderados.',
                        _ => 'Comida: proteína ≥ 130 g, carbohidratos moderados.',
                      },
                      style: text.bodySmall),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => startMobility(context, ref,
              routine: red ? nightSuelta() : recoveryActive()),
          style: FilledButton.styleFrom(
              backgroundColor: color, minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.self_improvement),
          label: Text(red
              ? 'Movilidad suave (Suelta)'
              : 'Empezar recuperación (30 min)'),
        ),
        if (test != null && a.moveTestToTomorrow) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _moveTest(context, ref),
            icon: const Icon(Icons.event_repeat),
            label: const Text('Mover test a mañana'),
          ),
        ],
        TextButton(
            onPressed: () => _trainAnyway(context, ref),
            child: const Text('Entrenar igual')),
      ],
    );
  }
}

/// Chips "Mañana ✓" y "Noche ✓" con la racha de movilidad (§19.14, §19.15).
/// `legs`: hoy hubo fútbol o piernas, la noche lleva el módulo de piernas.
/// Plan 057: si hoy toca repetir la rodilla a la pared (§16.30.2).
final kneeWallDueProvider = FutureProvider.autoDispose
    .family<KneeWallDue?, String>((ref, day) =>
        MobilityBenchmarkRepository(ref.watch(databaseProvider))
            .kneeWallDue(parseDay(day)));

class DailyRoutinesRow extends ConsumerWidget {
  const DailyRoutinesRow(
      {super.key,
      required this.date,
      required this.legs,
      required this.matchNight});

  final DateTime date;
  final bool legs;
  final bool matchNight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref
        .watch(readinessViewProvider((day: dayKey(date), test: false)))
        .valueOrNull;
    final done = view?.routines ?? const <String>{};
    final text = Theme.of(context).textTheme;
    Widget chip(String id, String label, VoidCallback onTap) {
      final ok = done.contains(id);
      return ActionChip(
        avatar: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18),
        label: Text(ok ? '$label ✓' : label),
        onPressed: onTap,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            chip(morningActivaId, 'Mañana', () => _morning(context, ref)),
            chip(
                nightSueltaId,
                legs ? 'Noche + piernas' : 'Noche',
                () => startMobility(context, ref,
                    routine:
                        nightSuelta(withLegs: legs, matchNight: matchNight))),
          ],
        ),
        if ((view?.mobilityStreak ?? 0) > 0)
          Text(
              'Movilidad: ${view!.mobilityStreak} ${view.mobilityStreak == 1 ? 'día' : 'días'} seguidos',
              style: text.bodySmall),
        // §16.30.2: cada 2 semanas mientras la diferencia pase de 2 cm.
        if (ref.watch(kneeWallDueProvider(dayKey(date))).valueOrNull
            case final due?) ...[
          const SizedBox(height: 6),
          Text(
              'En la rutina de mañana: rodilla a la pared, los dos lados. '
              'La última (${formatShort(due.last)}) tenía ${fmtDec(due.diff)} cm de diferencia.',
              key: const ValueKey('rodilla-pared'),
              style: text.bodySmall),
          TextButton.icon(
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const MobilityBenchmarksScreen()));
              ref.invalidate(kneeWallDueProvider);
            },
            icon: const Icon(Icons.straighten_outlined),
            label: const Text('Anotar rodilla a la pared'),
          ),
        ],
      ],
    );
  }

  Future<void> _morning(BuildContext context, WidgetRef ref) async {
    final short = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mañana · Activa'),
        content: const Text(
            '10 min dinámicos y suaves. Sin tiempo: la versión de 4 min.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('4 min')),
          FilledButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('10 min')),
        ],
      ),
    );
    if (short == null || !context.mounted) return;
    await startMobility(context, ref, routine: morningActiva(short: short));
  }
}
