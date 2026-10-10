import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clock/clock.dart';

import '../../app/providers.dart';
import '../../domain/fitness_test.dart';
import '../../domain/dates.dart' show dayKey;
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import '../training/test_mode_screen.dart';

/// Test 1 / Test 2 / Test 3 con el % de mejora (§19.11) y la dosis inicial
/// que sale del último test.
class TestResultsScreen extends ConsumerWidget {
  const TestResultsScreen({super.key, this.focusPart});
  final TestPart? focusPart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(fitnessTestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Test de condición')),
      body: results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (r) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const AppCard(children: [
              Text(
                  'Elige Test 1, 2 o 3 y la parte que quieras registrar. Por lado cuenta el más débil. Lo marcado "con dudas" lleva *. Abrir una prueba no guarda resultados.')
            ]),
            FutureBuilder<List<String>>(
                future: _planned(ref),
                builder: (_, dates) => dates.data == null || dates.data!.isEmpty
                    ? const SizedBox.shrink()
                    : AppCard(title: 'Calendario previsto', children: [for (final label in dates.data!) Text(label)])),
            AppCard(title: 'Abrir o continuar', children: [
              Wrap(spacing: 8, children: [
                for (final round in [1, 2, 3])
                  for (final part in [
                    if (focusPart != null) focusPart!,
                    ...TestPart.values.where((p) => p != focusPart)
                  ])
                    OutlinedButton(
                        onPressed: () async {
                          final date =
                              await ref.read(fitnessTestRepositoryProvider).recordedDateFor(round, part) ?? clock.now();
                          if (!context.mounted) return;
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => TestModeScreen(date: date, round: round, part: part)));
                        },
                        child: Text('T$round ${part == TestPart.torso ? 'torso' : 'piernas'}')),
              ]),
            ]),
            if (r.isEmpty)
              const AppCard(children: [Text('Aún no hay resultados. Elige una prueba cuando quieras medirla.')])
            else ...[
              AppCard(title: 'Torso, core y habilidades', children: [TestTable(results: r, items: torsoTests)]),
              AppCard(title: 'Piernas', children: [TestTable(results: r, items: legTests)]),
              AppCard(title: 'Dosis inicial', children: [TestDoses(results: r)]),
            ],
          ],
        ),
      ),
    );
  }

  Future<List<String>> _planned(WidgetRef ref) async {
    final repo = ref.read(fitnessTestRepositoryProvider);
    final labels = <String>[];
    for (final round in [1, 2, 3]) {
      for (final part in TestPart.values) {
        final day = await repo.plannedDateFor(round, part);
        if (day != null) {
          labels.add('Previsto: T$round ${part == TestPart.torso ? 'torso' : 'piernas'} · ${dayKey(day)}');
        }
      }
    }
    return labels;
  }
}

/// Último test completo y limpio; conservar parciales en las columnas.
int? lastRound(List<TestResult> results, String item) {
  int? last;
  for (final r in results) {
    if (r.item == item &&
        testValue(results, r.round, item) != null &&
        !results.any((x) => x.round == r.round && x.item == item && !x.clean) &&
        (last == null || r.round > last)) last = r.round;
  }
  return last;
}

class TestTable extends StatelessWidget {
  const TestTable({super.key, required this.results, required this.items});

  final List<TestResult> results;
  final List<TestItem> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    String cell(TestItem t, int round) {
      final v = testValue(results, round, t.id);
      if (v == null) {
        final partial = results.where((r) => r.round == round && r.item == t.id);
        return partial.isEmpty
            ? '—'
            : '${partial.map((r) => '${r.side}: ${formatTestValue(t, r.value)}${r.clean ? '' : '*'}').join('\n')}\nParcial';
      }
      final doubtful = results.any((r) => r.round == round && r.item == t.id && !r.clean);
      final date = results.firstWhere((r) => r.round == round && r.item == t.id).date;
      return '${formatTestValue(t, v)}${doubtful ? '*' : ''}\n${date == null ? 'Fecha sin registrar' : dayKey(date)}';
    }

    final rows = [
      for (final t in items)
        if (results.any((r) => r.item == t.id)) t
    ];
    if (rows.isEmpty) return Text('Sin resultados todavía.', style: text.bodySmall);
    return Table(
      columnWidths: const {0: FlexColumnWidth(2.4)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          for (final h in ['Prueba', 'T1', 'T2', 'T3', 'Mejora'])
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(h, style: text.labelSmall)),
        ]),
        for (final t in rows)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(t.perSide ? '${t.name} (por lado)' : t.name, style: text.bodySmall),
            ),
            for (final round in [1, 2, 3]) Text(cell(t, round), style: text.bodySmall),
            Builder(builder: (_) {
              final last = latestEligibleTestRound(results, t.id, asOf: clock.now());
              final pct = last == null || last == 1
                  ? null
                  : improvement(eligibleTestValue(results, 1, t.id, asOf: clock.now()),
                      eligibleTestValue(results, last, t.id, asOf: clock.now()));
              return Text(
                pct == null ? '—' : '${pct >= 0 ? '+' : ''}${pct.round()} %',
                style: text.bodySmall?.copyWith(
                  color: pct == null ? null : (pct >= 0 ? AppColors.record : Theme.of(context).colorScheme.error),
                ),
              );
            }),
          ]),
      ],
    );
  }
}

class TestDoses extends StatelessWidget {
  const TestDoses({super.key, required this.results});

  final List<TestResult> results;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lines = [
      for (final t in allTests)
        if (latestEligibleTestRound(results, t.id, asOf: clock.now()) case final round?)
          if (eligibleTestValue(results, round, t.id, asOf: clock.now()) case final v?)
            if (initialDose(t, v) case final dose?)
              '${t.name}: $dose${t.perSide ? ' por lado' : ''} (T$round)',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reps: el tope del rango al 70–75 % del máximo. Aguantes: series del 50–60 % del tiempo máximo.',
            style: text.bodySmall),
        const SizedBox(height: 6),
        const Text(
            'Sólo resultados completos y limpios con fecha registrada. Los parciales o con dudas siguen visibles; no aumentan la dosis.'),
        for (final l in lines) Text('• $l', style: text.bodyMedium),
      ],
    );
  }
}
