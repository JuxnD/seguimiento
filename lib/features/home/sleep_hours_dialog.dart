import 'package:flutter/material.dart';

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
