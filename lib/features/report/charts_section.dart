import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../domain/progress.dart';
import '../../domain/chart_evidence.dart';
import '../../domain/supplements.dart';
import '../../ui/widgets.dart';
import '../../ui/theme.dart';
import 'charts.dart';

class ChartsSection extends ConsumerWidget {
  const ChartsSection({super.key, required this.range, this.goalResolver});
  final (String, String) range;
  final ChartGoalResolver? goalResolver;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rounds = ref.watch(roundsSeriesProvider(range));
    final protein = ref.watch(proteinSeriesProvider(range));
    final weights = ref.watch(weightSeriesProvider(range));
    final sites = ref.watch(measurementSitesProvider(range));
    // Creatina (§16.27.5): sus 4 semanas que tocan el período.
    final water = [
      for (final w in ref.watch(creatineWindowsProvider).valueOrNull ?? const [])
        if (creatineWindowOverlaps(
            w.start, parseDay(range.$1), parseDay(range.$2)))
          w
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          'Gráficas: ${formatLong(parseDay(range.$1))} — ${formatLong(parseDay(range.$2))}'),
      AppCard(title: 'Rondas por sesión', children: [
        const Text(
            'Últimas 200 sesiones del período. Importadas, estimadas y cortadas son observaciones; no prueban mejora comparable.'),
        rounds.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text(
                'No se pudieron leer las sesiones. Vuelve a abrir el período.'),
            data: (points) => EvidenceSeries(
                points: points,
                color: Theme.of(context).colorScheme.primary,
                unit: 'rondas',
                integer: true,
                filterType: true)),
      ]),
      AppCard(title: 'Proteína por día · g', children: [
        protein.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text(
                'No se pudieron leer las comidas. Vuelve a abrir el período.'),
            data: (days) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${days.where((d) => d.value != null).length}/${days.length} días con registro · ${days.where((d) => d.status == ChartDayStatus.closed).length} cerrados'),
                      const Text(
                          'Sin registro no significa 0. Las barras apagadas son registros incompletos; revisa los estados abajo.'),
                      if (goalResolver == null)
                        const Text(
                            'Meta histórica no disponible: no usamos la meta actual para fechas pasadas.'),
                      if (goalResolver != null)
                        const Text(
                            'Barra fina: mínimo documentado para ese día. Sin vigencia conocida, no se dibuja meta.'),
                      DailyBarsChart(
                          points: [
                            for (final d in days)
                              if (d.value != null) SeriesPoint(d.date, d.value!)
                          ],
                          days: days,
                          color: AppColors.protein,
                          unit: 'g',
                          goalResolver: goalResolver),
                      ExpansionTile(
                          key: PageStorageKey(
                              'protein-evidence-${range.$1}-${range.$2}'),
                          title: const Text('Ver días y evidencia'),
                          children: [
                            for (final day in days) _dayRow(day),
                          ]),
                    ])),
      ]),
      AppCard(title: 'Peso', children: [
        for (final w in water)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
                '$creatineWaterNote (${formatShort(w.start)} – ${formatShort(w.end)}). '
                'En esas semanas una subida del peso no se lee como grasa.'),
          ),
        weights.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text(
                'No se pudo leer el peso. Vuelve a abrir el período.'),
            data: (points) => EvidenceSeries(
                points: points, color: AppColors.kcal, unit: 'kg'))
      ]),
      sites.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('No se pudieron leer las medidas.'),
          data: (list) => list.isEmpty
              ? const AppCard(title: 'Medidas', children: [
                  EmptyHint(
                      'Sin medidas en este período. Una toma ya aparece como observación.')
                ])
              : _MeasurementChart(sites: list, range: range)),
    ]);
  }

  Widget _dayRow(ChartDay day) {
    final goal = documentedChartGoal(goalResolver, day.date, 'proteinMin', 'g');
    return ListTile(
        title: Text(
            '${formatLong(day.date)} · ${day.value == null ? '—' : '${fmtDec(day.value!)} g'} · ${day.statusLabel}'),
        subtitle: Text(
            '${day.evidence.isEmpty ? 'No hay comida registrada para este día.' : day.evidence}${goal == null ? '' : '\nMínimo documentado: ${fmtDec(goal.value)} g · ${goal.source} (${formatLong(goal.from)} a ${goal.to == null ? "sin fin registrado" : formatLong(goal.to!)}).'}'));
  }
}

/// Type/routine controls change the line, summary and inspectable records together.
class EvidenceSeries extends StatefulWidget {
  const EvidenceSeries(
      {super.key,
      required this.points,
      required this.color,
      required this.unit,
      this.integer = false,
      this.filterType = false});
  final List<SeriesPoint> points;
  final Color color;
  final String unit;
  final bool integer, filterType;
  @override
  State<EvidenceSeries> createState() => _EvidenceSeriesState();
}

class _EvidenceSeriesState extends State<EvidenceSeries> {
  String? _type, _protocol;
  SeriesPoint? _selected;
  @override
  void didUpdateWidget(covariant EvidenceSeries old) {
    super.didUpdateWidget(old);
    _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return const EmptyHint('Sin registros en este período.');
    }
    final types = widget.points
        .map((p) => p.label?.split(' · ').first ?? 'Registro')
        .toSet()
        .toList();
    final type = types.contains(_type) ? _type : types.first;
    final filtered = widget.filterType
        ? widget.points
            .where((p) => p.label?.split(' · ').first == type)
            .toList()
        : widget.points;
    final groups = <String, List<SeriesPoint>>{};
    for (final p in filtered) {
      groups.putIfAbsent(p.protocol ?? 'registro', () => []).add(p);
    }
    final keys = groups.keys.toList();
    if (keys.contains('ayunas')) {
      keys.remove('ayunas');
      keys.insert(0, 'ayunas');
    }
    final key = groups.containsKey(_protocol) ? _protocol! : keys.first;
    final points = groups[key]!;
    final comparable = points.where((p) => p.comparable).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.filterType)
        Wrap(spacing: 6, children: [
          for (final t in types)
            ChoiceChip(
                label: Text(t),
                selected: type == t,
                onSelected: (_) => setState(() {
                      _type = t;
                      _protocol = null;
                      _selected = null;
                    }))
        ]),
      if (keys.length > 1)
        DropdownButtonFormField<String>(
            isExpanded: true,
            isDense: false,
            itemHeight: null,
            value: key,
            decoration:
                const InputDecoration(labelText: 'Condiciones del registro'),
            items: [
              for (var i = 0; i < keys.length; i++)
                DropdownMenuItem(
                    value: keys[i],
                    child: Text(groups[keys[i]]!.first.protocolLabel ??
                        '${groups[keys[i]]!.first.label ?? "Registro"} · condiciones sin detalle'))
            ],
            selectedItemBuilder: (_) => [
                  for (final k in keys)
                    Text(
                        groups[k]!.first.protocolLabel ??
                            groups[k]!.first.label ??
                            'Registro',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)
                ],
            onChanged: (v) => setState(() {
                  _protocol = v;
                  _selected = null;
                })),
      Text(
          '${points.first.label ?? "Registro"} · ${points.length} registros seleccionados · ${widget.unit}'),
      if (keys.length > 1 && points.first.protocolLabel != null)
        Text(points.first.protocolLabel!),
      if (comparable.length >= 2 &&
          dayKey(comparable.first.date) != dayKey(comparable.last.date))
        Text(
            'De ${fmtDec(comparable.first.value)} a ${fmtDec(comparable.last.value)} ${widget.unit} · ${formatLong(comparable.first.date)} a ${formatLong(comparable.last.date)}. Mismas condiciones registradas; diferencia descriptiva.'),
      if (comparable.length < 2)
        const Text(
            'No hay dos registros comparables para concluir una evolución. Los valores observados siguen visibles.'),
      TrendChart(
          points: points,
          color: widget.color,
          unit: widget.unit,
          integer: widget.integer,
          minY: widget.integer ? 0 : null,
          onPointSelected: (p) => setState(() => _selected = p)),
      if (_selected != null)
        Text(
            'Registro seleccionado: ${formatLong(_selected!.date)} · ${fmtDec(_selected!.value)} ${widget.unit}\n${_selected!.evidence}'),
      ExpansionTile(title: const Text('Ver registros y evidencia'), children: [
        for (final p in points)
          ListTile(
              onTap: () => setState(() => _selected = p),
              title: Text(
                  '${formatLong(p.date)} · ${fmtDec(p.value)} ${widget.unit}${p.comparable ? "" : " · observación"}'),
              subtitle: Text(p.evidence))
      ]),
    ]);
  }
}

class _MeasurementChart extends ConsumerStatefulWidget {
  const _MeasurementChart({required this.sites, required this.range});
  final List<MeasureSite> sites;
  final (String, String) range;
  @override
  ConsumerState<_MeasurementChart> createState() => _MeasurementChartState();
}

class _MeasurementChartState extends ConsumerState<_MeasurementChart> {
  MeasureSite? _site;
  @override
  Widget build(BuildContext context) {
    final site = widget.sites.contains(_site) ? _site! : widget.sites.first;
    final unit = ref.watch(profileProvider).value?.lengthUnit ?? LengthUnit.cm;
    final series = ref.watch(
        measurementSeriesProvider((site, widget.range.$1, widget.range.$2)));
    return AppCard(title: 'Medidas · ${site.label}', children: [
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final s in widget.sites)
          ChoiceChip(
              label: Text(s.shortLabel),
              selected: site == s,
              onSelected: (_) => setState(() => _site = s))
      ]),
      series.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('No se pudo leer esta medida.'),
          data: (points) => EvidenceSeries(
              points: points, color: AppColors.body, unit: unit.label)),
    ]);
  }
}
