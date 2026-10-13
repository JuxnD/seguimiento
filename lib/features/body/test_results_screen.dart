import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clock/clock.dart';

import '../../app/providers.dart';
import '../../domain/fitness_test.dart';
import '../../domain/test_protocol.dart';
import '../../domain/test_attempt_evidence.dart';
import '../../domain/plan_v32.dart';
import '../../data/repositories/plan_repository.dart';
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
            FutureBuilder<PlanDayView?>(
                future: ref.read(planRepositoryProvider).dayFor(clock.now()),
                builder: (context, plan) => plan.data?.scheme != v32Scheme
                    ? const SizedBox.shrink()
                    : AppCard(
                        title: 'Plan v3.2 · protocolo de 13 pruebas',
                        children: [
                            const Text(
                                'Nuevo intento conserva todos los anteriores. El retest copia condiciones; cambiarlas crea otra línea base.'),
                            Wrap(spacing: 8, children: [
                              for (final round in [1, 2, 3])
                                for (final part in TestPart.values)
                                  OutlinedButton(
                                      onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) => TestModeScreen(
                                                  date: clock.now(),
                                                  round: round,
                                                  part: part,
                                                  newAttempt: true,
                                                  scheduleKey: TestScheduleKey(
                                                      scheme: v32Scheme,
                                                      blockStart:
                                                          plan.data!.validFrom!,
                                                      protocolId:
                                                          TestProtocolId.v32_13,
                                                      round: round,
                                                      part: part)))),
                                      child: Text('Nuevo T$round ${part.name}'))
                            ]),
                          ])),
            _AttemptHistory(results: r),
            const AppCard(children: [
              Text(
                  'Elige Test 1, 2 o 3 y la parte que quieras registrar. Por lado cuenta el más débil. Lo marcado "con dudas" lleva *. Abrir una prueba no guarda resultados.')
            ]),
            FutureBuilder<List<String>>(
                future: _planned(ref),
                builder: (_, dates) => dates.data == null || dates.data!.isEmpty
                    ? const SizedBox.shrink()
                    : AppCard(title: 'Calendario previsto', children: [
                        for (final label in dates.data!) Text(label)
                      ])),
            AppCard(title: 'Protocolo anterior · 12 pruebas', children: [
              Wrap(spacing: 8, children: [
                for (final round in [1, 2, 3])
                  for (final part in [
                    if (focusPart != null) focusPart!,
                    ...TestPart.values.where((p) => p != focusPart)
                  ])
                    OutlinedButton(
                        onPressed: () async {
                          final date = await ref
                                  .read(fitnessTestRepositoryProvider)
                                  .recordedDateFor(round, part) ??
                              clock.now();
                          if (!context.mounted) return;
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => TestModeScreen(
                                      date: date, round: round, part: part)));
                        },
                        child: Text(
                            'T$round ${part == TestPart.torso ? 'torso' : 'piernas'}')),
              ]),
            ]),
            if (r.isEmpty)
              const AppCard(children: [
                Text(
                    'Aún no hay resultados. Elige una prueba cuando quieras medirla.')
              ])
            else ...[
              AppCard(
                  title: 'Historial legado de torso (condiciones desconocidas)',
                  children: [
                    TestTable(
                        results: r.where((v) => v.attemptId == null).toList(),
                        items: torsoTests)
                  ]),
              AppCard(title: 'Historial legado de piernas', children: [
                TestTable(
                    results: r.where((v) => v.attemptId == null).toList(),
                    items: legTests)
              ]),
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
          labels.add(
              'Previsto: T$round ${part == TestPart.torso ? 'torso' : 'piernas'} · ${dayKey(day)}');
        }
      }
    }
    return labels;
  }
}

class _AttemptHistory extends ConsumerWidget {
  const _AttemptHistory({required this.results});
  final List<TestResult> results;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
      future: ref.read(fitnessTestRepositoryProvider).attempts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        return Column(children: [
          for (final attempt in snapshot.data!)
            AppCard(
                title:
                    'T${attempt.round} · ${attempt.protocolId == 'v32_13' ? '13' : '12'} pruebas · ${attempt.part} · ${attempt.date}',
                children: [
                  Text(attempt.sessionId == null
                      ? 'Actividad auxiliar sin vínculo conocido; resultados conservados.'
                      : 'Intento registrado con su actividad.'),
                  for (final row
                      in results.where((r) => r.attemptId == attempt.id))
                    Text(
                        '${testItem(row.item)?.name ?? row.item}${row.side == null ? '' : ' (${row.side})'}: ${row.value}'
                        '${row.clean ? '' : ' · con dudas'} · ${row.conditions == null ? 'condiciones desconocidas; sin comparación' : testConditionsLabel(row.conditions)}'),
                  for (final item in results
                      .where((r) => r.attemptId == attempt.id)
                      .map((r) => r.item)
                      .toSet())
                    Text(_attemptSummary(results, attempt.id, item)),
                  Wrap(spacing: 8, children: [
                    for (final fresh in [false, true])
                      OutlinedButton(
                          onPressed: () {
                            final protocol = TestProtocolId.values
                                .where((p) => p.name == attempt.protocolId)
                                .firstOrNull;
                            final date = recordedTestDate(attempt.date);
                            final part = TestPart.values
                                .where((p) => p.name == attempt.part)
                                .firstOrNull;
                            final blockStart = attempt.blockStart == null
                                ? null
                                : recordedTestDate(attempt.blockStart!);
                            if (protocol == null ||
                                date == null ||
                                part == null ||
                                (attempt.blockStart != null &&
                                    blockStart == null)) {
                              showSnack(context,
                                  'Identidad o fecha desconocida; conserva el registro para revisar.');
                              return;
                            }
                            final key = attempt.blockStart == null
                                ? null
                                : TestScheduleKey(
                                    scheme: attempt.scheme,
                                    blockStart: blockStart!,
                                    protocolId: protocol,
                                    round: attempt.round,
                                    part: part);
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => TestModeScreen(
                                        date: fresh ? clock.now() : date,
                                        round: attempt.round,
                                        part: part,
                                        scheduleKey: key,
                                        attemptId: attempt.id,
                                        newAttempt: fresh)));
                          },
                          child: Text(fresh
                              ? 'Retest con estas condiciones'
                              : 'Editar este intento')),
                  ]),
                ]),
        ]);
      });
}

String _attemptSummary(List<TestResult> results, int id, String item) {
  final evidence = observedAttemptValue(results, id, item, asOf: clock.now());
  if (evidence == null) {
    return 'Sin dosis ni comparación: falta evidencia limpia, fecha, ambos lados o condiciones conocidas.';
  }
  final candidates = eligibleAttempts(results, item,
          asOf: clock.now(),
          protocol: evidence.protocol,
          conditions: evidence.conditions)
      .where((e) => e.attemptId <= id)
      .toList();
  final pct = candidates.isEmpty
      ? null
      : comparableAttemptImprovement(candidates.first, evidence);
  final definition = testItem(item)!;
  final dose = initialDose(definition, evidence.value);
  return '${definition.name}: ${dose ?? 'sin dosis derivada'}${definition.perSide ? ' por lado' : ''}'
      '${pct == null ? ' · sin comparación anterior compatible' : ' · ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)} % con la misma línea base'}';
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
        final partial =
            results.where((r) => r.round == round && r.item == t.id);
        return partial.isEmpty
            ? '—'
            : '${partial.map((r) => '${r.side}: ${formatTestValue(t, r.value)}${r.clean ? '' : '*'}').join('\n')}\nParcial';
      }
      final doubtful =
          results.any((r) => r.round == round && r.item == t.id && !r.clean);
      final date =
          results.firstWhere((r) => r.round == round && r.item == t.id).date;
      return '${formatTestValue(t, v)}${doubtful ? '*' : ''}\n${date == null ? 'Fecha sin registrar' : dayKey(date)}';
    }

    final rows = [
      for (final t in items)
        if (results.any((r) => r.item == t.id)) t
    ];
    if (rows.isEmpty) {
      return Text('Sin resultados todavía.', style: text.bodySmall);
    }
    return Table(
      columnWidths: const {0: FlexColumnWidth(2.4)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(children: [
          for (final h in ['Prueba', 'T1', 'T2', 'T3', 'Mejora'])
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(h, style: text.labelSmall)),
        ]),
        for (final t in rows)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(t.perSide ? '${t.name} (por lado)' : t.name,
                  style: text.bodySmall),
            ),
            for (final round in [1, 2, 3])
              Text(cell(t, round), style: text.bodySmall),
            Builder(builder: (_) {
              // Unknown legacy measurement conditions cannot establish a baseline.
              const double? pct = null;
              return Text(
                pct == null ? '—' : '${pct >= 0 ? '+' : ''}${pct.round()} %',
                style: text.bodySmall?.copyWith(
                  color: pct == null
                      ? null
                      : (pct >= 0
                          ? AppColors.record
                          : Theme.of(context).colorScheme.error),
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
    final lines = <String>[];
    for (final t in [...allTests, reversePlankTest]) {
      final measurements = eligibleAttempts(results, t.id, asOf: clock.now());
      if (measurements.isEmpty) continue;
      final latest = measurements.last;
      final dose = initialDose(t, latest.value);
      if (dose == null) continue;
      lines.add('${t.name}: $dose${t.perSide ? ' por lado' : ''} '
          '(intento${latest.attemptId}, ${dayKey(latest.date)}, ${latest.protocol}; condiciones conocidas)');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            'Reps: el tope del rango al 70–75 % del máximo. Aguantes: series del 50–60 % del tiempo máximo.',
            style: text.bodySmall),
        const SizedBox(height: 6),
        const Text(
            'Sólo intentos completos y limpios con fecha y condiciones conocidas. Cada dosis identifica su intento y protocolo; desconocidos y parciales siguen visibles sin aumentar la dosis.'),
        for (final l in lines) Text('• $l', style: text.bodyMedium),
      ],
    );
  }
}
