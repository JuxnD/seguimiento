import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart';
import '../../domain/reminders.dart';
import '../../ui/widgets.dart';

/// "Tus recordatorios" en Recordatorios: los que crea el usuario.
class CustomRemindersCard extends ConsumerWidget {
  const CustomRemindersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(customRemindersProvider).valueOrNull ?? const <CustomReminder>[];
    final text = Theme.of(context).textTheme;
    final today = ref.watch(todayProvider);
    return AppCard(
      title: 'Tus recordatorios',
      children: [
        if (list.isEmpty)
          Text(
            'Para lo que no está en el plan: ejercicios de cuello, estiramientos, tomar creatina… '
            'Cada cuántos días se cuenta desde la última vez que lo marcas como hecho en Hoy.',
            style: text.bodyMedium,
          ),
        for (final r in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_repeat),
            title: Text(r.title),
            subtitle: Text('${_capitalize(r.frequencyLabel)} · ${r.timeLabel} · ${_nextLabel(r, today)}'),
            trailing: Switch(
              value: r.enabled,
              onChanged: (v) => guarded(context, () => ref.read(customReminderRepositoryProvider).setEnabled(r.id, v)),
            ),
            onTap: () => openCustomReminderForm(context, existing: r),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => openCustomReminderForm(context),
          icon: const Icon(Icons.add_alarm),
          label: const Text('Nuevo recordatorio'),
        ),
      ],
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "toca hoy", "pendiente desde el lun 28 sep", "próximo: jue 1 oct".
String _nextLabel(CustomReminder r, DateTime today) {
  if (!r.enabled) return 'apagado';
  final next = r.nextDue;
  if (r.dueOn(today)) {
    return next.isBefore(dateOnly(today)) ? 'pendiente desde el ${weekdayShort(next.weekday)} ${formatShort(next)}' : 'toca hoy';
  }
  if (r.lastDone != null && dateOnly(r.lastDone!) == dateOnly(today)) {
    return 'hecho hoy · próximo ${weekdayShort(next.weekday)} ${formatShort(next)}';
  }
  return 'próximo ${weekdayShort(next.weekday)} ${formatShort(next)}';
}

Future<void> openCustomReminderForm(BuildContext context, {CustomReminder? existing}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomReminderFormScreen(existing: existing)));

class CustomReminderFormScreen extends ConsumerStatefulWidget {
  const CustomReminderFormScreen({super.key, this.existing});

  final CustomReminder? existing;

  @override
  ConsumerState<CustomReminderFormScreen> createState() => _CustomReminderFormScreenState();
}

class _CustomReminderFormScreenState extends ConsumerState<CustomReminderFormScreen> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _interval = TextEditingController(text: '${widget.existing?.intervalDays ?? 3}');
  late TimeOfDay _time = TimeOfDay(hour: widget.existing?.hour ?? 19, minute: widget.existing?.minute ?? 0);
  late DateTime _start = widget.existing?.startDate ?? dateOnly(DateTime.now());

  static const _quick = [1, 2, 3, 4, 7];

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  int? get _days {
    final v = int.tryParse(_interval.text.trim());
    return v == null || v < 1 || v > 90 ? null : v;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final days = _days;
    if (title.isEmpty) {
      showSnack(context, 'Ponle un nombre: "Ejercicios de cuello"');
      return;
    }
    if (days == null) {
      showSnack(context, 'Cada cuántos días: un número de 1 a 90');
      return;
    }
    final ok = await guarded(
      context,
      () => ref.read(customReminderRepositoryProvider).save(
            id: widget.existing?.id,
            title: title,
            note: _note.text,
            intervalDays: days,
            hour: _time.hour,
            minute: _time.minute,
            startDate: _start,
            enabled: widget.existing?.enabled ?? true,
          ),
      ok: widget.existing == null ? 'Recordatorio creado' : 'Recordatorio guardado',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirmDelete(context, 'el recordatorio "${widget.existing!.title}"')) return;
    if (!mounted) return;
    final ok = await guarded(context, () => ref.read(customReminderRepositoryProvider).delete(widget.existing!.id));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final days = _days;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Nuevo recordatorio' : 'Editar recordatorio'),
        actions: [
          if (widget.existing != null)
            IconButton(tooltip: 'Borrar', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        children: [
          AppCard(
            children: [
              TextField(
                controller: _title,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Qué',
                  hintText: 'Ejercicios de cuello',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Retracción de mentón 2×10, inclinación lateral 30 s por lado',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          AppCard(
            title: 'Cada cuántos días',
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in _quick)
                    ChoiceChip(
                      label: Text(n == 1 ? 'Diario' : (n == 7 ? 'Semanal' : 'Cada $n')),
                      selected: days == n,
                      onSelected: (_) => setState(() => _interval.text = '$n'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              NumberField(
                controller: _interval,
                label: 'Días',
                suffix: 'días',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                days == null
                    ? 'Escribe un número de 1 a 90.'
                    : 'Te avisa $days ${days == 1 ? 'día' : 'días'} después de la última vez que lo marques como '
                        'hecho en Hoy. Si ese día no lo marcas, vuelve a avisar al día siguiente.',
                style: text.bodySmall,
              ),
            ],
          ),
          AppCard(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Hora del aviso'),
                subtitle: Text(timeKey(_time.hour, _time.minute)),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: _time);
                  if (picked != null) setState(() => _time = picked);
                },
              ),
              DateTile(
                label: widget.existing?.lastDone == null ? 'Primera vez' : 'Contando desde (si nunca lo marcaste)',
                date: _start,
                onChanged: (v) => setState(() => _start = v),
              ),
              if (widget.existing?.lastDone case final done?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Última vez hecho: ${weekdayShort(done.weekday)} ${formatShort(done)}',
                      style: text.bodySmall),
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

/// En Hoy: lo propio que toca hoy o quedó pendiente, con "Hecho".
class TodayCustomRemindersCard extends ConsumerWidget {
  const TodayCustomRemindersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final list = ref.watch(customRemindersProvider).valueOrNull ?? const <CustomReminder>[];
    final due = [for (final r in list) if (r.dueOn(today)) r];
    if (due.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return AppCard(
      title: 'Pendiente hoy',
      children: [
        for (final r in due)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.event_repeat, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title, style: text.titleSmall),
                      Text(
                        [
                          if (r.note != null) r.note!,
                          _nextLabel(r, today) == 'toca hoy' ? _capitalize(r.frequencyLabel) : _capitalize(_nextLabel(r, today)),
                        ].join(' · '),
                        style: text.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    final repo = ref.read(customReminderRepositoryProvider);
                    final previous = r.lastDone;
                    final ok = await guarded(context, () => repo.markDone(r.id, today));
                    if (!ok || !context.mounted) return;
                    final next = addDays(today, r.intervalDays);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Hecho. Próximo: ${weekdayShort(next.weekday)} ${formatShort(next)}'),
                      action: SnackBarAction(label: 'Deshacer', onPressed: () => repo.setLastDone(r.id, previous)),
                    ));
                  },
                  child: const Text('Hecho'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
