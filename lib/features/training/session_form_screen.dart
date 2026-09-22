import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/session_math.dart';
import '../../ui/widgets.dart';

SessionType _sessionTypeFor(DayType type) => switch (type) {
      DayType.circuito => SessionType.circuito,
      DayType.circuitoLigero => SessionType.circuitoLigero,
      DayType.progresion => SessionType.progresion,
      DayType.bloques => SessionType.bloques,
      _ => SessionType.otro,
    };

/// Alta y edición de una sesión. Acepta un borrador ya poblado por el
/// contador de rondas.
class SessionFormScreen extends ConsumerStatefulWidget {
  const SessionFormScreen({super.key, required this.draft});

  final SessionDraft draft;

  @override
  ConsumerState<SessionFormScreen> createState() => _SessionFormScreenState();
}

class _SessionFormScreenState extends ConsumerState<SessionFormScreen> {
  late final SessionDraft d = widget.draft;
  late final _total = TextEditingController(text: d.totalSec == 0 ? '' : formatDuration(d.totalSec));
  late final _warmup = TextEditingController(text: d.warmupSec == 0 ? '' : formatDuration(d.warmupSec));
  late final _cooldown = TextEditingController(text: d.cooldownSec == 0 ? '' : formatDuration(d.cooldownSec));
  late final _rounds = TextEditingController(text: d.roundsDone?.toString() ?? '');
  late final _context = TextEditingController(text: d.context ?? '');
  late final _notes = TextEditingController(text: d.notes ?? '');
  late final _limiting = TextEditingController(text: d.limitingExercise ?? '');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_total, _warmup, _cooldown, _rounds, _context, _notes, _limiting]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncTimes() {
    d
      ..totalSec = parseDuration(_total.text) ?? 0
      ..warmupSec = parseDuration(_warmup.text) ?? 0
      ..cooldownSec = parseDuration(_cooldown.text) ?? 0;
  }

  Future<void> _loadPlanExercises() async {
    final view = await ref.read(planRepositoryProvider).dayFor(d.date);
    if (view == null || view.day.exercises.isEmpty) {
      if (mounted) showSnack(context, 'El plan no tiene ejercicios para ese día');
      return;
    }
    setState(() {
      d.planDayId = view.dayId;
      d.type = _sessionTypeFor(view.day.type);
      for (final e in view.day.exercises) {
        final sets = e.sets ?? 1;
        for (var i = 0; i < sets; i++) {
          d.sets.add(SetDraft(exercise: e.name, reps: e.repsMin ?? 0));
        }
      }
    });
  }

  Future<void> _estimateRounds() async {
    _syncTimes();
    final historical = await ref.read(trainingRepositoryProvider).historicalMeanRoundSec();
    if (!mounted) return;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _EstimateDialog(netSec: d.netSec, historicalMeanSec: historical),
    );
    if (result != null) {
      setState(() {
        d
          ..roundsDone = result
          ..roundsEstimated = true;
        _rounds.text = '$result';
      });
    }
  }

  Future<void> _addExercise() async {
    final exercises = ref.read(exercisesProvider).value ?? [];
    final res = await showDialog<_NewExercise>(
      context: context,
      builder: (_) => _AddExerciseDialog(known: exercises.map((e) => e.name).toList()),
    );
    if (res == null) return;
    setState(() {
      for (var i = 0; i < res.sets; i++) {
        d.sets.add(SetDraft(exercise: res.name, reps: res.reps));
      }
    });
  }

  Future<void> _save() async {
    _syncTimes();
    d
      ..roundsDone = int.tryParse(_rounds.text)
      ..context = _context.text
      ..notes = _notes.text
      ..limitingExercise = _limiting.text;
    setState(() => _saving = true);
    try {
      await ref.read(trainingRepositoryProvider).save(d);
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<SetDraft>>{};
    for (final s in d.sets) {
      groups.putIfAbsent(s.exercise, () => []).add(s);
    }
    final net = parseDuration(_total.text) == null
        ? null
        : circuitNetSec(
            totalSec: parseDuration(_total.text) ?? 0,
            warmupSec: parseDuration(_warmup.text) ?? 0,
            cooldownSec: parseDuration(_cooldown.text) ?? 0,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(d.id == null ? 'Nueva sesión' : 'Editar sesión'),
        actions: [
          if (d.id != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDelete(context, 'la sesión')) {
                  await ref.read(trainingRepositoryProvider).delete(d.id!);
                  if (context.mounted) Navigator.pop(context, true);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          AppCard(
            title: 'Cuándo',
            children: [
              DateTile(date: d.date, onChanged: (v) => setState(() => d.date = v)),
              TimeTile(time: d.startTime, onChanged: (v) => setState(() => d.startTime = v)),
              const SizedBox(height: 8),
              SegmentedButton<SessionType>(
                segments: [
                  for (final t in SessionType.values) ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {d.type},
                onSelectionChanged: (s) => setState(() => d.type = s.first),
              ),
            ],
          ),
          AppCard(
            title: 'Tiempos',
            children: [
              Row(
                children: [
                  Expanded(child: DurationField(controller: _total, label: 'Total', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DurationField(controller: _warmup, label: 'Calentamiento', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DurationField(controller: _cooldown, label: 'Enfriamiento', onChanged: (_) => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Text('Circuito neto: ${net == null ? '—' : formatDuration(net)}',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NumberField(
                      controller: _rounds,
                      label: 'Rondas',
                      onChanged: (_) => setState(() => d.roundsEstimated = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _estimateRounds,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('Estimar'),
                  ),
                ],
              ),
              if (d.roundsEstimated)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Rondas estimadas por tiempo (se marca en el informe)'),
                ),
              if (d.roundMarksSec.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Vueltas: ${lapDurations(d.roundMarksSec).map(formatDuration).join(' · ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          AppCard(
            title: 'Ejercicios',
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Cargar del plan',
                  icon: const Icon(Icons.playlist_add),
                  onPressed: _loadPlanExercises,
                ),
                IconButton(tooltip: 'Añadir', icon: const Icon(Icons.add), onPressed: _addExercise),
              ],
            ),
            children: [
              if (groups.isEmpty) const EmptyHint('Sin ejercicios. Cárgalos del plan o añádelos.'),
              for (final entry in groups.entries) ...[
                Row(
                  children: [
                    Expanded(child: Text(entry.key, style: Theme.of(context).textTheme.titleSmall)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => d.sets.add(SetDraft(
                            exercise: entry.key,
                            reps: entry.value.last.reps,
                          ))),
                    ),
                  ],
                ),
                for (var i = 0; i < entry.value.length; i++)
                  _SetRow(
                    index: i + 1,
                    set: entry.value[i],
                    onChanged: () => setState(() {}),
                    onDelete: () => setState(() => d.sets.remove(entry.value[i])),
                  ),
                const Divider(),
              ],
            ],
          ),
          AppCard(
            title: 'Regla de progresión',
            children: [
              const Text('Solo se sube de ronda con las tres en verde, sin series partidas y sin fallo.'),
              const SizedBox(height: 8),
              _TriToggle(
                label: 'Técnica buena',
                value: d.techniqueOk,
                onChanged: (v) => setState(() => d.techniqueOk = v),
              ),
              _TriToggle(
                label: 'Rango completo',
                value: d.fullRange,
                onChanged: (v) => setState(() => d.fullRange = v),
              ),
              _TriToggle(
                label: 'Recuperación normal',
                value: d.recoveryOk,
                onChanged: (v) => setState(() => d.recoveryOk = v),
              ),
            ],
          ),
          AppCard(
            title: 'Sensaciones y contexto',
            children: [
              ScaleSelector(label: 'RPE general', value: d.rpe, onChanged: (v) => setState(() => d.rpe = v)),
              const SizedBox(height: 12),
              _ExerciseAutocomplete(
                controller: _limiting,
                label: 'Ejercicio limitante',
                options: (ref.watch(exercisesProvider).value ?? []).map((e) => e.name).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _context,
                decoration: const InputDecoration(
                  labelText: 'Contexto',
                  hintText: 'Oficina, fútbol intenso ayer, dormí 5 h…',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()),
                maxLines: 3,
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save),
        label: const Text('Guardar'),
      ),
    );
  }
}

/// Sí / No / sin registrar. El null importa: no es lo mismo "no lo anoté" que
/// "la técnica falló".
class _TriToggle extends StatelessWidget {
  const _TriToggle({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          ChoiceChip(
            label: const Text('Sí'),
            selected: value == true,
            onSelected: (sel) => onChanged(sel ? true : null),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('No'),
            selected: value == false,
            onSelected: (sel) => onChanged(sel ? false : null),
          ),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.index, required this.set, required this.onChanged, required this.onDelete});

  final int index;
  final SetDraft set;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$index.')),
          SizedBox(
            width: 72,
            child: TextFormField(
              initialValue: set.reps == 0 ? '' : '${set.reps}',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'reps', border: OutlineInputBorder()),
              onChanged: (v) {
                set.reps = int.tryParse(v) ?? 0;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          if (set.split)
            Expanded(
              child: TextFormField(
                initialValue: set.splitDetail ?? '',
                decoration: const InputDecoration(labelText: 'partida', hintText: '12+3', border: OutlineInputBorder()),
                onChanged: (v) => set.splitDetail = v,
              ),
            )
          else
            const Spacer(),
          IconButton(
            tooltip: 'Serie partida',
            isSelected: set.split,
            icon: const Icon(Icons.call_split_outlined),
            selectedIcon: const Icon(Icons.call_split),
            onPressed: () {
              set.split = !set.split;
              onChanged();
            },
          ),
          IconButton(
            tooltip: 'Al fallo',
            isSelected: set.toFailure,
            icon: const Icon(Icons.local_fire_department_outlined),
            selectedIcon: const Icon(Icons.local_fire_department),
            onPressed: () {
              set.toFailure = !set.toFailure;
              // El plan dice no entrenar al fallo: se registra, pero se avisa.
              if (set.toFailure) showSnack(context, 'El plan pide no llegar al fallo (RIR 1–3)');
              onChanged();
            },
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: onDelete),
        ],
      ),
    );
  }
}

class _ExerciseAutocomplete extends StatelessWidget {
  const _ExerciseAutocomplete({required this.controller, required this.label, required this.options});

  final TextEditingController controller;
  final String label;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: controller.value,
      optionsBuilder: (value) => value.text.isEmpty
          ? options
          : options.where((o) => o.toLowerCase().contains(value.text.toLowerCase())),
      onSelected: (v) => controller.text = v,
      fieldViewBuilder: (context, textController, focusNode, onSubmit) {
        textController.addListener(() => controller.text = textController.text);
        return TextField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        );
      },
    );
  }
}

class _NewExercise {
  _NewExercise(this.name, this.sets, this.reps);

  final String name;
  final int sets;
  final int reps;
}

class _AddExerciseDialog extends StatefulWidget {
  const _AddExerciseDialog({required this.known});

  final List<String> known;

  @override
  State<_AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<_AddExerciseDialog> {
  final _name = TextEditingController();
  final _sets = TextEditingController(text: '1');
  final _reps = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _sets.dispose();
    _reps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Añadir ejercicio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ExerciseAutocomplete(controller: _name, label: 'Ejercicio', options: widget.known),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: NumberField(controller: _sets, label: 'Series')),
              const SizedBox(width: 8),
              Expanded(child: NumberField(controller: _reps, label: 'Reps')),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _NewExercise(name, int.tryParse(_sets.text) ?? 1, int.tryParse(_reps.text) ?? 0),
            );
          },
          child: const Text('Añadir'),
        ),
      ],
    );
  }
}

class _EstimateDialog extends StatefulWidget {
  const _EstimateDialog({required this.netSec, this.historicalMeanSec});

  final int netSec;
  final int? historicalMeanSec;

  @override
  State<_EstimateDialog> createState() => _EstimateDialogState();
}

class _EstimateDialogState extends State<_EstimateDialog> {
  late final _mean = TextEditingController(
      text: widget.historicalMeanSec == null ? '' : formatDuration(widget.historicalMeanSec!));
  late final _rest = TextEditingController(text: widget.historicalMeanSec == null ? '30' : '0');

  @override
  void dispose() {
    _mean.dispose();
    _rest.dispose();
    super.dispose();
  }

  int get _result => estimateRounds(
        netSec: widget.netSec,
        meanRoundSec: parseDuration(_mean.text) ?? 0,
        restSec: int.tryParse(_rest.text) ?? 0,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Estimar rondas'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Neto: ${formatDuration(widget.netSec)}'),
          const SizedBox(height: 12),
          DurationField(controller: _mean, label: 'Tiempo medio por ronda', onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          NumberField(
            controller: _rest,
            label: 'Descanso entre rondas',
            suffix: 's',
            onChanged: (_) => setState(() {}),
          ),
          if (widget.historicalMeanSec != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Media histórica del contador: ${formatDuration(widget.historicalMeanSec!)} '
                '(ya incluye el descanso, por eso va en 0)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Text('≈ $_result rondas', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _result == 0 ? null : () => Navigator.pop(context, _result), child: const Text('Usar')),
      ],
    );
  }
}
