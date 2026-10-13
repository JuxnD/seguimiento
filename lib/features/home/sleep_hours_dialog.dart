import 'package:flutter/material.dart';

import '../../data/repositories/sleep_repository.dart';
import '../../domain/dates.dart';
import '../../domain/sleep_entry.dart';

/// "Otro": escribir las horas en cama (10,2 · 10:11 · 10 h 11 min).
Future<double?> askSleepHours(BuildContext context, {double? initial}) => showDialog<double>(
      context: context,
      builder: (_) => _SleepHoursDialog(initial: initial),
    );

class _SleepHoursDialog extends StatefulWidget {
  const _SleepHoursDialog({this.initial});

  final double? initial;

  @override
  State<_SleepHoursDialog> createState() => _SleepHoursDialogState();
}

class _SleepHoursDialogState extends State<_SleepHoursDialog> {
  late final _field = TextEditingController(text: widget.initial?.toString().replaceAll('.', ',') ?? '');
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _accept() {
    final hours = parseSleepHours(_field.text);
    if (hours == null) {
      setState(() => _error = 'Escribe horas entre 0 y 16, p. ej. 10,2 o 10:11');
      return;
    }
    Navigator.pop(context, hours);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Horas en cama'),
        content: TextField(
          controller: _field,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            labelText: 'Horas',
            hintText: '10:11',
            helperText: 'Con decimales (10,2) o horas y minutos (10:11)',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _accept(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _accept, child: const Text('Guardar')),
        ],
      );
}

/// Lo que devuelve el editor de una noche: guardar o eliminar.
class SleepEdit {
  const SleepEdit.save({required this.hours, this.start, this.wake, required this.fromClock, this.note}) : delete = false;
  const SleepEdit.delete()
      : delete = true,
        hours = 0,
        start = null,
        wake = null,
        fromClock = false,
        note = null;

  final bool delete;
  final double hours;
  final DateTime? start;
  final DateTime? wake;
  final bool fromClock;
  final String? note;
}

/// Editar la noche que termina la mañana de `day` (plan 040): horas, o la
/// hora de acostarse y de despertar (cruza la medianoche), si se anotó del
/// reloj y una nota. Eliminar pide confirmación; Cancelar no escribe nada.
Future<SleepEdit?> editSleep(BuildContext context, {required DateTime day, SleepDetail? initial}) =>
    showDialog<SleepEdit>(context: context, builder: (_) => _SleepEditDialog(day: day, initial: initial));

class _SleepEditDialog extends StatefulWidget {
  const _SleepEditDialog({required this.day, this.initial});

  final DateTime day;
  final SleepDetail? initial;

  @override
  State<_SleepEditDialog> createState() => _SleepEditDialogState();
}

class _SleepEditDialogState extends State<_SleepEditDialog> {
  late final _hours = TextEditingController(
      text: widget.initial == null ? '' : widget.initial!.hours.toString().replaceAll('.', ','));
  late final _note = TextEditingController(text: widget.initial?.note ?? '');
  late (int, int)? _start = _hm(widget.initial?.start);
  late (int, int)? _wake = _hm(widget.initial?.wake);
  late bool _byTimes = widget.initial?.start != null;
  late bool _fromClock = widget.initial?.source == sleepSourceClock;
  String? _error;

  static (int, int)? _hm(DateTime? d) => d == null ? null : (d.hour, d.minute);

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  ({DateTime start, DateTime wake})? get _window =>
      _start == null || _wake == null ? null : sleepWindow(widget.day, _start!, _wake!);

  Future<void> _pick(bool start) async {
    final current = start ? _start : _wake;
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? (start ? const TimeOfDay(hour: 23, minute: 0) : const TimeOfDay(hour: 7, minute: 0))
          : TimeOfDay(hour: current.$1, minute: current.$2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = (picked.hour, picked.minute);
      } else {
        _wake = (picked.hour, picked.minute);
      }
      _error = null;
    });
  }

  String _at(DateTime d) => '${weekdayShort(d.weekday)} ${timeKey(d.hour, d.minute)}';

  void _accept() {
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (_byTimes) {
      final w = _window;
      final hours = w == null ? null : hoursBetween(w.start, w.wake);
      if (w == null || hours == null) {
        setState(() => _error = 'Elige a qué hora te acostaste y a qué hora despertaste (hasta 16 h)');
        return;
      }
      Navigator.pop(
          context, SleepEdit.save(hours: hours, start: w.start, wake: w.wake, fromClock: _fromClock, note: note));
      return;
    }
    final hours = parseSleepHours(_hours.text);
    if (hours == null) {
      setState(() => _error = 'Escribe horas entre 0 y 16, p. ej. 10,2 o 10:11');
      return;
    }
    Navigator.pop(context, SleepEdit.save(hours: hours, fromClock: _fromClock, note: note));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Eliminar el sueño de anoche?'),
        content: const Text('Se borran las horas anotadas de esa noche.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, const SleepEdit.delete());
  }

  @override
  Widget build(BuildContext context) {
    final w = _window;
    final hours = w == null ? null : hoursBetween(w.start, w.wake);
    final source = sleepSourceLabel(widget.initial?.source);
    return AlertDialog(
      title: const Text('Sueño de anoche'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (source != null) Text('Ahora: $source', style: Theme.of(context).textTheme.bodySmall),
            Wrap(spacing: 6, children: [
              ChoiceChip(
                  label: const Text('Horas'), selected: !_byTimes, onSelected: (_) => setState(() => _byTimes = false)),
              ChoiceChip(
                  label: const Text('Acostarse y despertar'),
                  selected: _byTimes,
                  onSelected: (_) => setState(() => _byTimes = true)),
            ]),
            const SizedBox(height: 8),
            if (_byTimes) ...[
              Wrap(spacing: 8, children: [
                OutlinedButton(
                    onPressed: () => _pick(true),
                    child: Text(_start == null ? 'Me acosté…' : 'Me acosté ${timeKey(_start!.$1, _start!.$2)}')),
                OutlinedButton(
                    onPressed: () => _pick(false),
                    child: Text(_wake == null ? 'Desperté…' : 'Desperté ${timeKey(_wake!.$1, _wake!.$2)}')),
              ]),
              if (w != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(hours == null
                      ? 'Pasa de 16 h: revisa las horas'
                      : '${_at(w.start)} → ${_at(w.wake)} · ${formatSleepHours(hours)}'),
                ),
            ] else
              TextField(
                controller: _hours,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Horas en cama',
                  hintText: '10:11',
                  helperText: 'Con decimales (10,2) o horas y minutos (10:11)',
                  border: OutlineInputBorder(),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lo anoté del reloj'),
              subtitle: const Text('Sólo dice de dónde salió; la app no lee el reloj.'),
              value: _fromClock,
              onChanged: (v) => setState(() => _fromClock = v),
            ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                  labelText: 'Nota (opcional)', hintText: 'Reloj descargado, siesta…', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.initial != null) TextButton(onPressed: _delete, child: const Text('Eliminar')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _accept, child: const Text('Guardar')),
      ],
    );
  }
}
