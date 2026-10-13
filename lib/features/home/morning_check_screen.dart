import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../domain/recovery.dart';
import '../../domain/sleep_entry.dart';
import '../../ui/widgets.dart';
import 'sleep_hours_dialog.dart';

/// Registro de la mañana (§16.15, §19.6) en una sola pantalla: peso en
/// ayunas, pulso en reposo al despertar, horas en cama y molestias por zona.
/// Cada dato es opcional: lo que se deja vacío no se toca.
class MorningCheckScreen extends ConsumerStatefulWidget {
  const MorningCheckScreen({super.key, this.date});

  final DateTime? date;

  @override
  ConsumerState<MorningCheckScreen> createState() => _MorningCheckScreenState();
}

class _MorningCheckScreenState extends ConsumerState<MorningCheckScreen> {
  late DateTime _date = dateOnly(widget.date ?? DateTime.now());
  final _kg = TextEditingController();
  final _hr = TextEditingController();
  double? _sleep;

  /// Cómo amaneció (plan 009): 1 descansado, 2 normal, 3 cansado; null sin
  /// responder.
  int? _feeling;
  final _sore = <String, int>{};

  /// Dolor muscular general 0–10 y "enfermo, fiebre o dolor agudo" (§19.17).
  /// Al guardar se responden siempre: 0 y no, si no se tocan, igual que las
  /// molestias por zona.
  int _muscle = 0;
  bool _ill = false;
  bool _loading = true;


  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kg.dispose();
    _hr.dispose();
    super.dispose();
  }

  /// Lo ya anotado ese día, para corregir sin reescribir todo.
  Future<void> _load() async {
    setState(() => _loading = true);
    final weights = await ref.read(bodyRepositoryProvider).weightsOn(_date);
    final fasted = weights.where((w) => weighMomentOf(w.moment, fasted: w.fasted) == WeighMoment.ayunas).firstOrNull;
    final hr = await ref.read(recoveryRepositoryProvider).restingHrOn(_date);
    final morning = await ref.read(recoveryRepositoryProvider).morningOn(_date);
    final feeling = morning?.feeling;
    final sleep = (await ref.read(sleepRepositoryProvider).range(_date, _date))[dayKey(_date)];
    final sore = (await ref.read(recoveryRepositoryProvider).sorenessRange(_date, days: 1))[_date] ?? const {};
    if (!mounted) return;
    setState(() {
      _kg.text = fasted == null ? '' : fmtDec(fasted.kg);
      _hr.text = hr?.toString() ?? '';
      _sleep = sleep;
      _feeling = feeling;
      _muscle = morning?.muscleSoreness ?? 0;
      _ill = morning?.ill ?? false;
      _sore
        ..clear()
        ..addAll(sore);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final kg = parseNum(_kg.text);
    final hr = int.tryParse(_hr.text.trim());
    if (hr != null && (hr < 25 || hr > 220)) {
      showSnack(context, 'El pulso en reposo debe estar entre 25 y 220 lpm');
      return;
    }
    final now = TimeOfDay.now();
    final ok = await guarded(context, () async {
      if (kg != null && kg > 0) {
        await ref
            .read(bodyRepositoryProvider)
            .addWeight(_date, kg, moment: WeighMoment.ayunas, time: timeKey(now.hour, now.minute));
      }
      await ref.read(recoveryRepositoryProvider).setRestingHr(_date, hr);
      await ref.read(recoveryRepositoryProvider).setFeeling(_date, _feeling);
      await ref.read(recoveryRepositoryProvider).setReadinessAnswers(_date, muscleSoreness: _muscle, ill: _ill);
      if (_sleep != null) await ref.read(sleepRepositoryProvider).set(_date, _sleep!);
      await ref.read(recoveryRepositoryProvider).setSoreness(_date, _sore);
    }, ok: 'Registro de la mañana guardado');
    if (!ok || !mounted) return;
    ref.invalidate(dashboardProvider);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final today = dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Registro de la mañana')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                AppCard(
                  children: [
                    DateTile(
                      date: _date,
                      onChanged: (v) {
                        final d = dateOnly(v);
                        if (d.isAfter(today) || daysBetween(d, today) > 7) {
                          showSnack(context, 'Hasta 7 días atrás');
                          return;
                        }
                        _date = d;
                        _load();
                      },
                    ),
                    const SizedBox(height: 8),
                    NumberField(controller: _kg, label: 'Peso en ayunas', suffix: 'kg', decimal: true),
                    const SizedBox(height: 8),
                    NumberField(controller: _hr, label: 'Pulso en reposo al despertar', suffix: 'lpm'),
                    Text('Acostado, antes de levantarte: cuenta 60 s o usa el reloj.', style: text.bodySmall),
                  ],
                ),
                AppCard(
                  title: '¿Cómo amaneciste?',
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final (v, label) in const [(1, 'Descansado'), (2, 'Normal'), (3, 'Cansado')])
                          ChoiceChip(
                            label: Text(label),
                            selected: _feeling == v,
                            onSelected: (_) => setState(() => _feeling = _feeling == v ? null : v),
                          ),
                      ],
                    ),
                    Text('"Cansado" pone la recuperación primero en Hoy. Sin respuesta no se toma como descanso.',
                        style: text.bodySmall),
                  ],
                ),
                AppCard(
                  title: 'Horas en cama anoche',
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final h in sleepOptions)
                          ChoiceChip(
                            label: Text(fmtDec(h)),
                            selected: _sleep == h,
                            onSelected: (_) => setState(() => _sleep = _sleep == h ? null : h),
                          ),
                        // Lo que no es un botón (10 h 11 min) se escribe y se ve aquí.
                        ChoiceChip(
                          label: Text(_sleep != null && !isSleepOption(_sleep) ? 'Otro: ${formatSleepHours(_sleep!)}' : 'Otro'),
                          selected: _sleep != null && !isSleepOption(_sleep),
                          onSelected: (_) async {
                            final hours = await askSleepHours(context, initial: isSleepOption(_sleep) ? null : _sleep);
                            if (hours != null && mounted) setState(() => _sleep = hours);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                AppCard(
                  title: 'Dolor muscular general',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _muscle.toDouble(),
                            max: 10,
                            divisions: 10,
                            label: '$_muscle',
                            onChanged: (v) => setState(() => _muscle = v.round()),
                          ),
                        ),
                        SizedBox(width: 24, child: Text('$_muscle', textAlign: TextAlign.end)),
                      ],
                    ),
                    Text('Agujetas o cansancio en los músculos, de 0 a 10. Con 6 o más, Hoy propone recuperación activa.',
                        style: text.bodySmall),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enfermo, con fiebre o con dolor agudo'),
                      subtitle: const Text('Hoy queda en solo descanso.'),
                      value: _ill,
                      onChanged: (v) => setState(() => _ill = v),
                    ),
                  ],
                ),
                AppCard(
                  title: 'Molestias (0 = nada · 10 = no puedo)',
                  children: [
                    Text('En escaleras o al caminar. Si una no baja en 3 días, Hoy avisa.', style: text.bodySmall),
                    for (final zone in sorenessZones)
                      Row(
                        children: [
                          SizedBox(width: 120, child: Text(zone)),
                          Expanded(
                            child: Slider(
                              value: (_sore[zone] ?? 0).toDouble(),
                              max: 10,
                              divisions: 10,
                              label: '${_sore[zone] ?? 0}',
                              onChanged: (v) => setState(() => _sore[zone] = v.round()),
                            ),
                          ),
                          SizedBox(width: 24, child: Text('${_sore[zone] ?? 0}', textAlign: TextAlign.end)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _save,
        icon: const Icon(Icons.save),
        label: const Text('Guardar'),
      ),
    );
  }
}
