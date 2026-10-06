import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../ui/widgets.dart';

/// Editor de una versión nueva del plan (siempre crea, nunca sobreescribe).
class PlanEditScreen extends ConsumerStatefulWidget {
  const PlanEditScreen({super.key, required this.draft});

  final PlanDraft draft;

  @override
  ConsumerState<PlanEditScreen> createState() => _PlanEditScreenState();
}

class _PlanEditScreenState extends ConsumerState<PlanEditScreen> {
  late final PlanDraft d = widget.draft;
  late final _notes = TextEditingController(text: d.notes ?? '');

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    d.notes = _notes.text;
    final problem = planDraftProblem(d) ?? _extendedRangesProblem();
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    final ok = await guarded(
        context, () => ref.read(planRepositoryProvider).saveAsNewVersion(d));
    if (ok && mounted) Navigator.pop(context, true);
  }

  /// Los campos que ahora se pueden editar usan el mismo modelo persistido.
  String? _extendedRangesProblem() {
    for (final day in d.days.where((day) => day.type.isTraining)) {
      for (final e in day.exercises.where((e) => e.name.trim().isNotEmpty)) {
        final name = '${weekdayLong(day.weekday)}, ${e.name.trim()}';
        if ((e.holdSecMin != null && e.holdSecMin! <= 0) ||
            (e.holdSecMax != null && e.holdSecMax! <= 0)) {
          return '$name: el sostén debe ser mayor que 0 segundos';
        }
        if (e.holdSecMax != null && e.holdSecMin == null) {
          return '$name: indica el sostén mínimo';
        }
        if ((e.rirMin != null && (e.rirMin! < 0 || e.rirMin! > 5)) ||
            (e.rirMax != null && (e.rirMax! < 0 || e.rirMax! > 5))) {
          return '$name: el RIR debe estar entre 0 y 5';
        }
        if (e.rirMax != null && e.rirMin == null) {
          return '$name: indica el RIR mínimo';
        }
        if (e.rirMin != null && e.rirMax != null && e.rirMin! > e.rirMax!) {
          return '$name: RIR mínimo mayor que el máximo';
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva versión del plan')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          AppCard(
            children: [
              DateTile(
                  label: 'Vigente desde',
                  date: d.validFrom,
                  onChanged: (v) => setState(() => d.validFrom = v)),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                    labelText: 'Qué cambia',
                    hintText: 'Subo a 8 rondas objetivo',
                    border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Las versiones anteriores no se tocan: el informe sabrá qué plan regía cada día.'),
              ),
            ],
          ),
          for (final day in d.days)
            _DayCard(
                key: ObjectKey(day),
                day: day,
                onChanged: () => setState(() {})),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: const Text('Guardar versión'),
      ),
    );
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard({super.key, required this.day, required this.onChanged});

  final PlanDayDraft day;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      title: weekdayLong(day.weekday),
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final t in DayType.values)
              ChoiceChip(
                label: Text(t.label),
                selected: day.type == t,
                onSelected: (_) {
                  day.type = t;
                  onChanged();
                },
              ),
          ],
        ),
        if (day.type.isCircuit) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: day.targetRounds?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Rondas objetivo',
                      border: OutlineInputBorder()),
                  onChanged: (v) => day.targetRounds = int.tryParse(v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: day.restBetweenRoundsSec?.toString() ?? '',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Descanso entre rondas',
                      suffixText: 's',
                      border: OutlineInputBorder()),
                  onChanged: (v) => day.restBetweenRoundsSec = int.tryParse(v),
                ),
              ),
            ],
          ),
        ],
        if (day.type.isTraining) ...[
          const SizedBox(height: 8),
          // La clave ata cada fila a su ejercicio: sin ella, al borrar uno los
          // campos de abajo heredan el texto del borrado y se guarda otra cosa.
          for (var i = 0; i < day.exercises.length; i++)
            _ExerciseRow(
              key: ObjectKey(day.exercises[i]),
              exercise: day.exercises[i],
              onChanged: onChanged,
              onDelete: () {
                day.exercises.removeAt(i);
                onChanged();
              },
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                day.exercises.add(PlanExerciseDraft(name: ''));
                onChanged();
              },
              icon: const Icon(Icons.add),
              label: const Text('Ejercicio'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow(
      {super.key,
      required this.exercise,
      required this.onDelete,
      required this.onChanged});

  final PlanExerciseDraft exercise;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: exercise.name,
                  decoration: const InputDecoration(
                      labelText: 'Ejercicio', border: OutlineInputBorder()),
                  onChanged: (v) => exercise.name = v,
                ),
              ),
              IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.close),
                  onPressed: onDelete),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (context, constraints) {
            final columns =
                MediaQuery.textScalerOf(context).scale(14) > 18 ? 1 : 2;
            final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final field in [
                _Num('Series', exercise.sets, (v) => exercise.sets = v),
                _Num('Reps mín', exercise.repsMin, (v) => exercise.repsMin = v),
                _Num('Reps máx', exercise.repsMax, (v) => exercise.repsMax = v),
                _Num(
                    'Desc. (s)', exercise.restSec, (v) => exercise.restSec = v),
                _Num('Desc. máx (s)', exercise.restSecMax,
                    (v) => exercise.restSecMax = v),
                _Num('Sostén mín (s)', exercise.holdSecMin,
                    (v) => exercise.holdSecMin = v),
                _Num('Sostén máx (s)', exercise.holdSecMax,
                    (v) => exercise.holdSecMax = v),
                _Num('RIR mín', exercise.rirMin, (v) => exercise.rirMin = v),
                _Num('RIR máx', exercise.rirMax, (v) => exercise.rirMax = v),
              ])
                SizedBox(width: width, child: field),
            ]);
          }),
          const SizedBox(height: 6),
          Text(
              'Sostén en segundos; RIR: repeticiones que quedan en reserva (0–5). '
              'Deja los rangos vacíos si no aplican.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: exercise.grip ?? '',
                  decoration: const InputDecoration(
                      labelText: 'Agarre / variante',
                      hintText: 'Prona, supina…',
                      border: OutlineInputBorder()),
                  onChanged: (v) => exercise.grip = v,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextFormField(
                  initialValue: exercise.block ?? '',
                  decoration: const InputDecoration(
                      labelText: 'Bloque',
                      hintText: 'core, hombro…',
                      border: OutlineInputBorder()),
                  onChanged: (v) =>
                      exercise.block = v.trim().isEmpty ? null : v.trim(),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Por lado'),
            value: exercise.perSide,
            onChanged: (v) {
              exercise.perSide = v;
              onChanged();
            },
          ),
          TextFormField(
            initialValue: exercise.notes ?? '',
            decoration: const InputDecoration(
                labelText: 'Notas del ejercicio', border: OutlineInputBorder()),
            maxLines: 3,
            onChanged: (v) =>
                exercise.notes = v.trim().isEmpty ? null : v.trim(),
          ),
        ],
      ),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num(this.label, this.value, this.onChanged);

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: value?.toString() ?? '',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        onChanged: (v) => onChanged(int.tryParse(v)),
      );
}
