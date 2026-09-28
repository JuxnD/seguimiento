/// Rutinas opcionales de movilidad (traspaso §13). Van por fuera del plan:
/// no cuentan para adherencia, récords, racha ni RPE, y no generan alertas si
/// no se hacen. Pensadas para la noche y los fines de semana, 8–10 min.
library;

class MobilityExercise {
  const MobilityExercise({
    required this.name,
    this.durationSec,
    this.reps,
    this.perSide = false,
    this.sets = 1,
    this.formCues = const [],
  }) : assert((durationSec == null) != (reps == null), 'o por tiempo o por repeticiones');

  final String name;

  /// Por tiempo (cuenta regresiva que avanza sola)…
  final int? durationSec;

  /// …o por repeticiones (se marca "Hecho").
  final int? reps;

  /// Se hace de un lado y luego del otro.
  final bool perSide;
  final int sets;
  final List<String> formCues;

  String get targetLabel =>
      [durationSec != null ? '$durationSec s' : '$reps reps', if (perSide) 'por lado'].join(' · ');
}

class MobilityRoutine {
  const MobilityRoutine({required this.id, required this.name, required this.exercises});

  final String id;
  final String name;
  final List<MobilityExercise> exercises;
}

const mobilityNight = MobilityRoutine(
  id: 'mobility_night',
  name: 'Movilidad nocturna',
  exercises: [
    MobilityExercise(
      name: 'Estiramiento de flexor de cadera (caballero)',
      durationSec: 45,
      perSide: true,
      formCues: [
        'Rodilla trasera en el suelo, pie delantero adelante.',
        'Aprieta el glúteo del lado de atrás.',
        'Lleva la cadera al frente sin arquear la espalda baja.',
      ],
    ),
    MobilityExercise(
      name: '90/90 de cadera',
      reps: 8,
      perSide: true,
      formCues: [
        'Sentado, ambas rodillas a 90 grados.',
        'Cambia de lado girando desde la cadera, lento.',
        'Torso erguido; apóyate en las manos si hace falta.',
      ],
    ),
    MobilityExercise(
      name: 'Rotación torácica en cuatro apoyos',
      reps: 8,
      perSide: true,
      formCues: [
        'Mano detrás de la cabeza.',
        'Gira abriendo el codo hacia el techo.',
        'La cadera no se mueve; gira solo la parte alta.',
      ],
    ),
    MobilityExercise(
      name: 'Movilidad de tobillo contra la pared',
      reps: 10,
      perSide: true,
      formCues: [
        'Pie a unos 10 cm de la pared.',
        'Lleva la rodilla a tocar la pared sin levantar el talón.',
        'Si toca fácil, aleja el pie un poco.',
      ],
    ),
    MobilityExercise(
      name: 'Colgado pasivo',
      durationSec: 25,
      sets: 2,
      formCues: [
        'Agarre al ancho de hombros.',
        'Suelta hombros y espalda, respira lento.',
        'Los pies pueden rozar el suelo si hace falta.',
      ],
    ),
  ],
);

/// Un paso del guion: un lado de un ejercicio, en una serie.
class MobilityStep {
  const MobilityStep({required this.exercise, this.side, required this.set});

  final MobilityExercise exercise;

  /// 'izquierdo' o 'derecho' en los ejercicios por lado; null en los demás.
  final String? side;
  final int set;

  bool get timed => exercise.durationSec != null;

  String get detail => [
        if (side != null) 'Lado $side',
        if (exercise.sets > 1) 'Serie $set/${exercise.sets}',
      ].join(' · ');

  /// "45 s" o "8 reps".
  String get target => timed ? '${exercise.durationSec} s' : '${exercise.reps} reps';
}

/// Cada ejercicio, serie por serie y lado por lado, en el orden de la rutina.
List<MobilityStep> buildMobilityScript(MobilityRoutine routine) => [
      for (final e in routine.exercises)
        for (var set = 1; set <= e.sets; set++)
          for (final side in e.perSide ? const ['izquierdo', 'derecho'] : const [null])
            MobilityStep(exercise: e, side: side, set: set),
    ];

/// Segundos de preparación antes de cada paso por tiempo: cambiar de lado o
/// de postura sin que el reloj ya esté corriendo.
const mobilityLeadInSec = 5;

/// Duración aproximada de la rutina, para decir cuánto toma antes de empezar.
/// Las repeticiones de movilidad son lentas: ~3 s cada una.
int estimatedMobilitySec(List<MobilityStep> steps) => steps.fold(
    0, (total, s) => total + (s.timed ? s.exercise.durationSec! + mobilityLeadInSec : s.exercise.reps! * 3 + 5));
