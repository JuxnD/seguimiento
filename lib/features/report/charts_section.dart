import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../ui/widgets.dart';
import 'charts.dart';

/// Gráficas del informe: rondas, proteína del rango, peso y medidas.
class ChartsSection extends ConsumerWidget {
  const ChartsSection({super.key, required this.range});

  /// (inicio, fin) en formato `YYYY-MM-DD`.
  final (String, String) range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final rounds = ref.watch(roundsSeriesProvider);
    final protein = ref.watch(proteinSeriesProvider(range));
    final weights = ref.watch(weightSeriesProvider);
    final sites = ref.watch(measurementSitesProvider);

    return Column(
      children: [
        AppCard(
          title: 'Rondas por sesión',
          children: [
            rounds.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (points) => Column(
                children: [
                  TrendChart(
                    points: points,
                    color: Theme.of(context).colorScheme.primary,
                    unit: 'rondas',
                    minY: 0,
                  ),
                  if (points.length >= 2)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'De ${fmtInt(points.first.value)} a ${fmtInt(points.last.value)} '
                        'entre ${formatShort(points.first.date)} y ${formatShort(points.last.date)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        AppCard(
          title: 'Proteína por día',
          children: [
            protein.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (points) => DailyBarsChart(
                points: points,
                color: const Color(0xFF4EA8FF),
                goal: (profile?.proteinMin ?? 130).toDouble(),
                unit: 'g',
              ),
            ),
            const SizedBox(height: 6),
            Text('La línea punteada es el mínimo de ${profile?.proteinMin ?? 130} g.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        AppCard(
          title: 'Peso',
          children: [
            weights.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (points) => TrendChart(points: points, color: const Color(0xFFFFB067), unit: 'kg'),
            ),
          ],
        ),
        sites.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? const AppCard(
                  title: 'Medidas',
                  children: [EmptyHint('Con dos tomas de medidas aparece la evolución.')],
                )
              : _MeasurementChart(sites: list),
        ),
      ],
    );
  }
}

class _MeasurementChart extends ConsumerStatefulWidget {
  const _MeasurementChart({required this.sites});

  final List<MeasureSite> sites;

  @override
  ConsumerState<_MeasurementChart> createState() => _MeasurementChartState();
}

class _MeasurementChartState extends ConsumerState<_MeasurementChart> {
  late MeasureSite _site = widget.sites.first;

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(profileProvider).value?.lengthUnit ?? LengthUnit.cm;
    final series = ref.watch(measurementSeriesProvider(_site));
    return AppCard(
      title: 'Medidas',
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final site in widget.sites)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(site.label.split(' ').first),
                    selected: _site == site,
                    onSelected: (_) => setState(() => _site = site),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        series.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (points) => TrendChart(
            points: points,
            color: const Color(0xFF7ED957),
            unit: unit.label,
          ),
        ),
      ],
    );
  }
}
