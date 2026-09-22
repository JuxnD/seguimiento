import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../ui/widgets.dart';
import '../meals/foods_screen.dart';
import '../plan/plan_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (p) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _ProfileCard(profile: p),
            AppCard(
              title: 'Catálogos',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Alimentos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FoodsScreen())),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_view_week),
                  title: const Text('Plan semanal'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanScreen())),
                ),
              ],
            ),
            AppCard(
              title: 'Respaldo',
              children: [
                const Text('Los datos viven solo en este dispositivo. Exporta la base de vez en cuando '
                    'y guárdala donde la puedas recuperar.'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _export(context, ref),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Exportar base de datos'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'seguimiento-${dayKey(DateTime.now())}.sqlite');
      final file = await ref.read(databaseProvider).exportTo(path);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Respaldo Seguimiento'));
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo exportar: $e');
    }
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({required this.profile});

  final ProfileRow profile;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final p = widget.profile;
  late final _height = TextEditingController(text: p.heightCm == null ? '' : fmtDec(p.heightCm!));
  late final _proteinMin = TextEditingController(text: '${p.proteinMin}');
  late final _proteinMax = TextEditingController(text: '${p.proteinMax}');
  late final _kcal = TextEditingController(text: '${p.kcalTarget}');
  late final _kcalFloor = TextEditingController(text: '${p.kcalFloor}');
  late final _warmup = TextEditingController(text: formatDuration(p.minWarmupSec));
  late final _interval = TextEditingController(text: '${p.measureIntervalDays}');
  late DateTime _start = p.programStart;
  late DateTime? _birth = p.birthDate == null ? null : parseDay(p.birthDate!);
  late LengthUnit _unit = p.lengthUnit;

  @override
  void dispose() {
    for (final c in [_height, _proteinMin, _proteinMax, _kcal, _kcalFloor, _warmup, _interval]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(profileRepositoryProvider).save(ProfilesCompanion(
          birthDate: Value(_birth == null ? null : dayKey(_birth!)),
          heightCm: Value(parseNum(_height.text)),
          startDate: Value(dayKey(_start)),
          proteinMin: Value(int.tryParse(_proteinMin.text) ?? p.proteinMin),
          proteinMax: Value(int.tryParse(_proteinMax.text) ?? p.proteinMax),
          kcalTarget: Value(int.tryParse(_kcal.text) ?? p.kcalTarget),
          kcalFloor: Value(int.tryParse(_kcalFloor.text) ?? p.kcalFloor),
          minWarmupSec: Value(parseDuration(_warmup.text) ?? p.minWarmupSec),
          measureIntervalDays: Value(int.tryParse(_interval.text) ?? p.measureIntervalDays),
          lengthUnit: Value(_unit),
        ));
    if (mounted) showSnack(context, 'Perfil guardado');
  }

  @override
  Widget build(BuildContext context) {
    final age = _birth == null ? null : (daysBetween(_birth!, DateTime.now()) / 365.25).floor();
    return AppCard(
      title: 'Perfil',
      children: [
        DateTile(
          label: 'Inicio del programa (ancla de las semanas)',
          date: _start,
          onChanged: (v) => setState(() => _start = v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cake_outlined),
          title: const Text('Fecha de nacimiento'),
          subtitle: Text(_birth == null ? 'Sin definir' : '${formatLong(_birth!)} · $age años'),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _birth ?? DateTime(1995),
              firstDate: DateTime(1940),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _birth = dateOnly(picked));
          },
        ),
        const SizedBox(height: 8),
        NumberField(controller: _height, label: 'Estatura', suffix: 'cm', decimal: true),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: NumberField(controller: _proteinMin, label: 'Proteína mín', suffix: 'g')),
            const SizedBox(width: 8),
            Expanded(child: NumberField(controller: _proteinMax, label: 'Proteína máx', suffix: 'g')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: NumberField(controller: _kcal, label: 'kcal objetivo')),
            const SizedBox(width: 8),
            Expanded(child: NumberField(controller: _kcalFloor, label: 'Piso de alerta kcal')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: DurationField(controller: _warmup, label: 'Calentamiento mínimo')),
            const SizedBox(width: 8),
            Expanded(child: NumberField(controller: _interval, label: 'Días entre medidas')),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<LengthUnit>(
          segments: const [
            ButtonSegment(value: LengthUnit.cm, label: Text('Mostrar en cm')),
            ButtonSegment(value: LengthUnit.inch, label: Text('En pulgadas')),
          ],
          selected: {_unit},
          onSelectionChanged: (s) => setState(() => _unit = s.first),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _save, child: const Text('Guardar perfil')),
        ),
      ],
    );
  }
}
