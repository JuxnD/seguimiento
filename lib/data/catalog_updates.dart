import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'database.dart';
import 'seed_foods.dart';

// Datos de catálogo que llegan después de la primera siembra. La siembra solo
// corre con la base vacía; esto corre una vez en la migración al esquema 8 y
// al sembrar una instalación nueva. Es idempotente: no pisa lo que el usuario
// haya escrito ni duplica lo que ya existe.

/// Claves de técnica, referencia visual y progresión de un ejercicio.
class ExerciseGuide {
  const ExerciseGuide({
    required this.name,
    this.mediaUrl,
    this.formCues = const [],
    this.progressionNote,
    this.tracksLoad = false,
    this.anchor,
  });

  final String name;
  final String? mediaUrl;
  final List<String> formCues;
  final String? progressionNote;
  final bool tracksLoad;

  /// Anclaje de la banda: 'alto', 'medio', 'bajo' o 'manos' (§18.7).
  final String? anchor;
}

const exerciseGuides = <ExerciseGuide>[
  ExerciseGuide(
    name: 'Sentadilla búlgara',
    mediaUrl: 'https://www.youtube.com/results?search_query=bulgarian+split+squat+form',
    formCues: [
      'Pie trasero sobre una silla o banco de unos 40 cm, empeine apoyado.',
      'Pie delantero un paso largo al frente; el peso va en ese pie.',
      'Baja recto hasta que el muslo delantero quede casi paralelo al suelo.',
      'La rodilla delantera sigue la línea de la punta del pie, no se va adentro.',
      'Empuja con el talón delantero. Torso ligeramente inclinado, no doblado.',
    ],
    progressionNote: 'Progresa con carga (mochila con peso), no con más repeticiones.',
    tracksLoad: true,
  ),
  ExerciseGuide(
    name: 'Pike push-up',
    mediaUrl: 'https://www.youtube.com/results?search_query=pike+push+up+tutorial',
    formCues: [
      'Posición de V invertida: caderas altas, piernas y brazos rectos.',
      'Manos al ancho de hombros, dedos al frente.',
      'Baja la coronilla hacia el suelo entre las manos, no hacia adelante.',
      'Codos a unos 45 grados del torso, no abiertos del todo.',
      'Empuja hasta extender los codos sin perder la V.',
    ],
    progressionNote: 'pike → pies elevados → HSPU asistido → HSPU',
  ),
  ExerciseGuide(
    name: 'Elevación de piernas colgado',
    mediaUrl: 'https://www.youtube.com/results?search_query=hanging+leg+raise+technique',
    formCues: [
      'Colgado de la barra, hombros activos (no colgado muerto).',
      'Sube sin balanceo. Si te meces, para y reinicia.',
      'Al final del recorrido lleva la pelvis hacia atrás, no solo las piernas.',
      'Baja controlado, más lento de lo que subes.',
      'Si no llegas con piernas rectas, hazlo con rodillas dobladas.',
    ],
    progressionNote: 'rodillas dobladas → piernas rectas → subir más alto',
  ),
  ExerciseGuide(
    name: 'Hollow body hold',
    mediaUrl: 'https://www.youtube.com/results?search_query=hollow+body+hold+tutorial',
    formCues: [
      'Boca arriba, zona lumbar pegada al suelo todo el tiempo.',
      'Si la espalda baja se despega, recoge las piernas hacia ti.',
      'Brazos junto a las orejas, hombros despegados del suelo.',
      'Respira. No aguantes el aire.',
    ],
    progressionNote: 'rodillas recogidas → piernas extendidas → brazos extendidos',
  ),
  ExerciseGuide(
    name: 'Plancha lateral',
    mediaUrl: 'https://www.youtube.com/results?search_query=side+plank+form',
    formCues: [
      'Codo justo debajo del hombro.',
      'Cadera alta: línea recta de tobillo a cabeza.',
      'No dejes caer la cadera ni gires el torso hacia el suelo.',
      'Cuenta el tiempo por lado, no total.',
    ],
    progressionNote: 'rodillas apoyadas → pies apoyados → con peso',
  ),
  // Plan v3 (§18.8). `anchor`: cómo se ancla la banda (§18.7).
  ExerciseGuide(
    name: 'Separaciones con banda',
    anchor: 'manos',
    formCues: [
      'Brazos rectos al frente, banda a la altura del pecho.',
      'Abre los brazos hasta que la banda toque el pecho.',
      'Junta las escápulas al final; vuelve lento.',
    ],
  ),
  ExerciseGuide(
    name: 'Fondos en barra',
    formCues: [
      'Hombros abajo, lejos de las orejas.',
      'Torso un poco inclinado adelante.',
      'Baja hasta que el hombro quede a la altura del codo.',
      'Sin rebote abajo.',
    ],
    progressionNote: 'peso corporal → pausa de 1 s abajo → lastre',
    tracksLoad: true,
  ),
  ExerciseGuide(
    name: 'Remo invertido (mesa)',
    formCues: [
      'Debajo de una mesa firme, agarra el borde con los brazos extendidos.',
      'Cuerpo recto de talones a cabeza, glúteo apretado.',
      'Lleva el pecho al borde juntando las escápulas.',
      'Si la mesa se mueve, no lo hagas ahí.',
    ],
    progressionNote: 'rodillas dobladas → piernas rectas → pies elevados → pausa de 2 s arriba',
  ),
  ExerciseGuide(
    name: 'Elevaciones laterales con banda',
    anchor: 'bajo',
    formCues: [
      'Pisa la banda, un extremo en cada mano.',
      'Codos apenas flexionados; sube hasta la altura del hombro.',
      'Guía con los codos, no con las manos.',
      'Baja en 2 segundos.',
    ],
  ),
  ExerciseGuide(
    name: 'Peso muerto a una pierna con mochila',
    formCues: [
      'Mochila en la mano contraria a la pierna de apoyo.',
      'Rodilla de apoyo un poco flexionada.',
      'Lleva la cadera atrás; la pierna libre sube en línea con el torso.',
      'Espalda recta; baja hasta sentir el isquio.',
    ],
    progressionNote: 'peso corporal → mochila 5 kg → 8 kg → 10 kg',
    tracksLoad: true,
  ),
  ExerciseGuide(
    name: 'Puente de glúteo a una pierna',
    formCues: [
      'Boca arriba, un pie apoyado cerca del glúteo.',
      'Empuja con el talón y sube la cadera.',
      'Aprieta el glúteo 1 s arriba.',
      'Sin arquear la zona lumbar.',
    ],
  ),
  ExerciseGuide(
    name: 'Gemelos a una pierna en escalón',
    formCues: [
      'Punta del pie en el borde de un escalón.',
      'Baja el talón todo lo posible.',
      'Sube hasta la punta y pausa 1 s.',
    ],
  ),
  ExerciseGuide(
    name: 'Pallof press con banda',
    anchor: 'medio',
    formCues: [
      'De lado al anclaje, banda en el pecho con ambas manos.',
      'Extiende los brazos al frente sin dejar que el torso gire.',
      'Aguanta 2 s y vuelve.',
    ],
  ),
  ExerciseGuide(
    name: 'Flexión arquero',
    formCues: [
      'Manos mucho más abiertas que en la flexión normal.',
      'Baja hacia una mano; el otro brazo queda casi recto.',
      'Cadera cuadrada al suelo, sin girar.',
    ],
    progressionNote: 'arquero → una mano con mano elevada → una mano pies abiertos → una mano estricta',
  ),
  ExerciseGuide(
    name: 'Flexión a una mano',
    formCues: [
      'Pies bien abiertos, mano bajo el hombro.',
      'Cadera y hombros paralelos al suelo.',
      'Codo pegado al cuerpo al bajar.',
      'Si la cadera gira, vuelve a la versión con mano elevada.',
    ],
  ),
  ExerciseGuide(
    name: 'Flexiones diamante',
    formCues: [
      'Índices y pulgares juntos formando un rombo bajo el pecho.',
      'Codos pegados al cuerpo.',
      'Pecho hasta tocar las manos.',
    ],
  ),
  ExerciseGuide(
    name: 'Remo con banda',
    anchor: 'medio',
    formCues: [
      'De frente al anclaje, brazos extendidos.',
      'Lleva los codos atrás pegados al cuerpo.',
      'Junta las escápulas 1 s.',
    ],
  ),
  ExerciseGuide(
    name: 'Curl con banda',
    anchor: 'bajo',
    formCues: [
      'Pisa la banda; codos fijos a los lados.',
      'Sube sin balancear el cuerpo.',
      'Baja en 2 segundos.',
    ],
  ),
  ExerciseGuide(
    name: 'Extensión de tríceps sobre la cabeza con banda',
    anchor: 'bajo',
    formCues: [
      'Pisa la banda detrás de ti; manos detrás de la cabeza.',
      'Codos apuntando al techo, quietos.',
      'Extiende los brazos por completo.',
    ],
  ),
  ExerciseGuide(
    name: 'Face pull con banda',
    anchor: 'alto',
    formCues: [
      'Tira de la banda hacia la frente, separando las manos.',
      'Codos altos, a la altura de los hombros.',
      'Al final, pulgares apuntando atrás.',
    ],
  ),
  ExerciseGuide(
    name: 'L-sit',
    formCues: [
      'En la barra o con las manos en el suelo junto a la cadera.',
      'Hombros abajo, brazos bloqueados.',
      'Empieza con rodillas recogidas; extiende cuando aguantes 20 s.',
    ],
    progressionNote: 'tuck (rodillas recogidas) → una pierna extendida → L-sit completo',
  ),
  ExerciseGuide(
    name: 'Toes-to-bar',
    formCues: [
      'Colgado con hombros activos.',
      'Sube las piernas rectas hasta tocar la barra con los pies.',
      'Sin balanceo; baja controlado.',
    ],
    progressionNote: 'rodillas → piernas rectas → toes-to-bar',
  ),
  ExerciseGuide(
    name: 'Burpees',
    formCues: [
      'Pecho al suelo.',
      'Salta con extensión completa de cadera.',
      'Aterriza suave, rodillas flexionadas.',
    ],
  ),
  ExerciseGuide(
    name: 'Escaladores',
    formCues: [
      'Manos bajo los hombros, cuerpo en plancha.',
      'Lleva las rodillas al pecho alternando, rápido.',
      'La cadera no sube.',
    ],
  ),
  ExerciseGuide(
    name: 'Sentadilla con salto',
    formCues: [
      'Baja a sentadilla completa.',
      'Salta con todo y aterriza suave.',
      'Rodillas en línea con los pies.',
    ],
  ),
  ExerciseGuide(
    name: 'Rodillas arriba',
    formCues: [
      'Trote en el sitio subiendo las rodillas a la cadera.',
      'Brazos activos, torso erguido.',
      'Apoya la punta del pie, no el talón.',
    ],
  ),
  // Los del circuito ya se dominan: basta un recordatorio.
  ExerciseGuide(name: 'Dominadas', formCues: ['Recorrido completo: brazos extendidos abajo, barbilla sobre la barra.']),
  ExerciseGuide(name: 'Flexiones', formCues: ['Cuerpo en bloque: pecho casi al suelo, sin hundir la cadera.']),
  ExerciseGuide(name: 'Sentadillas', formCues: ['Cadera por debajo de las rodillas, talones apoyados.']),
];

/// Completa las guías de los ejercicios que ya existen. Solo llena campos
/// vacíos: si el usuario escribió sus propias claves, se quedan. Los
/// ejercicios que aún no existen se completan cuando el plan los crea.
Future<void> applyExerciseGuides(AppDatabase db) async {
  for (final g in exerciseGuides) {
    final row = await (db.select(db.exercises)..where((t) => t.name.equals(g.name))).getSingleOrNull();
    if (row == null) continue;
    await (db.update(db.exercises)..where((t) => t.id.equals(row.id))).write(ExercisesCompanion(
      mediaUrl: row.mediaUrl == null && g.mediaUrl != null ? Value(g.mediaUrl) : const Value.absent(),
      formCues: row.formCues == null && g.formCues.isNotEmpty ? Value(g.formCues.join('\n')) : const Value.absent(),
      progressionNote:
          row.progressionNote == null && g.progressionNote != null ? Value(g.progressionNote) : const Value.absent(),
      tracksLoad: g.tracksLoad && !row.tracksLoad ? const Value(true) : const Value.absent(),
      anchor: row.anchor == null && g.anchor != null ? Value(g.anchor) : const Value.absent(),
    ));
  }
}

/// Alimentos y combos añadidos al catálogo después de la primera versión.
const addedFoodNames = [
  'Almuerzo corriente (arroz + grano + carne + jugo)',
  'Peto sin maíz (vaso)',
  'Salchichón de pollo',
  'Pan Mipan',
  'Avena bebida (vaso 350 g)',
  'Sopa de mondongo + arroz',
  'Pasta con queso y salchicha (plato grande)',
];
const addedTemplateNames = ['Almuerzo corriente'];

/// Añade a una base existente los alimentos y combos nuevos que falten (por
/// nombre). Una base nueva ya los trae de la siembra.
Future<void> addMissingCatalog(AppDatabase db) async {
  final foods = await db.select(db.foods).get();
  final idsByName = {for (final f in foods) f.name: f.id};
  for (final food in initialFoods.where((f) => addedFoodNames.contains(f.name))) {
    if (idsByName.containsKey(food.name)) continue;
    idsByName[food.name] = await db.into(db.foods).insert(food.toCompanion());
  }

  final templates = {for (final t in await db.select(db.mealTemplates).get()) t.name};
  var position = templates.length;
  for (final (name, slot, items) in initialTemplates.where((t) => addedTemplateNames.contains(t.$1))) {
    if (templates.contains(name)) continue;
    await insertTemplate(db, name, slot, items, idsByName, position: position++);
  }
}

/// Pan por unidad que pasa a pesarse: nombre → gramos de una unidad.
const _breadByUnit = {'Pan (unidad)': 75.0, 'Pan Mipan (unidad 60 g)': 60.0};

/// Pan y salchichón por gramos (traspaso §16.3 y §17, 29 sep 2026). El pan
/// por unidad (50 g de referencia, o la unidad Mipan de 60 g) se reemplaza
/// por "Pan Mipan" por 100 g de etiqueta; los combos que lo usaban pasan a
/// gramos (1 unidad → 75 g o 60 g) y las comidas ya registradas conservan sus
/// macros (solo pierden el vínculo con el alimento borrado). El salchichón
/// propone una rodaja (22 g) en vez de 100 g. Idempotente.
Future<void> applyGramsCatalog(AppDatabase db) async {
  final mipan = initialFoods.firstWhere((f) => f.name == 'Pan Mipan');
  var mipanId = (await (db.select(db.foods)..where((t) => t.name.equals(mipan.name))).getSingleOrNull())?.id;
  mipanId ??= await db.into(db.foods).insert(mipan.toCompanion());

  for (final MapEntry(key: name, value: grams) in _breadByUnit.entries) {
    final old = await (db.select(db.foods)..where((t) => t.name.equals(name) & t.basis.equalsValue(FoodBasis.unit)))
        .getSingleOrNull();
    if (old == null) continue;
    for (final item in await (db.select(db.mealTemplateItems)..where((t) => t.foodId.equals(old.id))).get()) {
      await (db.update(db.mealTemplateItems)..where((t) => t.id.equals(item.id))).write(MealTemplateItemsCompanion(
        foodId: Value(mipanId),
        quantity: Value(item.quantity * grams),
      ));
    }
    await (db.update(db.mealItems)..where((t) => t.foodId.equals(old.id)))
        .write(const MealItemsCompanion(foodId: Value(null)));
    if (old.favorite) {
      await (db.update(db.foods)..where((t) => t.id.equals(mipanId!))).write(const FoodsCompanion(favorite: Value(true)));
    }
    await (db.delete(db.foods)..where((t) => t.id.equals(old.id))).go();
  }

  await (db.update(db.foods)
        ..where((t) =>
            t.name.equals('Salchichón de pollo') &
            t.basis.equalsValue(FoodBasis.per100) &
            t.defaultQuantity.equals(100)))
      .write(const FoodsCompanion(defaultQuantity: Value(22)));
}

/// Crea un combo con sus alimentos (por nombre). Los que no existan se omiten.
Future<void> insertTemplate(
  AppDatabase db,
  String name,
  MealSlot? slot,
  List<(String, double)> items,
  Map<String, int> idsByName, {
  required int position,
}) async {
  final templateId = await db.into(db.mealTemplates).insert(MealTemplatesCompanion.insert(
        name: name,
        slot: Value(slot),
        position: Value(position),
      ));
  var itemPosition = 0;
  for (final (foodName, quantity) in items) {
    final foodId = idsByName[foodName];
    if (foodId == null) continue;
    await db.into(db.mealTemplateItems).insert(MealTemplateItemsCompanion.insert(
          templateId: templateId,
          foodId: foodId,
          quantity: quantity,
          position: Value(itemPosition++),
        ));
  }
}
