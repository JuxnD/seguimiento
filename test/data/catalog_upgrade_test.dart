import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/catalog_patches.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/enums.dart';
import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';
import '../support/derived_historical_037.dart';

void main() {
  setUpAll(useHostSqlite);
  test(
      'schema20→21 adds missing references, preserves custom homonym and history',
      () async {
    final dir =
        await Directory('build/010-catalog-upgrade').create(recursive: true);
    final file = File(
        '${dir.path}/synthetic-${DateTime.now().microsecondsSinceEpoch}.sqlite');
    copyHistorical037(20, file);
    // Empty authentic20 DDL, with one independently inserted custom homonym.
    const id = 1;
    var db = AppDatabase(NativeDatabase(file));
    final custom =
        await (db.select(db.foods)..where((f) => f.id.equals(id))).getSingle();
    expect(custom.kcal, 65);
    expect(custom.favorite, isTrue);
    expect(custom.origin, FoodOrigin.usuario);
    expect(
        await (db.select(db.foods)..where((f) => f.name.equals('Leche entera')))
            .get(),
        hasLength(1));
    final marks = await db.select(db.catalogPatches).get();
    expect(marks, hasLength(initialFoods.length));
    expect(
        marks.firstWhere((r) => r.sourceId == 'catalog-v1:Leche entera').foodId,
        isNull);
    final before = await db.select(db.foods).get();
    await applyCatalogPatchV1(db);
    expect(await db.select(db.foods).get(), before);
    final known = before.firstWhere((f) => f.origin == FoodOrigin.semilla);
    await (db.update(db.foods)..where((f) => f.id.equals(known.id))).write(
        const FoodsCompanion(
            name: Value('Mi nombre personalizado'), kcal: Value(777)));
    await applyCatalogPatchV1(db);
    expect(
        (await (db.select(db.foods)..where((f) => f.id.equals(known.id)))
                .getSingle())
            .kcal,
        777);
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    expect(
        await (db.select(db.foods)..where((f) => f.name.equals(known.name)))
            .get(),
        isEmpty);
    await NutritionRepository(db).deleteFood(known.id);
    await applyCatalogPatchV1(db);
    expect(
        await (db.select(db.foods)..where((f) => f.name.equals(known.name)))
            .get(),
        isEmpty);
    await db.close();
    await file.delete();
  });

  test('first install records identities after combos and does not duplicate',
      () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    expect(await seedFoodsIfEmpty(db), isTrue);
    expect(await db.select(db.catalogPatches).get(),
        hasLength(initialFoods.length));
    final rows = await db.select(db.catalogPatches).get();
    final byId = {
      for (final food in await db.select(db.foods).get()) food.id: food
    };
    for (final mark in rows) {
      expect(mark.patchVersion, 1);
      expect(byId[mark.foodId]!.name,
          mark.sourceId.substring('catalog-v1:'.length));
    }
    final rice = byId[rows
        .singleWhere((r) => r.sourceId == 'catalog-v1:Arroz blanco cocido')
        .foodId]!;
    final milk = byId[rows
        .singleWhere((r) => r.sourceId == 'catalog-v1:Leche entera')
        .foodId]!;
    final klim = byId[rows
        .singleWhere((r) => r.sourceId == 'catalog-v1:Leche Klim en polvo')
        .foodId]!;
    expect((rice.basis, rice.unitLabel, rice.defaultQuantity, rice.kcal),
        (FoodBasis.per100, 'g', 100.0, 130.0));
    expect((milk.basis, milk.unitLabel, milk.defaultQuantity, milk.kcal),
        (FoodBasis.per100, 'ml', 100.0, 61.0));
    expect((klim.basis, klim.unitLabel, klim.defaultQuantity, klim.kcal),
        (FoodBasis.unit, 'papeleta', 1.0, 125.0));
    expect(await NutritionRepository(db).templates(),
        hasLength(initialTemplates.length));
    expect(await seedFoodsIfEmpty(db), isFalse);
    expect(await db.select(db.foods).get(), hasLength(initialFoods.length));
  });
  test('ZIP→restaurar→reabrir conserva registry IDs y provenance de comida',
      () async {
    final base = Directory('build').absolute.path;
    final root = await Directory(
            '$base/010-backup-${DateTime.now().microsecondsSinceEpoch}')
        .create(recursive: true);
    final aDir = await Directory('${root.path}/A').create();
    final bDir = await Directory('${root.path}/B').create();
    final a = DatabaseHost(File('${aDir.path}/seguimiento.sqlite'),
        (f) => AppDatabase(NativeDatabase(f)));
    final b = DatabaseHost(File('${bDir.path}/seguimiento.sqlite'),
        (f) => AppDatabase(NativeDatabase(f)));
    await seedFoodsIfEmpty(a.db);
    // Quien registra comidas ya pasó el alta (plan 022).
    await asExistingUser(a.db, goals: false);
    final repo = NutritionRepository(a.db);
    const notes =
        'Descripción original · IA: 250 g de arroz chino\nSupuesto: aceite desconocido\nEstimación IA gpt-6-luna revisada';
    await repo.saveMeal(MealDraft(
        date: DateTime(2026, 10, 9),
        slot: MealSlot.otro,
        notes: notes,
        items: [
          MealItemDraft(
              label: 'Arroz chino',
              quantity: 250,
              quantityUnit: 'g',
              macros: const Macros(kcal: 500, protein: 20, carbs: 70, fat: 16))
        ]));
    final registry = await a.db.select(a.db.catalogPatches).get();
    final snapshot = await a.db.select(a.db.mealItems).get();
    final exported = await BackupArchive(host: a, documents: aDir)
        .exportTo('${root.path}/backup.zip');
    await BackupArchive(host: b, documents: bDir).restoreFrom(exported.file);
    expect(await b.db.select(b.db.catalogPatches).get(), registry);
    expect(await b.db.select(b.db.mealItems).get(), snapshot);
    expect((await b.db.select(b.db.meals).get()).single.notes, notes);
    await b.db.close();
    final reopen = AppDatabase(NativeDatabase(b.file));
    expect(await reopen.select(reopen.catalogPatches).get(), registry);
    expect((await reopen.select(reopen.meals).get()).single.notes, notes);
    await reopen.close();
    await a.db.close();
    final resolvedRoot = await root.resolveSymbolicLinks();
    final resolvedBase = await Directory(base).resolveSymbolicLinks();
    if (!p.isWithin(resolvedBase, resolvedRoot)) {
      throw StateError('Fixture cleanup outside build is forbidden');
    }
    await root.delete(recursive: true);
  });
}
