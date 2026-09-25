import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('una base del esquema 1 llega al 9 sin perder datos', () async {
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

    expect(await userVersion(migrated), 9);

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

  test('una base del esquema 2 llega al 9 conservando el catálogo', () async {
    await buildOldSchema(2);

    final old = AppDatabase(NativeDatabase(file));
    await old.customStatement(
        "insert into foods (name, basis, unit_label, kcal, protein) values ('Atún', 'unit', 'lata', 120, 25)");
    await old.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final food = (await migrated.select(migrated.foods).get()).firstWhere((f) => f.name == 'Atún');
    expect(food.kcal, 120);
    expect(food.source, MacroSource.referencia);
    expect(await userVersion(migrated), 9);
    await migrated.close();
  });

  test('una base del esquema 7 llega al 9 con guías, catálogo nuevo y rondas sin separar', () async {
    await buildOldSchema(7, rows: (old) async {
      await old.customStatement("insert into exercises (name) values ('Pike push-up'), ('Sentadilla búlgara')");
      await old.customStatement(
          "insert into foods (name, basis, unit_label, kcal, protein) values ('Peto sin maíz (vaso)', 'unit', 'vaso', 180, 6)");
      await old.customStatement(
          "insert into sessions (date, type, total_sec, warmup_sec, cooldown_sec) values ('2026-09-25', 'progresion', 1153, 370, 180)");
      await old.customStatement('insert into session_rounds (session_id, round_index, elapsed_sec) values (1, 1, 50)');
    });

    final migrated = AppDatabase(NativeDatabase(file));
    expect(await userVersion(migrated), 9);

    final pike = await (migrated.select(migrated.exercises)..where((t) => t.name.equals('Pike push-up'))).getSingle();
    expect(pike.formCues, startsWith('Posición de V invertida'));
    expect(pike.progressionNote, 'pike → pies elevados → HSPU asistido → HSPU');
    expect(pike.tracksLoad, isFalse);
    final bulgara =
        await (migrated.select(migrated.exercises)..where((t) => t.name.equals('Sentadilla búlgara'))).getSingle();
    expect(bulgara.tracksLoad, isTrue, reason: 'la búlgara progresa con carga');

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
    expect(await userVersion(migrated), 9);
    final repo = ReminderRepository(migrated);
    await repo.ensureDefaults(); // lo que hace el arranque
    final settings = await repo.settings();
    expect(settings[ReminderKind.sesion]!.enabled, isTrue);
    expect(settings[ReminderKind.sesion]!.hour, 15);
    expect(settings[ReminderKind.proteina]!.hour, 20);
    expect(settings[ReminderKind.proteina]!.threshold, 100);
    expect(settings[ReminderKind.calorias]!.threshold, 1800);
    expect(settings[ReminderKind.comidasSinRegistrar]!.hour, 22);
    expect(settings.length, ReminderKind.values.length);
    expect(await migrated.select(migrated.sessions).get(), hasLength(1), reason: 'solo se tocan los avisos');
    await migrated.close();
  });

  test('una base del esquema 6 llega al 9: las sesiones viejas quedan con descanso 0', () async {
    await buildOldSchema(6);
    final old = AppDatabase(NativeDatabase(file));
    await old.customStatement(
        "insert into sessions (date, type, total_sec, warmup_sec, cooldown_sec) values ('2026-09-20', 'circuito', 1200, 360, 180)");
    await old.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final session = await migrated.select(migrated.sessions).getSingle();
    expect(session.totalSec, 1200);
    expect(session.restSec, 0);
    expect(await userVersion(migrated), 9);
    await migrated.close();
  });
}
