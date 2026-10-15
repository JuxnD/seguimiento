import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/equipment_repository.dart';
import 'package:seguimiento/domain/equipment.dart';
import 'package:seguimiento/features/settings/equipment_card.dart';
import '../support/sqlite_host.dart';

/// Plan 052 (§16.27.4): la tarjeta Material de Ajustes.
void main() {
  setUpAll(useHostSqlite);
  Future<void> settle(WidgetTester t) async {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  // Igual que plan034_equipment_and_criteria_test: cerrar SQLite con los dos
  // relojes avanzando antes de que Flutter revise temporizadores pendientes.
  Future<void> closeDatabase(
      WidgetTester t, ProviderContainer container, AppDatabase db) async {
    await t.runAsync(() async => container.dispose());
    var closed = false;
    Object? closeError;
    await t.runAsync(() async {
      unawaited(db.close().then<void>((_) {
        closed = true;
      }, onError: (Object error) {
        closeError = error;
        closed = true;
      }));
    });
    final deadline = Stopwatch()..start();
    while (!closed && deadline.elapsed < const Duration(seconds: 2)) {
      await t.pump(const Duration(milliseconds: 10));
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(closeError, isNull);
    expect(closed, isTrue);
    await t.pumpWidget(const SizedBox());
    await t.pump();
  }

  testWidgets(
      'Material: valores por omisión sin inventar; "Tengo" en anillas guarda la fila y la bandera',
      (t) async {
    late AppDatabase db;
    late LocalFlags flags;
    late ProviderContainer container;
    final dir = Directory.systemTemp.createTempSync('plan052-material-card');
    await t.runAsync(() async {
      db = openInMemoryDatabase();
      flags = LocalFlags(File('${dir.path}/flags.json'));
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        localFlagsProvider.overrideWithValue(flags),
      ]);
    });
    try {
      await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(child: EquipmentCard())))));
      await settle(t);
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('Colchoneta antideslizante de 6 mm'), findsOneWidget);
      SegmentedButton<String> segments(String key) =>
          t.widget<SegmentedButton<String>>(find.ancestor(
              of: find.byKey(ValueKey('material:$key:${EquipmentStatus.tengo}')),
              matching: find.byType(SegmentedButton<String>)));
      expect(segments(EquipmentKeys.bar).selected, {EquipmentStatus.tengo});
      expect(segments(EquipmentKeys.band).selected, {EquipmentStatus.tengo});
      expect(segments(EquipmentKeys.scale).selected, {EquipmentStatus.tengo});
      expect(segments(EquipmentKeys.mat).selected, {EquipmentStatus.noTengo});
      expect(segments(EquipmentKeys.parallettes).selected,
          {EquipmentStatus.noTengo});
      expect(
          segments(EquipmentKeys.rings).selected, {EquipmentStatus.noTengo});
      expect(segments(EquipmentKeys.backpack).selected,
          {EquipmentStatus.noTengo});
      expect(find.text('En compra'), findsNWidgets(6),
          reason: 'la mochila es sí/no');

      final rings = find.byKey(
          const ValueKey('material:${EquipmentKeys.rings}:${EquipmentStatus.tengo}'));
      await t.ensureVisible(rings);
      await settle(t);
      await t.runAsync(() async {
        // El callback escribe la base y luego el archivo de banderas: se
        // espera el resultado observable, no un tiempo fijo.
        await t.tap(rings);
        final deadline = Stopwatch()..start();
        while (flags.get<bool>(FlagKeys.hasRings) != true &&
            deadline.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await settle(t);
      expect(flags.get<bool>(FlagKeys.hasRings), isTrue);
      await t.runAsync(() async {
        expect((await EquipmentRepository(db).rows())[EquipmentKeys.rings]!
                .status,
            EquipmentStatus.tengo);
        expect(
            (await EquipmentRepository(db).rows())
                .containsKey(EquipmentKeys.mat),
            isFalse,
            reason: 'sólo se guarda lo que el usuario cambió');
      });
      await settle(t);
      expect(segments(EquipmentKeys.rings).selected, {EquipmentStatus.tengo});
      expect(t.takeException(), isNull);
    } finally {
      await closeDatabase(t, container, db);
      await t.runAsync(() => dir.delete(recursive: true));
    }
  });
}
