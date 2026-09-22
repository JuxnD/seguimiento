import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../domain/dates.dart';
import '../../ui/widgets.dart';

class FootballFormScreen extends ConsumerStatefulWidget {
  const FootballFormScreen({super.key, this.existing});

  final FootballGameRow? existing;

  @override
  ConsumerState<FootballFormScreen> createState() => _FootballFormScreenState();
}

class _FootballFormScreenState extends ConsumerState<FootballFormScreen> {
  late DateTime _date = widget.existing == null ? dateOnly(DateTime.now()) : parseDay(widget.existing!.date);
  late int _format = widget.existing?.format ?? 5;
  late final _minutes = TextEditingController(text: widget.existing?.minutes.toString() ?? '');
  late final _steps = TextEditingController(text: widget.existing?.steps?.toString() ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late int? _intensity = widget.existing?.intensity;
  late int? _fatigue = widget.existing?.fatigueAfter;

  @override
  void dispose() {
    _minutes.dispose();
    _steps.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes.text);
    if (minutes == null) {
      showSnack(context, 'Faltan los minutos jugados');
      return;
    }
    await ref.read(trainingRepositoryProvider).saveFootball(FootballGamesCompanion(
          id: widget.existing == null ? const Value.absent() : Value(widget.existing!.id),
          date: Value(dayKey(_date)),
          format: Value(_format),
          minutes: Value(minutes),
          steps: Value(int.tryParse(_steps.text)),
          intensity: Value(_intensity),
          fatigueAfter: Value(_fatigue),
          notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
        ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Nuevo fútbol' : 'Editar fútbol'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDelete(context, 'el partido')) {
                  await ref.read(trainingRepositoryProvider).deleteFootball(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context, true);
                }
              },
            ),
        ],
      ),
      body: ListView(
        children: [
          AppCard(
            children: [
              DateTile(date: _date, onChanged: (v) => setState(() => _date = v)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('Fútbol 5')),
                  ButtonSegment(value: 7, label: Text('Fútbol 7')),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: NumberField(controller: _minutes, label: 'Minutos', suffix: 'min')),
                  const SizedBox(width: 8),
                  Expanded(child: NumberField(controller: _steps, label: 'Pasos')),
                ],
              ),
            ],
          ),
          AppCard(
            title: 'Sensaciones',
            children: [
              ScaleSelector(
                  label: 'Intensidad percibida', value: _intensity, onChanged: (v) => setState(() => _intensity = v)),
              const SizedBox(height: 12),
              ScaleSelector(label: 'Fatiga posterior', value: _fatigue, onChanged: (v) => setState(() => _fatigue = v)),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: const Text('Guardar'),
      ),
    );
  }
}
