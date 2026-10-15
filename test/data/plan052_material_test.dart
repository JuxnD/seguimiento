import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/plan_v32_template.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/equipment_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/fitness_test_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/training_repository.dart';
import 'package:seguimiento/domain/core_ladders.dart' show hollowHold;
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/equipment.dart';
import 'package:seguimiento/domain/fitness_test.dart';
import 'package:seguimiento/domain/test_protocol.dart';
import '../support/sqlite_host.dart';

/// Plan 052 (§16.27.4): material en Ajustes, requisitos por ejercicio y la
/// prueba que espera a la colchoneta. Fechas ficticias: bloque v3.2 desde el
/// lunes 4 feb 2030; sin datos personales.
void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  late PlanRepository plan;
  late TrainingRepository training;
  late Directory dir;
  late LocalFlags flags;
  late EquipmentRepository equipment;
  final start = DateTime(2030, 2, 4);
  const pino = 'Pino pecho a la pared';

  setUp(() async {
    db = openInMemoryDatabase();
    final ex = ExerciseRepository(db);
    plan = PlanRepository(db, ex);
    training = TrainingRepository(db, ex);
    await activatePlanV32(db, plan, start);
    dir = Directory.systemTemp.createTempSync('plan052-material');
    flags = LocalFlags(File('${dir.path}/flags.json'));
    equipment = EquipmentRepository(db, flags: flags);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<PlanDayDraft> day(DateTime date) async {
    final view = (await plan.dayFor(date))!;
    return training.withV31Blocks(
        view.day, date, await training.blockDay(view, date),
        planche: false);
  }

  List<String> names(PlanDayDraft d) => [for (final e in d.exercises) e.name];

  test(
      'sin filas: barra, banda y báscula "tengo"; colchoneta y mochila "no tengo"; paralelas y anillas según su bandera',
      () async {
    var s = await equipment.statuses();
    expect(
        [
          s[EquipmentKeys.bar],
          s[EquipmentKeys.band],
          s[EquipmentKeys.scale]
        ],
        everyElement(EquipmentStatus.tengo));
    expect(s[EquipmentKeys.mat], EquipmentStatus.noTengo);
    expect(s[EquipmentKeys.backpack], EquipmentStatus.noTengo);
    expect(s[EquipmentKeys.parallettes], EquipmentStatus.noTengo);
    expect(s[EquipmentKeys.rings], EquipmentStatus.noTengo);

    await flags.set(FlagKeys.hasParallettes, true);
    s = await equipment.statuses();
    expect(s[EquipmentKeys.parallettes], EquipmentStatus.tengo,
        reason: 'sin fila, la bandera que ya existía');
    expect(s[EquipmentKeys.rings], EquipmentStatus.noTengo);
    expect(s[EquipmentKeys.mat], EquipmentStatus.noTengo,
        reason: 'la colchoneta nunca se inventa');
    expect(await db.select(db.equipmentItems).get(), isEmpty,
        reason: 'leer no guarda filas');
  });

  test('Material ↔ banderas: el inventario manda y Plan lo actualiza',
      () async {
    // Desde Material.
    await equipment.set(EquipmentKeys.rings, EquipmentStatus.tengo);
    expect(flags.get<bool>(FlagKeys.hasRings), isTrue);
    await equipment.set(EquipmentKeys.rings, EquipmentStatus.enCompra);
    expect(flags.get<bool>(FlagKeys.hasRings), isFalse);

    // Desde el interruptor de Plan.
    await equipment.setFromToggle(EquipmentKeys.parallettes, true);
    expect((await equipment.statuses())[EquipmentKeys.parallettes],
        EquipmentStatus.tengo);
    expect(flags.get<bool>(FlagKeys.hasParallettes), isTrue);
    await equipment.setFromToggle(EquipmentKeys.rings, false);
    expect((await equipment.statuses())[EquipmentKeys.rings],
        EquipmentStatus.enCompra,
        reason: 'apagar conserva "en compra"');

    // Tras restaurar: una bandera vieja no gana a la fila guardada.
    await flags.set(FlagKeys.hasParallettes, false);
    expect((await equipment.statuses(parallettes: false))[
            EquipmentKeys.parallettes],
        EquipmentStatus.tengo);
    await equipment.syncFlagsFromInventory();
    expect(flags.get<bool>(FlagKeys.hasParallettes), isTrue);

    // Mochila: sí/no y kg.
    await equipment.set(EquipmentKeys.backpack, EquipmentStatus.tengo, kg: 8);
    expect((await equipment.rows())[EquipmentKeys.backpack]!.kg, 8);
    await expectLater(
        equipment.set('trx', EquipmentStatus.tengo), throwsArgumentError);
  });

  test('requisitos declarados: obligatorio y recomendado', () {
    EquipmentNeed need(String name, {String? variant}) =>
        equipmentNeeds(name, variantKey: variant).single;
    expect((need(pino).key, need(pino).required), (EquipmentKeys.mat, true));
    for (final name in [
      hollowHold,
      'Hollow rocks',
      'Tuck-up',
      'Plancha inversa sobre antebrazos',
      'Plancha inversa con pies elevados',
      'Pike push-up con pies elevados',
    ]) {
      expect((need(name).key, need(name).required), (EquipmentKeys.mat, false),
          reason: name);
    }
    for (final name in [
      'Inclinación de planche',
      'Flexión pseudo-planche',
      'Tuck planche',
      'Support hold en paralelas'
    ]) {
      expect((need(name).key, need(name).required),
          (EquipmentKeys.parallettes, true),
          reason: name);
    }
    expect(need('Support hold en paralelas', variant: 'support_rings').key,
        EquipmentKeys.rings);
    for (final name in [
      'Dominadas',
      'Colgarse de la barra',
      'Elevación de piernas colgado',
      'Scap pull-up'
    ]) {
      expect(need(name).key, EquipmentKeys.bar, reason: name);
    }
    expect(need('Pallof press con banda').key, EquipmentKeys.band);
    expect(need('Curl con banda').key, EquipmentKeys.band);
    expect((need('Sóleo sentado con mochila').key,
            need('Sóleo sentado con mochila').required),
        (EquipmentKeys.backpack, false));
    expect(equipmentNeeds('Flexiones'), isEmpty);
  });

  test(
      'sin colchoneta el pino sale del día con su nota (y Hoy la muestra); con ella vuelve',
      () async {
    final dashboard = DashboardRepository(
        db, plan, NutritionRepository(db), ProfileRepository(db));
    final monday = await day(start);
    expect(names(monday), isNot(contains(pino)));
    expect(monday.notes, contains('$pino pendiente: falta colchoneta'));
    final home = await dashboard.today(now: start);
    expect(home.equipmentNotes, ['$pino pendiente: falta colchoneta.']);
    expect(home.blockExercises.join(' '), isNot(contains(pino)));
    expect(home.mainExercises.join(' '), isNot(contains(pino)));

    await equipment.set(EquipmentKeys.mat, EquipmentStatus.enCompra);
    expect((await day(start)).notes,
        contains('$pino pendiente: falta colchoneta (en compra).'));

    await equipment.set(EquipmentKeys.mat, EquipmentStatus.tengo);
    final withMat = await day(start);
    expect(names(withMat), contains(pino));
    expect(withMat.notes ?? '', isNot(contains('pendiente: falta colchoneta')));
    expect((await dashboard.today(now: start)).equipmentNotes, isEmpty);
  });

  test('sin colchoneta el hollow se queda con "Mejor con colchoneta."',
      () async {
    final hollow = (await day(start))
        .exercises
        .singleWhere((e) => e.name == hollowHold);
    expect(hollow.notes, contains('Mejor con colchoneta.'));
    expect(hollow.notes, contains('Lumbar pegada al suelo'),
        reason: 'conserva la nota del plan');
    await equipment.set(EquipmentKeys.mat, EquipmentStatus.tengo);
    expect(
        (await day(start))
            .exercises
            .singleWhere((e) => e.name == hollowHold)
            .notes,
        isNot(contains('Mejor con colchoneta')));
  });

  test(
      'día sin bloques: el mismo filtro, sin tocar el plan guardado; con todo, el mismo día',
      () {
    final circuit = PlanDayDraft(
        weekday: DateTime.friday,
        type: DayType.progresion,
        targetRounds: 10,
        notes: 'Circuito.',
        exercises: [
          PlanExerciseDraft(name: 'Dominadas', repsMin: 5),
          PlanExerciseDraft(name: 'Flexiones', repsMin: 10),
          PlanExerciseDraft(
              name: 'Sóleo sentado con mochila', sets: 2, repsMin: 15),
          PlanExerciseDraft(name: 'Scap pull-up', sets: 2, repsMin: 8),
        ]);
    final noBar = {
      for (final item in equipmentCatalog)
        item.key: item.defaultStatus ?? EquipmentStatus.noTengo
    }..[EquipmentKeys.bar] = EquipmentStatus.noTengo;
    final out = applyEquipmentDetailed(circuit, noBar);
    expect(names(out.day),
        ['Flexiones', 'Sóleo sentado con mochila', 'Scap pull-up']);
    expect(out.pending, ['Dominadas pendiente: falta barra.']);
    expect(out.day.notes, 'Circuito. · Dominadas pendiente: falta barra.');
    expect(out.day.targetRounds, 10);
    expect(out.day.exercises[1].notes, contains('Sin mochila con peso'));
    expect(out.day.exercises[2].notes, contains('deslizamientos en la pared'),
        reason: 'con alternativa se queda y la dice');
    expect(names(circuit), hasLength(4), reason: 'no toca el día del plan');
    expect(circuit.exercises[2].notes, isNull);

    final all = {
      for (final item in equipmentCatalog) item.key: EquipmentStatus.tengo
    };
    expect(identical(applyEquipment(circuit, all), circuit), isTrue);
  });

  test(
      'test pendiente por colchoneta: aparece sólo con colchoneta y se va al medirlo en un intento posterior',
      () async {
    final tests = FitnessTestRepository(db);
    final first = await tests.save(
        date: start,
        round: 1,
        part: TestPart.torso,
        protocol: TestProtocolId.v32_13,
        scheme: 'v3.2',
        blockStart: start,
        totalSec: 0,
        results: const [TestResult(round: 1, item: 'pullup', value: 8)]);
    await db.into(db.fitnessTestPending).insert(
        FitnessTestPendingCompanion.insert(
            attemptId: first,
            item: 'wall_handstand',
            reason: 'equipo',
            requires: const Value('mat')));
    // Una pendiente sin material no es de esta tarjeta.
    await db.into(db.fitnessTestPending).insert(
        FitnessTestPendingCompanion.insert(
            attemptId: first, item: 'dips', reason: 'dolor'));
    final repo = EquipmentRepository(db);
    expect(await repo.pendingReadyForEquipment(), isEmpty,
        reason: 'sin colchoneta no se ofrece');
    await repo.set(EquipmentKeys.mat, EquipmentStatus.enCompra);
    expect(await repo.pendingReadyForEquipment(), isEmpty);

    await repo.set(EquipmentKeys.mat, EquipmentStatus.tengo);
    final ready = (await repo.pendingReadyForEquipment()).single;
    expect(ready.itemName, pino);
    expect(ready.attempt.id, first);
    expect(ready.part, TestPart.torso);
    expect(ready.requiresLabel, 'colchoneta');

    // Otro protocolo no la cierra.
    await tests.save(
        date: start.add(const Duration(days: 1)),
        round: 1,
        part: TestPart.torso,
        totalSec: 0,
        results: const [
          TestResult(round: 1, item: 'wall_handstand', value: 20)
        ]);
    expect(await repo.pendingReadyForEquipment(), hasLength(1));

    // Medido en un intento posterior del mismo protocolo: resuelto.
    await tests.save(
        date: start.add(const Duration(days: 7)),
        round: 1,
        part: TestPart.torso,
        protocol: TestProtocolId.v32_13,
        scheme: 'v3.2',
        blockStart: start,
        totalSec: 0,
        results: const [
          TestResult(round: 1, item: 'wall_handstand', value: 25)
        ]);
    expect(await repo.pendingReadyForEquipment(), isEmpty);
  });
}
