import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/report_repository.dart';
import 'package:seguimiento/data/repositories/supplement_repository.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/report/report_builder.dart';
import 'package:seguimiento/domain/supplements.dart';

import '../support/sqlite_host.dart';

/// Plan 052 (§16.27.5): creatina con envase de 68 tomas. Lo que queda, el
/// aviso con 7 o menos, la constancia, las 4 semanas de agua y la toma del
/// día sin duplicados. Fechas ficticias.
void main() {
  late AppDatabase db;
  late SupplementRepository repo;
  DateTime d(int month, int day) => DateTime(2026, month, day);

  setUpAll(useHostSqlite);
  setUp(() {
    db = openInMemoryDatabase();
    repo = SupplementRepository(db);
  });
  tearDown(() => db.close());

  Future<SupplementRow> creatine({DateTime? start, int? servings = 68, bool active = true}) async {
    final id = await repo.add(
        name: 'Creatina',
        dose: '1 cucharada (6 g ≈ 5 g de creatina)',
        servingsPerPack: servings,
        start: start,
        active: active);
    return (await repo.all()).singleWhere((s) => s.id == id);
  }

  Future<int> logCount() async => (await db.select(db.supplementLogs).get()).length;

  test('alta: nombre y dosis sin espacios de sobra; inicio vacío hasta empezar', () async {
    final id = await repo.add(name: '  Creatina ', dose: ' 1 cucharada ', servingsPerPack: 68);
    final row = (await repo.all()).single;
    expect((row.id, row.name, row.dose, row.servingsPerPack, row.startDate, row.active),
        (id, 'Creatina', '1 cucharada', 68, null, true));
    expect(await repo.remaining(row), isNull, reason: 'sin inicio no se cuenta nada');
    expect(await repo.dueOn(d(10, 20)), isEmpty, reason: 'sin inicio no aparece en la mañana');

    await repo.edit(id, name: 'Creatina', dose: '1 cucharada', servingsPerPack: 68, start: d(10, 15), active: true);
    expect((await repo.all()).single.startDate, '2026-10-15');
    expect(() => repo.add(name: ' ', dose: ''), throwsArgumentError);
    expect(() => repo.add(name: 'Creatina', dose: '', servingsPerPack: 0), throwsArgumentError);
  });

  test('marcar la toma es idempotente y desmarcar la quita', () async {
    final s = await creatine(start: d(10, 15));
    await repo.setTaken(s.id, d(10, 16), true);
    await repo.setTaken(s.id, d(10, 16), true);
    expect(await logCount(), 1);
    expect(await repo.logsOn(d(10, 16)), {s.id});
    await repo.setTaken(s.id, d(10, 16), false);
    await repo.setTaken(s.id, d(10, 16), false);
    expect(await logCount(), 0);
    expect(await repo.toggle(s.id, d(10, 17)), isTrue);
    expect(await repo.logsOn(d(10, 17)), {s.id});
    expect(await repo.toggle(s.id, d(10, 17)), isFalse);
    expect(await repo.logsOn(d(10, 17)), isEmpty);
  });

  test('en la mañana: sólo activos que ya empezaron ese día', () async {
    final s = await creatine(start: d(10, 15));
    expect(await repo.dueOn(d(10, 14)), isEmpty);
    expect([for (final r in await repo.dueOn(d(10, 15))) r.id], [s.id]);
    await repo.setActive(s.id, false);
    expect(await repo.dueOn(d(10, 20)), isEmpty);
  });

  test('quedan 68 − tomas desde el inicio; aviso con 7 o menos y al acabarse', () async {
    final s = await creatine(start: d(10, 15));
    // Una toma anotada antes del inicio no gasta el envase.
    await repo.setTaken(s.id, d(10, 10), true);
    expect(await repo.remaining(s), 68);
    for (var i = 0; i < 60; i++) {
      await repo.setTaken(s.id, addDays(d(10, 15), i), true);
    }
    expect(await repo.remaining(s), 8);
    expect(stockMessage(s.name, 8), isNull, reason: '8 tomas: todavía no avisa');
    expect((await repo.stock()).single.message, isNull);

    await repo.setTaken(s.id, addDays(d(10, 15), 60), true);
    expect(await repo.remaining(s), 7);
    expect((await repo.stock()).single.message, 'Te quedan 7 tomas de Creatina');

    for (var i = 61; i < 67; i++) {
      await repo.setTaken(s.id, addDays(d(10, 15), i), true);
    }
    expect(await repo.remaining(s), 1);
    expect((await repo.stock()).single.message, 'Te queda 1 toma de Creatina');

    await repo.setTaken(s.id, addDays(d(10, 15), 67), true);
    await repo.setTaken(s.id, addDays(d(10, 15), 68), true);
    expect(await repo.remaining(s), 0, reason: 'nunca menos de 0');
    expect((await repo.stock()).single.message, startsWith('Se acabaron las tomas de Creatina'));

    await repo.setActive(s.id, false);
    expect(await repo.stock(), isEmpty, reason: 'en pausa no avisa');
  });

  test('constancia: días con toma de los días desde el inicio, sin pasar de hoy', () async {
    final s = await creatine(start: d(10, 15));
    for (final day in [15, 16, 18]) {
      await repo.setTaken(s.id, d(10, day), true);
    }
    final week = await repo.constancy(d(10, 12), d(10, 18), today: d(10, 18));
    expect(week[s], (taken: 3, days: 4));
    final midWeek = await repo.constancy(d(10, 12), d(10, 18), today: d(10, 16));
    expect(midWeek[s], (taken: 2, days: 2), reason: 'los días que no llegan no cuentan');
    final before = await repo.constancy(d(10, 5), d(10, 11), today: d(10, 18));
    expect(before.containsKey(s), isFalse, reason: 'antes del inicio no hay días');
  });

  test('4 semanas de agua: del inicio al día 28; sólo creatina activa', () async {
    final s = await creatine(start: d(10, 15));
    await repo.add(name: 'Omega 3', dose: '1 cápsula', servingsPerPack: 90, start: d(10, 1));
    expect(await repo.creatineWindowOn(d(10, 14)), isNull);
    expect(await repo.creatineWindowOn(d(10, 15)), d(10, 15));
    expect(await repo.creatineWindowOn(d(11, 11)), d(10, 15), reason: 'día 28');
    expect(await repo.creatineWindowOn(d(11, 12)), isNull, reason: 'día 29');
    expect(await repo.creatineWindows(), [(name: 'Creatina', start: d(10, 15), end: d(11, 11))]);
    await repo.setActive(s.id, false);
    expect(await repo.creatineWindowOn(d(10, 20)), isNull);
    expect(isCreatineName('CREATÍNA monohidratada'), isTrue);
    expect(isCreatineName('Omega 3'), isFalse);
  });

  test('informe: constancia y nota del agua en el rango', () async {
    final s = await creatine(start: d(10, 15));
    for (final day in [15, 16, 18]) {
      await repo.setTaken(s.id, d(10, day), true);
    }
    final input = await ReportRepository(db, NutritionRepository(db)).load(d(10, 12), d(10, 18), today: d(10, 18));
    expect(input.supplements.single.logs, {'2026-10-15', '2026-10-16', '2026-10-18'});
    final report = buildReport(input);
    expect(report, contains('- Creatina: 3 de 4 días'));
    expect(report, contains(creatineWaterNote));
    expect(dayKey(input.supplements.single.start!), '2026-10-15');
  });
}
