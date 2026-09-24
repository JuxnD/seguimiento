import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/progress.dart';
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
  });

  final List<SeriesPoint> points;
  final Color color;

  /// Línea horizontal de referencia (meta o mínimo).
  final double? goal;
  final String unit;
  final double? minY;

  /// Valores enteros (rondas): el eje no muestra "1,5 rondas".
  final bool integer;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const EmptyHint('Hacen falta al menos dos registros para ver la línea.');
    }
    final scheme = Theme.of(context).colorScheme;
    final values = points.map((p) => p.value).toList();
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final top = (goal == null ? maxValue : (maxValue > goal! ? maxValue : goal!)) * 1.15;
    final bottom = minY ?? (minValue * 0.9);

    return SizedBox(
      height: 190,
      child: LineChart(
        LineChartData(
          minY: bottom,
          maxY: top,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                interval: integer ? ((top - bottom) / 4).ceilToDouble().clamp(1, double.infinity) : null,
                getTitlesWidget: (value, meta) => value == meta.max ||
                        (integer && value != value.roundToDouble())
                    ? const SizedBox.shrink()
                    : Text(
                        integer ? fmtInt(value) : fmtDec(value, decimals: value.abs() < 10 ? 1 : 0),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (points.length / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(formatShort(points[i].date),
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
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${formatShort(points[s.x.round()].date)}\n${fmtDec(s.y)} $unit'.trim(),
                    TextStyle(color: scheme.onSurface),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value)],
              color: color,
              barWidth: 3,
              isCurved: true,
              curveSmoothness: 0.2,
              dotData: FlDotData(
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3.5,
                  color: color,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withOpacity(0.30), color.withOpacity(0.02)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barras por día: proteína o kcal de la semana, con la meta marcada.
class DailyBarsChart extends StatelessWidget {
  const DailyBarsChart({super.key, required this.points, required this.color, this.goal, this.unit = ''});

  final List<SeriesPoint> points;
  final Color color;
  final double? goal;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (points.every((p) => p.value == 0)) {
      return const EmptyHint('Sin comidas registradas en el rango.');
    }
    final scheme = Theme.of(context).colorScheme;
    final maxValue = seriesMax(points);
    final top = (goal == null ? maxValue : (maxValue > goal! ? maxValue : goal!)) * 1.2;

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: top,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => value == meta.max
                    ? const SizedBox.shrink()
                    : Text(fmtInt(value), style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  // En rangos largos, una etiqueta cada tantas barras (con el
                  // día del mes, no el de la semana, que se repite).
                  final every = (points.length / 8).ceil();
                  if (i % every != 0) return const SizedBox.shrink();
                  final d = points[i].date;
                  return Text(points.length <= 8 ? weekdayShort(d.weekday) : '${d.day}',
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
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${formatShort(points[group.x].date)}\n${fmtInt(rod.toY)} $unit'.trim(),
                TextStyle(color: scheme.onSurface),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].value,
                    // 16 para una semana; más delgadas si el rango es largo.
                    width: (16 * 7 / points.length).clamp(3, 16).toDouble(),
                    borderRadius: BorderRadius.circular(6),
                    // Bajo la meta se ve apagado: el día flojo salta a la vista.
                    color: goal != null && points[i].value < goal!
                        ? color.withOpacity(0.45)
                        : color,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
