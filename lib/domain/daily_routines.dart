/// Rutinas diarias del Plan v3.2 (§19.14, §19.15) y la recuperación activa
/// (§19.17). Se guardan como movilidad con su id en `mode`: no suman carga
/// ni la cadena de días intensos. Toda actividad guardada mantiene constancia;
/// las rutinas completas llevan además su propia racha de movilidad.
library;

import 'mobility.dart';

const morningActivaId = 'morning_activa';
const nightSueltaId = 'night_suelta';
const recoveryActiveId = 'recovery_active';

/// Ids que cuentan como rutina diaria guardada (chips "Mañana ✓", "Noche ✓").
const dailyRoutineIds = {morningActivaId, nightSueltaId, recoveryActiveId};

/// Precondición: una sesión de movilidad ya guardada, incluso parcial.
/// Su modo (también desconocido) no excluye actividad de la constancia.
/// No sirve para adherencia, recuperación hecha ni racha de rutinas completas.
bool keepsConstancyStreak(String? mode) => true;

/// RPE por encima del cual una recuperación ya no lo fue (§19.17).
const recoveryMaxRpe = 5;

// ---------------------------------------------------------------------------
// Mañana · Activa (§19.14): 10 min, dinámico y suave (3/10).
// ---------------------------------------------------------------------------

const _breathing = MobilityExercise(
  id: 'breathing_90_90',
  name: 'Respiración 90/90',
  purpose: 'Costillas abajo y pelvis neutra: la base del hollow y del pino sin arco.',
  reps: 5,
  formCues: [
    'Boca arriba, pantorrillas sobre la cama: cadera y rodillas a 90°.',
    'Inhala 4 s por la nariz inflando barriga y costados, no el pecho.',
    'Exhala 6 s por la boca: las costillas bajan y la lumbar se apoya.',
  ],
);

const _catCow = MobilityExercise(
  id: 'cat_cow',
  name: 'Gato-camello',
  purpose: 'Mover la columna vértebra a vértebra después de dormir.',
  reps: 8,
  formCues: [
    'A cuatro patas: manos bajo los hombros, rodillas bajo la cadera.',
    'Exhala y redondea empujando el suelo; inhala y lleva el pecho adelante.',
    'Lento, 3 s en cada extremo. Muévete como una ola, de la pelvis a la cabeza.',
  ],
);

const _openBook = MobilityExercise(
  id: 'open_book',
  name: 'Libro abierto',
  purpose: 'Rotación torácica para disparar, girar y llegar a la línea del pino.',
  reps: 6,
  perSide: true,
  formCues: [
    'De lado, rodillas juntas y dobladas a 90°, brazos al frente.',
    'Abre el brazo de arriba al otro lado siguiéndolo con la mirada.',
    'Las rodillas no se separan; pausa 2 s abierto y vuelve despacio.',
  ],
);

const _wristRocks = MobilityExercise(
  id: 'wrist_rocks',
  name: 'Muñecas a cuatro patas',
  purpose: 'Tendones de la muñeca para planche, pino y fondos.',
  reps: 30,
  formCues: [
    '10 balanceos con las palmas abajo, hombros por delante de las manos.',
    '10 muy suaves con los dorsos de la mano en el suelo.',
    '10 con las palmas abajo y los dedos hacia las rodillas. Nunca hasta el dolor.',
  ],
);

const _wallSlides = MobilityExercise(
  id: 'wall_slides',
  name: 'Deslizamientos en la pared',
  purpose: 'Subir los brazos rectos sin arquear: la línea del pino.',
  reps: 10,
  formCues: [
    'Espalda, cabeza y lumbar pegadas a la pared; brazos en W.',
    'Desliza hasta una Y sin despegar la lumbar ni las manos.',
    'Baja llevando los codos hacia los bolsillos.',
  ],
);

const _hip9090 = MobilityExercise(
  id: 'hip_90_90',
  name: '90/90 de cadera',
  purpose: 'Rotación de cadera: ingle sana y cambios de dirección.',
  reps: 6,
  perSide: true,
  formCues: [
    'Sentado, rodilla de adelante a 90° delante y la de atrás a 90° al lado.',
    'Gira las rodillas al otro lado sin mover los pies de sitio.',
    'Pausa 2 s en cada lado con el pecho alto.',
  ],
);

const _worldsGreatest = MobilityExercise(
  id: 'worlds_greatest',
  name: 'Zancada del mundo',
  purpose: 'Flexor de cadera, isquios y torácica en un gesto: la zancada de sprint.',
  reps: 3,
  perSide: true,
  formCues: [
    'Zancada larga, rodilla de atrás estirada y en el aire.',
    'Codo hacia el empeine por dentro del pie; luego gira y lleva ese brazo al techo.',
    'Estira la pierna de adelante (cadera atrás). 3 s en cada posición.',
  ],
);

const _kneeToWall = MobilityExercise(
  id: 'knee_to_wall',
  name: 'Rodilla a la pared',
  purpose: 'Dorsiflexión de tobillo para pistol, sentadilla profunda y aceleración.',
  reps: 10,
  perSide: true,
  formCues: [
    'Medio arrodillado, pie de adelante a 8–10 cm de la pared.',
    'Lleva la rodilla a tocar la pared sin despegar el talón.',
    'Rodilla en línea con el segundo dedo. Pausa de 1 s.',
  ],
);

const _deepSquat = MobilityExercise(
  id: 'deep_squat_hold',
  name: 'Sentadilla profunda',
  purpose: 'Posición base de cadera y tobillo; descomprime tras estar sentado.',
  durationSec: 60,
  formCues: [
    'Pies algo más abiertos que la cadera, talones en el suelo.',
    'Codos por dentro de las rodillas empujándolas hacia fuera; pecho alto.',
    'Respira y muévete suave de lado a lado.',
  ],
);

const _shortFoot = MobilityExercise(
  id: 'short_foot',
  name: 'Pie corto',
  purpose: 'Arco y propulsión del pie.',
  durationSec: 5,
  sets: 5,
  perSide: true,
  formCues: [
    'Pie descalzo apoyado.',
    'Acerca la base del dedo gordo al talón sin encoger los dedos: el arco sube.',
    'Mantén respirando y suelta. Los dedos quedan largos.',
  ],
);

/// La rutina de la mañana. `short`: la versión de 4 min (respiración,
/// muñecas, zancada del mundo y rodilla a la pared).
MobilityRoutine morningActiva({bool short = false}) => MobilityRoutine(
      id: morningActivaId,
      name: short ? 'Mañana · Activa (4 min)' : 'Mañana · Activa',
      intensity: '3/10, dinámico',
      exercises: short
          ? const [_breathing, _wristRocks, _worldsGreatest, _kneeToWall]
          : const [
              _breathing,
              _catCow,
              _openBook,
              _wristRocks,
              _wallSlides,
              _hip9090,
              _worldsGreatest,
              _kneeToWall,
              _deepSquat,
              _shortFoot,
            ],
    );

// ---------------------------------------------------------------------------
// Noche · Suelta (§19.15): estático 45 s, 5–6/10, nunca dolor.
// ---------------------------------------------------------------------------

MobilityExercise _pike({required bool gentle}) => MobilityExercise(
      id: 'pike_stretch',
      name: 'Pike sentado',
      purpose: 'Isquios en longitud para L-sit, V-up y compresión.',
      durationSec: 45,
      formCues: [
        'Piernas juntas y estiradas; inclínate desde la cadera con la espalda larga.',
        gentle ? 'Noche de partido: tensión 4/10 y sin pulsos.' : 'Tensión 5–6/10. Al final, 10 pulsos levantando las puntas.',
        'No redondees la espalda para llegar más lejos.',
      ],
    );

MobilityExercise _pancake({required bool gentle}) => MobilityExercise(
      id: 'pancake_stretch',
      name: 'Pancake',
      purpose: 'Aductores e isquios internos: compresión en straddle.',
      durationSec: 45,
      formCues: [
        'Piernas abiertas lo que permita la espalda recta, rodillas al techo.',
        gentle
            ? 'Noche de partido: tensión 4/10 y sin good mornings.'
            : 'Antes, 10 good mornings con las manos en la nuca; luego quédate abajo.',
        'Inclínate desde la cadera, nunca redondeando.',
      ],
    );

const _hipFlexor = MobilityExercise(
  id: 'hip_flexor_kneel',
  name: 'Flexor de cadera de rodillas',
  purpose: 'Extensión de cadera para el sprint; compensa estar sentado.',
  durationSec: 45,
  perSide: true,
  formCues: [
    'Rodilla de atrás sobre un cojín, el otro pie adelante.',
    'Aprieta el glúteo de atrás y mete un poco la pelvis.',
    'Cadera adelante sin arquear la espalda.',
  ],
);

const _latBed = MobilityExercise(
  id: 'lat_stretch_bed',
  name: 'Dorsal en la cama',
  purpose: 'Flexión de hombro completa para el pino en línea.',
  durationSec: 45,
  formCues: [
    'De rodillas frente a la cama, codos en el borde y manos juntas.',
    'Cadera atrás; deja caer pecho y cabeza entre los brazos.',
    'Al exhalar baja un poco más. Sin arquear la lumbar.',
  ],
);

const _pecDoorway = MobilityExercise(
  id: 'pec_doorway',
  name: 'Pectoral en el marco de la puerta',
  purpose: 'Compensa fondos y flexiones; hombros atrás.',
  durationSec: 45,
  perSide: true,
  formCues: [
    'Antebrazo en el marco, codo a la altura del hombro.',
    'Paso adelante y gira el pecho un poco al lado contrario.',
    'Hombro abajo y atrás. Si pincha delante del hombro, afloja.',
  ],
);

const _figureFour = MobilityExercise(
  id: 'figure_four',
  name: 'Glúteo en figura 4',
  purpose: 'Cadera y zona lumbar sueltas.',
  durationSec: 45,
  perSide: true,
  formCues: [
    'Boca arriba, cruza un tobillo sobre la rodilla contraria.',
    'Acerca la pierna de apoyo al pecho agarrando el muslo.',
    'La cadera no se levanta del suelo.',
  ],
);

const _soleus = MobilityExercise(
  id: 'soleus_wall',
  name: 'Sóleo en la pared',
  purpose: 'Aquiles y tobillo para sprint y pistol.',
  durationSec: 30,
  perSide: true,
  formCues: [
    'Manos en la pared, pie de atrás a medio paso.',
    'Dobla las dos rodillas con el talón de atrás en el suelo.',
    'Se siente bajo en la pantorrilla, cerca del tobillo.',
  ],
);

const _legsUpWall = MobilityExercise(
  id: 'legs_up_wall',
  name: 'Piernas en la pared',
  purpose: 'Bajar pulsaciones para dormir.',
  durationSec: 120,
  formCues: [
    'Glúteo cerca de la pared, piernas apoyadas en ella.',
    'Brazos relajados a los lados.',
    'Respira 4 s inhalando y 6 s exhalando.',
  ],
);

/// Módulo de piernas (+3 min): días de fútbol y de piernas.
const legsModule = [
  MobilityExercise(
    id: 'knees_to_chest',
    name: 'Rodillas al pecho',
    purpose: 'Zona lumbar y glúteos.',
    durationSec: 45,
    formCues: ['Boca arriba, abraza las rodillas.', 'Balancéate suave; deja que la espalda baja se relaje.'],
  ),
  MobilityExercise(
    id: 'quad_side_lying',
    name: 'Cuádriceps',
    purpose: 'Frente del muslo.',
    durationSec: 45,
    perSide: true,
    formCues: ['Acostado de lado o apoyado en la pared: talón al glúteo.', 'Rodilla apuntando al suelo, sin abrirla.'],
  ),
  MobilityExercise(
    id: 'calf_wall',
    name: 'Gemelo contra la pared',
    purpose: 'Gemelo y tobillo.',
    durationSec: 30,
    perSide: true,
    formCues: ['Pierna de atrás estirada, talón en el suelo.', 'Inclínate hacia la pared; luego dobla un poco la rodilla.'],
  ),
];

/// La rutina de la noche. `withLegs`: añade el módulo de piernas (hoy hubo
/// fútbol o sesión de piernas). `matchNight`: pike y pancake al 4/10, sin
/// pulsos. Piernas en la pared cierra siempre.
MobilityRoutine nightSuelta({bool withLegs = false, bool matchNight = false}) => MobilityRoutine(
      id: nightSueltaId,
      name: withLegs ? 'Noche · Suelta + piernas' : 'Noche · Suelta',
      intensity: matchNight ? '4/10 en pike y pancake, estático' : '5–6/10, estático, nunca dolor',
      exercises: [
        _pike(gentle: matchNight),
        _pancake(gentle: matchNight),
        _hipFlexor,
        _latBed,
        _pecDoorway,
        _figureFour,
        _soleus,
        if (withLegs) ...legsModule,
        _legsUpWall,
      ],
    );

// ---------------------------------------------------------------------------
// Recuperación activa (§19.17): ~30 min, 3–4/10, nunca al fallo.
// ---------------------------------------------------------------------------

/// Bloque B: activación suave, 2 vueltas con 45 s entre vueltas.
const recoveryActivation = [
  MobilityExercise(
    id: 'scap_pushup',
    name: 'Flexiones escapulares',
    purpose: 'Serrato y protracción (planche, flexiones).',
    reps: 10,
    formCues: [
      'Plancha alta, brazos rectos y cuerpo en línea.',
      'Baja el pecho juntando las escápulas sin doblar los codos.',
      'Empuja el suelo separándolas. Pausa 1 s arriba.',
    ],
  ),
  MobilityExercise(
    id: 'scap_pullup',
    name: 'Scap pull-up',
    purpose: 'Depresión escapular (dominadas). Sin barra: 8 deslizamientos en la pared.',
    reps: 8,
    formCues: [
      'Colgado con los brazos rectos y relajados.',
      'Sin doblar los codos, hunde los hombros: el cuerpo sube unos centímetros.',
      'Pausa 1 s y vuelve a colgar pasivo.',
    ],
  ),
  MobilityExercise(
    id: 'prone_y_t',
    name: 'Y-T prono',
    purpose: 'Trapecio inferior y escápula.',
    reps: 8,
    formCues: [
      'Boca abajo, frente en una toalla, pulgares al techo.',
      'Sube los brazos en Y y luego en T llevando las escápulas a los bolsillos.',
      'Pausa 2 s arriba. Sin levantar la cabeza ni arquear la lumbar.',
    ],
  ),
  MobilityExercise(
    id: 'side_lying_hip_abduction',
    name: 'Abducción de cadera de lado',
    purpose: 'Glúteo medio: la rodilla estable al aterrizar y girar.',
    reps: 12,
    perSide: true,
    formCues: [
      'Tumbado de lado, pierna de abajo doblada.',
      'Pierna de arriba recta, punta al frente: súbela 30–40 cm sin girar la cadera.',
      'Pausa 2 s arriba y baja en 2 s.',
    ],
  ),
  MobilityExercise(
    id: 'hollow_body_hold',
    name: 'Hollow body hold',
    purpose: 'Core sin fatiga: rodillas dobladas.',
    durationSec: 15,
    formCues: ['Lumbar pegada al suelo todo el tiempo.', 'Rodillas dobladas hacia ti.', 'Respira; no aguantes el aire.'],
  ),
];

/// Pausa entre las dos vueltas del bloque B.
const recoveryRoundRestSec = 45;

const _roundRest = MobilityExercise(
  id: 'rest',
  name: 'Descanso',
  purpose: 'Entre vueltas de la activación.',
  durationSec: recoveryRoundRestSec,
  formCues: ['Respira tranquilo. La siguiente vuelta igual de suave.'],
);

/// A (Activa) · B (activación, 2 vueltas) · C (Suelta con el módulo de
/// piernas). La caminata opcional va fuera del cronómetro.
MobilityRoutine recoveryActive() => MobilityRoutine(
      id: recoveryActiveId,
      name: 'Recuperación activa',
      intensity: '3–4/10, nunca al fallo',
      closingNote: 'Opcional: caminata de 20–30 min a ritmo de conversación, pulso por debajo de 120.',
      exercises: [
        ...morningActiva().exercises,
        ...recoveryActivation,
        _roundRest,
        ...recoveryActivation,
        ...nightSuelta(withLegs: true).exercises,
      ],
    );

/// La rutina de un id guardado, para repetirla desde el historial.
MobilityRoutine? dailyRoutineById(String? id) => switch (id) {
      morningActivaId => morningActiva(),
      nightSueltaId => nightSuelta(),
      recoveryActiveId => recoveryActive(),
      _ => null,
    };
