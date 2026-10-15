import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/seed_plan.dart';
import 'package:seguimiento/domain/enums.dart';

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';

class _Thursday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 10, 15);
}

/// Plan 053, reporte del owner (15 oct): rodó desde el lunes y Hoy siguió
/// con tren superior hasta reabrir la app; probó más días y se acumularon.
void main() {
  setUpAll(useHostSqlite);

  test('rodar y deshacer refrescan el día de Hoy sin reabrir la app', () async {
    final mon = DateTime(2026, 10, 12);
    final db = openInMemoryDatabase();
    await asExistingUser(db, since: mon);
    final plan = PlanRepository(db, ExerciseRepository(db));
    await seedIfEmpty(db, plan);
    await activatePlanV31(db, plan, mon, now: mon);
    final dir = Directory.systemTemp.createTempSync('seguimiento_053_refresh');
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      localFlagsProvider.overrideWithValue(LocalFlags(File('${dir.path}/f.json'))),
      todayProvider.overrideWith(_Thursday.new),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final sub = container.listen(dashboardProvider, (_, __) {});
    addTearDown(sub.close);

    /// Espera (hasta 3 s) a que Hoy muestre `expected`; devuelve lo último.
    Future<DayType?> settled(DayType expected) async {
      DayType? last;
      for (var i = 0; i < 150; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final v = container.read(dashboardProvider);
        if (!v.isLoading && v.hasValue) last = v.value!.dayType;
        if (last == expected) break;
      }
      return last;
    }

    expect(await settled(DayType.trenSuperior), DayType.trenSuperior);
    await plan.rollDay(mon);
    expect(await settled(DayType.piernas), DayType.piernas,
        reason: 'el jueves pasa a piernas en cuanto se rueda');
    await plan.undoWeekRolls(mon);
    expect(await settled(DayType.trenSuperior), DayType.trenSuperior);
  });
}
