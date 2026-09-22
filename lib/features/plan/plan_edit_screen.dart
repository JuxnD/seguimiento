import 'package:flutter/material.dart';
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
    await ref.read(planRepositoryProvider).saveAsNewVersion(d);
    if (mounted) Navigator.pop(context, true);
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
              DateTile(label: 'Vigente desde', date: d.validFrom, onChanged: (v) => setState(() => d.validFrom = v)),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                    labelText: 'Qué cambia', hintText: 'Subo a 8 rondas objetivo', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Las versiones anteriores no se tocan: el informe sabrá qué plan regía cada día.'),
              ),
            ],
          ),
          for (final day in d.days) _DayCard(day: day, onChanged: () => setState(() {})),
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
  const _DayCard({required this.day, required this.onChanged});

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
        if (day.type == DayType.circuito) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: day.targetRounds?.toString() ?? '',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Rondas objetivo', border: OutlineInputBorder()),
            onChanged: (v) => day.targetRounds = int.tryParse(v),
          ),
        ],
        if (day.type.isTraining) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < day.exercises.length; i++) _ExerciseRow(
            exercise: day.exercises[i],
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
  const _ExerciseRow({required this.exercise, required this.onDelete});

  final PlanExerciseDraft exercise;
  final VoidCallback onDelete;

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
                  decoration: const InputDecoration(labelText: 'Ejercicio', border: OutlineInputBorder()),
                  onChanged: (v) => exercise.name = v,
                ),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: onDelete),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _Num('Series', exercise.sets, (v) => exercise.sets = v)),
              const SizedBox(width: 6),
              Expanded(child: _Num('Reps mín', exercise.repsMin, (v) => exercise.repsMin = v)),
              const SizedBox(width: 6),
              Expanded(child: _Num('Reps máx', exercise.repsMax, (v) => exercise.repsMax = v)),
              const SizedBox(width: 6),
              Expanded(child: _Num('Desc. (s)', exercise.restSec, (v) => exercise.restSec = v)),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: exercise.grip ?? '',
            decoration: const InputDecoration(
                labelText: 'Agarre / variante', hintText: 'Prono, supino…', border: OutlineInputBorder()),
            onChanged: (v) => exercise.grip = v,
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
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: (v) => onChanged(int.tryParse(v)),
      );
}
