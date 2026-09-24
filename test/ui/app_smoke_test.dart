import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/app.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/auto_backup.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/reminders.dart';

import '../support/sqlite_host.dart';

/// Notificaciones sin plataforma: la prueba no tiene Android debajo.
class _NoNotifications extends NotificationService {
  _NoNotifications() : super(FlutterLocalNotificationsPlugin());

  @override
  Future<void> init() async {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async {}
}

/// Humo de la app completa sobre una base real en memoria.
///
/// `flutter_test` corre en tiempo simulado: cualquier E/S real (archivos,
/// isolates) que la app espere se queda colgada. Por eso: la base es SQLite en
/// memoria en el mismo isolate (sus futures se resuelven con microtareas), las
/// banderas se escriben antes de montar (tiempo real) y quedan listas para que
/// la app no toque disco, y al final se desmonta y se cierra la base dentro de
/// la prueba para que drift suelte sus timers.
void main() {
  setUpAll(() {
    useHostSqlite();
    // Cada prueba abre su propia base en memoria: es a propósito.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Directory dir;
  late AppDatabase db;
  late DatabaseHost host;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_ui');
    db = openInMemoryDatabase();
    host = DatabaseHost(File('${dir.path}/no-se-usa.sqlite'), (_) => openInMemoryDatabase(), initial: db);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // En Windows algún archivo puede seguir tomado; no afecta la prueba.
    }
  });

  /// Deja correr las consultas y pinta lo que produjeron. No sirve
  /// pumpAndSettle: los indicadores de carga animan sin fin.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    // Pantalla alta (las listas solo construyen lo visible) y ancha: la fuente
    // de prueba dibuja cada letra como un cuadrado, así que a ancho de
    // teléfono daría desbordes que con la fuente real no existen.
    tester.view.physicalSize = const Size(1400, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await ReminderRepository(db).ensureDefaults();
    final flags = LocalFlags(File('${dir.path}/flags.json'));
    // Permiso ya pedido y respaldo de hoy ya hecho: la app no abre diálogos
    // del sistema ni escribe a disco durante la prueba.
    await tester.runAsync(() async {
      await flags.set(FlagKeys.notificationsAsked, true);
      await flags.set(FlagKeys.lastAutoBackup, DateTime.now());
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseHostProvider.overrideWithValue(host),
        localFlagsProvider.overrideWithValue(flags),
        activeSessionStoreProvider.overrideWithValue(ActiveSessionStore(File('${dir.path}/sesion.json'))),
        notificationServiceProvider.overrideWithValue(_NoNotifications()),
        documentsDirProvider.overrideWith((ref) => dir),
        appVersionProvider.overrideWith((ref) => '0.0.0'),
        updateCheckProvider.overrideWith((ref) => const UpdateCheck(currentVersion: '0.0.0')),
        autoBackupProvider.overrideWith(
          (ref) => AutoBackup(host: host, flags: flags, dir: Directory('${dir.path}/respaldos')),
        ),
      ],
      child: const SeguimientoApp(),
    ));
    await settle(tester);
  }

  /// Desmonta dentro de la prueba: cancela streams y el timer de medianoche,
  /// deja correr los timers de limpieza de drift y cierra la base.
  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('arranca en Hoy y abre todas las pestañas', (tester) async {
    await pumpApp(tester);
    expect(find.text('Hoy'), findsWidgets);
    expect(find.text('Registrar'), findsOneWidget);

    for (final tab in ['Entreno', 'Comidas', 'Cuerpo', 'Informe']) {
      await tester.tap(find.text(tab).last);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'falló al abrir $tab');
    }
    await disposeApp(tester);
  });

  testWidgets('Comidas muestra lo registrado hoy', (tester) async {
    await NutritionRepository(db).saveMeal(
      MealDraft(date: DateTime.now(), slot: MealSlot.desayuno)
        ..items.add(MealItemDraft(label: 'Huevo', macros: const Macros(kcal: 216, protein: 19))),
    );
    await pumpApp(tester);
    await tester.tap(find.text('Comidas').last);
    await settle(tester);

    expect(find.textContaining('Huevo'), findsWidgets);
    await disposeApp(tester);
  });

  testWidgets('el informe se genera con lo registrado', (tester) async {
    await NutritionRepository(db).saveMeal(
      MealDraft(date: DateTime.now(), slot: MealSlot.almuerzo)
        ..items.add(MealItemDraft(label: 'Bandeja', macros: const Macros(kcal: 1500, protein: 50))),
    );
    await pumpApp(tester);
    await tester.tap(find.text('Informe').last);
    await settle(tester);

    expect(find.textContaining('Bandeja'), findsWidgets);
    await disposeApp(tester);
  });

  testWidgets('Ajustes abre con el perfil y las copias automáticas', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await settle(tester);

    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Copias automáticas'), findsOneWidget);
    await disposeApp(tester);
  });
}
