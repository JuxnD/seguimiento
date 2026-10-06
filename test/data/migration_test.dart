import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/domain/reminders.dart';
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

const _v7Columns = {
  'sessions': ['rest_sec'],
};

const _v8Columns = {
  'exercises': ['media_url', 'form_cues', 'progression_note', 'tracks_load'],
  'session_rounds': ['work_sec', 'rest_sec'],
  'session_sets': ['load_kg'],
};
const _v8Tables = ['closed_days'];

const _v10Columns = {
  'profiles': ['steps_target'],
  'football_games': ['knock'],
  'foods': ['origin', 'favorite'],
};
const _v10Tables = ['daily_steps'];

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
  /// `rows` inserta datos con el esquema viejo ya armado, antes de cerrar: si
  /// se insertaran abriendo otra vez con la app, la migración correría antes.
  Future<void> buildOldSchema(int version, {Future<void> Function(AppDatabase db)? rows}) async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customStatement('select 1'); // crea el esquema actual
    if (version < 18) {
      await db.customStatement('drop table ai_messages');
      await db.customStatement('drop table ai_conversations');
    }
    if (version >= 17) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    for (final (table, column) in [
      ('body_weights', 'moment'),
      ('body_weights', 'time'),
      ('foods', 'eggs_per_unit'),
    ]) {
      await db.customStatement('alter table $table drop column $column');
    }
    for (final table in ['morning_checks', 'soreness_logs', 'skill_achievements']) {
      await db.customStatement('drop table if exists $table');
    }
    if (version >= 16) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    for (final (table, column) in [
      ('session_sets', 'rir'),
      ('profiles', 'kcal_target_football'),
      ('football_games', 'weight_before_kg'),
      ('football_games', 'weight_after_kg'),
      ('football_games', 'fluid_ml'),
    ]) {
      await db.customStatement('alter table $table drop column $column');
    }
    await db.customStatement('drop table if exists sleep_logs');
    if (version >= 15) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    for (final (table, column) in [
      ('plan_versions', 'scheme'),
      ('plan_exercises', 'superset_group'),
      ('exercises', 'anchor'),
      ('session_sets', 'variant'),
      ('sessions', 'mode'),
      ('sessions', 'extra_reps'),
    ]) {
      await db.customStatement('alter table $table drop column $column');
    }
    if (version >= 14) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    await db.customStatement('alter table sessions drop column pending_review');
    await db.customStatement('alter table measurements drop column time');
    if (version >= 13) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    if (version >= 12) {
      // El 13 solo cambia datos: basta con marcar la versión.
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    await db.customStatement('drop table if exists custom_reminders');
    if (version >= 11) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    await db.customStatement('drop table if exists exercise_photos');
    if (version >= 10) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    for (final entry in _v10Columns.entries) {
      for (final column in entry.value) {
        await db.customStatement('alter table ${entry.key} drop column $column');
      }
    }
    for (final table in _v10Tables) {
      await db.customStatement('drop table if exists $table');
    }
    if (version >= 8) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    for (final entry in _v8Columns.entries) {
      for (final column in entry.value) {
        await db.customStatement('alter table ${entry.key} drop column $column');
      }
    }
    for (final table in _v8Tables) {
      await db.customStatement('drop table if exists $table');
    }
    if (version >= 7) {
      await rows?.call(db);
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
    for (final entry in _v7Columns.entries) {
      for (final column in entry.value) {
        await db.customStatement('alter table ${entry.key} drop column $column');
      }
    }
    if (version >= 6) {
      await db.customStatement('pragma user_version = $version');
      await db.close();
      return;
    }
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

  test('fixture sintética congelada 17 migra a 18 sin reconstruir el esquema', () async {
    final frozen = File('test/fixtures/schema17-synthetic.sqlite');
    expect(frozen.existsSync(), isTrue);
    frozen.copySync(file.path);
    final raw = sqlite.sqlite3.open(file.path);
    expect(raw.select('pragma user_version').single.values.first, 17);
    expect(raw.select("select name from sqlite_master where type='table' and name in ('ai_conversations', 'ai_messages')"), isEmpty);
    raw.dispose();

    final migrated = AppDatabase(NativeDatabase(file));
    expect(await userVersion(migrated), 18);
    expect((await BodyRepository(migrated).watchWeights().first).map((row) => row.kg), [70]);
    final meal = await migrated.customSelect('select m.date, i.label, i.kcal from meals m join meal_items i on i.meal_id = m.id').getSingle();
    expect(meal.data, {'date': '2026-09-29', 'label': 'Dato sintético', 'kcal': 350});
    expect(await migrated.select(migrated.aiConversations).get(), isEmpty);
    await migrated.close();
  });

  test('una base del esquema 1 llega al 18 sin perder datos', () async {
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

    // La migración al 8 añade al catálogo lo nuevo; lo del usuario sigue ahí.
    final food = (await migrated.select(migrated.foods).get()).firstWhere((f) => f.name == 'Huevo');
    expect(food.source, MacroSource.referencia, reason: 'lo que ya existía queda como referencia');
    expect(food.servingGrams, isNull);

    expect(await userVersion(migrated), 18);

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

  test('una base del esquema 2 llega al 18 conservando el catálogo', () async {
    await buildOldSchema(2);

    final old = AppDatabase(NativeDatabase(file));
    await old.customStatement(
        "insert into foods (name, basis, unit_label, kcal, protein) values ('Atún', 'unit', 'lata', 120, 25)");
    await old.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final food = (await migrated.select(migrated.foods).get()).firstWhere((f) => f.name == 'Atún');
    expect(food.kcal, 120);
    expect(food.source, MacroSource.referencia);
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 7 llega al 18 con guías, catálogo nuevo y rondas sin separar', () async {
    await buildOldSchema(7, rows: (old) async {
      // 'Separaciones con banda' lleva anclaje: antes la guía se escribía en
      // el paso 8, cuando `exercises.anchor` (paso 15) aún no existía.
      await old.customStatement(
          "insert into exercises (name) values ('Pike push-up'), ('Sentadilla búlgara'), ('Separaciones con banda')");
      await old.customStatement(
          "insert into foods (name, basis, unit_label, kcal, protein) values ('Peto sin maíz (vaso)', 'unit', 'vaso', 180, 6)");
      await old.customStatement(
          "insert into sessions (date, type, total_sec, warmup_sec, cooldown_sec) values ('2026-09-25', 'progresion', 1153, 370, 180)");
      await old.customStatement('insert into session_rounds (session_id, round_index, elapsed_sec) values (1, 1, 50)');
    });

    final migrated = AppDatabase(NativeDatabase(file));
    expect(await userVersion(migrated), 18);

    final pike = await (migrated.select(migrated.exercises)..where((t) => t.name.equals('Pike push-up'))).getSingle();
    expect(pike.formCues, startsWith('Posición de V invertida'));
    expect(pike.progressionNote, 'pike → pies elevados → HSPU asistido → HSPU');
    expect(pike.tracksLoad, isFalse);
    final bulgara =
        await (migrated.select(migrated.exercises)..where((t) => t.name.equals('Sentadilla búlgara'))).getSingle();
    expect(bulgara.tracksLoad, isTrue, reason: 'la búlgara progresa con carga');
    final band =
        await (migrated.select(migrated.exercises)..where((t) => t.name.equals('Separaciones con banda'))).getSingle();
    expect(band.anchor, 'manos');

    final foods = {for (final f in await migrated.select(migrated.foods).get()) f.name: f};
    expect(foods['Peto sin maíz (vaso)']!.kcal, 180, reason: 'lo que el usuario ya tenía no se pisa');
    expect(foods.keys, containsAll(['Salchichón de pollo', 'Almuerzo corriente (arroz + grano + carne + jugo)']));
    final templates = await migrated.select(migrated.mealTemplates).get();
    expect(templates.map((t) => t.name), contains('Almuerzo corriente'));

    final round = await migrated.select(migrated.sessionRounds).getSingle();
    expect(round.elapsedSec, 50);
    expect(round.workSec, isNull, reason: 'una ronda vieja no sabe cuánto fue descanso');
    expect(await migrated.select(migrated.closedDays).get(), isEmpty);
    await migrated.close();
  });

  test('del esquema 8 al 9 los recordatorios vuelven a los valores acordados', () async {
    await buildOldSchema(8, rows: (old) async {
      await old.customStatement(
          "insert into reminders (kind, enabled, hour, minute, threshold) values ('sesion', 0, 9, 30, null), ('proteina', 1, 18, 0, 80)");
      await old.customStatement("insert into sessions (date, type) values ('2026-09-25', 'progresion')");
    });

    final migrated = AppDatabase(NativeDatabase(file));
    expect(await userVersion(migrated), 18);
    final repo = ReminderRepository(migrated);
    await repo.ensureDefaults(); // lo que hace el arranque
    final settings = await repo.settings();
    expect(settings[ReminderKind.sesion]!.enabled, isTrue);
    expect(settings[ReminderKind.sesion]!.hour, 15);
    expect(settings[ReminderKind.proteina]!.hour, 20);
    expect(settings[ReminderKind.proteina]!.threshold, 100);
    expect(settings[ReminderKind.calorias]!.threshold, 1800);
    expect(settings[ReminderKind.comidasSinRegistrar]!.hour, 22);
    // Los propios no tienen fila en `reminders`: viven en `custom_reminders`.
    expect(settings.length, ReminderKind.values.length - 1);
    expect(await migrated.select(migrated.sessions).get(), hasLength(1), reason: 'solo se tocan los avisos');
    await migrated.close();
  });

  test('una base del esquema 6 llega al 18: las sesiones viejas quedan con descanso 0', () async {
    await buildOldSchema(6);
    final old = AppDatabase(NativeDatabase(file));
    await old.customStatement(
        "insert into sessions (date, type, total_sec, warmup_sec, cooldown_sec) values ('2026-09-20', 'circuito', 1200, 360, 180)");
    await old.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final session = await migrated.select(migrated.sessions).getSingle();
    expect(session.totalSec, 1200);
    expect(session.restSec, 0);
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 9 llega al 18: pasos, golpe en el fútbol y alimentos marcados', () async {
    await buildOldSchema(9, rows: (db) async {
      await db.customStatement(
          "insert into foods (name, basis, unit_label, kcal, protein) values ('Pan (unidad)', 'unit', 'unidad', 140, 4.5)");
      await db.customStatement(
          "insert into foods (name, basis, unit_label, kcal, protein) values ('Arepa de huevo', 'unit', 'unidad', 400, 12)");
      await db.customStatement("insert into football_games (date, minutes) values ('2026-09-27', 90)");
    });

    final migrated = AppDatabase(NativeDatabase(file));
    final foods = {for (final f in await migrated.select(migrated.foods).get()) f.name: f};
    expect(foods['Arepa de huevo']!.origin, FoodOrigin.usuario, reason: 'lo demás lo creó el usuario');
    expect(foods.containsKey('Pan (unidad)'), isFalse, reason: 'el 13 lo pasa a Pan Mipan por gramos');
    expect(foods['Pan Mipan']!.kcal, 331);
    expect(foods['Pan Mipan']!.source, MacroSource.etiqueta);
    expect(foods['Salchichón de pollo']!.defaultQuantity, 22);
    expect(foods['Sopa de mondongo + arroz']!.source, MacroSource.estimado);

    final game = await migrated.select(migrated.footballGames).getSingle();
    expect(game.minutes, 90);
    expect(game.knock, isNull);

    final profile = await migrated.select(migrated.profiles).getSingle();
    expect(profile.stepsTarget, 7500);
    expect(await migrated.select(migrated.dailySteps).get(), isEmpty);
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 10 llega al 18 con la tabla de fotos de referencia', () async {
    await buildOldSchema(10);
    final migrated = AppDatabase(NativeDatabase(file));
    expect(await migrated.select(migrated.exercisePhotos).get(), isEmpty);
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 11 llega al 18 con la tabla de recordatorios propios', () async {
    await buildOldSchema(11);
    final migrated = AppDatabase(NativeDatabase(file));
    expect(await migrated.select(migrated.customReminders).get(), isEmpty);
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 12 llega al 18: pan y salchichón por gramos', () async {
    late int panId;
    await buildOldSchema(12, rows: (db) async {
      panId = await db.into(db.foods).insert(FoodsCompanion.insert(
          name: 'Pan (unidad)', basis: FoodBasis.unit, kcal: 140, protein: 4.5, favorite: const Value(true)));
      final mipan60 = await db.into(db.foods).insert(
          FoodsCompanion.insert(name: 'Pan Mipan (unidad 60 g)', basis: FoodBasis.unit, kcal: 199, protein: 5.8));
      await db.into(db.foods).insert(FoodsCompanion.insert(
          name: 'Salchichón de pollo',
          basis: FoodBasis.per100,
          unitLabel: const Value('g'),
          kcal: 200,
          protein: 13,
          defaultQuantity: const Value(100)));
      final combo = await db.into(db.mealTemplates).insert(MealTemplatesCompanion.insert(name: 'Huevos con pan'));
      await db.into(db.mealTemplateItems)
          .insert(MealTemplateItemsCompanion.insert(templateId: combo, foodId: panId, quantity: 2));
      await db.into(db.mealTemplateItems)
          .insert(MealTemplateItemsCompanion.insert(templateId: combo, foodId: mipan60, quantity: 1));
      final meal = await db.into(db.meals).insert(MealsCompanion.insert(date: '2026-09-28', slot: MealSlot.desayuno));
      await db.into(db.mealItems).insert(MealItemsCompanion.insert(
          mealId: meal, foodId: Value(panId), label: 'Pan (unidad)', quantity: const Value(1), kcal: 140, protein: 4.5));
    });

    final migrated = AppDatabase(NativeDatabase(file));
    final foods = {for (final f in await migrated.select(migrated.foods).get()) f.name: f};
    expect(foods.keys, isNot(contains('Pan (unidad)')));
    expect(foods.keys, isNot(contains('Pan Mipan (unidad 60 g)')));
    final mipan = foods['Pan Mipan']!;
    expect((mipan.basis, mipan.kcal, mipan.protein, mipan.defaultQuantity), (FoodBasis.per100, 331, 9.6, 75));
    expect(mipan.favorite, isTrue, reason: 'hereda la marca del pan que reemplaza');
    expect(foods['Salchichón de pollo']!.defaultQuantity, 22);

    final items = await migrated.select(migrated.mealTemplateItems).get();
    expect(items.map((i) => (i.foodId, i.quantity)), [(mipan.id, 150), (mipan.id, 60)],
        reason: '2 panes de 75 g y una unidad Mipan de 60 g');

    final logged = await migrated.select(migrated.mealItems).getSingle();
    expect((logged.label, logged.kcal), ('Pan (unidad)', 140), reason: 'lo ya comido no cambia');
    expect(logged.foodId, isNull, reason: 'solo pierde el vínculo con el alimento borrado');
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 13 llega al 18: las sesiones quedan revisadas', () async {
    await buildOldSchema(13, rows: (db) async {
      await db.customStatement("insert into sessions (date, type, total_sec) values ('2026-10-01', 'circuito', 1200)");
    });
    final migrated = AppDatabase(NativeDatabase(file));
    final session = await migrated.select(migrated.sessions).getSingle();
    expect(session.pendingReview, isFalse, reason: 'lo ya guardado no queda como pendiente');
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 14 llega al 18: plan y sesiones listos para el v3', () async {
    await buildOldSchema(14, rows: (db) async {
      await db.customStatement("insert into plan_versions (valid_from) values ('2026-09-28')");
      await db.customStatement("insert into sessions (date, type, total_sec) values ('2026-10-02', 'progresion', 1332)");
    });
    final migrated = AppDatabase(NativeDatabase(file));
    final version = await migrated.select(migrated.planVersions).getSingle();
    expect(version.scheme, isNull, reason: 'el v2 sigue siendo un plan plano');
    final session = await migrated.select(migrated.sessions).getSingle();
    expect((session.mode, session.extraReps), (null, null));
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 15 llega al 18: RIR, fútbol, sueño y meta de fútbol', () async {
    await buildOldSchema(15, rows: (db) async {
      await db.customStatement("insert into exercises (name) values ('Dominadas')");
      await db.customStatement("insert into sessions (date, type, total_sec) values ('2026-10-05', 'bloques', 1800)");
      await db.customStatement('insert into session_sets (session_id, exercise_id, set_index, reps) values (1, 1, 1, 8)');
      await db.customStatement("insert into football_games (date, minutes) values ('2026-10-04', 90)");
    });
    final migrated = AppDatabase(NativeDatabase(file));
    final set = await migrated.select(migrated.sessionSets).getSingle();
    expect((set.reps, set.rir), (8, null), reason: 'las series viejas quedan sin RIR anotado');
    final game = await migrated.select(migrated.footballGames).getSingle();
    expect((game.minutes, game.weightBeforeKg, game.fluidMl), (90, null, null));
    final profile = await migrated.select(migrated.profiles).getSingle();
    expect(profile.kcalTargetFootball, isNull, reason: 'sin meta propia, el fútbol usa la de entre semana');
    await migrated.into(migrated.sleepLogs).insert(SleepLogsCompanion.insert(date: '2026-10-06', hours: 7.5));
    expect((await migrated.select(migrated.sleepLogs).getSingle()).hours, 7.5);
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });

  test('una base del esquema 16 llega al 18: momento del pesaje, mañana y huevos por porción', () async {
    await buildOldSchema(16, rows: (db) async {
      await db.customStatement("insert into body_weights (date, kg, fasted) values ('2026-10-05', 80.5, 0)");
      await db.customStatement(
          "insert into foods (name, basis, unit_label, kcal, protein) values ('Desayuno típico', 'unit', 'porción', 700, 40)");
    });
    final migrated = AppDatabase(NativeDatabase(file));
    final w = await migrated.select(migrated.bodyWeights).getSingle();
    expect((w.kg, w.fasted, w.moment, w.time), (80.5, false, null, null), reason: 'el momento se deduce de fasted');
    final food = (await migrated.select(migrated.foods).get()).firstWhere((f) => f.name == 'Desayuno típico');
    expect(food.eggsPerUnit, isNull);
    await migrated.into(migrated.morningChecks).insert(MorningChecksCompanion.insert(date: '2026-10-06', restingHr: const Value(58)));
    await migrated.into(migrated.sorenessLogs).insert(SorenessLogsCompanion.insert(date: '2026-10-06', zone: 'Isquios', level: 4));
    await migrated.into(migrated.skillAchievements).insert(SkillAchievementsCompanion.insert(skill: 'l_sit', date: '2026-12-11'));
    expect(await userVersion(migrated), 18);
    await migrated.close();
  });
}
