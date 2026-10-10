import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/dates.dart';
import '../../domain/format.dart';
import '../../ui/widgets.dart';
import '../settings/restore_access.dart';

/// Alta de un usuario nuevo (plan 022): su propia fecha, sus medidas
/// opcionales, sus pasos y, si quiere, su nutrición. No hay valores del dueño
/// ni ejemplos que se acepten solos. O bien restaura su propio respaldo.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Nutrition { now, later }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _defaultSteps = 5000;

  late DateTime _start = dateOnly(DateTime.now());
  DateTime? _birth;
  _Nutrition? _nutrition;
  bool _busy = false;
  final _height = TextEditingController();
  final _steps = TextEditingController(text: '$_defaultSteps');
  final _proteinMin = TextEditingController();
  final _proteinPreferred = TextEditingController();
  final _kcalWeekly = TextEditingController();
  final _kcalFootball = TextEditingController();
  final _kcalFloor = TextEditingController();

  List<TextEditingController> get _controllers =>
      [_height, _steps, _proteinMin, _proteinPreferred, _kcalWeekly, _kcalFootball, _kcalFloor];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Reiniciar: borra lo escrito sin guardar nada (el alta sigue pendiente).
  void _reset() => setState(() {
        _start = dateOnly(DateTime.now());
        _birth = null;
        _nutrition = null;
        for (final c in _controllers) {
          c.clear();
        }
        _steps.text = '$_defaultSteps';
      });

  /// null si está vacío; lanza FormatException si no es un número.
  int? _int(TextEditingController c, String what) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t) ?? (throw FormatException('$what: escribe un número entero.'));
  }

  SetupDraft _draft() {
    final heightText = _height.text.trim();
    final height = heightText.isEmpty ? null : parseNum(heightText);
    if (heightText.isNotEmpty && height == null) throw const FormatException('Estatura: escribe un número.');
    final steps = _int(_steps, 'Pasos');
    if (steps == null) throw const FormatException('Los pasos diarios son obligatorios.');
    final d = SetupDraft(startDate: _start, heightCm: height, birthDate: _birth, stepsTarget: steps);
    if (_nutrition == _Nutrition.now) {
      d
        ..proteinMin = _int(_proteinMin, 'Proteína mínima')
        ..proteinPreferred = _int(_proteinPreferred, 'Proteína preferida')
        ..kcalWeekly = _int(_kcalWeekly, 'kcal entre semana')
        ..kcalFootball = _int(_kcalFootball, 'kcal en días de fútbol')
        ..kcalFloor = _int(_kcalFloor, 'Piso de kcal');
    }
    return d;
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final SetupDraft draft;
    try {
      if (_nutrition == null) throw const FormatException('Elige si defines tu nutrición ahora o más adelante.');
      draft = _draft();
    } on FormatException catch (e) {
      showSnack(context, e.message);
      return;
    }
    if (draft.problem(DateTime.now()) case final p?) {
      showSnack(context, p);
      return;
    }
    String goal(int? v, String unit) => v == null ? 'sin meta' : '${fmtInt(v)} $unit';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('¿Confirmar tu perfil?'),
        content: Text([
          'Inicio del programa: ${formatLong(draft.startDate)}',
          'Estatura: ${draft.heightCm == null ? 'sin definir' : '${fmtDec(draft.heightCm!)} cm'}',
          'Nacimiento: ${draft.birthDate == null ? 'sin definir' : formatLong(draft.birthDate!)}',
          'Pasos diarios entre semana: ${fmtInt(draft.stepsTarget)}',
          'Proteína mínima: ${goal(draft.proteinMin, 'g')}',
          'Proteína preferida: ${goal(draft.proteinPreferred, 'g')}',
          'kcal entre semana: ${goal(draft.kcalWeekly, 'kcal')}',
          'kcal en días de fútbol: ${draft.kcalFootball == null ? (draft.kcalWeekly == null ? 'sin meta' : 'la misma de entre semana') : '${fmtInt(draft.kcalFootball!)} kcal'}',
          'Piso de kcal: ${goal(draft.kcalFloor, 'kcal')}',
          '',
          'Estas metas rigen desde hoy; las puedes cambiar en Ajustes. La rutina la configuras después.',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Seguir editando')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).confirmSetup(draft);
    } on Object catch (e) {
      if (mounted) showSnack(context, 'No se guardó nada: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await pickAndRestoreBackup(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate({required bool birth}) async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: birth ? (_birth ?? DateTime(today.year - 30)) : _start,
      firstDate: birth ? DateTime(1900) : DateTime(2000),
      lastDate: birth ? addDays(today, -1) : today,
    );
    if (picked == null) return;
    setState(() => birth ? _birth = dateOnly(picked) : _start = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Bienvenida')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AppCard(
            children: [
              Text('Configura tu perfil', style: text.titleLarge),
              const SizedBox(height: 4),
              const Text('Empiezas sin registros, sin rutina y sin metas de otra persona. '
                  'Si ya usabas la app, restaura tu respaldo en lugar de configurar.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar mi respaldo (ZIP)'),
              ),
            ],
          ),
          AppCard(
            title: 'Tú',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Inicio del programa'),
                subtitle: Text('${weekdayLong(_start.weekday)} ${formatLong(_start)} · ancla tus semanas'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () => _pickDate(birth: false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cake_outlined),
                title: const Text('Fecha de nacimiento (opcional)'),
                subtitle: Text(_birth == null ? 'Sin definir' : formatLong(_birth!)),
                trailing: _birth == null
                    ? const Icon(Icons.edit_calendar)
                    : IconButton(
                        tooltip: 'Quitar fecha',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _birth = null),
                      ),
                onTap: () => _pickDate(birth: true),
              ),
              NumberField(controller: _height, label: 'Estatura (opcional)', suffix: 'cm', decimal: true),
              const SizedBox(height: 8),
              NumberField(controller: _steps, label: 'Pasos diarios', suffix: 'pasos'),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Meta entre semana. 5.000 es un punto de partida; cámbialo si quieres.'),
              ),
            ],
          ),
          AppCard(
            title: 'Nutrición',
            children: [
              const Text('Puedes fijar tus metas ahora o dejarlas para después. '
                  'Lo que dejes vacío queda "sin meta": la app no lo inventa.'),
              RadioListTile<_Nutrition>(
                contentPadding: EdgeInsets.zero,
                value: _Nutrition.now,
                groupValue: _nutrition,
                onChanged: (v) => setState(() => _nutrition = v),
                title: const Text('Definir ahora'),
              ),
              RadioListTile<_Nutrition>(
                contentPadding: EdgeInsets.zero,
                value: _Nutrition.later,
                groupValue: _nutrition,
                onChanged: (v) => setState(() => _nutrition = v),
                title: const Text('Más adelante'),
                subtitle: const Text('Sin metas de proteína ni kcal hasta que las fijes en Ajustes.'),
              ),
              if (_nutrition == _Nutrition.now) ...[
                NumberField(controller: _proteinMin, label: 'Proteína mínima', suffix: 'g'),
                const SizedBox(height: 8),
                NumberField(controller: _proteinPreferred, label: 'Proteína preferida', suffix: 'g'),
                const SizedBox(height: 8),
                NumberField(controller: _kcalWeekly, label: 'kcal entre semana', suffix: 'kcal'),
                const SizedBox(height: 8),
                NumberField(controller: _kcalFootball, label: 'kcal fútbol', suffix: 'kcal'),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Días de fútbol. Vacío = la misma de entre semana.'),
                ),
                const SizedBox(height: 8),
                NumberField(controller: _kcalFloor, label: 'Piso de kcal', suffix: 'kcal'),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Opcional: el mínimo bajo el que la app te avisaría.'),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _confirm,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirmar mi perfil'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _busy ? null : _reset, child: const Text('Empezar de nuevo')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
