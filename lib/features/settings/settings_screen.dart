import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/database_host.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import '../../ui/widgets.dart';
import '../meals/foods_screen.dart';
import '../plan/plan_screen.dart';
import 'reminders_screen.dart';
import 'updates_card.dart';

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
            // La clave recrea la tarjeta al restaurar: si no, mostraría (y al
            // guardar escribiría) el perfil anterior.
            _ProfileCard(key: ValueKey(ref.watch(databaseGenerationProvider)), profile: p),
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
              title: 'Recordatorios',
              children: [
                ref.watch(remindersProvider).when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                      data: (rows) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.notifications_active_outlined),
                        title: const Text('Avisos y horas'),
                        subtitle: Text(remindersSummary(rows)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const RemindersScreen())),
                      ),
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
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _restore(context, ref),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restaurar desde un respaldo'),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Restaurar reemplaza TODO lo registrado por el contenido del respaldo.'),
                ),
                const SizedBox(height: 12),
                Text('Copias automáticas', style: Theme.of(context).textTheme.titleSmall),
                const Text('Una por semana, dentro de la app; se guardan las 4 últimas. Sirven para '
                    'deshacer un error, no para cambiar de teléfono: para eso, exporta.'),
                ref.watch(autoBackupsProvider).when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                      data: (list) => list.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('Todavía no hay copias: la primera se hace al abrir la app.'),
                            )
                          : Column(
                              children: [
                                for (final b in list)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.history),
                                    title: Text('${weekdayLong(b.date.weekday)} ${formatLong(b.date)}'),
                                    subtitle: Text('${fmtDec(b.bytes / 1024, decimals: 0)} KB'),
                                    trailing: TextButton(
                                      onPressed: () => _restoreFile(context, ref, b.file,
                                          'la copia automática del ${formatLong(b.date)}'),
                                      child: const Text('Restaurar'),
                                    ),
                                  ),
                              ],
                            ),
                    ),
              ],
            ),
            const UpdatesCard(),
          ],
        ),
      ),
    );
  }

  /// Reemplaza la base por un archivo `.sqlite` exportado antes. Pide
  /// confirmación explícita porque borra lo registrado desde ese respaldo.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(withData: false);
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;
    await _restoreFile(context, ref, File(path), p.basename(path));
  }

  Future<void> _restoreFile(BuildContext context, WidgetRef ref, File file, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Restaurar este respaldo?'),
        content: Text('Respaldo: $label\n\n'
            'Se reemplazan todas las sesiones, comidas y medidas actuales por las del respaldo. '
            'Esto no se puede deshacer.\n\n'
            'Si lo de ahora te sirve, exporta primero.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(databaseHostProvider).restoreFrom(file);
      if (context.mounted) showSnack(context, 'Respaldo restaurado');
    } on RestoreException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo restaurar: $e');
    } finally {
      // Siempre: aunque falle, la conexión pudo cerrarse y reabrirse en el
      // rollback. Sin esto, repositorios y streams quedan sobre la vieja.
      ref.read(databaseGenerationProvider.notifier).state++;
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = p.join(dir.path, 'seguimiento-${dayKey(DateTime.now())}.sqlite');
      // Las exportaciones anteriores ya se compartieron: se borran para no
      // acumular una copia de la base por día. La de hoy se deja, porque la
      // app que la recibe puede leerla después de cerrar el menú de compartir.
      await _deleteOldExports(dir, keep: p.basename(path));
      final file = await ref.read(databaseHostProvider).exportTo(path);
      await Share.shareXFiles([XFile(file.path)], subject: 'Respaldo Seguimiento');
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo exportar: $e');
    }
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({super.key, required this.profile});

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
  late final _intervalMax = TextEditingController(text: '${p.measureIntervalMaxDays}');
  late final _cooldown = TextEditingController(text: formatDuration(p.cooldownTargetSec));
  late DateTime _start = p.programStart;
  late DateTime? _birth = p.birthDate == null ? null : parseDay(p.birthDate!);
  late DateTime? _nextMeasurement = p.nextMeasurementDate == null ? null : parseDay(p.nextMeasurementDate!);
  late LengthUnit _unit = p.lengthUnit;
  late bool _neverToFailure = p.neverToFailure;

  @override
  void dispose() {
    for (final c in [_height, _proteinMin, _proteinMax, _kcal, _kcalFloor, _warmup, _interval, _intervalMax, _cooldown]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final proteinMin = int.tryParse(_proteinMin.text) ?? p.proteinMin;
    final proteinMax = int.tryParse(_proteinMax.text) ?? p.proteinMax;
    final kcal = int.tryParse(_kcal.text) ?? p.kcalTarget;
    final kcalFloor = int.tryParse(_kcalFloor.text) ?? p.kcalFloor;
    final interval = int.tryParse(_interval.text) ?? p.measureIntervalDays;
    final intervalMax = int.tryParse(_intervalMax.text) ?? p.measureIntervalMaxDays;
    final problem = proteinMin > proteinMax
        ? 'La proteína mínima no puede ser mayor que la máxima'
        : kcalFloor > kcal
            ? 'El piso de alerta no puede ser mayor que las kcal objetivo'
            : interval <= 0 || intervalMax < interval
                ? 'La ventana de medición va de un mínimo (> 0) a un máximo mayor o igual'
                : null;
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    await guarded(context, () => ref.read(profileRepositoryProvider).save(ProfilesCompanion(
          birthDate: Value(_birth == null ? null : dayKey(_birth!)),
          heightCm: Value(parseNum(_height.text)),
          startDate: Value(dayKey(_start)),
          proteinMin: Value(proteinMin),
          proteinMax: Value(proteinMax),
          kcalTarget: Value(kcal),
          kcalFloor: Value(kcalFloor),
          minWarmupSec: Value(parseDuration(_warmup.text) ?? p.minWarmupSec),
          measureIntervalDays: Value(interval),
          measureIntervalMaxDays: Value(intervalMax),
          nextMeasurementDate: Value(_nextMeasurement == null ? null : dayKey(_nextMeasurement!)),
          cooldownTargetSec: Value(parseDuration(_cooldown.text) ?? p.cooldownTargetSec),
          neverToFailure: Value(_neverToFailure),
          lengthUnit: Value(_unit),
        )), ok: 'Perfil guardado');
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
            Expanded(child: DurationField(controller: _cooldown, label: 'Meta de enfriamiento')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: NumberField(controller: _interval, label: 'Medir desde', suffix: 'días')),
            const SizedBox(width: 8),
            Expanded(child: NumberField(controller: _intervalMax, label: 'Medir hasta', suffix: 'días')),
          ],
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_available_outlined),
          title: const Text('Próxima medición acordada'),
          subtitle: Text(_nextMeasurement == null
              ? 'Sin fecha: se calcula desde la última toma'
              : '${weekdayLong(_nextMeasurement!.weekday)} ${formatLong(_nextMeasurement!)}'),
          trailing: _nextMeasurement == null
              ? const Icon(Icons.edit_calendar)
              : IconButton(
                  tooltip: 'Quitar fecha',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _nextMeasurement = null),
                ),
          onTap: () async {
            final today = dateOnly(DateTime.now());
            final picked = await showDatePicker(
              context: context,
              initialDate: _nextMeasurement ?? today,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _nextMeasurement = dateOnly(picked));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('No entrenar al fallo'),
          subtitle: const Text('Avisa si marcas una serie al fallo'),
          value: _neverToFailure,
          onChanged: (v) => setState(() => _neverToFailure = v),
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

Future<void> _deleteOldExports(Directory dir, {required String keep}) async {
  final exports = RegExp(r'^seguimiento-\d{4}-\d{2}-\d{2}\.sqlite$');
  for (final f in dir.listSync().whereType<File>()) {
    final name = p.basename(f.path);
    if (name == keep || !exports.hasMatch(name)) continue;
    try {
      await f.delete();
    } on Object {
      // Tomado por otra app: se intenta la próxima vez.
    }
  }
}
