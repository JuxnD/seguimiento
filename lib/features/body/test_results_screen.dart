import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/fitness_test.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

/// Test 1 / Test 2 / Test 3 con el % de mejora (§19.11) y la dosis inicial
/// que sale del último test.
class TestResultsScreen extends ConsumerWidget {
  const TestResultsScreen({super.key});

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
            const AppCard(
              children: [
                Text('Test 1 en la semana 1 del v3.1, Test 2 en la descarga (16–22 nov) y Test 3 con las pruebas '
                    'del 11 dic. Por lado cuenta el más débil. Lo marcado "con dudas" lleva *.'),
              ],
            ),
            if (r.isEmpty)
              const AppCard(children: [Text('Aún no hay resultados: el Test 1 es el lunes de la semana 1.')])
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
}

/// Último test con resultado de una prueba.
int? lastRound(List<TestResult> results, String item) {
  int? last;
  for (final r in results) {
    if (r.item == item && (last == null || r.round > last)) last = r.round;
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
      if (v == null) return '—';
      final doubtful = results.any((r) => r.round == round && r.item == t.id && !r.clean);
      return '${formatTestValue(t, v)}${doubtful ? '*' : ''}';
    }

    final rows = [for (final t in items) if (results.any((r) => r.item == t.id)) t];
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
              final last = lastRound(results, t.id);
              final pct = last == null || last == 1
                  ? null
                  : improvement(testValue(results, 1, t.id), testValue(results, last, t.id));
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
        if (lastRound(results, t.id) case final round?)
          if (testValue(results, round, t.id) case final v?)
            if (initialDose(t, v) case final dose?) '${t.name}: $dose${t.perSide ? ' por lado' : ''}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reps: el tope del rango al 70–75 % del máximo. Aguantes: series del 50–60 % del tiempo máximo.',
            style: text.bodySmall),
        const SizedBox(height: 6),
        for (final l in lines) Text('• $l', style: text.bodyMedium),
      ],
    );
  }
}
