import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/progress.dart';
import '../../domain/chart_evidence.dart';
import '../../ui/widgets.dart';

/// Línea de evolución: rondas, peso o una medida. Muestra la tendencia, no
/// cada decimal.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.color,
    this.goal,
    this.unit = '',
    this.minY,
    this.integer = false,
    this.onPointSelected,
  });

  final List<SeriesPoint> points;
  final Color color;

  /// Línea horizontal de referencia (meta o mínimo).
  final double? goal;
  final String unit;
  final double? minY;

  /// Valores enteros (rondas): el eje no muestra "1,5 rondas".
  final bool integer;
  final ValueChanged<SeriesPoint>? onPointSelected;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const EmptyHint('Sin registros en este período.');
    }
    final scheme = Theme.of(context).colorScheme;
    final values = points.map((p) => p.value).toList();
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final top =
        ((goal == null ? maxValue : (maxValue > goal! ? maxValue : goal!)) *
                1.15)
            .clamp(1, double.infinity)
            .toDouble();
    final bottom = minY ?? (minValue * 0.9);

    final span = daysBetween(points.first.date, points.last.date).toDouble();
    final segments = _segments(points);
    return Column(children: [
      if (points.length == 1)
        Text(
            '${formatLong(points.single.date)} · ${fmtDec(points.single.value)} $unit'),
      SizedBox(
        height: 190,
        child: LineChart(
          LineChartData(
            minY: bottom,
            maxY: top,
            minX: 0,
            maxX: span > 0 ? span : 1,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              // Margen derecho para que la última fecha no se corte.
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (_, __) => const SizedBox.shrink(),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  interval: integer
                      ? ((top - bottom) / 4)
                          .ceilToDouble()
                          .clamp(1, double.infinity)
                      : null,
                  getTitlesWidget: (value, meta) => value == meta.max ||
                          (integer && value != value.roundToDouble())
                      ? const SizedBox.shrink()
                      : Text(
                          integer
                              ? fmtInt(value)
                              : fmtDec(value,
                                  decimals: value.abs() < 10 ? 1 : 0),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: (span / 3)
                      .ceilToDouble()
                      .clamp(1, double.infinity)
                      .toDouble(),
                  getTitlesWidget: (value, meta) {
                    if (value != value.roundToDouble()) {
                      return const SizedBox.shrink();
                    }
                    if (points.length == 1 && value != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          formatShort(
                              addDays(points.first.date, value.toInt())),
                          style: Theme.of(context).textTheme.labelSmall),
                    );
                  },
                ),
              ),
            ),
            extraLinesData: goal == null
                ? const ExtraLinesData()
                : ExtraLinesData(horizontalLines: [
                    HorizontalLine(
                      y: goal!,
                      color: scheme.onSurfaceVariant.withOpacity(0.6),
                      strokeWidth: 1,
                      dashArray: [6, 4],
                    ),
                  ]),
            lineTouchData: LineTouchData(
              touchCallback: (event, response) {
                if (event is FlTapUpEvent &&
                    response?.lineBarSpots?.isNotEmpty == true) {
                  final spot = response!.lineBarSpots!.first;
                  onPointSelected
                      ?.call(segments[spot.barIndex][spot.spotIndex]);
                }
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${formatLong(addDays(points.first.date, s.x.round()))}\n${fmtDec(s.y)} $unit'
                          .trim(),
                      TextStyle(color: scheme.onSurface),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              for (final segment in segments)
                LineChartBarData(
                  spots: [
                    for (final p in segment)
                      FlSpot(daysBetween(points.first.date, p.date).toDouble(),
                          p.value)
                  ],
                  color: color,
                  barWidth: 3,
                  isCurved: false,
                  dotData: FlDotData(
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                      radius: 3.5,
                      color: color,
                      strokeWidth: 0,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: false,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withOpacity(0.30),
                        color.withOpacity(0.02)
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      )
    ]);
  }
}

/// Break at an observation that cannot support a comparable line. Protocol
/// mismatches also break even when a caller forgets the series selector.
List<List<SeriesPoint>> _segments(List<SeriesPoint> points) {
  final out = <List<SeriesPoint>>[];
  for (final p in points) {
    if (out.isEmpty ||
        !p.comparable ||
        !out.last.last.comparable ||
        out.last.last.protocol != p.protocol) {
      out.add([p]);
    } else {
      out.last.add(p);
    }
  }
  return out;
}

/// Barras por día: proteína o kcal de la semana, con la meta marcada.
class DailyBarsChart extends StatelessWidget {
  const DailyBarsChart({
    super.key,
    required this.points,
    required this.color,
    this.goal,
    this.unit = '',
    this.emptyText = 'Sin comidas registradas en el rango.',
    this.days,
    this.goalResolver,
  });

  final List<SeriesPoint> points;
  final Color color;
  final double? goal;
  final String unit;
  final String emptyText;
  final List<ChartDay>? days;
  final ChartGoalResolver? goalResolver;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty &&
        (days == null || days!.every((d) => d.value == null))) {
      return EmptyHint(emptyText);
    }
    final scheme = Theme.of(context).colorScheme;
    final timeline = [
      for (final d in days ??
          [
            for (final p in points)
              ChartDay(p.date, p.value, ChartDayStatus.closed)
          ])
        d.date
    ];
    final goals = [
      for (final d in timeline)
        documentedChartGoal(goalResolver, d, 'proteinMin', unit)
    ];
    final maxValue = goals.fold(seriesMax(points),
        (double high, g) => g != null && g.value > high ? g.value : high);
    final top =
        (goal == null ? maxValue : (maxValue > goal! ? maxValue : goal!)) * 1.2;

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: top,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => value == meta.max
                    ? const SizedBox.shrink()
                    : Text(fmtInt(value),
                        style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= (days?.length ?? points.length)) {
                    return const SizedBox.shrink();
                  }
                  // En rangos largos, una etiqueta cada tantas barras (con el
                  // día del mes, no el de la semana, que se repite).
                  final every = ((days?.length ?? points.length) / 5)
                      .ceil()
                      .clamp(1, 10000);
                  if (i % every != 0) return const SizedBox.shrink();
                  final d = days?[i].date ?? points[i].date;
                  return Text(
                      timeline.length <= 8
                          ? weekdayShort(d.weekday)
                          : '${d.day}',
                      style: Theme.of(context).textTheme.labelSmall);
                },
              ),
            ),
          ),
          extraLinesData: goal == null
              ? const ExtraLinesData()
              : ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: goal!,
                    color: scheme.onSurfaceVariant.withOpacity(0.6),
                    strokeWidth: 1,
                    dashArray: [6, 4],
                  ),
                ]),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                '${formatLong(timeline[group.x])}\n${rodIndex == group.barRods.length - 1 && goals[group.x] != null ? "Meta documentada: " : ""}${fmtInt(rod.toY)} $unit\n${rodIndex == group.barRods.length - 1 && goals[group.x] != null ? goals[group.x]?.source : days?[group.x].statusLabel ?? ""}'
                    .trim(),
                TextStyle(color: scheme.onSurface),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < (days?.length ?? points.length); i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  if (days == null || days![i].value != null)
                    BarChartRodData(
                      toY: days?[i].value ?? points[i].value,
                      // 16 para una semana; más delgadas si el rango es largo.
                      width: (16 * 7 / (days?.length ?? points.length))
                          .clamp(3, 16)
                          .toDouble(),
                      borderRadius: BorderRadius.circular(6),
                      // Bajo la meta se ve apagado: el día flojo salta a la vista.
                      color: days?[i].status == ChartDayStatus.incomplete
                          ? color.withOpacity(0.45)
                          : color,
                    ),
                  if (goals[i] != null)
                    BarChartRodData(
                        toY: goals[i]!.value,
                        width: 2,
                        color: scheme.onSurfaceVariant,
                        borderRadius: BorderRadius.zero),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
