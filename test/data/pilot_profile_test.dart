import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/corrections_29sep.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/history_import.dart' show corrections7Oct;
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/repositories/goal_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/seed_foods.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/goal_history.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/sqlite_host.dart';

/// Plan 022: un usuario nuevo no hereda nada del dueño y el existente sigue
/// igual. SQLite real (AppDatabase) con personas ficticias.
void main() {
  // Sin suprimir el aviso de Drift (plan 024): bases múltiples quedan visibles.
  setUpAll(useHostSqlite);

  final confirmedAt = DateTime(2026, 10, 10, 9, 30);
  final today = dateOnly(confirmedAt);

  late AppDatabase db;
  setUp(() => db = openInMemoryDatabase());
  tearDown(() => db.close());

  Future<Map<String, int>> counts(AppDatabase db) async => {
        for (final t in db.allTables)
          t.actualTableName:
              (await db.customSelect('select count(*) as n from "${t.actualTableName}"').getSingle()).data['n'] as int,
      };

  /// Lo que hace el arranque de main.dart con una base nueva.
  Future<void> startup(AppDatabase db) async {
    await seedFoodsIfEmpty(db);
    await ReminderRepository(db).ensureDefaults();
  }

  Future<List<GoalVersionRow>> versions(AppDatabase db) => db.select(db.goalVersions).get();

  group('instalación nueva', () {
    test('una instalación nueva no tiene vigencias aceptadas antes del alta', () async {
      expect(await db.select(db.goalVersions).get(), isEmpty,
          reason: 'pending: ninguna meta se acepta hasta confirmar el alta');
    });

    test('arranca new/pending, con referencias compartidas y sin nada personal ni del dueño', () async {
      await startup(db);
      final status = await ProfileRepository(db).setupStatus();
      expect((status.origin, status.state, status.confirmedAt, status.handoffConsentAt),
          (ProfileOrigin.newInstall, SetupState.pending, null, null));
      expect(await personalTablesWithRows(db), isEmpty);
      expect(await db.select(db.planVersions).get(), isEmpty, reason: 'sin plan del dueño');
      expect(await db.select(db.foods).get(), isNotEmpty, reason: 'el catálogo es referencia compartida');
      expect(await db.select(db.mealTemplates).get(), isNotEmpty);
      final p = await ProfileRepository(db).get();
      expect(p.startDate, isNot('2026-08-26'), reason: 'no hereda la fecha del dueño');
      expect((p.heightCm, p.birthDate, p.nextMeasurementDate), (null, null, null));
    });
  });

  group('alta', () {
    SetupDraft draft() => SetupDraft(startDate: DateTime(2026, 9, 1), stepsTarget: 6500);

    test('confirmar escribe perfil, seis aceptaciones desde la confirmación real y ready', () async {
      final d = draft()
        ..heightCm = 171.5
        ..birthDate = DateTime(1990, 5, 4)
        ..proteinMin = 110
        ..proteinPreferred = 140
        ..kcalWeekly = 2200
        ..kcalFootball = null
        ..kcalFloor = null;
      expect(await ProfileRepository(db).confirmSetup(d, now: confirmedAt), isTrue);

      final p = await ProfileRepository(db).get();
      expect((p.startDate, p.heightCm, p.birthDate, p.stepsTarget), ('2026-09-01', 171.5, '1990-05-04', 6500));
      expect((p.proteinMin, p.proteinMax, p.kcalTarget, p.kcalTargetFootball), (110, 140, 2200, null));
      final status = await ProfileRepository(db).setupStatus();
      expect((status.ready, status.confirmedAt), (true, confirmedAt));

      final rows = await versions(db);
      expect({
        for (final r in rows) r.metric: r.value
      }, {
        'pasos': 6500.0,
        'proteinaMin': 110.0,
        'proteinaMax': 140.0,
        'kcal': 2200.0,
        'kcalFutbol': null,
        'kcalFloor': null,
      });
      expect(
          rows.map((r) => (r.effectiveFrom, r.acceptedAt, r.origin)).toSet(), {('2026-10-10', '2026-10-10', 'inicio')},
          reason: 'la vigencia es la confirmación, no la fecha histórica elegida');
      final h = await GoalRepository(db).history();
      expect(h.on(GoalMetric.proteinaMin, DateTime(2026, 9, 15)), isNull,
          reason: 'el inicio elegido (1 sep) no vuelve retroactiva la meta');
      expect(await db.select(db.coachProposals).get(), isEmpty);
    });

    test('confirmar dos veces no duplica', () async {
      final repo = ProfileRepository(db);
      final results = await Future.wait(
          [repo.confirmSetup(draft(), now: confirmedAt), repo.confirmSetup(draft(), now: confirmedAt)]);
      expect(results.where((confirmed) => confirmed), hasLength(1), reason: 'sólo una confirma');
      expect(await repo.confirmSetup(draft(), now: confirmedAt), isFalse);
      expect(await versions(db), hasLength(6));
    });

    test('un fallo dentro de la transacción revierte todo y deja pending', () async {
      final before = await counts(db);
      final profile = await ProfileRepository(db).get();
      await db.customStatement(
          "CREATE TRIGGER falla BEFORE INSERT ON goal_versions WHEN NEW.metric = 'kcalFloor' BEGIN SELECT RAISE(ABORT, 'fallo simulado'); END");
      await expectLater(ProfileRepository(db).confirmSetup(draft(), now: confirmedAt), throwsA(anything));
      await db.customStatement('DROP TRIGGER falla');
      expect(await counts(db), before);
      expect(await ProfileRepository(db).get(), profile, reason: 'perfil, metas y estado intactos');
      expect((await ProfileRepository(db).setupStatus()).pending, isTrue);
    });

    test('datos inválidos no escriben nada', () async {
      final before = await counts(db);
      for (final bad in [
        draft()..stepsTarget = 0,
        draft()..startDate = addDays(today, 1),
        draft()
          ..proteinMin = 150
          ..proteinPreferred = 120,
        draft()
          ..kcalWeekly = 1800
          ..kcalFloor = 2000,
        draft()..heightCm = 20,
      ]) {
        await expectLater(
            ProfileRepository(db).confirmSetup(bad, now: confirmedAt), throwsA(isA<SetupValidationException>()));
      }
      expect(await counts(db), before);
    });

    test('cancelar o reiniciar la app deja pending (base en archivo, reabierta)', () async {
      final dir = Directory.systemTemp.createTempSync('seguimiento_022_cancel');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/seguimiento.sqlite');
      var a = AppDatabase(NativeDatabase(file));
      await startup(a);
      // El usuario abre el alta, escribe y cancela: no hay ninguna escritura.
      await a.close();
      a = AppDatabase(NativeDatabase(file));
      expect((await ProfileRepository(a).setupStatus()).pending, isTrue);
      expect(await versions(a), isEmpty);
      await a.close();
    });

    test('«Más adelante»: decisión sin meta conocida, sin imponer 130/160/2400/2000', () async {
      final d = draft()..clearNutrition();
      await ProfileRepository(db).confirmSetup(d, now: confirmedAt);
      final h = await GoalRepository(db).history();
      for (final m in [
        GoalMetric.proteinaMin,
        GoalMetric.proteinaMax,
        GoalMetric.kcal,
        GoalMetric.kcalFutbol,
        GoalMetric.kcalFloor
      ]) {
        final at = h.on(m, today)!;
        expect((at.known, at.value), (true, null), reason: '$m: decisión sin meta, no desconocido ni default');
      }
      expect(h.on(GoalMetric.pasos, today)!.value, 6500);
      expect(h.on(GoalMetric.proteinaMin, addDays(today, -1)), isNull, reason: 'antes del alta: desconocido');
    });

    test('un número igual al valor de ejemplo también queda aceptado', () async {
      final d = SetupDraft(startDate: today)
        ..proteinMin = 130
        ..proteinPreferred = 160
        ..kcalWeekly = 2400
        ..kcalFloor = 2000;
      await ProfileRepository(db).confirmSetup(d, now: confirmedAt);
      expect({
        for (final r in await versions(db)) r.metric: r.value
      }, {
        'pasos': 5000.0,
        'proteinaMin': 130.0,
        'proteinaMax': 160.0,
        'kcal': 2400.0,
        'kcalFutbol': null,
        'kcalFloor': 2000.0,
      });
    });

    test('un alta pendiente con registros personales no se confirma', () async {
      await BodyRepository(db).addWeight(today, 70);
      await expectLater(
          ProfileRepository(db).confirmSetup(draft(), now: confirmedAt), throwsA(isA<InvalidSetupException>()));
      expect(await versions(db), isEmpty);
      expect((await ProfileRepository(db).setupStatus()).pending, isTrue);
    });
  });

  group('metas después del alta', () {
    Future<void> confirmLater() =>
        ProfileRepository(db).confirmSetup(SetupDraft(startDate: today)..clearNutrition(), now: confirmedAt);

    test('editar la estatura no acepta metas', () async {
      await confirmLater();
      await ProfileRepository(db).save(const ProfilesCompanion(heightCm: Value(180)));
      expect(await versions(db), hasLength(6));
    });

    test('null → 130 escribe la aceptación aunque la proyección del perfil ya diga 130', () async {
      await confirmLater();
      expect((await ProfileRepository(db).get()).proteinMin, 130, reason: 'proyección interna, no elección');
      await ProfileRepository(db).save(const ProfilesCompanion(proteinMin: Value(130)));
      final h = await GoalRepository(db).history();
      expect(h.current(GoalMetric.proteinaMin, today)!.value, 130);
      expect(await versions(db), hasLength(7));
      // Repetir el mismo valor ya aceptado no duplica.
      await ProfileRepository(db).save(const ProfilesCompanion(proteinMin: Value(130)));
      expect(await versions(db), hasLength(7));
    });

    test('kcal de fútbol null hereda la semanal conocida; semanal null no inventa objetivo', () async {
      await ProfileRepository(db).confirmSetup(SetupDraft(startDate: today)..kcalWeekly = 2300, now: confirmedAt);
      final h = await GoalRepository(db).history();
      expect(h.on(GoalMetric.kcalFutbol, today)!.value, isNull);
      expect(h.on(GoalMetric.kcal, today)!.value, 2300, reason: 'el fútbol hereda esta, conocida');
      expect(h.on(GoalMetric.kcalFloor, today)!.value, isNull, reason: 'el piso es opcional');
    });

    test('el piso de kcal es una meta del mismo core: editarlo deja vigencia', () async {
      await ProfileRepository(db).confirmSetup(SetupDraft(startDate: today)..kcalWeekly = 2300, now: confirmedAt);
      await ProfileRepository(db).save(const ProfilesCompanion(kcalFloor: Value(1700)));
      final h = await GoalRepository(db).history();
      expect(h.current(GoalMetric.kcalFloor, DateTime.now())!.value, 1700);
    });
  });

  group('estado inválido', () {
    for (final (column, value) in [
      ('profile_origin', 'owner'),
      ('setup_state', 'listo'),
      ('setup_confirmed_at', 'ayer'),
    ]) {
      test('$column = $value es un error visible, no se corrige', () async {
        await db.customStatement("UPDATE profiles SET $column = '$value'");
        await expectLater(ProfileRepository(db).setupStatus(), throwsA(isA<InvalidSetupException>()));
      });
    }

    test('legacyUnknown pendiente y new listo sin confirmación no son válidos', () async {
      await db.customStatement("UPDATE profiles SET profile_origin = 'legacyUnknown'");
      await expectLater(ProfileRepository(db).setupStatus(), throwsA(isA<InvalidSetupException>()));
      await db.customStatement("UPDATE profiles SET profile_origin = 'new', setup_state = 'ready'");
      await expectLater(ProfileRepository(db).setupStatus(), throwsA(isA<InvalidSetupException>()));
    });
  });

  group('correcciones del traspaso', () {
    late Directory dir;
    late File backup;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('seguimiento_022_corr');
      backup = await db.exportTo('${dir.path}/respaldo.sqlite');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('aplicar correcciones del traspaso sin consentimiento no escribe nada', () async {
      final before = await counts(db);
      try {
        await applyPendingCorrections(db);
      } on Object {
        // El rechazo es lo esperado; lo que importa es que no haya escrituras.
      }
      expect(await counts(db), before, reason: 'ni nuevo ni legado autorizan sembrar sesiones/medidas/pasos');
    });

    test('ni legado, ni nuevo listo, ni flags de descartado autorizan; con respaldo tampoco', () async {
      final flags = LocalFlags(File('${dir.path}/flags.json'));
      for (final k in [
        FlagKeys.corrections29SepDismissed,
        FlagKeys.corrections5OctDismissed,
        FlagKeys.corrections7OctDismissed
      ]) {
        await flags.set(k, true);
      }
      await ProfileRepository(db).confirmSetup(SetupDraft(startDate: today)..clearNutrition(), now: confirmedAt);
      final asNew = await counts(db);
      await expectLater(applyPendingCorrections(db, null, backup), throwsA(isA<CorrectionsNotAuthorized>()));
      for (final c in allCorrections) {
        await expectLater(c.apply(db), throwsA(isA<CorrectionsNotAuthorized>()), reason: c.id);
      }
      expect(await counts(db), asNew);

      await db.customStatement("UPDATE profiles SET profile_origin = 'legacyUnknown', setup_confirmed_at = NULL");
      final asLegacy = await counts(db);
      await expectLater(applyPendingCorrections(db, null, backup), throwsA(isA<CorrectionsNotAuthorized>()));
      await expectLater(corrections7Oct.first.apply(db), throwsA(isA<CorrectionsNotAuthorized>()));
      expect(await counts(db), asLegacy);
    });

    test('con consentimiento pero sin respaldo previo válido: cero escrituras', () async {
      await db.customStatement("UPDATE profiles SET profile_origin = 'legacyUnknown', setup_state = 'ready'");
      await ProfileRepository(db).recordHandoffConsent(now: confirmedAt);
      final before = await counts(db);
      await expectLater(applyPendingCorrections(db), throwsA(isA<CorrectionsNotAuthorized>()));
      await expectLater(applyPendingCorrections(db, null, File('${dir.path}/no-existe.sqlite')),
          throwsA(isA<CorrectionsNotAuthorized>()));
      expect(await counts(db), before);
    });

    test('el consentimiento se revalida dentro de la transacción', () async {
      await db.customStatement("UPDATE profiles SET profile_origin = 'legacyUnknown', setup_state = 'ready'");
      await ProfileRepository(db).recordHandoffConsent(now: confirmedAt);
      // Retirado entre la pantalla y la escritura: la transacción lo vuelve a leer.
      await db.customStatement('UPDATE profiles SET handoff_consent_at = NULL');
      final before = await counts(db);
      await expectLater(applyPendingCorrections(db, null, backup), throwsA(isA<CorrectionsNotAuthorized>()));
      expect(await counts(db), before);
    });

    test('el dueño conserva la recuperación: consentimiento fechado + respaldo aplica', () async {
      await db.customStatement("UPDATE profiles SET profile_origin = 'legacyUnknown', setup_state = 'ready'");
      await ProfileRepository(db).recordHandoffConsent(now: confirmedAt);
      expect((await ProfileRepository(db).setupStatus()).handoffConsentAt, confirmedAt);
      expect(await applyPendingCorrections(db, null, backup), greaterThan(0));
      expect(await db.select(db.sessions).get(), isNotEmpty);
    });
  });

  group('respaldo con alta', () {
    late Directory root;
    late DatabaseHost a;
    late DatabaseHost b;
    late Directory dirA;
    late Directory dirB;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('seguimiento_022_zip_');
      dirA = Directory('${root.path}/A')..createSync();
      dirB = Directory('${root.path}/B')..createSync();
      a = DatabaseHost(File('${dirA.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
      b = DatabaseHost(File('${dirB.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
      await a.db.customSelect('select 1').get();
      await b.db.customSelect('select 1').get();
    });

    tearDown(() async {
      await a.db.close();
      await b.db.close();
      root.deleteSync(recursive: true);
    });

    Future<SetupStatus> statusOf(DatabaseHost h) => ProfileRepository(h.db).setupStatus();

    test('dos personas ficticias quedan aisladas y un ZIP pending/ready conserva estado, origen y nulos', () async {
      // Persona A confirma con «Más adelante» y registra un peso.
      await ProfileRepository(a.db)
          .confirmSetup(SetupDraft(startDate: DateTime(2026, 9, 7))..clearNutrition(), now: confirmedAt);
      await BodyRepository(a.db).addWeight(today, 64);
      // Persona B confirma sus propias metas.
      await ProfileRepository(b.db)
          .confirmSetup(SetupDraft(startDate: today, stepsTarget: 9000)..proteinMin = 90, now: confirmedAt);
      expect(await b.db.select(b.db.bodyWeights).get(), isEmpty, reason: 'B no ve nada de A');
      expect((await ProfileRepository(b.db).get()).stepsTarget, 9000);

      final zipA = await BackupArchive(host: a, documents: dirA).exportTo('${root.path}/a.zip');
      await BackupArchive(host: b, documents: dirB).restoreFrom(zipA.file);
      final s = await statusOf(b);
      expect((s.origin, s.state, s.confirmedAt), (ProfileOrigin.newInstall, SetupState.ready, confirmedAt));
      final h = await GoalRepository(b.db).history();
      expect((h.on(GoalMetric.proteinaMin, today)!.known, h.on(GoalMetric.proteinaMin, today)!.value), (true, null),
          reason: 'el ZIP23 porta las decisiones null');
      expect((await ProfileRepository(b.db).get()).startDate, '2026-09-07');

      // Un ZIP de un alta pendiente se restaura pendiente: no se pide ni se salta nada.
      final fresh = DatabaseHost(
          File('${root.path}/C/seguimiento.sqlite')..parent.createSync(), (f) => AppDatabase(NativeDatabase(f)));
      addTearDown(() => fresh.db.close());
      await seedFoodsIfEmpty(fresh.db);
      final zipPending =
          await BackupArchive(host: fresh, documents: fresh.file.parent).exportTo('${root.path}/pending.zip');
      await BackupArchive(host: b, documents: dirB).restoreFrom(zipPending.file);
      expect((await statusOf(b)).pending, isTrue);
      expect(await b.db.select(b.db.goalVersions).get(), isEmpty);
    });

    test('un ZIP23 con origen/estado inválido se rechaza antes de tocar base, fotos y flags', () async {
      await ProfileRepository(b.db).confirmSetup(SetupDraft(startDate: today), now: confirmedAt);
      File('${dirB.path}/fotos/vieja.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([7]);
      File('${dirB.path}/flags.json').writeAsStringSync('flags-B');
      final bytes = b.file.readAsBytesSync();
      final beforeCounts = await counts(b.db);

      for (final (column, value) in [('profile_origin', 'owner'), ('setup_state', 'listo')]) {
        await a.db.customStatement("UPDATE profiles SET $column = '$value'");
        final bad = await BackupArchive(host: a, documents: dirA).exportTo('${root.path}/bad-$column.zip');
        await expectLater(BackupArchive(host: b, documents: dirB).prepare(bad.file), throwsA(isA<RestoreException>()),
            reason: column);
        await a.db.customStatement("UPDATE profiles SET profile_origin = 'new', setup_state = 'pending'");
      }
      // Pendiente con registros personales: tampoco.
      await BodyRepository(a.db).addWeight(today, 66);
      final inconsistent = await BackupArchive(host: a, documents: dirA).exportTo('${root.path}/inconsistent.zip');
      await expectLater(BackupArchive(host: b, documents: dirB).restoreFrom(inconsistent.file),
          throwsA(isA<RestoreException>().having((e) => e.message, 'message', contains('alta'))));

      expect(b.file.readAsBytesSync(), bytes, reason: '0 cambios en la base');
      expect(await counts(b.db), beforeCounts);
      expect(File('${dirB.path}/fotos/vieja.jpg').readAsBytesSync(), [7]);
      expect(File('${dirB.path}/flags.json').readAsStringSync(), 'flags-B');
      expect((await statusOf(b)).ready, isTrue);
    });

    test('un fallo tardío revierte al alta anterior con sus fotos', () async {
      await ProfileRepository(b.db).confirmSetup(SetupDraft(startDate: today, stepsTarget: 7100), now: confirmedAt);
      File('${dirB.path}/fotos/vieja.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([9]);
      // A pendiente (su ZIP es válido): el fallo es tardío, al reabrir B.
      final zipA = await BackupArchive(host: a, documents: dirA).exportTo('${root.path}/a.zip');
      var fail = true;
      final file = b.file;
      b = DatabaseHost(file, (f) {
        if (f.path == file.path && fail) {
          fail = false;
          throw StateError('fallo tardío sintético');
        }
        return AppDatabase(NativeDatabase(f));
      }, initial: b.db);
      await expectLater(
          BackupArchive(host: b, documents: dirB).restoreFrom(zipA.file), throwsA(isA<RestoreException>()));
      final s = await statusOf(b);
      expect((s.ready, (await ProfileRepository(b.db).get()).stepsTarget), (true, 7100),
          reason: 'vuelve el alta lista anterior, no la pendiente del ZIP');
      expect(File('${dirB.path}/fotos/vieja.jpg').readAsBytesSync(), [9]);
    });

    test('un SQLite 22 restaurado migra a legacyUnknown/ready sin pedir configurar', () async {
      final legacy = File('${root.path}/legacy22.sqlite');
      final raw = AppDatabase(NativeDatabase(legacy));
      await raw.customSelect('select 1').get();
      await raw.close();
      // Lleva la base al esquema 22 real en estructura: sin las columnas del 23.
      final s = sqlite.sqlite3.open(legacy.path);
      for (final c in ['profile_origin', 'setup_state', 'setup_confirmed_at', 'handoff_consent_at']) {
        s.execute('alter table profiles drop column $c');
      }
      s.execute("update profiles set start_date = '2026-08-26', steps_target = 7500");
      s.execute("insert into body_weights (date, kg, fasted) values ('2026-10-01', 80.2, 1)");
      s.execute('pragma user_version = 22');
      s.dispose();
      await BackupArchive(host: b, documents: dirB).restoreFrom(legacy);
      final st = await statusOf(b);
      expect((st.origin, st.state, st.confirmedAt, st.handoffConsentAt),
          (ProfileOrigin.legacyUnknown, SetupState.ready, null, null));
      expect((await ProfileRepository(b.db).get()).startDate, '2026-08-26');
      expect((await b.db.select(b.db.bodyWeights).getSingle()).kg, 80.2);
    });
  });
}
