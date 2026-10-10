import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/search.dart';
import '../../data/catalog_updates.dart';
import '../../domain/mobility.dart';
import '../../ui/exercise_figure_3d_view.dart';
import '../../ui/exercise_figure_3d.dart';
import 'technique_sheet.dart';

/// Consulta previa al entrenamiento; no crea sesiones ni cambia el plan.
class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  ConsumerState<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  String _query = '';
  String? _group;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(figure3dProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Guías de ejercicios')),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('No se pudieron abrir las ilustraciones.'),
          FilledButton(onPressed: () => ref.invalidate(figure3dProvider), child: const Text('Reintentar')),
        ])),
        data: (data) {
          final all = data.all.toList()..sort((a, b) => a.name.compareTo(b.name));
          final groups = all.map((f) => f.group).toSet().toList()..sort();
          final matching = all
              .where((f) => nameKey(f.name).contains(nameKey(_query)) && (_group == null || f.group == _group))
              .toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(labelText: 'Busca un ejercicio', prefixIcon: Icon(Icons.search)),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: Text(_group ?? 'Todos los ejercicios')),
                PopupMenuButton<String>(
                  tooltip: 'Filtrar por grupo',
                  onSelected: (value) => setState(() => _group = value == 'todos' ? null : value),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'todos', child: Text('Todos')),
                    for (final group in groups) PopupMenuItem(value: group, child: Text(group)),
                  ],
                  icon: const Icon(Icons.filter_list),
                ),
              ]),
            ),
            if (matching.isEmpty)
              const Expanded(child: Center(child: Text('No hay coincidencias. Prueba otro nombre.')))
            else
              Expanded(
                  child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: matching.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final figure = matching[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    leading: SizedBox(
                        width: 70,
                        height: 76,
                        child: RepaintBoundary(child: CustomPaint(painter: Figure3DPainter(figure, 0)))),
                    title: Text(figure.name),
                    subtitle: Text(figure.group),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _GuideScreen(figure: figure))),
                  );
                },
              )),
          ]);
        },
      ),
    );
  }
}

class _GuideScreen extends StatefulWidget {
  const _GuideScreen({required this.figure});
  final Figure3D figure;

  @override
  State<_GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<_GuideScreen> {
  String _side = 'izquierdo';
  String _grip = 'prona';
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final figure = widget.figure;
    final pull = nameKey(figure.name) == nameKey('Dominadas');
    final guide = exerciseGuides.where((g) => nameKey(g.name) == nameKey(figure.name)).firstOrNull;
    final mobility = [...mobilityNight.exercises, ...legRecovery.exercises]
        .where((g) => nameKey(g.name) == nameKey(figure.name))
        .firstOrNull;
    final loadable = {nameKey('Dominadas'), nameKey('Fondos en barra'), nameKey('Flexiones diamante')}
        .contains(nameKey(figure.name));
    return Scaffold(
      appBar: AppBar(title: const Text('Guía del ejercicio')),
      body: Column(children: [
        if (figure.perSide || pull || loadable)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                if (figure.perSide) ...[
                  ChoiceChip(
                      label: const Text('Lado izquierdo'),
                      selected: _side == 'izquierdo',
                      onSelected: (_) => setState(() => _side = 'izquierdo')),
                  ChoiceChip(
                      label: const Text('Lado derecho'),
                      selected: _side == 'derecho',
                      onSelected: (_) => setState(() => _side = 'derecho')),
                ],
                if (pull) ...[
                  ChoiceChip(
                      label: const Text('Prona'),
                      selected: _grip == 'prona',
                      onSelected: (_) => setState(() => _grip = 'prona')),
                  ChoiceChip(
                      label: const Text('Supina'),
                      selected: _grip == 'supina',
                      onSelected: (_) => setState(() => _grip = 'supina')),
                ],
                if (loadable)
                  ChoiceChip(
                      label: const Text('Con mochila'),
                      selected: _loaded,
                      onSelected: (value) => setState(() => _loaded = value)),
              ])),
        Expanded(
            child: TechniqueContent(
                exercise: figure.name,
                side: figure.perSide ? _side : null,
                grip: pull ? _grip : null,
                loaded: loadable ? _loaded : null,
                cues: guide?.formCues ?? mobility?.formCues ?? const [],
                progressionNote: guide?.progressionNote,
                mediaUrl: guide?.mediaUrl,
                anchor: guide?.anchor)),
      ]),
    );
  }
}
