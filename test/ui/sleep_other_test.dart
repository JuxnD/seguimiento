import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/features/home/morning_check_screen.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

/// §16.19: 10 h 11 min en cama se escribe con "Otro" y se guarda tal cual.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(useHostSqlite);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('registro de la mañana: 9,5, 10 y "Otro" con 10:11', (tester) async {
    await loadTestFonts(tester);
    final db = openInMemoryDatabase();
    final host = DatabaseHost(File('unused.sqlite'), (_) => openInMemoryDatabase(), initial: db);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseHostProvider.overrideWithValue(host)],
      child: MaterialApp(home: MorningCheckScreen(date: DateTime(2026, 10, 8))),
    ));
    await settle(tester);

    expect(find.widgetWithText(ChoiceChip, '9,5'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '10'), findsOneWidget);
    final other = find.widgetWithText(ChoiceChip, 'Otro');
    await tester.ensureVisible(other);
    await tester.tap(other);
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '10:11');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Guardar')));
    await settle(tester);
    expect(find.text('Otro: 10 h 11 min'), findsOneWidget);

    await pickStairs(tester);
    await tester.tap(find.text('Guardar'));
    await settle(tester);
    final row = (await tester.runAsync(() => db.select(db.sleepLogs).getSingle()))!;
    expect((row.date, row.hours), ('2026-10-08', 10.18));

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
