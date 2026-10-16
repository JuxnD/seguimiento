import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../data/repositories/mobility_benchmark_repository.dart';
import '../../ui/widgets.dart';

const _names = {
  'knee_to_wall': 'Rodilla a la pared (cm por lado)',
  'seated_pike': 'Pike sentado (cm; negativo si no llegas)',
  'pancake': 'Pancake (pecho al suelo, cm)',
  'shoulder_wall': 'Pulgares en la pared',
  'deep_squat': 'Sentadilla profunda (s)'
};

class MobilityBenchmarksScreen extends ConsumerWidget {
  const MobilityBenchmarksScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = MobilityBenchmarkRepository(ref.watch(databaseProvider));
    return Scaffold(
        appBar: AppBar(title: const Text('Movilidad: mediciones')),
        body: ListView(children: [
          const AppCard(children: [
            Text(
                'Mide cada 28 días desde el inicio del bloque. Registra sólo lo observado. '
                'Rodilla a la pared: talón apoyado; pike: distancia respecto a los dedos; pancake: pecho al suelo; '
                'hombro: espalda y lumbar pegadas; sentadilla: talones apoyados y sin ayuda.')
          ]),
          AppCard(children: [
            for (final entry in _names.entries)
              OutlinedButton(
                  onPressed: () => _record(context, ref, repo, entry.key),
                  child: Text(entry.value))
          ]),
          StreamBuilder(
              stream: repo.watch(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return AppCard(children: [Text('Error: ${snapshot.error}')]);
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                if (snapshot.data!.isEmpty) {
                  return const AppCard(children: [
                    Text('Aún sin mediciones; desconocido no es cero.')
                  ]);
                }
                return AppCard(title: 'Historial', children: [
                  for (final row in snapshot.data!)
                    Text('${row.date} · ${_names[row.item]} ${row.side ?? ''}: '
                        '${row.value ?? (row.touches == null ? 'sin dato' : row.touches! ? 'sí' : 'no')} '
                        '· condiciones: ${row.conditions ?? 'desconocidas'}')
                ]);
              }),
        ]));
  }

  Future<void> _record(BuildContext context, WidgetRef ref,
      MobilityBenchmarkRepository repo, String item) async {
    final field = TextEditingController();
    final conditions = TextEditingController();
    String side = 'I';
    bool? touches;
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: Text(_names[item]!),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      if (item == 'shoulder_wall')
                        DropdownButtonFormField<bool>(
                            value: touches,
                            items: const [
                              DropdownMenuItem(value: true, child: Text('Sí')),
                              DropdownMenuItem(value: false, child: Text('No'))
                            ],
                            onChanged: (v) => set(() => touches = v),
                            decoration: const InputDecoration(
                                labelText: '¿Tocan la pared?'))
                      else
                        TextField(
                            controller: field,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: 'Valor medido')),
                      if (item == 'knee_to_wall')
                        DropdownButtonFormField<String>(
                            value: side,
                            items: const [
                              DropdownMenuItem(
                                  value: 'I', child: Text('Izquierda')),
                              DropdownMenuItem(
                                  value: 'D', child: Text('Derecha'))
                            ],
                            onChanged: (v) => set(() => side = v!)),
                      TextField(
                          controller: conditions,
                          decoration: const InputDecoration(
                              labelText: 'Condiciones del intento (opcional)')),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Guardar'))
                    ])));
    final raw = double.tryParse(field.text.replaceAll(',', '.'));
    // Auditoría 053, P1-7: una toma vacía no se guarda.
    if (ok == true && item != 'shoulder_wall' && raw == null) {
      if (context.mounted) showSnack(context, 'Falta el valor: no se guardó nada');
    } else if (ok == true && context.mounted) {
      await guarded(context, () async {
        final plan =
            await ref.read(planRepositoryProvider).dayFor(DateTime.now());
        await repo.save(
            date: DateTime.now(),
            item: item,
            side: item == 'knee_to_wall' ? side : null,
            value: item == 'shoulder_wall'
                ? null
                : double.tryParse(field.text.replaceAll(',', '.')),
            touches: touches,
            conditions:
                conditions.text.trim().isEmpty ? null : conditions.text.trim(),
            blockStart: plan?.validFrom);
      }, ok: 'Medición guardada');
    }
    // Los controladores se liberan cuando el diálogo ya cerró del todo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      field.dispose();
      conditions.dispose();
    });
  }
}
