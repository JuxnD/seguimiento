import 'package:drift/drift.dart';
import '../domain/enums.dart';
import '../domain/search.dart';
import 'database.dart';
import 'seed_foods.dart';

String _key(String name) =>
    foldText(name.trim()).replaceAll(RegExp(r'\s+'), ' ');

/// Frozen version1 source keys. These are original source identities, not
/// current display names. Future catalog renames/additions need a new patch.
const catalogV1Names = [
  'Huevo (unidad)',
  'Atún en lata (escurrido)',
  'Leche Klim en polvo',
  'Nestum',
  'Leche entera Colanta (bolsa)',
  'Leche entera',
  'Banano',
  'Arroz blanco cocido',
  'Frijoles cocidos',
  'Lentejas cocidas',
  'Carne de res (magra, cocida)',
  'Pechuga de pollo (cocida)',
  'Chicharrón',
  'Chorizo',
  'Pan tajado',
  'Pan Mipan',
  'Bollo de maíz',
  'Patacón / tajada de plátano frito',
  'Yuca frita',
  'Papa frita',
  'Aguacate',
  'Queso costeño',
  'Sardinas en lata',
  'Avena en hojuelas (seca)',
  'Jugo de fruta',
  'Manzana',
  'Crema de maní',
  'Ensalada (tomate, cebolla, lechuga)',
  'Avena Alpina original (vaso)',
  'Almuerzo corriente (arroz + grano + carne + jugo)',
  'Peto sin maíz (vaso)',
  'Salchichón de pollo',
  'Avena bebida (vaso 350 g)',
  'Sopa de mondongo + arroz',
  'Pasta con queso y salchicha (plato grande)',
  'Yogur Colanta arequipe',
];

/// Version1 recovers missing existing seed references on upgrades. It adds no
/// invented recipe values. IDs below are frozen source names; later renames
/// update display separately while this registry preserves identity.
Future<void> applyCatalogPatchV1(AppDatabase db) async {
  final foods = await db.select(db.foods).get();
  if (foods.isEmpty) return; // First-install seeding also creates its combos.
  await db.transaction(() async {
    final applied = (await db.select(db.catalogPatches).get())
        .map((r) => r.sourceId)
        .toSet();
    final existing = {for (final f in foods) _key(f.name): f};
    for (final sourceName in catalogV1Names) {
      final food = initialFoods.singleWhere((f) => f.name == sourceName);
      final sourceId = 'catalog-v1:$sourceName';
      if (applied.contains(sourceId)) continue;
      final sameName = existing[_key(food.name)];
      // Preserve edits and ambiguity: a custom homonym is not identified as seed.
      final id = sameName == null
          ? await db.into(db.foods).insert(food.toCompanion())
          : sameName.origin == FoodOrigin.semilla
              ? sameName.id
              : null;
      await db.into(db.catalogPatches).insert(CatalogPatchesCompanion.insert(
          sourceId: sourceId, patchVersion: 1, foodId: Value(id)));
    }
  });
}
