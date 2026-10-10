import 'package:flutter/material.dart';

import '../../domain/warmup.dart';
import '../../ui/widgets.dart';
import 'technique_sheet.dart';

/// Antes de un intento o test (§16.23): el calentamiento y el checklist
/// siempre a la vista; no se puede ocultar. Las marcas son ayuda en
/// pantalla: no se guardan ni bloquean el test.
class PreAttemptCard extends StatefulWidget {
  const PreAttemptCard({super.key, required this.torso});

  final bool torso;

  @override
  State<PreAttemptCard> createState() => _PreAttemptCardState();
}

class _PreAttemptCardState extends State<PreAttemptCard> {
  late final _items = testWarmup(torso: widget.torso);
  final _done = <String>{};

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      key: const ValueKey('pre-attempt'),
      title: 'Antes del intento',
      children: [
        Text('Calentamiento', style: text.labelLarge),
        for (final item in _items)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _done.contains(item.key),
            onChanged: (_) => setState(() => _done.contains(item.key) ? _done.remove(item.key) : _done.add(item.key)),
            title: Text('${item.exercise} · ${item.dose}'),
            secondary: IconButton(
              tooltip: 'Cómo',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () => showTechniqueSheet(context, exercise: item.exercise),
            ),
          ),
        const SizedBox(height: 6),
        Text('Checklist', style: text.labelLarge),
        for (final check in preAttemptChecklist)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _done.contains(check),
            onChanged: (_) => setState(() => _done.contains(check) ? _done.remove(check) : _done.add(check)),
            title: Text(check),
          ),
      ],
    );
  }
}
