import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/dates.dart';
import '../domain/progress.dart';

/// Tarjeta con título: unidad visual de todas las pantallas.
class AppCard extends StatelessWidget {
  const AppCard({super.key, this.title, this.trailing, required this.children, this.padding, this.margin});

  final String? title;

  /// Por defecto separa la tarjeta del borde; dentro de un layout con padding
  /// propio (cronómetro) va a ras para alinear con los botones.
  final EdgeInsets? margin;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin ?? const EdgeInsets.fromLTRB(12, 6, 12, 6),
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

/// Botón de acción compacto para filas de 2–3 botones: el texto nunca parte
/// en dos líneas, se recorta.
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false),
            ),
          ],
        ),
      );
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

class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.controller,
    required this.label,
    this.suffix,
    this.decimal = false,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final bool decimal;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Abre el teclado con el valor seleccionado: se escribe encima sin borrar.
  /// Pensado para diálogos de un solo número (cantidad, peso, umbral).
  final bool autofocus;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  @override
  void initState() {
    super.initState();
    if (widget.autofocus) selectAll(widget.controller);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(widget.decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.suffix,
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
      );
}

/// Selecciona todo el texto: el siguiente dígito reemplaza el valor sugerido.
void selectAll(TextEditingController c) =>
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);

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
        // Solo si aporta: "45" se lee como 45:00; "0:36" no necesita eco.
        helperText: value == null || formatDuration(value) == controller.text.trim()
            ? null
            : formatDuration(value),
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
            : IconButton(tooltip: 'Quitar', icon: const Icon(Icons.clear), onPressed: () => onChanged(null)),
        onTap: () async {
          final initial = parseTimeOfDay(time) ?? TimeOfDay.now();
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

/// Selector de RPE con la escala a la vista, no en un menú de ayuda.
class RpeSelector extends StatelessWidget {
  const RpeSelector({super.key, required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScaleSelector(label: 'RPE: ¿cuántas repeticiones te quedaban?', value: value, onChanged: onChanged),
        if (value != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('RPE $value: ${rpeMeaning(value!)}', style: text.bodyMedium),
          ),
        const SizedBox(height: 8),
        for (final (v, meaning) in rpeScale)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                SizedBox(width: 40, child: Text(v, style: text.labelLarge)),
                Expanded(child: Text(meaning, style: text.bodySmall)),
              ],
            ),
          ),
      ],
    );
  }
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

/// `HH:mm` (o `HH:mm:ss`) → hora. null si no se entiende: un respaldo viejo o
/// editado a mano no debe tumbar la pantalla.
TimeOfDay? parseTimeOfDay(String? time) {
  final parts = time?.split(':');
  if (parts == null || parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim()), m = int.tryParse(parts[1].trim());
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);
}

/// Corre una escritura y avisa si falla, en vez de dejar un future perdido y
/// la pantalla sin respuesta. Devuelve true si salió bien.
Future<bool> guarded(BuildContext context, Future<void> Function() action,
    {String? ok, String failure = 'No se pudo guardar'}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    if (ok != null) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(ok)));
    }
    return true;
  } on Object catch (e) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$failure: $e')));
    return false;
  }
}

/// Aviso con "Deshacer": para borrados de un toque, en lugar de un diálogo
/// de confirmación que frena cada corrección.
void showUndoSnack(BuildContext context, String message, Future<void> Function() undo) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: SnackBarAction(label: 'Deshacer', onPressed: () => undo()),
    ));
}

/// Pide un texto corto en un diálogo. El diálogo es dueño de su controller:
/// liberarlo al volver de `showDialog` falla mientras la ruta anima la salida.
Future<String?> promptText(BuildContext context, {required String title, required String label}) =>
    showDialog<String>(context: context, builder: (_) => _PromptTextDialog(title: title, label: label));

class _PromptTextDialog extends StatefulWidget {
  const _PromptTextDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_PromptTextDialog> createState() => _PromptTextDialogState();
}

class _PromptTextDialogState extends State<_PromptTextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _submit, child: const Text('Listo')),
        ],
      );
}

/// Texto de cuándo medir, igual en Hoy y en Cuerpo.
String measurementLabel(MeasurementDue due) {
  final left = due.daysLeft;
  if (left > 0) {
    final when = due.agreed ? ' (fecha acordada)' : '';
    return 'Próxima medición en $left ${left == 1 ? 'día' : 'días'}$when';
  }
  if (due.daysLate > 0) {
    return 'Medición atrasada ${due.daysLate} ${due.daysLate == 1 ? 'día' : 'días'}: mídete en ayunas';
  }
  return due.agreed
      ? 'Hoy toca medir (fecha acordada). En ayunas.'
      : 'Toca medir: estás en la ventana hasta el ${formatShort(due.windowEnd)}. En ayunas.';
}
