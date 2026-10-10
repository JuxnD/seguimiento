import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/features/settings/health_connect_card.dart';
import 'package:seguimiento/features/settings/settings_screen.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  setUp(() async {
    db = openInMemoryDatabase();
    await db.select(db.profiles).getSingle();
    await (db.update(db.profiles)..where((p) => p.id.equals(1))).write(const ProfilesCompanion(
        stepsTarget: Value(7500), proteinMin: Value(147), proteinMax: Value(163), kcalTarget: Value(2333)));
  });
  tearDown(() => db.close());
  testWidgets('base5000 requiere guardar; abrir y seleccionar no cambia el perfil', (tester) async {
    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: [
      databaseProvider.overrideWithValue(db),
      documentsDirProvider.overrideWith((_) => Directory.systemTemp),
      autoBackupsProvider.overrideWith((_) => []),
      healthConnectStateProvider.overrideWith(
          (_) => const HealthConnectState(status: HealthConnectStatus.desconocido, permitted: false, enabled: false)),
      appVersionProvider.overrideWith((_) => '1.22.0'),
      updateCheckProvider.overrideWith((_) => const UpdateCheck(currentVersion: '1.22.0')),
    ], child: const MaterialApp(home: SettingsScreen())));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Usar 5.000 pasos como base'), findsOneWidget);
    await tester.runAsync(() async => expect((await db.select(db.profiles).getSingle()).stepsTarget, 7500));
    await tester.tap(find.text('Usar 5.000 pasos como base'));
    await tester.pump();
    await tester.runAsync(() async => expect((await db.select(db.profiles).getSingle()).stepsTarget, 7500));
    await tester.tap(find.text('Guardar perfil'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.runAsync(() async {
      final p = await db.select(db.profiles).getSingle();
      expect((p.stepsTarget, p.proteinMin, p.proteinMax, p.kcalTarget), (5000, 147, 163, 2333));
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
