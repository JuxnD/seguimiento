import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/repositories/reminder_repository.dart';
import '../../domain/dates.dart';
import '../../domain/reminders.dart';
import '../../ui/widgets.dart';

/// Activar, apagar y mover de hora cada recordatorio.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  bool? _permission;
  bool? _exact;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final service = ref.read(notificationServiceProvider);
    final ok = await service.hasPermission();
    final exact = await service.canScheduleExact();
    if (mounted) {
      setState(() {
        _permission = ok;
        _exact = exact;
      });
    }
  }

  Future<void> _askExact() async {
    await ref.read(notificationServiceProvider).requestExactAlarms();
    await _checkPermission();
  }

  Future<void> _askPermission() async {
    await ref.read(notificationServiceProvider).requestPermission();
    await _checkPermission();
    if (mounted) await ref.read(rescheduleRemindersProvider)();
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(remindersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recordatorios'),
        actions: [
          IconButton(
            tooltip: 'Ver programados',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: _showPending,
          ),
        ],
      ),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          final byKind = {for (final r in list) r.kind: r};
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (_permission == false)
                AppCard(
                  children: [
                    const Text('Las notificaciones están bloqueadas para esta app. '
                        'Sin permiso no llega ningún aviso.'),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: _askPermission, child: const Text('Pedir permiso')),
                  ],
                ),
              if (_permission == true && _exact == false && byKind[ReminderKind.descanso]?.enabled == true)
                AppCard(
                  children: [
                    const Text('Android no deja a esta app usar alarmas exactas. El aviso de fin de '
                        'descanso con la pantalla apagada puede llegar varios minutos tarde.'),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: _askExact, child: const Text('Permitir alarmas exactas')),
                  ],
                ),
              for (final kind in ReminderKind.values)
                if (byKind[kind] != null) _ReminderCard(row: byKind[kind]!),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showPending() async {
    final pending = await ref.read(notificationServiceProvider).pending();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Programados: ${pending.length}'),
        content: SizedBox(
          width: double.maxFinite,
          child: pending.isEmpty
              ? const Text('Nada en cola. Si acabas de cambiar algo, vuelve a entrar.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in pending.take(20))
                      ListTile(
                        dense: true,
                        title: Text(p.title ?? '—'),
                        subtitle: Text(p.body ?? ''),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard({required this.row});

  final ReminderRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(reminderRepositoryProvider);
    final setting = row.toSetting();
    return AppCard(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.kind.label, style: Theme.of(context).textTheme.titleSmall),
                  Text(row.kind.description, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Switch(
              value: row.enabled,
              onChanged: (v) => guarded(context, () => repo.save(row.kind, enabled: v)),
            ),
          ],
        ),
        if (row.enabled && row.kind.isScheduled)
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(row.kind == ReminderKind.sesion
                    ? 'Entreno a las ${setting.timeLabel} (avisa 15 min antes)'
                    : 'A las ${setting.timeLabel}'),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: row.hour ?? 8, minute: row.minute),
                  );
                  if (picked != null) {
                    if (context.mounted) await guarded(context, () => repo.save(row.kind, hour: picked.hour, minute: picked.minute));
                  }
                },
              ),
              if (row.kind == ReminderKind.proteina) ...[
                const Spacer(),
                TextButton(
                  child: Text('Bajo ${row.threshold ?? 100} g'),
                  onPressed: () => _editThreshold(context, repo),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Future<void> _editThreshold(BuildContext context, ReminderRepository repo) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _ThresholdDialog(initial: row.threshold ?? 100),
    );
    if (value != null && context.mounted) await guarded(context, () => repo.save(row.kind, threshold: value));
  }
}

/// Dueño de su controller: se libera cuando el diálogo termina de cerrarse,
/// no mientras todavía anima la salida.
class _ThresholdDialog extends StatefulWidget {
  const _ThresholdDialog({required this.initial});

  final int initial;

  @override
  State<_ThresholdDialog> createState() => _ThresholdDialogState();
}

class _ThresholdDialogState extends State<_ThresholdDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Avisar si voy por debajo de'),
        content: NumberField(controller: _controller, label: 'Proteína', suffix: 'g', autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(_controller.text)),
            child: const Text('Guardar'),
          ),
        ],
      );
}

/// Texto corto para la pantalla de ajustes: cuántos avisos están activos.
String remindersSummary(List<ReminderRow> rows) {
  final active = rows.where((r) => r.enabled).length;
  if (active == 0) return 'Todos apagados';
  final next = rows.where((r) => r.enabled && r.kind.isScheduled && r.hour != null).toList()
    ..sort((a, b) => (a.hour! * 60 + a.minute).compareTo(b.hour! * 60 + b.minute));
  if (next.isEmpty) return '$active activos';
  return '$active activos · primero ${timeKey(next.first.hour!, next.first.minute)}';
}
