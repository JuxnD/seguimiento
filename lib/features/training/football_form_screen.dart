import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/habits.dart';
import '../../domain/recovery.dart';
import '../../ui/widgets.dart';

class FootballFormScreen extends ConsumerStatefulWidget {
  const FootballFormScreen({super.key, this.existing, this.date});

  final FootballGameRow? existing;

  /// Día del partido al crear uno; por defecto, hoy.
  final DateTime? date;

  @override
  ConsumerState<FootballFormScreen> createState() => _FootballFormScreenState();
}

class _FootballFormScreenState extends ConsumerState<FootballFormScreen> {
  late DateTime _date =
      widget.existing == null ? dateOnly(widget.date ?? DateTime.now()) : parseDay(widget.existing!.date);
  late int _format = widget.existing?.format ?? 5;
  late final _minutes = TextEditingController(text: widget.existing?.minutes.toString() ?? '');
  late final _steps = TextEditingController(text: widget.existing?.steps?.toString() ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late int? _intensity = widget.existing?.intensity;
  late int? _fatigue = widget.existing?.fatigueAfter;
  late bool _knock = widget.existing?.knock ?? false;

  // Hidratación (§19.3): pesarse antes y después y anotar lo que se bebió.
  late final _before = TextEditingController(
      text: widget.existing?.weightBeforeKg == null ? '' : fmtDec(widget.existing!.weightBeforeKg!));
  late final _after = TextEditingController(
      text: widget.existing?.weightAfterKg == null ? '' : fmtDec(widget.existing!.weightAfterKg!));
  late final _fluid = TextEditingController(text: widget.existing?.fluidMl?.toString() ?? '');

  /// Los dos pesajes son del mismo partido y comparables (plan 040): true sólo
  /// si se confirma; false después de comer o con la medición alterada; null
  /// sin responder (y en los partidos de antes).
  late bool? _comparable = widget.existing?.weightsComparable;

  /// Pesajes "antes/después del fútbol" anotados ese día, ofrecidos para
  /// este partido. No se copian sin confirmar: con dos partidos el mismo día
  /// podrían ser del otro.
  ({String? before, String? after})? _dayWeights;

  @override
  void initState() {
    super.initState();
    if (widget.existing == null) _loadDayWeights();
  }

  Future<void> _loadDayWeights() async {
    final weights = await ref.read(bodyRepositoryProvider).weightsOn(_date);
    if (!mounted) return;
    String? kgOf(WeighMoment m) {
      final w = weights.where((w) => weighMomentOf(w.moment, fasted: w.fasted) == m).firstOrNull;
      return w == null ? null : fmtDec(w.kg);
    }

    final before = kgOf(WeighMoment.antesFutbol);
    final after = kgOf(WeighMoment.despuesFutbol);
    setState(() => _dayWeights = before == null && after == null ? null : (before: before, after: after));
  }

  /// "Sí, usarlos": pasan al formulario los que estén vacíos.
  void _useDayWeights() {
    final w = _dayWeights;
    if (w == null) return;
    setState(() {
      if (_before.text.isEmpty && w.before != null) _before.text = w.before!;
      if (_after.text.isEmpty && w.after != null) _after.text = w.after!;
      _dayWeights = null;
    });
  }

  bool get _bothWeights => parseNum(_before.text) != null && parseNum(_after.text) != null;

  @override
  void dispose() {
    for (final c in [_minutes, _steps, _notes, _before, _after, _fluid]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes.text);
    if (minutes == null) {
      showSnack(context, 'Faltan los minutos jugados');
      return;
    }
    // Con el peso de antes, pedir lo que falta para la hidratación (§16.26).
    final missing = [
      if (parseNum(_after.text) == null) 'el peso de después',
      if (int.tryParse(_fluid.text) == null) 'lo bebido durante (0 si nada)',
    ];
    if (parseNum(_before.text) != null && missing.isNotEmpty) {
      final saveAnyway = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Falta para la hidratación'),
          content: Text('Anotaste el peso de antes, pero falta ${missing.join(' y ')}. '
              'Sin eso no se calcula el sudor ni cuánto reponer.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Completar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar así')),
          ],
        ),
      );
      if (saveAnyway != true || !mounted) return;
    }
    final ok = await guarded(context, () => ref.read(trainingRepositoryProvider).saveFootball(FootballGamesCompanion(
          id: widget.existing == null ? const Value.absent() : Value(widget.existing!.id),
          date: Value(dayKey(_date)),
          format: Value(_format),
          minutes: Value(minutes),
          steps: Value(int.tryParse(_steps.text)),
          intensity: Value(_intensity),
          fatigueAfter: Value(_fatigue),
          knock: Value(_knock),
          notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
          weightBeforeKg: Value(parseNum(_before.text)),
          weightAfterKg: Value(parseNum(_after.text)),
          fluidMl: Value(int.tryParse(_fluid.text)),
          weightsComparable: Value(_bothWeights ? _comparable : null),
        )));
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Nuevo fútbol' : 'Editar fútbol'),
        actions: [
          if (widget.existing != null)
            IconButton(tooltip: 'Borrar', 
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDelete(context, 'el partido')) {
                  if (!context.mounted) return;
                  final ok = await guarded(context, () => ref.read(trainingRepositoryProvider).deleteFootball(widget.existing!.id), failure: 'No se pudo borrar');
                  if (ok && context.mounted) Navigator.pop(context, true);
                }
              },
            ),
        ],
      ),
      body: ListView(
        children: [
          AppCard(
            children: [
              DateTile(
                date: _date,
                onChanged: (v) {
                  setState(() {
                    _date = v;
                    _dayWeights = null;
                  });
                  if (widget.existing == null) _loadDayWeights();
                },
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('Fútbol 5')),
                  ButtonSegment(value: 7, label: Text('Fútbol 7')),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: NumberField(controller: _minutes, label: 'Minutos', suffix: 'min', autofocus: widget.existing == null)),
                  const SizedBox(width: 8),
                  Expanded(child: NumberField(controller: _steps, label: 'Pasos')),
                ],
              ),
            ],
          ),
          AppCard(
            title: 'Hidratación',
            children: [
              const Text('400–560 ml unas 4 h antes. Si pasa de 60 min, 0,5–0,8 L por hora con sodio.'),
              const SizedBox(height: 8),
              if (_dayWeights case final w?) ...[
                Text(
                  'Hay pesajes de ese día: '
                  '${[if (w.before != null) 'antes ${w.before} kg', if (w.after != null) 'después ${w.after} kg'].join(' · ')}. '
                  '¿Son de este partido?',
                ),
                Wrap(spacing: 8, children: [
                  TextButton(onPressed: () => setState(() => _dayWeights = null), child: const Text('No son de este')),
                  FilledButton.tonal(onPressed: _useDayWeights, child: const Text('Sí, usarlos')),
                ]),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                      child: NumberField(
                          controller: _before, label: 'Peso antes', suffix: 'kg', decimal: true, onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: NumberField(
                          controller: _after, label: 'Peso después', suffix: 'kg', decimal: true, onChanged: (_) => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              NumberField(
                  controller: _fluid, label: 'Bebido durante (0 si nada)', suffix: 'ml', onChanged: (_) => setState(() {})),
              if (_bothWeights) ...[
                const SizedBox(height: 8),
                const Text('¿Los dos pesajes son comparables (sin comer ni beber entre medias, misma ropa)?'),
                Wrap(spacing: 6, children: [
                  ChoiceChip(
                    label: const Text('Sí, comparables'),
                    selected: _comparable == true,
                    onSelected: (_) => setState(() => _comparable = _comparable == true ? null : true),
                  ),
                  ChoiceChip(
                    label: const Text('No: comí o cambió algo'),
                    selected: _comparable == false,
                    onSelected: (_) => setState(() => _comparable = _comparable == false ? null : false),
                  ),
                ]),
                if (_comparable == false)
                  const Text('Con pesajes no comparables no se calcula el sudor.')
                else if (_comparable == null)
                  const Text('Confirma si son comparables para calcular el sudor.')
                else if (int.tryParse(_fluid.text) == null)
                  const Text('Anota lo bebido (0 si nada) para calcular el sudor.'),
              ],
              if (sweatReading(
                beforeKg: parseNum(_before.text),
                afterKg: parseNum(_after.text),
                fluidMl: int.tryParse(_fluid.text),
                minutes: int.tryParse(_minutes.text),
                weightsComparable: _comparable,
              )
                  case final s?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    s.lossKg > 0
                        ? 'Perdiste ${fmtDec(s.lossKg)} kg · sudor ≈ ${fmtDec(s.ratePerHourL)} L/h. '
                            'Bebe ≈ ${fmtDec(s.replaceL)} L en las próximas horas.'
                        : 'No perdiste peso: la hidratación alcanzó (sudor ≈ ${fmtDec(s.ratePerHourL)} L/h).',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
            ],
          ),
          AppCard(
            title: 'Sensaciones',
            children: [
              ScaleSelector(
                  label: 'Intensidad percibida', value: _intensity, onChanged: (v) => setState(() => _intensity = v)),
              const SizedBox(height: 12),
              ScaleSelector(label: 'Fatiga posterior', value: _fatigue, onChanged: (v) => setState(() => _fatigue = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hubo golpe o molestia'),
                subtitle: const Text('Si fue intenso o hubo golpe, el lunes baja'),
                value: _knock,
                onChanged: (v) => setState(() => _knock = v),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: const Text('Guardar'),
      ),
    );
  }
}
