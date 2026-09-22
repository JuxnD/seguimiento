import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/dates.dart';

/// Tarjeta con título: unidad visual de todas las pantallas.
class AppCard extends StatelessWidget {
  const AppCard({super.key, this.title, this.trailing, required this.children, this.padding});

  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Row(
                children: [
                  Expanded(
                    child: Text(title!, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            if (title != null) const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.suffix,
    this.decimal = false,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final bool decimal;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
        ],
        decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
        onChanged: onChanged,
      );
}

/// Campo de duración en `mm:ss` (o minutos sueltos).
class DurationField extends StatelessWidget {
  const DurationField({super.key, required this.controller, required this.label, this.onChanged});

  final TextEditingController controller;
  final String label;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final value = parseDuration(controller.text);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'mm:ss',
        helperText: value == null ? null : formatDuration(value),
        errorText: controller.text.trim().isNotEmpty && value == null ? 'Formato mm:ss' : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: (t) => onChanged?.call(parseDuration(t)),
    );
  }
}

class DateTile extends StatelessWidget {
  const DateTile({super.key, required this.date, required this.onChanged, this.label = 'Fecha'});

  final DateTime date;
  final String label;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event),
        title: Text(label),
        subtitle: Text('${weekdayLong(date.weekday)} ${formatLong(date)}'),
        trailing: const Icon(Icons.edit_calendar),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked != null) onChanged(dateOnly(picked));
        },
      );
}

class TimeTile extends StatelessWidget {
  const TimeTile({super.key, required this.time, required this.onChanged, this.label = 'Hora'});

  /// `HH:mm` o null.
  final String? time;
  final String label;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule),
        title: Text(label),
        subtitle: Text(time ?? 'Sin hora'),
        trailing: time == null
            ? const Icon(Icons.more_time)
            : IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null)),
        onTap: () async {
          final parts = time?.split(':');
          final initial = parts == null
              ? TimeOfDay.now()
              : TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          final picked = await showTimePicker(context: context, initialTime: initial);
          if (picked != null) onChanged(timeKey(picked.hour, picked.minute));
        },
      );
}

/// Selector 1–10 (RPE, intensidad, fatiga).
class ScaleSelector extends StatelessWidget {
  const ScaleSelector({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 1; i <= 10; i++)
                ChoiceChip(
                  label: Text('$i'),
                  selected: value == i,
                  onSelected: (sel) => onChanged(sel ? i : null),
                ),
            ],
          ),
        ],
      );
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('¿Borrar $what?'),
      content: const Text('No se puede deshacer.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
      ],
    ),
  );
  return ok ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Parseo tolerante de números escritos con coma.
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
