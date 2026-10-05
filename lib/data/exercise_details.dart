/// Guía de ejercicios v3.1 (5 oct): para cada ejercicio, qué trabaja, cómo
/// se hace paso a paso, los errores que más se ven y cómo hacerlo más fácil o
/// más difícil. Contenido fijo: vive en código, no en la base, y la hoja de
/// técnica lo muestra junto a las claves del catálogo (que el usuario puede
/// editar).
library;

import '../domain/search.dart';

class ExerciseDetail {
  const ExerciseDetail({
    required this.muscles,
    required this.steps,
    this.mistakes = const [],
    this.easier,
    this.harder,
    this.note,
    this.unit,
  });

  /// Qué trabaja ("Dorsal, bíceps, espalda alta").
  final String muscles;
  final List<String> steps;
  final List<String> mistakes;
  final String? easier;
  final String? harder;

  /// Aviso aparte ("Normal sentir agujetas fuertes las primeras 2 semanas").
  final String? note;

  /// Qué cuenta una repetición cuando no es una repetición: 'm' (metros),
  /// 'saltos', 'sprints'. null = repeticiones.
  final String? unit;
}

/// El detalle de un ejercicio por nombre (sin mayúsculas ni tildes), o null.
ExerciseDetail? exerciseDetail(String name) => _byKey[nameKey(name)];

/// Unidad de las repeticiones del ejercicio ('reps' si no tiene otra).
String repsUnit(String name) => exerciseDetail(name)?.unit ?? 'reps';

final _byKey = {for (final e in exerciseDetails.entries) nameKey(e.key): e.value};

const exerciseDetails = <String, ExerciseDetail>{
  'Pino pecho a la pared': ExerciseDetail(
    muscles: 'Hombros, tríceps, core, equilibrio',
    steps: [
      'Ponte en plancha alta con los pies contra la base de la pared, de espaldas a ella.',
      'Sube los pies por la pared mientras caminas con las manos hacia atrás, hasta que las piernas queden '
          'horizontales (forma de L).',
      'Sigue caminando con las manos hasta que el pecho mire a la pared y las manos queden a 10–20 cm de ella.',
      'Brazos bloqueados, empuja el suelo, aprieta abdomen y glúteo: cuerpo en línea recta.',
      'Para bajar, camina con las manos hacia afuera y baja los pies por la pared.',
    ],
    mistakes: ['Arquear la espalda en forma de banana.', 'Doblar los codos.', 'Dejarse caer de cabeza en vez de bajar caminando.'],
    easier: 'Quédate en la L con los pies en la pared (20–30 s).',
    harder: 'Acércate más a la pared o separa un pie unos segundos.',
  ),
  'Dominadas': ExerciseDetail(
    muscles: 'Dorsal, bíceps, espalda alta',
    steps: [
      'Con mochila: correas ajustadas y el peso envuelto en una toalla para que no se mueva.',
      'Cuélgate con los brazos estirados y los hombros activos (prono: un poco más ancho que los hombros).',
      'Sube llevando los codos hacia las costillas hasta pasar la barbilla sobre la barra.',
      'Baja en 2 segundos hasta estirar los brazos por completo.',
    ],
    mistakes: ['Medias repeticiones arriba o abajo.', 'Balancear las piernas para ayudarte.', 'Encoger los hombros hacia las orejas.'],
    easier: 'Sin mochila, o con 2,5 kg.',
    harder: 'Sube 2–5 kg cuando completes todas las series al tope con RIR 1–2.',
  ),
  'Remo invertido (mesa)': ExerciseDetail(
    muscles: 'Espalda media, dorsal, deltoide posterior, bíceps',
    steps: [
      'Comprueba antes que la mesa no se mueva ni se vuelque con tu peso.',
      'Acuéstate debajo, agarra el borde con las manos al ancho de los hombros y apoya los talones en una silla.',
      'Cuerpo recto de talones a cabeza, glúteo apretado.',
      'Lleva el pecho al borde juntando las escápulas; pausa 1 s arriba.',
      'Baja controlado hasta estirar los brazos.',
    ],
    mistakes: ['Dejar caer la cadera.', 'Tirar con el cuello hacia la mesa.', 'Usar una mesa que se mueve.'],
    easier: 'Pies en el suelo con las rodillas dobladas.',
    harder: 'Pausa de 2 s arriba o mochila sobre el pecho.',
  ),
  'Elevaciones laterales con banda': ExerciseDetail(
    muscles: 'Deltoide lateral (anchura de hombros)',
    steps: [
      'Pisa la banda con los dos pies; agarra un extremo en cada mano.',
      'Codos un poco flexionados y fijos en ese ángulo.',
      'Sube los brazos hacia los lados hasta la altura de los hombros, guiando con los codos.',
      'Baja en 2 segundos sin soltar la tensión.',
    ],
    mistakes: ['Subir las manos más alto que los codos.', 'Encoger los trapecios.', 'Balancear el torso.'],
    easier: 'Pisa la banda con un solo pie para tener menos tensión.',
    harder: 'Pisa la banda más abierta o agárrala más corta.',
  ),
  'Face pull con banda': ExerciseDetail(
    muscles: 'Deltoide posterior, manguito rotador, espalda alta',
    steps: [
      'Ancla la banda en la barra a la altura de la cara (nudo de alondra).',
      'Agarra la banda con las palmas hacia abajo y da un paso atrás para tensarla.',
      'Tira hacia la frente separando las manos; los codos quedan altos, a la altura de los hombros.',
      'Al final, los pulgares apuntan hacia atrás; vuelve lento.',
    ],
    mistakes: ['Bajar los codos y convertirlo en un remo.', 'Echarse atrás con todo el cuerpo.'],
    easier: 'Acércate al anclaje.',
    harder: 'Aléjate o pausa 2 s con los codos atrás.',
  ),
  'Elevación de piernas colgado': ExerciseDetail(
    muscles: 'Abdomen (recto), flexores de cadera, agarre',
    steps: [
      'Cuélgate con los hombros activos y el cuerpo quieto.',
      'Sube las piernas rectas metiendo la pelvis.',
      'Baja controlado, sin balanceo, hasta quedar colgado de nuevo.',
    ],
    mistakes: ['Usar el balanceo para subir.', 'Soltar el abdomen al bajar.'],
    easier: 'Rodillas al pecho, luego piernas rectas a 90°.',
    harder: 'Toes-to-bar: toca la barra con los empeines.',
  ),
  'Toes-to-bar': ExerciseDetail(
    muscles: 'Abdomen (recto), flexores de cadera, agarre',
    steps: [
      'Cuélgate con los hombros activos y el cuerpo quieto.',
      'Sube las piernas rectas metiendo la pelvis, hasta tocar la barra con los empeines.',
      'Baja controlado, sin balanceo, hasta quedar colgado de nuevo.',
    ],
    mistakes: ['Usar el balanceo para subir.', 'Doblar mucho las rodillas.', 'Soltar el abdomen al bajar.'],
    easier: 'Elevación de piernas a 90°.',
    harder: 'Toca la barra en cada repetición con 1 s de pausa arriba.',
  ),
  'Rollout con toalla': ExerciseDetail(
    muscles: 'Abdomen (recto) en estiramiento, serrato, dorsal',
    steps: [
      'De rodillas sobre algo blando, manos sobre una toalla doblada en baldosa lisa.',
      'Aprieta el abdomen y mete la pelvis (la zona lumbar no se hunde).',
      'Desliza las manos hacia adelante, bajando el cuerpo en bloque.',
      'Llega solo hasta donde mantengas la espalda neutra y vuelve tirando con el abdomen.',
    ],
    mistakes: ['Hundir la zona lumbar.', 'Volver empujando con la cadera primero.'],
    easier: 'Recorrido corto, o frente a una pared que te frene.',
    harder: 'Recorrido completo o desde los pies en vez de las rodillas.',
  ),
  'Fondos en barra': ExerciseDetail(
    muscles: 'Pecho bajo, tríceps, hombro anterior',
    steps: [
      'Apóyate en las barras con los brazos estirados y los hombros abajo, lejos de las orejas.',
      'Inclina un poco el torso hacia adelante y dobla las rodillas hacia atrás.',
      'Baja hasta que el hombro quede a la altura del codo.',
      'Sube empujando hasta bloquear los codos, sin rebotar abajo.',
    ],
    mistakes: ['Bajar demasiado con dolor en el hombro.', 'Hombros encogidos.', 'Abrir mucho los codos.'],
    easier: 'Sin mochila, o solo la bajada lenta (negativos de 3–4 s).',
    harder: 'Más peso en la mochila o pausa de 1 s abajo.',
  ),
  'Flexión arquero': ExerciseDetail(
    muscles: 'Pecho, tríceps, hombro; prepara la flexión a una mano',
    steps: [
      'Manos mucho más abiertas que en la flexión normal, dedos un poco hacia afuera.',
      'Baja el pecho hacia una mano doblando ese codo; el otro brazo queda casi recto.',
      'Cadera y hombros paralelos al suelo, sin girar.',
      'Empuja de vuelta al centro y alterna lados.',
    ],
    mistakes: ['Girar la cadera.', 'Doblar el brazo que debería ir recto.'],
    easier: 'Manos elevadas en una mesa o banco.',
    harder: 'Pasa a la flexión a una mano con la mano elevada.',
  ),
  'Flexión a una mano': ExerciseDetail(
    muscles: 'Pecho, tríceps, core antirotación',
    steps: [
      'Pies bien abiertos, más que el ancho de los hombros.',
      'Mano de trabajo bajo el pecho; la otra en la espalda.',
      'Baja con el codo pegado al cuerpo, cadera y hombros paralelos al suelo.',
      'Sube sin girar el torso.',
    ],
    mistakes: ['Girar la cadera hacia arriba.', 'Abrir el codo hacia afuera.', 'Juntar los pies demasiado pronto.'],
    easier: 'Mano elevada en una mesa (escalera: mesa → silla → escalón → suelo).',
    harder: 'Pies más juntos o bajada de 3 s.',
  ),
  'Flexiones con pies elevados': ExerciseDetail(
    muscles: 'Pecho alto, hombro anterior, tríceps',
    steps: [
      'Pies en una silla o la cama; manos al ancho de los hombros.',
      'Cuerpo recto, glúteo y abdomen apretados.',
      'Baja hasta casi tocar el suelo con el pecho.',
      'Sube hasta estirar los brazos. Cuanto más alta la silla, más difícil.',
    ],
    mistakes: ['Hundir la cadera.', 'Mover solo la cabeza en vez del pecho.'],
    easier: 'Pies en un escalón bajo.',
    harder: 'Pies más altos o pausa abajo.',
  ),
  'Extensión de tríceps sobre la cabeza con banda': ExerciseDetail(
    muscles: 'Tríceps (cabeza larga)',
    steps: [
      'Pisa la banda con el pie de atrás, en posición de paso.',
      'Lleva las manos detrás de la cabeza con los codos apuntando al techo.',
      'Extiende los brazos por completo sin mover los codos.',
      'Baja lento detrás de la cabeza.',
    ],
    mistakes: ['Abrir los codos hacia los lados.', 'Arquear la espalda baja.'],
    easier: 'Agarra la banda más larga.',
    harder: 'Agarra la banda más corta o dóblala.',
  ),
  'Curl con banda': ExerciseDetail(
    muscles: 'Bíceps, braquial',
    steps: [
      'Pisa la banda con los dos pies al ancho de la cadera.',
      'Codos pegados a los lados, palmas hacia adelante.',
      'Sube las manos hacia los hombros sin mover los codos.',
      'Baja en 2 segundos.',
    ],
    mistakes: ['Balancear el cuerpo.', 'Adelantar los codos al subir.'],
    easier: 'Pies más juntos.',
    harder: 'Pies más separados o pausa arriba.',
  ),
  'Colgarse de la barra': ExerciseDetail(
    muscles: 'Agarre, hombros, descompresión de espalda',
    steps: [
      'Agarre completo con el pulgar alrededor de la barra.',
      'Brazos rectos y hombros ligeramente activos, sin hundirte en las orejas.',
      'Respira normal y acumula el tiempo en varias series (2–3 min en total).',
    ],
    mistakes: ['Encoger los hombros hacia las orejas.', 'Soltar con un salto brusco.'],
    easier: 'Con los pies apoyados en una silla.',
    harder: 'Colgado a una mano por momentos, alternando.',
  ),
  'Calentamiento tipo FIFA 11+': ExerciseDetail(
    muscles: 'Todo el cuerpo; reduce lesiones',
    steps: [
      'Trote suave 2 min con apertura y cierre de cadera (rodilla arriba y hacia afuera / hacia adentro).',
      'Desplazamientos laterales y trote con giros, 1 min.',
      'Plancha frontal 30 s y plancha lateral 20 s por lado.',
      '3 nórdicos suaves y 5 sentadillas a una pierna por lado, controladas.',
      'Saltos verticales y laterales cortos, 30 s.',
      'Aceleraciones progresivas de 10–20 m y cambios de dirección, 4–6.',
    ],
    mistakes: ['Saltártelo los días de partido.', 'Hacerlo con prisa y sin control de rodilla.'],
    easier: 'Menos repeticiones, mismo orden.',
    harder: 'Añade los sprints al final del bloque de saltos.',
  ),
  'Salto vertical': ExerciseDetail(
    muscles: 'Potencia de piernas',
    unit: 'saltos',
    steps: [
      'Pies al ancho de la cadera; baja a media sentadilla llevando los brazos atrás.',
      'Salta lo más alto posible extendiendo cadera, rodillas y tobillos y subiendo los brazos.',
      'Aterriza suave en la parte delantera del pie, rodillas alineadas con las puntas.',
      'Reinicia antes del siguiente salto: calidad, no cansancio.',
    ],
    mistakes: ['Rodillas que se van hacia dentro al aterrizar.', 'Encadenar saltos cansado.'],
    easier: 'Saltos más bajos, centrados en aterrizar bien.',
    harder: 'Saltos seguidos con contacto corto (pliometría reactiva).',
  ),
  'Salto largo': ExerciseDetail(
    muscles: 'Potencia horizontal (aceleración)',
    unit: 'saltos',
    steps: [
      'De pie, baja con los brazos atrás.',
      'Lanza los brazos adelante y salta lo más lejos posible.',
      'Aterriza con los dos pies a la vez, absorbiendo con cadera y rodillas.',
      'Aguanta el aterrizaje 1 s antes de volver.',
    ],
    mistakes: ['Aterrizar con las piernas rectas.', 'Caer hacia atrás.'],
    easier: 'Salto corto con aterrizaje perfecto.',
    harder: 'Mide la distancia y trata de superarla cada semana.',
  ),
  'Salto de patinador': ExerciseDetail(
    muscles: 'Potencia lateral, glúteo medio, estabilidad de rodilla',
    unit: 'saltos',
    steps: [
      'Apoyado en una pierna, salta de lado hacia la otra.',
      'Aterriza en una sola pierna, con la rodilla sobre el pie (sin que se vaya hacia dentro).',
      'La pierna libre cruza por detrás; pausa 1 s y salta al otro lado.',
    ],
    mistakes: ['Rodilla hacia dentro.', 'Aterrizar con el tronco muy inclinado.'],
    easier: 'Salto corto apoyando un instante la pierna libre.',
    harder: 'Más distancia, sin pausa entre saltos.',
  ),
  'Aceleración 10–20 m': ExerciseDetail(
    muscles: 'Velocidad, isquios, glúteo',
    unit: 'sprint',
    steps: [
      'Salida con un pie adelante y el cuerpo inclinado hacia adelante.',
      'Primeros pasos cortos y potentes, empujando el suelo hacia atrás.',
      'Rodilla arriba y brazos fuertes de la cadera a la mejilla.',
      'Desacelera poco a poco; camina de vuelta y descansa completo.',
    ],
    mistakes: ['Hacerlas cansado o sin calentar.', 'Pasos largos desde el inicio.'],
    note: 'Solo si tienes un espacio seguro. Si no, haz las aceleraciones en el calentamiento del partido.',
    easier: 'Al 80 %, o en una cuesta suave.',
    harder: 'Al 100 % con salida desde el suelo.',
  ),
  'Sentadilla búlgara': ExerciseDetail(
    muscles: 'Cuádriceps, glúteo',
    steps: [
      'Mochila en la espalda; empeine del pie de atrás sobre una silla o cama.',
      'Pie de adelante lo bastante lejos para que la rodilla no pase mucho la punta.',
      'Baja recto hasta que el muslo de adelante quede casi horizontal.',
      'Sube empujando con el talón de adelante.',
    ],
    mistakes: ['Rodilla de adelante hacia dentro.', 'Empujar con la pierna de atrás.'],
    easier: 'Sin mochila, o sujetándote de una pared.',
    harder: 'Más peso en la mochila o bajada de 3 s.',
  ),
  'Peso muerto a una pierna con mochila': ExerciseDetail(
    muscles: 'Isquios, glúteo, equilibrio',
    steps: [
      'Mochila en la mano contraria a la pierna de apoyo.',
      'Rodilla de apoyo un poco flexionada y fija.',
      'Lleva la cadera atrás; la pierna libre sube en línea con el torso.',
      'Baja con la espalda recta hasta sentir el estiramiento del isquio; vuelve apretando el glúteo.',
    ],
    mistakes: ['Redondear la espalda.', 'Abrir la cadera hacia un lado.'],
    easier: 'Apoya la punta del pie libre o tócate a una pared con una mano.',
    harder: 'Más peso o pausa de 2 s abajo.',
  ),
  'Nórdico (isquios)': ExerciseDetail(
    muscles: 'Isquios (prevención de lesiones)',
    steps: [
      'De rodillas sobre un cojín, talones trabados bajo el sofá o con alguien sujetándolos.',
      'Cuerpo recto de rodillas a cabeza, glúteo apretado.',
      'Déjate caer hacia adelante lo más lento posible (3–5 s).',
      'Frena con las manos al final y empújate para volver arriba.',
    ],
    mistakes: ['Doblar la cadera (sentarte atrás) para hacerlo más fácil.', 'Caer sin control al final.'],
    note: 'Normal sentir agujetas fuertes las primeras 2 semanas. Empieza con 2 series.',
    easier: 'Recorrido corto: baja solo hasta donde controles.',
    harder: 'Bajada completa con un empujón mínimo de las manos.',
  ),
  'Gemelos a una pierna en escalón': ExerciseDetail(
    muscles: 'Gemelos y sóleo',
    steps: [
      'Parte delantera del pie en el borde de un escalón; una mano en la pared.',
      'Baja el talón todo lo posible.',
      'Sube hasta la punta y aguanta 1 s arriba.',
    ],
    mistakes: ['Rebotar abajo.', 'Hacer medio recorrido.'],
    easier: 'Los dos pies a la vez.',
    harder: 'Mochila en la mano libre o bajada de 3 s.',
  ),
  'Carga de maleta con mochila': ExerciseDetail(
    muscles: 'Oblicuos, agarre, estabilidad',
    unit: 'm',
    steps: [
      'Mochila pesada en una mano, brazo estirado.',
      'Camina erguido sin inclinarte hacia el lado del peso.',
      'Abdomen apretado; cambia de mano a mitad de recorrido.',
    ],
    mistakes: ['Inclinarse hacia el peso.', 'Encoger el hombro del lado de la mochila.'],
    easier: 'Menos peso o menos distancia.',
    harder: 'Más peso o caminar más lento.',
  ),
  'Carga abrazada al pecho': ExerciseDetail(
    muscles: 'Core, espalda alta, brazos',
    unit: 'm',
    steps: [
      'Abraza la mochila contra el pecho.',
      'Camina con pasos cortos, espalda recta.',
      'No te eches hacia atrás para compensar el peso.',
    ],
    mistakes: ['Arquear la espalda baja.'],
    easier: 'Menos peso.',
    harder: 'Más peso o más distancia.',
  ),
  'Pallof press con banda': ExerciseDetail(
    muscles: 'Core antirotación, oblicuos',
    steps: [
      'Ancla la banda a la altura del pecho (en la puerta o una columna) y ponte de lado.',
      'Agarra la banda con las dos manos en el pecho, pies al ancho de los hombros.',
      'Extiende los brazos al frente sin dejar que el torso gire hacia el anclaje.',
      'Aguanta 2 s y vuelve al pecho.',
    ],
    mistakes: ['Girar el torso.', 'Encoger los hombros.'],
    easier: 'Más cerca del anclaje.',
    harder: 'Más lejos o con los pies juntos.',
  ),
  'Elevaciones en pike sentado': ExerciseDetail(
    muscles: 'Flexores de cadera, abdomen bajo; base del L-sit',
    steps: [
      'Sentado con las piernas juntas y estiradas.',
      'Manos en el suelo al lado de las rodillas.',
      'Levanta las dos piernas unos centímetros sin inclinarte atrás.',
      'Baja controlado sin descansar los talones del todo.',
    ],
    mistakes: ['Echar el torso atrás para levantar las piernas.', 'Doblar las rodillas.'],
    note: 'Al principio las piernas casi no despegan. Es normal.',
    easier: 'Una pierna a la vez.',
    harder: 'Pausa de 2 s arriba en cada repetición.',
  ),
  'Elevaciones en straddle': ExerciseDetail(
    muscles: 'Flexores de cadera, aductores, abdomen',
    steps: [
      'Sentado con las piernas abiertas en V, rodillas estiradas.',
      'Manos en el suelo entre las piernas, delante de la cadera.',
      'Levanta las dos piernas a la vez.',
      'Baja controlado.',
    ],
    mistakes: ['Doblar las rodillas.', 'Inclinarse atrás.'],
    easier: 'Una pierna a la vez.',
    harder: 'Manos más adelante o pausa arriba.',
  ),
  'Barca / V-sit': ExerciseDetail(
    muscles: 'Abdomen, flexores de cadera',
    steps: [
      'Siéntate y equilibra el peso sobre los glúteos.',
      'Levanta las piernas y echa el torso un poco atrás, espalda recta.',
      'Brazos estirados al frente; aguanta respirando.',
    ],
    mistakes: ['Redondear mucho la espalda.', 'Contener la respiración.'],
    easier: 'Rodillas recogidas.',
    harder: 'Piernas estiradas y brazos arriba.',
  ),
  'L-sit': ExerciseDetail(
    muscles: 'Abdomen, flexores de cadera, tríceps, hombros',
    steps: [
      'Manos en el suelo junto a la cadera (o en las barras de fondos).',
      'Empuja el suelo con los brazos bloqueados y los hombros abajo.',
      'Despega la cadera y lleva las piernas al frente.',
      'Empieza con rodillas recogidas; estíralas cuando aguantes 20 s.',
    ],
    mistakes: ['Hombros encogidos.', 'Doblar los codos.'],
    easier: 'Tuck (rodillas recogidas) o una pierna estirada.',
    harder: 'L-sit completo con las piernas rectas.',
  ),
  'Plancha inversa con patada': ExerciseDetail(
    muscles: 'Glúteo, isquios, hombros (compensa el empuje)',
    steps: [
      'Sentado, manos detrás de la cadera con los dedos hacia los pies.',
      'Sube la cadera hasta que el cuerpo quede recto de hombros a talones.',
      'Patea una pierna arriba sin dejar caer la cadera; alterna.',
    ],
    mistakes: ['Dejar caer la cadera.', 'Doblar los codos.'],
    easier: 'Solo la plancha inversa (20–30 s), sin patada.',
    harder: 'Patada más alta y con pausa arriba.',
  ),
  'Progresión de pistol': ExerciseDetail(
    muscles: 'Cuádriceps, glúteo, equilibrio, movilidad de tobillo',
    steps: [
      'De pie frente a una cama o banco, sobre una pierna; la otra estirada al frente.',
      'Baja controlado hasta sentarte con el talón de apoyo pegado al suelo.',
      'Sube sin impulso, con los brazos al frente para equilibrar.',
    ],
    mistakes: ['Dejarse caer al banco.', 'Rodilla hacia dentro.'],
    easier: 'Banco más alto.',
    harder: 'Banco más bajo hasta llegar al pistol completo.',
  ),
  'Escaladores': ExerciseDetail(
    muscles: 'Core, hombros, cardio',
    steps: [
      'Plancha alta con los hombros sobre las manos.',
      'Lleva una rodilla al pecho y cambia de pierna rápido.',
      'Cadera baja y estable.',
    ],
    mistakes: ['Subir la cadera.', 'Hombros por detrás de las manos.'],
    easier: 'Más lento, apoyando el pie.',
    harder: 'Más rápido manteniendo la cadera baja.',
  ),
  'Hollow rocks': ExerciseDetail(
    muscles: 'Abdomen',
    steps: [
      'Posición hollow: zona lumbar pegada al suelo, brazos y piernas estirados.',
      'Mécete adelante y atrás como una barca sin perder la forma.',
    ],
    mistakes: ['Despegar la zona lumbar.', 'Doblar las piernas.'],
    easier: 'Brazos a los lados o rodillas dobladas.',
    harder: 'Brazos estirados por encima de la cabeza.',
  ),
};
