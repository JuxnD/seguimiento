import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/progress_metrics.dart';
import '../../domain/personal_radar.dart';
import '../../ui/widgets.dart';

/// Standalone renderer; the caller owns evidence, references and navigation.
class PersonalRadarWidget extends StatefulWidget {
  const PersonalRadarWidget(
      {super.key,
      required this.radar,
      this.onRegister,
      this.onConfigure,
      this.onAxisSelected});
  final PersonalRadar radar;
  final ValueChanged<RadarAxis>? onRegister, onConfigure, onAxisSelected;
  @override
  State<PersonalRadarWidget> createState() => _PersonalRadarWidgetState();
}

class _PersonalRadarWidgetState extends State<PersonalRadarWidget> {
  bool _showInitial = true;
  RadarAxis? _selected;
  void _select(RadarAxis axis) {
    setState(() => _selected = axis);
    widget.onAxisSelected?.call(axis);
  }

  @override
  Widget build(BuildContext context) {
    final radar = widget.radar, scheme = Theme.of(context).colorScheme;
    final current = RadarProfile(radar, initial: false),
        initial = RadarProfile(radar, initial: true);
    final count = current.fractions.where((v) => v != null).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(title: 'Capacidades medidas', children: [
        Text(
            'Evidencia hasta ${formatLong(radar.asOf)}. No es una nota universal de condición física.'),
        if (!radar.hasRecords)
          const Text(
              'Sin registros de pruebas. Sin medición no significa cero ni debilidad.'),
        if (radar.hasRecords && count == 0)
          const Text(
              'Sin ejes normalizados: revisa mediciones y referencias personales. Los valores crudos siguen abajo.'),
        if (count > 0 && count < 6)
          Text(
              '$count de 6 ejes con medición apta y referencia. Los demás quedan sin coordenada.'),
        Wrap(spacing: 16, runSpacing: 6, children: [
          Text('Actual: última apta', style: TextStyle(color: scheme.primary)),
          if (_showInitial)
            const Text('Inicio: primera apta (línea discontinua)',
                style: TextStyle(color: RadarPainter.initialColor))
        ]),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar punto de partida'),
            value: _showInitial,
            onChanged: (v) => setState(() => _showInitial = v)),
        LayoutBuilder(
            builder: (context, constraints) => Semantics(
                label:
                    'Radar personal, $count de 6 ejes normalizados. Usa los botones de cada eje para consultar su evidencia.',
                child: GestureDetector(
                    key: const Key('radar-canvas'),
                    onTapUp: (details) {
                      final size = Size.square(constraints.maxWidth);
                      var best = 0, distance = double.infinity;
                      for (var i = 0; i < 6; i++) {
                        final d = (details.localPosition -
                                RadarPainter.axisPoint(size, i, 1.4))
                            .distance;
                        if (d < distance) {
                          distance = d;
                          best = i;
                        }
                      }
                      _select(RadarAxis.values[best]);
                    },
                    child: SizedBox.square(
                        dimension: constraints.maxWidth,
                        child: CustomPaint(
                            painter: RadarPainter(
                                current: current,
                                initial: initial,
                                showInitial: _showInitial,
                                currentColor: scheme.primary,
                                gridColor: scheme.outlineVariant,
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .labelLarge!
                                    .copyWith(fontSize: 16),
                                textScaler:
                                    MediaQuery.textScalerOf(context))))))),
        const Text(
            '100% equivale a la referencia personal mostrada abajo. Ambos contornos usan la misma referencia. Un hueco no se rellena con 0.'),
        if (radar.freshness == null)
          const Text(
              'Sin ventana de actualidad definida: consulta fecha y antigüedad; la última prueba no describe necesariamente cómo estás hoy.')
        else
          Text(
              'Ventana de actualidad: ${radar.freshness!.maxAgeDays} días · ${radar.freshness!.source}.'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final axis in RadarAxis.values)
            OutlinedButton(
                key: Key('radar-axis-${axis.name}'),
                onPressed: () => _select(axis),
                child: Text('${axis.index + 1}. ${axis.label}'))
        ]),
      ]),
      if (_selected != null)
        AppCard(title: 'Evidencia de ${_selected!.label}', children: [
          _details(radar.axis(_selected!)),
        ]),
      for (final axis in radar.axes)
        AppCard(title: '${axis.axis.index + 1}. ${axis.axis.label}', children: [
          _details(axis),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (widget.onRegister != null)
              OutlinedButton(
                  onPressed: () => widget.onRegister!(axis.axis),
                  child: Text('Registrar ${axis.axis.label}')),
            if (widget.onConfigure != null)
              TextButton(
                  onPressed: () => widget.onConfigure!(axis.axis),
                  child: Text(
                      '${axis.reference == null ? 'Definir' : 'Revisar'} referencia de ${axis.axis.label}'))
          ]),
        ]),
    ]);
  }

  Widget _details(RadarAxisEvidence axis) {
    final a = axis.axis, ref = axis.reference;
    String date(RadarObservation o) => o.date == null
        ? 'fecha común sin registrar'
        : '${formatLong(o.date!)} · ${daysBetween(o.date!, widget.radar.asOf)} ${daysBetween(o.date!, widget.radar.asOf).abs() == 1 ? 'día' : 'días'} respecto del corte';
    String value(RadarObservation o) => o.cindy == null
        ? o.value == null
            ? 'valor no resoluble'
            : '${fmtDec(o.value!)} ${a.unit}'
        : '${o.cindy!.rounds ?? '?'} rondas + ${o.cindy!.extraReps ?? '?'} reps';
    final first = axis.firstEligible,
        current = axis.current,
        latest = axis.latestObserved;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Protocolo: ${testProtocolName(a)}.'),
      if (first != null) Text('Inicio: ${value(first)} · ${date(first)}.'),
      if (current != null)
        Text('Última apta: ${value(current)} · ${date(current)}.'),
      if (current != null) Text(current.quality),
      if (current == null) Text(axis.currentIssue),
      if (current == null && axis.lastEligible != null)
        Text(
            'Histórica apta: ${value(axis.lastEligible!)} · ${date(axis.lastEligible!)}.'),
      if (ref == null)
        Text(
            '${axis.referenceIssue} Se conserva el valor crudo; no hay puntuación.'),
      if (ref != null)
        Text(
            'Referencia común: ${fmtDec(ref.value)} ${ref.unit} · ${ref.source}. Vigente desde ${formatLong(ref.from)}${ref.until == null ? ', sin fin registrado' : ' hasta ${formatLong(ref.until!)}'}.'),
      if (axis.initialPercent != null)
        Text('Inicio hacia referencia: ${fmtDec(axis.initialPercent!)}%.'),
      if (axis.currentPercent != null)
        Text(
            'Actual hacia referencia: ${fmtDec(axis.currentPercent!)}%${axis.currentPercent! > 100 ? ' (dibujo limitado a 100%; valor real conservado)' : ''}.'),
      if (first != null && current != null)
        Text(!axis.hasDifferentDates
            ? 'Una sola fecha apta: no hay cambio entre fechas demostrado.'
            : axis.changePercent == null
                ? 'Cambio porcentual desde 0: no calculable.'
                : 'Cambio de la prueba: ${fmtDec(axis.changePercent!)}%; mismo protocolo.'),
      if (latest != null && latest != current)
        Text(
            'Último intento observado: ${value(latest)} · ${date(latest)}. ${latest.reason}'),
      if (axis.observations.any((o) => o.orderDate == null))
        const Text(
            'Hay observaciones sin fecha; no se puede afirmar cuál fue la última.'),
      if (axis.observations.isNotEmpty)
        ExpansionTile(title: const Text('Ver intentos guardados'), children: [
          for (final o in axis.observations)
            ListTile(
                title: Text(
                    '${o.cindy != null ? 'Cindy' : o.testRows.isEmpty ? 'Prueba' : 'Test ${o.testRows.first.round} · ${testProtocolName(a)}'} · ${o.eligible ? 'Apta para esta prueba' : 'Observación'}'),
                subtitle: Text('${o.raw}\n${o.quality}\n${o.reason}'))
        ]),
      if (a != RadarAxis.circuit)
        const Text(
            'Peso corporal y carga no se guardan en estos tests. No se calculan fuerza máxima o cocientes de peso.'),
    ]);
  }
}

String testProtocolName(RadarAxis axis) => switch (axis) {
      RadarAxis.pull => 'Dominadas pronas estrictas, prueba máxima',
      RadarAxis.push => 'Flexiones normales, prueba máxima',
      RadarAxis.core => 'Hollow con lumbar pegada, segundos',
      RadarAxis.legs => 'Búlgara sin peso, I/D del mismo día, cuenta el menor',
      RadarAxis.jump => 'Salto horizontal desde parado, cm',
      RadarAxis.circuit => 'Cindy 5/10/15, 20 min, sin peso externo'
    };

class RadarPainter extends CustomPainter {
  RadarPainter(
      {required this.current,
      required this.initial,
      required this.showInitial,
      required this.currentColor,
      required this.gridColor,
      required this.textStyle,
      required this.textScaler});
  static const initialColor = Color(0xff3dd6c6);
  final RadarProfile current, initial;
  final bool showInitial;
  final Color currentColor, gridColor;
  final TextStyle textStyle;
  final TextScaler textScaler;
  List<String> axisLabels(Size size) => [
        for (final axis in RadarAxis.values)
          textScaler.scale(16) >= 32 || size.shortestSide < 280
              ? '${axis.index + 1}'
              : axis.label
      ];
  static Offset axisPoint(Size size, int index, double fraction) {
    final angle = -math.pi / 2 + index * math.pi / 3;
    return Offset(size.width / 2, size.height / 2) +
        Offset(math.cos(angle), math.sin(angle)) *
            size.shortestSide *
            .29 *
            fraction;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final fraction in [.25, .5, .75, 1.0]) {
      final path = Path()
        ..moveTo(
            axisPoint(size, 0, fraction).dx, axisPoint(size, 0, fraction).dy);
      for (var i = 1; i < 6; i++) {
        final p = axisPoint(size, i, fraction);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, grid);
    }
    for (var i = 0; i < 6; i++) {
      canvas.drawLine(axisPoint(size, i, 0), axisPoint(size, i, 1), grid);
      final text = TextPainter(
          text: TextSpan(text: axisLabels(size)[i], style: textStyle),
          textDirection: TextDirection.ltr,
          textScaler: textScaler)
        ..layout();
      final wanted =
          axisPoint(size, i, 1.4) - Offset(text.width / 2, text.height / 2);
      text.paint(
          canvas,
          Offset(
              wanted.dx
                  .clamp(0, math.max(0, size.width - text.width))
                  .toDouble(),
              wanted.dy
                  .clamp(0, math.max(0, size.height - text.height))
                  .toDouble()));
      text.dispose();
    }
    if (showInitial) _profile(canvas, size, initial, initialColor, true);
    _profile(canvas, size, current, currentColor, false);
  }

  void _profile(Canvas canvas, Size size, RadarProfile profile, Color color,
      bool dashed) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    if (profile.closed && !dashed) {
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final p = axisPoint(size, i, profile.fractions[i]!);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color.withOpacity(.12));
    }
    for (var i = 0; i < 6; i++) {
      final fraction = profile.fractions[i];
      if (fraction == null) continue;
      final start = axisPoint(size, i, fraction);
      final next = (i + 1) % 6, nextFraction = profile.fractions[next];
      if (nextFraction != null) {
        final end = axisPoint(size, next, nextFraction);
        if (dashed) {
          final vector = end - start, length = vector.distance;
          if (length > 0) {
            for (var d = 0.0; d < length; d += 9) {
              canvas.drawLine(start + vector * (d / length),
                  start + vector * (math.min(d + 5, length) / length), paint);
            }
          }
        } else {
          canvas.drawLine(start, end, paint);
        }
      }
      canvas.drawCircle(start, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) => true;
}
