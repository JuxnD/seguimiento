import 'enums.dart';
import 'recovery.dart' show legExercises;
import 'session_script.dart';

// Calentamiento guiado (§16.23, handoff del 9 oct): 5–8 min al inicio de
// toda sesión. Movilidad general, activación según el día y una ronda de
// aproximación al ~40 % de la dosis del día, con 2 min de descanso antes de
// la primera serie que cuenta. Cada paso lo marca la persona: el tiempo que
// pasa no lo da por hecho. Ver ADR 0015.

enum WarmupFocus {
  tiron('tirón'),
  empuje('empuje'),
  piernas('piernas');

  const WarmupFocus(this.label);
  final String label;
}

enum WarmupStage {
  movilidad('Movilidad general'),
  activacion('Activación'),
  aproximacion('Ronda de aproximación');

  const WarmupStage(this.label);
  final String label;
}

class WarmupItem {
  const WarmupItem(this.stage, this.exercise, {this.seconds, this.sets = 1, this.reps, this.note});

  final WarmupStage stage;
  final String exercise;

  /// Por tiempo (30 s); null si va por repeticiones.
  final int? seconds;
  final int sets;
  final int? reps;
  final String? note;

  /// Identidad estable para guardar qué se marcó y retomar.
  String get key => '${stage.name}:$exercise';

  String get dose {
    if (seconds != null) return sets > 1 ? '$sets × $seconds s' : '$seconds s';
    if (reps != null) return sets > 1 ? '$sets × $reps' : '$reps';
    return '';
  }
}

const _pull = {'Dominadas', 'Remo invertido (mesa)', 'Colgarse de la barra', 'Elevación de piernas colgado', 'Toes-to-bar'};

const warmupMobility = [
  ('Círculos de hombros', 30),
  ('Rotación torácica en cuatro apoyos', 30),
  ('Balanceos de pierna', 30),
  ('Movilidad de tobillo contra la pared', 30),
];

/// Descanso tras la ronda de aproximación.
const warmupApproachRestSec = 120;

/// Fracción de la dosis del día para la aproximación.
const warmupApproachFraction = 0.4;

/// ≈ 40 % de `reps`, hacia abajo, mínimo 1.
int approachReps(int reps) {
  final r = (reps * warmupApproachFraction).floor();
  return r < 1 ? 1 : r;
}

WarmupFocus warmupFocusFor(ScriptDay day) {
  if (day.type == DayType.piernas) return WarmupFocus.piernas;
  final first = day.main.firstOrNull?.name;
  if (first == null) return WarmupFocus.empuje;
  if (_pull.contains(first)) return WarmupFocus.tiron;
  if (legExercises.contains(first)) return WarmupFocus.piernas;
  return WarmupFocus.empuje;
}

List<WarmupItem> _activation(WarmupFocus f) => switch (f) {
      WarmupFocus.tiron => const [
          WarmupItem(WarmupStage.activacion, 'Colgado pasivo', seconds: 20),
          WarmupItem(WarmupStage.activacion, 'Retracciones escapulares', sets: 2, reps: 8),
        ],
      WarmupFocus.empuje => const [
          WarmupItem(WarmupStage.activacion, 'Flexiones escapulares', sets: 2, reps: 8),
          WarmupItem(WarmupStage.activacion, 'Muñecas (planche)', seconds: 30),
        ],
      WarmupFocus.piernas => const [
          WarmupItem(WarmupStage.activacion, 'Sentadillas', reps: 10, note: 'Al aire y lenta'),
          WarmupItem(WarmupStage.activacion, 'Puente de glúteo', reps: 10),
        ],
    };

/// Aproximación: en circuito, una ronda del circuito; si no, el primer
/// ejercicio del día. Reps al 40 %; los aguantes al 40 % del tiempo.
List<WarmupItem> _approach(ScriptDay day) {
  final main = day.main;
  if (main.isEmpty) return const [];
  final targets = day.type.isCircuit ? main : [main.first];
  return [
    for (final e in targets)
      if (e.holdSecMin != null)
        WarmupItem(WarmupStage.aproximacion, e.name, seconds: approachReps(e.holdSecMin!))
      else if (e.repsMin != null)
        WarmupItem(WarmupStage.aproximacion, e.name, reps: approachReps(e.repsMin!),
            note: e.perSide ? 'Por lado' : null),
  ];
}

/// El bloque del día. `ownWarmup`: el día trae su calentamiento (FIFA 11+ el
/// miércoles): ése reemplaza movilidad y activación; queda la aproximación.
/// Una molestia no agrega ejercicios: se avisa con [soreWarmupNotes].
List<WarmupItem> buildWarmup(ScriptDay day, {bool ownWarmup = false}) {
  final focus = warmupFocusFor(day);
  return [
    if (!ownWarmup) ...[
      for (final (name, sec) in warmupMobility) WarmupItem(WarmupStage.movilidad, name, seconds: sec),
      ..._activation(focus),
    ],
    ..._approach(day),
  ];
}

/// Molestia de hoy o ayer (≥ 3 de 10): se explica, no se receta un
/// movimiento nuevo sin evidencia (revisión de Codex al ADR 0015). Una por
/// zona, con la nota más alta, en el orden del registro de molestias.
List<String> soreWarmupNotes(Map<String, int> zones, {List<String> order = const []}) {
  final keys = [
    for (final z in order) if ((zones[z] ?? 0) >= 3) z,
    for (final z in zones.keys) if (!order.contains(z) && zones[z]! >= 3) z,
  ];
  return [
    for (final z in keys)
      'Molestia en ${z.toLowerCase()} (${zones[z]}/10): calienta suave esa zona, baja el rango o salta lo que duela.',
  ];
}

/// Calentamiento antes de un test (§19.11): sin aproximación, porque cada
/// prueba es una serie máxima. Torso: movilidad y activación de tirón y de
/// empuje. Piernas: el FIFA 11+ del día ya es el calentamiento.
List<WarmupItem> testWarmup({required bool torso}) => torso
    ? [
        for (final (name, sec) in warmupMobility) WarmupItem(WarmupStage.movilidad, name, seconds: sec),
        ..._activation(WarmupFocus.tiron),
        ..._activation(WarmupFocus.empuje),
      ]
    : const [WarmupItem(WarmupStage.activacion, 'Calentamiento tipo FIFA 11+', seconds: 600)];

/// Antes de un intento o un test (§16.23, §19.11): se revisa a la vista.
const preAttemptChecklist = [
  'Pulso en reposo anotado esta mañana',
  'Escaleras: molestia de 0 a 10 anotada',
  'Agua a mano',
  'Reloj en modo entrenamiento',
];

/// "Calentamiento: 7 de 9 pasos (5:40)" o "Calentamiento saltado", para la
/// nota de la sesión.
String warmupRecord({required int done, required int total, required int seconds, required bool skipped}) {
  if (skipped) return 'Calentamiento saltado';
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return 'Calentamiento: $done de $total pasos ($m:$s)';
}
