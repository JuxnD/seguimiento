import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/repositories/supplement_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/features/home/morning_check_screen.dart';
import 'package:seguimiento/features/settings/health_connect_card.dart';
import 'package:seguimiento/features/settings/settings_screen.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

/// Plan 052 (§16.27.5): alta de la creatina en Ajustes y su toma en el
/// registro de la mañana. Fechas ficticias.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
  }

  // Ajustes tiene indicadores que pumpAndSettle no espera: pasos cortos.
  Future<void> steps(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  testWidgets('Ajustes: agregar la creatina con dosis y envase, sin fecha de inicio', (tester) async {
    await loadTestFonts(tester);
    tester.view.physicalSize = const Size(1400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = openInMemoryDatabase();
    await tester.runAsync(() => db.select(db.profiles).getSingle());
    await tester.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWithValue(db),
      documentsDirProvider.overrideWith((_) => Directory.systemTemp),
      autoBackupsProvider.overrideWith((_) => []),
      healthConnectStateProvider.overrideWith(
          (_) => const HealthConnectState(status: HealthConnectStatus.desconocido, permitted: false, enabled: false)),
      appVersionProvider.overrideWith((_) => '1.22.0'),
      updateCheckProvider.overrideWith((_) => const UpdateCheck(currentVersion: '1.22.0')),
    ], child: const MaterialApp(home: SettingsScreen())));
    await steps(tester);

    expect(find.text('Suplementos'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Agregar suplemento'));
    await tester.tap(find.byTooltip('Agregar suplemento'));
    await steps(tester);
    await tester.enterText(find.byKey(const ValueKey('supplement-name')), 'Creatina');
    await tester.enterText(find.byKey(const ValueKey('supplement-dose')), '1 cucharada (6 g ≈ 5 g de creatina)');
    await tester.enterText(
        find.descendant(of: find.byKey(const ValueKey('supplement-servings')), matching: find.byType(TextField)),
        '68');
    expect(find.text('Sin fecha: elígela el día que empieces'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Guardar')));
    await steps(tester);

    final row = (await tester.runAsync(() => db.select(db.supplements).getSingle()))!;
    expect((row.name, row.dose, row.servingsPerPack, row.startDate, row.active),
        ('Creatina', '1 cucharada (6 g ≈ 5 g de creatina)', 68, null, true));
    expect(find.text('1 cucharada (6 g ≈ 5 g de creatina) · 68 tomas por envase · sin empezar'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });

  testWidgets('registro de la mañana: marcar y desmarcar la creatina escribe y quita la toma', (tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    final host = DatabaseHost(File('unused.sqlite'), (_) => openInMemoryDatabase(), initial: db);
    final repo = SupplementRepository(db);
    final id = (await tester.runAsync(() => repo.add(
        name: 'Creatina', dose: '1 cucharada', servingsPerPack: 68, start: DateTime(2026, 10, 1))))!;
    // Uno sin empezar no aparece.
    await tester.runAsync(() => repo.add(name: 'Omega 3', dose: '1 cápsula'));

    Future<void> open() async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [databaseHostProvider.overrideWithValue(host)],
        child: MaterialApp(home: MorningCheckScreen(date: DateTime(2026, 10, 8))),
      ));
      await settle(tester);
    }

    Future<List<SupplementLogRow>> logs() async => (await tester.runAsync(() => db.select(db.supplementLogs).get()))!;

    await open();
    expect(find.text('Omega 3'), findsNothing);
    final chip = find.widgetWithText(FilterChip, 'Creatina');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    expect(find.widgetWithText(FilterChip, 'Creatina ✓'), findsOneWidget);
    await pickStairs(tester);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect([for (final l in await logs()) (l.supplementId, l.date)], [(id, '2026-10-08')]);

    await open();
    final taken = find.widgetWithText(FilterChip, 'Creatina ✓');
    expect(taken, findsOneWidget, reason: 'lo guardado se ve al volver');
    await tester.ensureVisible(taken);
    await tester.tap(taken);
    await tester.pump();
    await pickStairs(tester);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    expect(await logs(), isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}

/// Plan 055: la rodilla en escaleras es obligatoria para guardar.
Future<void> pickStairs(WidgetTester tester) async {
  final field = find.byKey(const ValueKey('escaleras'));
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text('0 / 10').last);
  await tester.pumpAndSettle();
}
