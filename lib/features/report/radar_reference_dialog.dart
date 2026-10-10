import 'package:flutter/material.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/progress_metrics.dart';

/// The dialog owns its controller until the route's exit animation completes.
class RadarReferenceDialog extends StatefulWidget {
  const RadarReferenceDialog({super.key, required this.axis, required this.decision, required this.cutoff, this.value});
  final RadarAxis axis;
  final DateTime decision, cutoff;
  final double? value;
  @override
  State<RadarReferenceDialog> createState() => _RadarReferenceDialogState();
}

class _RadarReferenceDialogState extends State<RadarReferenceDialog> {
  late final controller = TextEditingController(text: widget.value == null ? '' : fmtDec(widget.value!));
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text('Referencia de ${widget.axis.label}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  'Tu referencia personal en ${widget.axis.unit}. La misma referencia compara inicio y última medición; no es una calificación general.'),
              Text(
                  'Se guarda desde ${formatLong(widget.decision)}. ${widget.cutoff.isBefore(dateOnly(widget.decision)) ? "El período que estás viendo es anterior: este cambio no lo modifica." : "No cambia las referencias de fechas anteriores."}'),
              TextField(
                  key: const Key('radar-reference-value'),
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Valor (${widget.axis.unit})', errorText: error))
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(context, (value: null)), child: const Text('Sin referencia')),
            FilledButton(
                onPressed: () {
                  final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
                  if (value == null || !value.isFinite || value <= 0) {
                    setState(() => error = 'Escribe un número mayor que 0');
                    return;
                  }
                  Navigator.pop(context, (value: value));
                },
                child: const Text('Guardar'))
          ]);
}
