import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/backup_archive.dart';
import '../../data/database.dart';
import '../../data/database_host.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import 'corrections_screen.dart';
import '../../ui/widgets.dart';
import '../meals/foods_screen.dart';
import '../plan/plan_screen.dart';
import 'health_connect_card.dart';
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
            const HealthConnectCard(),
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Correcciones del traspaso'),
                  subtitle: const Text('Datos que el traspaso pidió corregir'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openCorrections(context),
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
                        onTap: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const RemindersScreen())),
                      ),
                    ),
              ],
            ),
            const _BackupCard(),
            const UpdatesCard(),
          ],
        ),
      ),
    );
  }
}

class _BackupCard extends ConsumerStatefulWidget {
  const _BackupCard();

  @override
  ConsumerState<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<_BackupCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => AppCard(
        title: 'Respaldo',
        children: [
          const Text('Exporta un ZIP con tus registros y fotos de progreso y ejercicios. '
              'Guárdalo fuera del teléfono para poder recuperarlo si lo pierdes.'),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _export(context, ref),
            icon: const Icon(Icons.save_alt),
            label: const Text('Exportar registros y fotos'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _restore(context, ref),
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar desde un respaldo'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child:
                Text('Un ZIP reemplaza registros y fotos. Los respaldos antiguos .sqlite solo reemplazan registros.'),
          ),
          const SizedBox(height: 12),
          Text('Copias automáticas', style: Theme.of(context).textTheme.titleSmall),
          const Text('Una por semana, dentro de la app; se guardan las 4 últimas. '
              'Solo contienen registros, sin fotos. Sirven para deshacer un error; '
              'si pierdes el teléfono se pierden también. Para cambiar de teléfono, exporta el ZIP.'),
          ref.watch(autoBackupsProvider).when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Todavía no hay copias: la primera se hace al abrir la app.'),
                      )
                    : Column(children: [
                        for (final b in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history),
                            title: Text('${weekdayLong(b.date.weekday)} ${formatLong(b.date)}'),
                            subtitle: Text('${fmtDec(b.bytes / 1024, decimals: 0)} KB · registros sin fotos'),
                            trailing: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _restoreFile(
                                      context, ref, b.file, 'la copia automática del ${formatLong(b.date)}'),
                              child: const Text('Restaurar'),
                            ),
                          ),
                      ]),
              ),
        ],
      );

  Future<BackupArchive> _archive(WidgetRef ref) async =>
      BackupArchive(host: ref.read(databaseHostProvider), documents: await ref.read(documentsDirProvider.future));

  Future<T> _progress<T>(String title, Future<T> Function() action) async {
    final navigator = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: const Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Espera mientras verificamos los archivos.'))
          ]),
        ),
      ),
    ));
    try {
      return await action();
    } finally {
      navigator.pop();
    }
  }

  /// Reemplaza registros y, para ZIP, fotos. Pide
  /// confirmación explícita porque borra lo registrado desde ese respaldo.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(withData: false);
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;
    await _restoreFile(context, ref, File(path), p.basename(path));
  }

  Future<void> _restoreFile(BuildContext context, WidgetRef ref, File file, String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    PreparedBackup? prepared;
    var replaced = false;
    try {
      final archive = await _archive(ref);
      final ready = await _progress('Verificando respaldo', () => archive.prepare(file));
      prepared = ready;
      if (!context.mounted) return;
      final legacy = ready.legacy;
      final missing = ready.missingPhotos.length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Restaurar este respaldo?'),
          content: Text('Respaldo: $label\n\n'
              'Se reemplazan todas las sesiones, comidas y medidas actuales por las del respaldo. '
              '${legacy ? 'Es un respaldo antiguo: NO contiene fotos. Las fotos actuales se conservan.' : 'Se reemplazan también las fotos actuales por las ${ready.photoCount} fotos del ZIP.'}\n\n'
              '${missing == 0 ? '' : 'RESPALDO INCOMPLETO: $missing fotos ya faltaban al exportarlo y no se pueden recuperar.\n\n'}'
              'Esto no se puede deshacer.\n\n'
              'Si lo de ahora te sirve, exporta primero.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurar')),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      replaced = true;
      await _progress('Restaurando respaldo', () => archive.restore(ready, allowMissingPhotos: true));
      if (context.mounted) {
        showSnack(
            context,
            legacy
                ? 'Registros restaurados; fotos actuales conservadas'
                : 'Registros y ${ready.photoCount} fotos restaurados${missing == 0 ? '' : '; $missing fotos faltantes'}');
      }
    } on RestoreException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo restaurar: $e');
    } finally {
      // Siempre: aunque falle, la conexión pudo cerrarse y reabrirse en el
      // rollback. Sin esto, repositorios y streams quedan sobre la vieja.
      if (replaced) ref.read(databaseGenerationProvider.notifier).state++;
      await prepared?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final path =
          p.join(dir.path, 'seguimiento-${dayKey(DateTime.now())}-${DateTime.now().microsecondsSinceEpoch}.zip');
      // Se limpian exportaciones temporales de días anteriores. Las de hoy
      // se dejan, porque la
      // app que la recibe puede leerla después de cerrar el menú de compartir.
      await _deleteOldExports(dir, keep: p.basename(path));
      final archive = await _archive(ref);
      final exported = await _progress('Creando respaldo', () => archive.exportTo(path));
      if (!context.mounted) return;
      if (!exported.complete) {
        final sharePartial = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Respaldo incompleto'),
            content: Text('${exported.missingPhotos.length} fotos ya no están en el teléfono. '
                'El ZIP contiene los registros y ${exported.photoCount} fotos disponibles, pero no las faltantes. '
                '¿Quieres compartirlo de todos modos?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Compartir incompleto'))
            ],
          ),
        );
        if (sharePartial != true || !context.mounted) return;
      }
      await Share.shareXFiles([XFile(exported.file.path, mimeType: 'application/zip')],
          subject: 'Respaldo Seguimiento');
      if (context.mounted) showSnack(context, 'Comprueba que el ZIP quedó guardado donde lo puedas recuperar.');
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
  late final _kcalFootball = TextEditingController(text: p.kcalTargetFootball == null ? '' : '${p.kcalTargetFootball}');
  late final _warmup = TextEditingController(text: formatDuration(p.minWarmupSec));
  late final _interval = TextEditingController(text: '${p.measureIntervalDays}');
  late final _intervalMax = TextEditingController(text: '${p.measureIntervalMaxDays}');
  late final _cooldown = TextEditingController(text: formatDuration(p.cooldownTargetSec));
  late final _steps = TextEditingController(text: '${p.stepsTarget}');
  late DateTime _start = p.programStart;
  late DateTime? _birth = p.birthDate == null ? null : parseDay(p.birthDate!);
  late DateTime? _nextMeasurement = p.nextMeasurementDate == null ? null : parseDay(p.nextMeasurementDate!);
  late LengthUnit _unit = p.lengthUnit;
  late bool _neverToFailure = p.neverToFailure;

  @override
  void dispose() {
    for (final c in [_height, _proteinMin, _proteinMax, _kcal, _kcalFloor, _kcalFootball, _warmup, _interval, _intervalMax, _cooldown, _steps]) {
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
          kcalTargetFootball: Value(_positiveInt(_kcalFootball.text)),
          minWarmupSec: Value(parseDuration(_warmup.text) ?? p.minWarmupSec),
          measureIntervalDays: Value(interval),
          measureIntervalMaxDays: Value(intervalMax),
          nextMeasurementDate: Value(_nextMeasurement == null ? null : dayKey(_nextMeasurement!)),
          cooldownTargetSec: Value(parseDuration(_cooldown.text) ?? p.cooldownTargetSec),
          neverToFailure: Value(_neverToFailure),
          stepsTarget: Value(_positiveInt(_steps.text) ?? p.stepsTarget),
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
        NumberField(controller: _kcalFootball, label: 'kcal en días de fútbol (sáb y dom; vacío = la misma)'),
        const SizedBox(height: 8),
        NumberField(controller: _steps, label: 'Pasos diarios entre semana', suffix: 'pasos'),
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
  final exports = RegExp(r'^seguimiento-\d{4}-\d{2}-\d{2}(?:-\d+)?\.(?:sqlite|zip)$');
  for (final f in dir.listSync().whereType<File>()) {
    final name = p.basename(f.path);
    if (name == keep || name.startsWith('seguimiento-${dayKey(DateTime.now())}') || !exports.hasMatch(name)) continue;
    try {
      await f.delete();
    } on Object {
      // Tomado por otra app: se intenta la próxima vez.
    }
  }
}

int? _positiveInt(String text) {
  final v = int.tryParse(text.trim());
  return v == null || v <= 0 ? null : v;
}
