import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/training_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/progress.dart';
import '../../domain/session_math.dart';
import '../../ui/record_celebration.dart';
import '../../ui/widgets.dart';

/// Alta y edición de una sesión. Acepta un borrador ya poblado por el
/// contador de rondas.
class SessionFormScreen extends ConsumerStatefulWidget {
  const SessionFormScreen({super.key, required this.draft, this.celebrate = true});

  final SessionDraft draft;

  /// false cuando viene del cronómetro guiado, que ya celebró en su cierre.
  final bool celebrate;

  @override
  ConsumerState<SessionFormScreen> createState() => _SessionFormScreenState();
}

class _SessionFormScreenState extends ConsumerState<SessionFormScreen> {
  late final SessionDraft d = widget.draft;
  late final _total = TextEditingController(text: d.totalSec == 0 ? '' : formatDuration(d.totalSec));
  late final _warmup = TextEditingController(text: d.warmupSec == 0 ? '' : formatDuration(d.warmupSec));
  late final _cooldown = TextEditingController(text: d.cooldownSec == 0 ? '' : formatDuration(d.cooldownSec));
  late final _rest = TextEditingController(text: d.restSec == 0 ? '' : formatDuration(d.restSec));
  late final _rounds = TextEditingController(text: d.roundsDone?.toString() ?? '');
  late final _context = TextEditingController(text: d.context ?? '');
  late final _notes = TextEditingController(text: d.notes ?? '');
  late final _limiting = TextEditingController(text: d.limitingExercise ?? '');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_total, _warmup, _cooldown, _rest, _rounds, _context, _notes, _limiting]) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncTimes() {
    d
      ..totalSec = parseDuration(_total.text) ?? 0
      ..warmupSec = parseDuration(_warmup.text) ?? 0
      ..cooldownSec = parseDuration(_cooldown.text) ?? 0
      ..restSec = parseDuration(_rest.text) ?? 0;
  }

  Future<void> _loadPlanExercises() async {
    final view = await ref.read(planRepositoryProvider).dayFor(d.date);
    if (view == null || view.day.exercises.isEmpty) {
      if (mounted) showSnack(context, 'El plan no tiene ejercicios para ese día');
      return;
    }
    setState(() {
      d.planDayId = view.dayId;
      d.type = view.day.type.asSessionType;
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
      // Las vueltas del contador incluyen el descanso: se estima sobre el
      // tiempo de circuito con descansos, no sobre el neto.
      builder: (_) => _EstimateDialog(netSec: d.spanSec, historicalMeanSec: historical),
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

  /// Pasa `sec` del trabajo de la ronda siguiente al descanso `gap` (entre la
  /// ronda gap+1 y la gap+2). El total no cambia: solo se reparte distinto.
  void _shiftRest(int gap, int sec) {
    final before = List.of(d.roundRestSec);
    d.roundRestSec[gap] += sec;
    d.restSec += sec;
    _rest.text = formatDuration(d.restSec);
    _audit(before);
  }

  /// Deja constancia de los descansos originales: el informe se audita.
  void _audit(List<int> before) {
    if ((d.context ?? '').contains('Descansos corregidos a mano')) return;
    final original = before.take(before.length - 1).map(formatDuration).join(' · ');
    final note = 'Descansos corregidos a mano (antes: $original)';
    _context.text = _context.text.trim().isEmpty ? note : '${_context.text.trim()}. $note';
    d.context = _context.text;
  }

  Future<void> _editRests() async {
    final gaps = d.roundRestSec.length - 1;
    if (gaps < 1) return;
    final laps = lapDurations(d.roundMarksSec);
    final result = await showDialog<List<int>>(
      context: context,
      builder: (_) => _RestsDialog(rests: d.roundRestSec.take(gaps).toList(), laps: laps),
    );
    if (result == null) return;
    setState(() {
      final before = List.of(d.roundRestSec);
      var delta = 0;
      for (var i = 0; i < gaps; i++) {
        delta += result[i] - d.roundRestSec[i];
        d.roundRestSec[i] = result[i];
      }
      if (delta == 0) return;
      d.restSec += delta;
      _rest.text = formatDuration(d.restSec);
      _audit(before);
    });
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

  /// El plan manda: si el tipo no coincide con el día, hay que confirmarlo y
  /// la sesión queda marcada como fuera de plan (y así sale en el informe).
  Future<bool> _confirmAgainstPlan() async {
    // La movilidad va por fuera del plan a propósito: no es una desviación.
    if (d.type == SessionType.movilidad) {
      d.outOfPlan = false;
      return true;
    }
    final view = await ref.read(planRepositoryProvider).dayFor(d.date);
    if (view == null) return true;
    final planned = view.day.type;
    final matches = planned.isTraining && planned.asSessionType == d.type;
    if (matches) {
      d.outOfPlan = false;
      return true;
    }
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('No es lo que toca hoy'),
        content: Text('El plan pide ${planned.label.toLowerCase()} y estás registrando '
            '${d.type.label.toLowerCase()}.\n\nSi guardas, queda marcada como fuera de plan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Corregir')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar igual')),
        ],
      ),
    );
    if (ok != true) return false;
    d.outOfPlan = true;
    return true;
  }

  /// Validaciones blandas: avisan y dejan seguir. Un dato imperfecto
  /// registrado vale más que uno perfecto que nunca se anota. Solo el RPE es
  /// obligatorio: sin él la regla de progresión no funciona.
  Future<bool> _softChecks() async {
    // Movilidad: sin RPE ni fases; no entra en la regla de progresión.
    if (d.type == SessionType.movilidad) return true;
    if (d.rpe == null) {
      final rpe = await showDialog<int>(context: context, builder: (_) => const _RpeDialog());
      if (rpe == null || !mounted) return false;
      setState(() => d.rpe = rpe);
    }
    if ((d.rpe ?? 0) >= 9 && d.type == SessionType.circuitoLigero) {
      final ok = await _confirm(
        'RPE ${d.rpe} en día ligero',
        '¿Seguro? Este día debería salir cómodo (RPE 5–6). RPE ${d.rpe} significa que '
            '${rpeMeaning(d.rpe!)} repetición más.',
        keep: 'Sí, fue duro',
      );
      if (!ok) return false;
    }
    const minPhaseSec = 60;
    final shortPhases = [
      if (d.totalSec > 0 && d.warmupSec < minPhaseSec) 'calentamiento de ${formatDuration(d.warmupSec)}',
      if (d.totalSec > 0 && d.cooldownSec < minPhaseSec) 'enfriamiento de ${formatDuration(d.cooldownSec)}',
    ];
    if (shortPhases.isNotEmpty) {
      final ok = await _confirm(
        'Fase muy corta',
        'Registraste ${shortPhases.join(' y ')}. Menos de 1 min casi siempre es un descuido al '
            'tocar el cronómetro.',
        keep: 'Guardar igual',
      );
      if (!ok) return false;
    }
    return true;
  }

  Future<bool> _confirm(String title, String body, {required String keep}) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Corregir')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(keep)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _save() async {
    _syncTimes();
    if (!await _softChecks()) return;
    if (!await _confirmAgainstPlan()) return;
    d
      ..roundsDone = int.tryParse(_rounds.text)
      ..context = _context.text
      ..notes = _notes.text
      ..limitingExercise = _limiting.text
      ..pendingReview = false;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(trainingRepositoryProvider);
      if (!await guarded(context, () => repo.save(d))) return;
      unawaited(ref.read(notificationServiceProvider).cancelReviewReminder());
      if (widget.celebrate) await _celebrateIfRecord(repo);
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Si esta sesión superó la mejor marca, se muestra. Es el momento que más
  /// motiva y antes pasaba desapercibido.
  Future<void> _celebrateIfRecord(TrainingRepository repo) async {
    final rounds = d.roundsDone;
    if (!d.type.isCircuit || rounds == null || d.roundsEstimated) return;
    final previous = await repo.bestRounds(excludeSessionId: d.id);
    if (!isRecord(rounds, previous) || !mounted) return;
    await showRecordCelebration(context, rounds: rounds, previous: previous);
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
            restSec: parseDuration(_rest.text) ?? 0,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(d.id == null ? 'Nueva sesión' : 'Editar sesión'),
        actions: [
          if (d.id != null)
            IconButton(tooltip: 'Borrar', 
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDelete(context, 'la sesión')) {
                  if (!context.mounted) return;
                  final ok = await guarded(context, () => ref.read(trainingRepositoryProvider).delete(d.id!), failure: 'No se pudo borrar');
                  if (ok && context.mounted) Navigator.pop(context, true);
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
              // Cinco tipos no caben en un SegmentedButton de teléfono.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in SessionType.values)
                    ChoiceChip(
                      label: Text(t.label),
                      selected: d.type == t,
                      onSelected: (_) => setState(() => d.type = t),
                    ),
                ],
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
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: DurationField(controller: _rest, label: 'Descansos', onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: DurationField(controller: _cooldown, label: 'Enfriamiento', onChanged: (_) => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Text('Trabajo neto (sin descansos): ${net == null ? '—' : formatDuration(net)}',
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
                    d.roundWorkSec != null
                        ? 'Trabajo por ronda: ${d.roundWorkSec!.map(formatDuration).join(' · ')}'
                        : 'Vueltas (con descanso): ${lapDurations(d.roundMarksSec).map(formatDuration).join(' · ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (d.roundWorkSec case final work? when work.length > 1) ...[
                for (final k in suspectRounds(work, d.roundRestSec))
                  _SuspectRound(
                    round: k,
                    work: work,
                    rests: d.roundRestSec,
                    onReassign: (sec) => setState(() => _shiftRest(k - 1, sec)),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _editRests,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Corregir descansos'),
                  ),
                ),
              ],
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
                    IconButton(tooltip: 'Añadir otra serie', 
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
                    warnFailure: ref.watch(profileProvider).value?.neverToFailure ?? true,
                  ),
                const Divider(),
              ],
            ],
          ),
          if (d.outOfPlan)
            AppCard(
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Fuera de plan: el día pedía otra cosa.',
                        style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ],
            ),
          if (d.incomplete)
            AppCard(
              children: [
                Text('Cerrada antes de completar el plan'
                    '${d.plannedRounds == null ? '' : ' (${d.roundsDone ?? 0} de ${d.plannedRounds})'}.'),
              ],
            ),
          AppCard(
            title: 'Regla de progresión',
            children: [
              const Text('Solo se sube de ronda con las tres en verde, sin series partidas y sin fallo.'),
              const SizedBox(height: 8),
              TriToggle(
                label: 'Técnica buena',
                value: d.techniqueOk,
                onChanged: (v) => setState(() => d.techniqueOk = v),
              ),
              TriToggle(
                label: 'Rango completo',
                value: d.fullRange,
                onChanged: (v) => setState(() => d.fullRange = v),
              ),
              TriToggle(
                label: 'Recuperación normal',
                value: d.recoveryOk,
                onChanged: (v) => setState(() => d.recoveryOk = v),
              ),
            ],
          ),
          AppCard(
            title: 'Sensaciones y contexto',
            children: [
              RpeSelector(value: d.rpe, onChanged: (v) => setState(() => d.rpe = v)),
              const SizedBox(height: 12),
              _LimitingPicker(
                value: _limiting.text.trim().isEmpty ? null : _limiting.text.trim(),
                // Primero los ejercicios de esta sesión: casi siempre es uno de ellos.
                options: {
                  ...d.sets.map((s) => s.exercise),
                  if (d.sets.isEmpty) ...(ref.watch(exercisesProvider).value ?? []).map((e) => e.name),
                }.toList(),
                onChanged: (v) => setState(() => _limiting.text = v ?? ''),
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

/// ⚠ de una ronda que se comió el descanso previo, con la propuesta de
/// devolvérselo (§16.9).
class _SuspectRound extends StatelessWidget {
  const _SuspectRound({required this.round, required this.work, required this.rests, required this.onReassign});

  final int round;
  final List<int> work;
  final List<int> rests;
  final ValueChanged<int> onReassign;

  @override
  Widget build(BuildContext context) {
    final sec = reassignableSec(work, round);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'R${round + 1}: ${formatDuration(work[round])} de trabajo tras un descanso de '
              '${formatDuration(rests[round - 1])}. Seguramente el descanso se contó como trabajo.',
              style: text.bodySmall,
            ),
          ),
          if (sec > 0)
            TextButton(onPressed: () => onReassign(sec), child: Text('Pasar $sec s al descanso')),
        ],
      ),
    );
  }
}

/// Descansos entre rondas, editables. Cambiar un descanso mueve ese tiempo
/// desde (o hacia) el trabajo de la ronda siguiente: el total no cambia.
class _RestsDialog extends StatefulWidget {
  const _RestsDialog({required this.rests, required this.laps});

  final List<int> rests;
  final List<int> laps;

  @override
  State<_RestsDialog> createState() => _RestsDialogState();
}

class _RestsDialogState extends State<_RestsDialog> {
  late final _fields = [for (final r in widget.rests) TextEditingController(text: '$r')];

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  /// Trabajo que le queda a la ronda siguiente con el descanso escrito.
  String _workLabel(int i) {
    final v = int.tryParse(_fields[i].text.trim());
    return v == null ? '' : 'R${i + 2} ${formatDuration(widget.laps[i + 1] - v)}';
  }

  List<int>? get _values {
    final out = <int>[];
    for (var i = 0; i < _fields.length; i++) {
      final v = int.tryParse(_fields[i].text.trim());
      // El descanso no puede comerse toda la vuelta siguiente.
      if (v == null || v < 0 || v >= widget.laps[i + 1]) return null;
      out.add(v);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final values = _values;
    return AlertDialog(
      title: const Text('Descansos entre rondas'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('En segundos. Lo que sumes a un descanso sale del trabajo de la ronda siguiente.'),
            const SizedBox(height: 8),
            for (var i = 0; i < _fields.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(width: 90, child: Text('R${i + 1} → R${i + 2}')),
                    Expanded(
                      child: TextField(
                        controller: _fields[i],
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(suffixText: 's', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: Text(_workLabel(i), style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: values == null ? null : () => Navigator.pop(context, values), child: const Text('Usar')),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.set,
    required this.onChanged,
    required this.onDelete,
    this.warnFailure = true,
  });

  final int index;
  final SetDraft set;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  /// Regla del perfil `neverToFailure`: si está activa, marcar fallo avisa.
  final bool warnFailure;

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
              if (set.toFailure && warnFailure) showSnack(context, 'El plan pide no llegar al fallo (RIR 1–3)');
              onChanged();
            },
          ),
          IconButton(tooltip: 'Quitar', icon: const Icon(Icons.close), onPressed: onDelete),
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
          Text('Tiempo de circuito: ${formatDuration(widget.netSec)}'),
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

/// Ejercicio limitante con chips de un toque. "Ninguno" es una opción
/// explícita: hay sesiones en las que nada costó más que lo demás.
class _LimitingPicker extends StatelessWidget {
  const _LimitingPicker({required this.value, required this.options, required this.onChanged});

  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final all = [...options, if (value != null && !options.contains(value)) value!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Qué te costó más?', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('Ninguno'),
              selected: value == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final name in all)
              ChoiceChip(
                label: Text(name),
                selected: value == name,
                onSelected: (sel) => onChanged(sel ? name : null),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Otro'),
              onPressed: () async {
                final other = await promptText(context, title: 'Ejercicio limitante', label: 'Nombre');
                if (other != null && other.trim().isNotEmpty) onChanged(other.trim());
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// El RPE se pide al cerrar: sin él la regla de progresión no funciona. La
/// escala va en la misma pantalla.
class _RpeDialog extends StatefulWidget {
  const _RpeDialog();

  @override
  State<_RpeDialog> createState() => _RpeDialogState();
}

class _RpeDialogState extends State<_RpeDialog> {
  int? _value;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('¿Qué tan duro fue?'),
        content: SingleChildScrollView(
          child: RpeSelector(value: _value, onChanged: (v) => setState(() => _value = v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
          FilledButton(
            onPressed: _value == null ? null : () => Navigator.pop(context, _value),
            child: const Text('Guardar'),
          ),
        ],
      );
}
