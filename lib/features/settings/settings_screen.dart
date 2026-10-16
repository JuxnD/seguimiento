import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/backup_archive.dart';
import '../../data/manual_export.dart';
import '../../data/database.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/goal_history.dart';
import '../../domain/dates.dart';
import '../../domain/enums.dart';
import '../../domain/format.dart';
import 'corrections_screen.dart';
import 'equipment_card.dart';
import 'restore_access.dart';
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
            ref.watch(goalHistoryProvider).when(
                  loading: () =>
                      const AppCard(children: [Text('Consultando metas…')]),
                  error: (e, _) => AppCard(children: [
                    Text('No se pudieron consultar las metas: $e')
                  ]),
                  data: (history) => _ProfileCard(key: ValueKey((ref.watch(databaseGenerationProvider),
                        p,
                        ref.watch(todayProvider),
                        history.versions
                            .map((v) => '${v.id}:${v.value}:${v.effectiveFrom}')
                            .join('|')
                      )), profile: p,
                      history: history,
                      day: ref.watch(todayProvider)),
                ),
            const HealthConnectCard(),
            AppCard(
              title: 'Rayito',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rayito en pantalla'),
                  subtitle: const Text(
                      'Tu compañero abajo a la derecha: te habla y festeja lo que guardas. Mantenlo presionado para esconderlo.'),
                  value: !ref.watch(rayitoHiddenProvider),
                  onChanged: (show) => setRayitoHidden(ref, !show),
                ),
              ],
            ),
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
            const _SupplementsCard(),
            const _BackupCard(),
            const UpdatesCard(),
            // Plan 052 (§16.27.4): al final, para no mover lo de arriba.
            const EquipmentCard(),
          ],
        ),
      ),
    );
  }
}

/// Suplementos (plan 052, §16.27.5): nombre, dosis, tomas por envase,
/// fecha de inicio (la elige el usuario el día que empieza) y si está activo.
/// La toma se marca en el registro de la mañana; Hoy avisa con 7 o menos.
class _SupplementsCard extends ConsumerWidget {
  const _SupplementsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppCard(
        title: 'Suplementos',
        trailing: IconButton(
          tooltip: 'Agregar suplemento',
          icon: const Icon(Icons.add),
          onPressed: () => _edit(context, ref, null),
        ),
        children: [
          ref.watch(supplementsProvider).when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (rows) => rows.isEmpty
                    ? const Text('Sin suplementos. Agrega uno para marcar la toma '
                        'en el registro de la mañana y saber cuántas tomas quedan.')
                    : Column(children: [
                        for (final s in rows)
                          ListTile(
                            key: ValueKey('supplement:${s.id}'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.medication_outlined),
                            title: Text(s.name),
                            subtitle: Text(_supplementSummary(s)),
                            trailing: Switch(
                              value: s.active,
                              onChanged: (v) => guarded(
                                  context,
                                  () => ref
                                      .read(supplementRepositoryProvider)
                                      .setActive(s.id, v)),
                            ),
                            onTap: () => _edit(context, ref, s),
                          ),
                      ]),
              ),
        ],
      );

  Future<void> _edit(
      BuildContext context, WidgetRef ref, SupplementRow? existing) async {
    final draft = await showDialog<_SupplementDraft>(
        context: context,
        builder: (_) => _SupplementDialog(existing: existing));
    if (draft == null || !context.mounted) return;
    final repo = ref.read(supplementRepositoryProvider);
    await guarded(
        context,
        () async {
          if (existing == null) {
            await repo.add(
                name: draft.name,
                dose: draft.dose,
                servingsPerPack: draft.servings,
                start: draft.start,
                active: draft.active);
          } else {
            await repo.edit(existing.id,
                name: draft.name,
                dose: draft.dose,
                servingsPerPack: draft.servings,
                start: draft.start,
                active: draft.active);
          }
        },
        ok: existing == null ? 'Suplemento agregado' : 'Suplemento guardado');
  }
}

String _supplementSummary(SupplementRow s) => [
      if (s.dose.isNotEmpty) s.dose,
      if (s.servingsPerPack != null) '${s.servingsPerPack} tomas por envase',
      s.startDate == null
          ? 'sin empezar'
          : 'desde el ${formatLong(parseDay(s.startDate!))}',
      if (!s.active) 'en pausa',
    ].join(' · ');

typedef _SupplementDraft = ({
  String name,
  String dose,
  int? servings,
  DateTime? start,
  bool active,
});

/// Alta o edición. El diálogo es dueño de sus controllers.
class _SupplementDialog extends StatefulWidget {
  const _SupplementDialog({this.existing});

  final SupplementRow? existing;

  @override
  State<_SupplementDialog> createState() => _SupplementDialogState();
}

class _SupplementDialogState extends State<_SupplementDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _dose = TextEditingController(text: widget.existing?.dose ?? '');
  late final _servings = TextEditingController(
      text: widget.existing?.servingsPerPack?.toString() ?? '');
  late DateTime? _start = widget.existing?.startDate == null
      ? null
      : parseDay(widget.existing!.startDate!);
  late bool _active = widget.existing?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _servings.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Escribe el nombre del suplemento');
      return;
    }
    final raw = _servings.text.trim();
    final servings = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && (servings == null || servings <= 0)) {
      showSnack(context, 'Las tomas del envase van de 1 en adelante');
      return;
    }
    final _SupplementDraft draft = (
      name: name,
      dose: _dose.text.trim(),
      servings: servings,
      start: _start,
      active: _active,
    );
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.existing == null
            ? 'Agregar suplemento'
            : 'Editar suplemento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('supplement-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Nombre', hintText: 'Creatina'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('supplement-dose'),
              controller: _dose,
              decoration: const InputDecoration(
                  labelText: 'Dosis diaria',
                  hintText: '1 cucharada (6 g ≈ 5 g de creatina)'),
            ),
            const SizedBox(height: 8),
            NumberField(
                key: const ValueKey('supplement-servings'),
                controller: _servings,
                label: 'Tomas por envase',
                suffix: 'tomas'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Inicio'),
              subtitle: Text(_start == null
                  ? 'Sin fecha: elígela el día que empieces'
                  : '${weekdayLong(_start!.weekday)} ${formatLong(_start!)}'),
              trailing: _start == null
                  ? const Icon(Icons.edit_calendar)
                  : IconButton(
                      tooltip: 'Quitar fecha',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _start = null),
                    ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start ?? dateOnly(DateTime.now()),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null && mounted) {
                  setState(() => _start = dateOnly(picked));
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              subtitle: const Text('Aparece en el registro de la mañana.'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(onPressed: _submit, child: const Text('Guardar')),
        ],
      );
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
          const Text('Exporta un ZIP con tus registros, historial de IA '
              '(preguntas, respuestas y contexto) y fotos de progreso y ejercicios. '
              'El archivo se guarda sin cifrar: quien lo reciba puede leer esos datos. '
              'Guárdalo en un lugar privado fuera del teléfono para recuperarlo si lo pierdes. '
              'La licencia de IA no se incluye.'),
          const SizedBox(height: 8),
          const Text('Esta app está configurada para excluir sus datos de copias automáticas de Android '
              'y del traslado entre teléfonos. Usa el ZIP. No borra copias previas '
              'ni controla herramientas del fabricante o de terceros.'),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _export(context, ref),
            icon: const Icon(Icons.save_alt),
            label: const Text('Exportar registros y fotos'),
          ),
          const SizedBox(height: 8),
          // Plan 056 (§16.28.4 B): para el entrenador, generado de los datos.
          OutlinedButton.icon(
            key: const ValueKey('exportar-manual'),
            onPressed: _busy ? null : () => _exportManual(context, ref),
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Exportar manual'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _restore(context, ref),
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar desde un respaldo'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Un ZIP reemplaza registros, historial de IA y fotos. '
                'Los respaldos antiguos .sqlite reemplazan la base, incluido el historial de IA '
                'que contengan; conservan las fotos actuales. No reemplazan el cronómetro en curso ni los permisos.'),
          ),
          const SizedBox(height: 12),
          Text('Copias automáticas', style: Theme.of(context).textTheme.titleSmall),
          const Text('Una por semana, sin cifrar dentro de la app; se guardan las 4 últimas. '
              'Contienen la base y el historial de IA, sin fotos ni licencia. '
              'Al restaurarlas pueden recuperar conversaciones borradas después de la copia. '
              'Sirven para deshacer un error; '
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
                            subtitle:
                                Text('${fmtDec(b.bytes / 1024, decimals: 0)} KB · base e historial IA, sin fotos'),
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

  /// Reemplaza registros y, para ZIP, fotos, con el acceso común de
  /// restauración (también lo usa el alta).
  Future<void> _restore(BuildContext context, WidgetRef ref) => _whileBusy(() => pickAndRestoreBackup(context, ref));

  Future<void> _restoreFile(BuildContext context, WidgetRef ref, File file, String label) =>
      _whileBusy(() => restoreBackupFile(context, ref, file, label));

  Future<void> _whileBusy(Future<Object?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Plan 056: el manual de la app (plan, días, tests, metas y avisos) en
  /// Markdown, generado de los datos vivos, para compartir.
  Future<void> _exportManual(BuildContext context, WidgetRef ref) async {
    await guarded(context, () async {
      final version = await ref.read(appVersionProvider.future);
      final text = await buildAppManual(ref.read(databaseProvider),
          appVersion: version);
      await Share.share(text, subject: 'Manual de My Prime $version');
    }, failure: 'No se pudo generar el manual');
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('Antes de exportar'),
          content: const Text('El ZIP incluye perfil, plan, sesiones, comidas, medidas, catálogos, '
              'fotos de progreso y ejercicios, e historial de IA con preguntas, respuestas y contexto.\n\n'
              'Se guarda sin cifrar. Compártelo sólo donde quieras conservar esos datos privados. '
              'No incluye la licencia, los permisos ni el cronómetro en curso.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Crear respaldo')),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
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
          subject: 'Respaldo My Prime');
      if (context.mounted) showSnack(context, 'Comprueba que el ZIP quedó guardado donde lo puedas recuperar.');
    } on Object catch (e) {
      if (context.mounted) showSnack(context, 'No se pudo exportar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({super.key, required this.profile,
      required this.history,
      required this.day});

  final ProfileRow profile;
  final GoalHistory history;
  final DateTime day;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final p = widget.profile;
  late final _height = TextEditingController(text: p.heightCm == null ? '' : fmtDec(p.heightCm!));
  late final _proteinMin = TextEditingController(text: _goalText(GoalMetric.proteinaMin));
  late final _proteinMax = TextEditingController(text: _goalText(GoalMetric.proteinaMax));
  late final _kcal = TextEditingController(text: _goalText(GoalMetric.kcal));
  late final _kcalFloor = TextEditingController(text: _goalText(GoalMetric.kcalFloor));
  late final _kcalFootball = TextEditingController(text: _goalText(GoalMetric.kcalFutbol));
  late final _warmup = TextEditingController(text: formatDuration(p.minWarmupSec));
  late final _interval = TextEditingController(text: '${p.measureIntervalDays}');
  late final _intervalMax = TextEditingController(text: '${p.measureIntervalMaxDays}');
  late final _cooldown = TextEditingController(text: formatDuration(p.cooldownTargetSec));
  late final _steps = TextEditingController(text: _goalText(GoalMetric.pasos));
  late DateTime _start = p.programStart;
  late DateTime? _birth = p.birthDate == null ? null : parseDay(p.birthDate!);
  late DateTime? _nextMeasurement = p.nextMeasurementDate == null ? null : parseDay(p.nextMeasurementDate!);
  late LengthUnit _unit = p.lengthUnit;
  late bool _neverToFailure = p.neverToFailure;

  late final _goalFields = {
    GoalMetric.proteinaMin: _proteinMin,
    GoalMetric.proteinaMax: _proteinMax,
    GoalMetric.kcal: _kcal,
    GoalMetric.kcalFloor: _kcalFloor,
    GoalMetric.kcalFutbol: _kcalFootball,
    GoalMetric.pasos: _steps,
  };

  GoalAt _at(GoalMetric metric) =>
      goalReferenceOn(widget.history, metric, widget.day);
  String _goalText(GoalMetric metric) =>
      _at(metric).comparable ? '${_at(metric).value!.round()}' : '';
  String _label(GoalMetric metric, String label) => _at(metric).comparable
      ? label
      : '$label (${_at(metric).absenceLabel.toLowerCase()})';

  Future<void> _removeGoal(GoalMetric metric) async {
    final football = metric == GoalMetric.kcalFutbol;
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text(football
                  ? '¿Usar la meta semanal en fútbol?'
                  : '¿Quitar ${metric.label.toLowerCase()}?'),
              content: Text(football
                  ? 'Desde la confirmación se usa la meta semanal si está definida. Los registros anteriores se conservan.'
                  : 'Desde la confirmación queda sin meta. Se conservan registros y metas anteriores; puedes definirla después.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(football ? 'Usar la misma' : 'Quitar meta')),
              ],
            ));
    if (ok != true || !mounted) return;
    await guarded(
        context,
        () => GoalRepository(ref.read(databaseProvider)).setPersonalGoals(
            {metric: null},
            now: ref.read(decisionClockProvider)()),
        ok: football ? 'Se usa la meta semanal' : 'Meta quitada');
      }

  @override
  void dispose() {
    for (final c in [
      _height,
      _proteinMin,
      _proteinMax,
      _kcal,
      _kcalFloor,
      _kcalFootball,
      _warmup,
      _interval,
      _intervalMax,
      _cooldown,
      _steps
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final selections = <GoalMetric, double?>{};
    for (final entry in _goalFields.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) {
        if (_at(entry.key).comparable) {
          showSnack(context,
              'Para quitar ${entry.key.label.toLowerCase()}, usa su acción explícita; no se guardó nada.');
          return;
        }
        continue;
      }
      final value = _positiveInt(raw);
      if (value == null) {
        showSnack(context,
            'Revisa ${entry.key.label.toLowerCase()}: escribe una cifra entera positiva.');
        return;
      }
      if (!_at(entry.key).known || _at(entry.key).value != value)
      {
        selections[entry.key] = value.toDouble();
      }
    }
    final interval = int.tryParse(_interval.text) ?? p.measureIntervalDays;
    final intervalMax = int.tryParse(_intervalMax.text) ?? p.measureIntervalMaxDays;
    final problem = interval <= 0 || intervalMax < interval
                ? 'La ventana de medición va de un mínimo (> 0) a un máximo mayor o igual'
                : null;
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    await guarded(
        context,
        () => GoalRepository(ref.read(databaseProvider)).setPersonalGoals(
            selections,
            profileChanges: ProfilesCompanion(
              birthDate: Value(_birth == null ? null : dayKey(_birth!)),
              heightCm: Value(parseNum(_height.text)),
              startDate: Value(dayKey(_start)),
              minWarmupSec: Value(parseDuration(_warmup.text) ?? p.minWarmupSec),
              measureIntervalDays: Value(interval),
              measureIntervalMaxDays: Value(intervalMax),
              nextMeasurementDate: Value(_nextMeasurement == null ? null : dayKey(_nextMeasurement!)),
              cooldownTargetSec: Value(parseDuration(_cooldown.text) ?? p.cooldownTargetSec),
              neverToFailure: Value(_neverToFailure),
              lengthUnit: Value(_unit),
            ),
            now: ref.read(decisionClockProvider)()),
        ok: 'Perfil guardado');
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
            Expanded(
                child: NumberField(
                    controller: _proteinMin, label: _label(GoalMetric.proteinaMin, 'Proteína mín'), suffix: 'g')),
            const SizedBox(width: 8),
            Expanded(
                child: NumberField(
                    controller: _proteinMax, label: _label(GoalMetric.proteinaMax, 'Proteína máx'), suffix: 'g')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: NumberField(controller: _kcal, label: _label(GoalMetric.kcal, 'kcal objetivo'))),
            const SizedBox(width: 8),
            Expanded(
                child: NumberField(controller: _kcalFloor, label: _label(GoalMetric.kcalFloor, 'Piso de alerta kcal'))),
          ],
        ),
        const SizedBox(height: 8),
        NumberField(controller: _kcalFootball, label: 'kcal en días de fútbol (sáb y dom; vacío = la misma)'),
        const Text(
            'En fútbol, «la misma» hereda la meta semanal si está definida. Vaciar un número no lo cambia.'),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final metric in _goalFields.keys
              .where((m) => m != GoalMetric.pasos && _at(m).comparable))
            TextButton(
                onPressed: () => _removeGoal(metric),
                child: Text(metric == GoalMetric.kcalFutbol
                    ? 'Fútbol: usar la misma'
                    : 'Quitar ${metric.label.toLowerCase()}')),
        ]),
        const SizedBox(height: 8),
        NumberField(controller: _steps, label: 'Pasos diarios entre semana', suffix: 'pasos'),
        if (p.stepsTarget == 7500) ...[
          const Text('Puedes adoptar el mínimo inicial de 5.000 pasos. El cambio se aplica al guardar el perfil.'),
          TextButton(
              onPressed: () => setState(() => _steps.text = '5000'), child: const Text('Usar 5.000 pasos como base')),
        ],
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
