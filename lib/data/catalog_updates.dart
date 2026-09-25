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
  });

  final String name;
  final String? mediaUrl;
  final List<String> formCues;
  final String? progressionNote;
  final bool tracksLoad;
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
    ));
  }
}

/// Alimentos y combos añadidos al catálogo después de la primera versión.
const addedFoodNames = [
  'Almuerzo corriente (arroz + grano + carne + jugo)',
  'Peto sin maíz (vaso)',
  'Salchichón de pollo',
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
