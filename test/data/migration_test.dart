import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/sqlite_host.dart';

/// Columnas y tablas que añadió cada esquema, para poder reconstruir una base
/// anterior a partir de la actual.
const _v2Columns = {
  'profiles': ['measure_interval_max_days', 'next_measurement_date', 'cooldown_target_sec', 'never_to_failure'],
  'plan_days': ['rest_between_rounds_sec'],
  'plan_exercises': [
    'rest_sec_max',
    'block',
    'variant',
    'hold_sec_min',
    'hold_sec_max',
    'per_side',
    'rir_min',
    'rir_max',
    'notes',
  ],
  'sessions': ['technique_ok', 'full_range', 'recovery_ok'],
};

const _v3Columns = {
  'foods': ['serving_grams', 'source'],
  'meal_items': ['source_verified'],
};
const _v3Tables = ['meal_template_items', 'meal_templates'];
const _v5Tables = ['reminders'];
const _v6Tables = ['progress_photos'];

const _v4Columns = {
  'sessions': ['out_of_plan', 'incomplete', 'planned_rounds'],
};

void main() {
  setUpAll(useHostSqlite);

  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_migracion');
    file = File('${dir.path}/seguimiento.sqlite');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows puede mantener el archivo tomado; no afecta la prueba.
    }
  });

  /// Deja el archivo como lo tendría una app instalada con el esquema `version`.
  Future<void> buildOldSchema(int version) async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customStatement('select 1'); // crea el esquema actual
    for (final entry in _v4Columns.entries) {
      for (final column in entry.value) {
        await db.customStatement('alter table ${entry.key} drop column $column');
      }
    }
    for (final table in [..._v6Tables, ..._v5Tables, ..._v3Tables]) {
      await db.customStatement('drop table if exists $table');
    }
    for (final entry in _v3Columns.entries) {
      for (final column in entry.value) {
        await db.customStatement('alter table ${entry.key} drop column $column');
      }
    }
    if (version < 2) {
      for (final entry in _v2Columns.entries) {
        for (final column in entry.value) {
          await db.customStatement('alter table ${entry.key} drop column $column');
        }
      }
    }
    await db.customStatement('pragma user_version = $version');
    await db.close();
  }

  Future<int> userVersion(AppDatabase db) =>
      db.customSelect('pragma user_version').map((r) => r.data.values.first as int).getSingle();

  test('una base del esquema 1 llega al 6 sin perder datos', () async {
    await buildOldSchema(1);

    // Datos ya registrados por el usuario antes de actualizar.
    final old = AppDatabase(NativeDatabase(file));
    await old.customStatement("update profiles set start_date = '2026-08-26', kcal_target = 2500");
    await BodyRepository(old).addWeight(DateTime(2026, 9, 18), 71.4);
    await old.customStatement(
        "insert into foods (name, basis, unit_label, kcal, protein) values ('Huevo', 'unit', 'unidad', 70, 6)");
    await old.close();

    // Abrir con la app nueva dispara onUpgrade.
    final migrated = AppDatabase(NativeDatabase(file));
    final profile = await (migrated.select(migrated.profiles)..where((t) => t.id.equals(1))).getSingle();

    expect(profile.startDate, '2026-08-26', reason: 'los datos del usuario se conservan');
    expect(profile.kcalTarget, 2500);
    expect(profile.cooldownTargetSec, 180, reason: 'las columnas nuevas toman su valor por defecto');
    expect(profile.measureIntervalMaxDays, 28);
    expect(profile.neverToFailure, isTrue);
    expect(profile.nextMeasurementDate, isNull);

    final weights = await BodyRepository(migrated).watchWeights().first;
    expect(weights.single.kg, 71.4);

    final food = (await migrated.select(migrated.foods).get()).single;
    expect(food.name, 'Huevo');
    expect(food.source, MacroSource.referencia, reason: 'lo que ya existía queda como referencia');
    expect(food.servingGrams, isNull);

    expect(await userVersion(migrated), 6);

    // El esquema nuevo ya acepta lo que el plan y los combos necesitan.
    await migrated.into(migrated.planVersions).insert(
          PlanVersionsCompanion.insert(validFrom: '2026-09-28', notes: const Value('v2')),
        );
    final dayId = await migrated.into(migrated.planDays).insert(PlanDaysCompanion.insert(
          planVersionId: 1,
          weekday: 1,
          type: DayType.circuitoLigero,
          restBetweenRoundsSec: const Value(30),
        ));
    expect(dayId, greaterThan(0));

    final templateId =
        await migrated.into(migrated.mealTemplates).insert(MealTemplatesCompanion.insert(name: 'Batido'));
    expect(templateId, greaterThan(0));
    await migrated.close();
  });

  test('una base del esquema 2 llega al 6 conservando el catálogo', () async {
    await buildOldSchema(2);

    final old = AppDatabase(NativeDatabase(file));
    await old.customStatement(
        "insert into foods (name, basis, unit_label, kcal, protein) values ('Atún', 'unit', 'lata', 120, 25)");
    await old.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final food = (await migrated.select(migrated.foods).get()).single;
    expect(food.name, 'Atún');
    expect(food.kcal, 120);
    expect(food.source, MacroSource.referencia);
    expect(await userVersion(migrated), 6);
    await migrated.close();
  });
}
