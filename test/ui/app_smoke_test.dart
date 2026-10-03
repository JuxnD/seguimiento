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
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/custom_reminder_repository.dart';
import 'package:seguimiento/data/repositories/nutrition_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/dates.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/features/meals/meal_form_screen.dart';

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

  Future<void> pumpApp(WidgetTester tester, {List<Override> extra = const []}) async {
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
        ...extra,
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

  testWidgets('los pasos se traen solos cada 2 min y al deslizar Hoy hacia abajo', (tester) async {
    final sync = _CountingSync(db);
    await pumpApp(tester, extra: [stepsSyncProvider.overrideWithValue(sync)]);
    expect(sync.runs, 1, reason: 'al abrir la app');
    expect(find.textContaining('Pasos del reloj · actualizado'), findsOneWidget);

    await tester.pump(const Duration(minutes: 2));
    await settle(tester);
    expect(sync.runs, 2, reason: 'a los 2 minutos, sin tocar nada');

    // El umbral del gesto es proporcional al alto de la vista (6000 px aquí).
    await tester.drag(find.byType(RefreshIndicator).first, const Offset(0, 2500));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(sync.runs, 3, reason: 'deslizar hacia abajo');
    await disposeApp(tester);
  });

  testWidgets('un recordatorio propio que toca hoy sale en Hoy y se marca hecho', (tester) async {
    await CustomReminderRepository(db).save(
      title: 'Ejercicios de cuello',
      intervalDays: 3,
      hour: 19,
      minute: 0,
      startDate: DateTime.now(),
    );
    await pumpApp(tester);
    expect(find.text('Pendiente hoy'), findsOneWidget);
    expect(find.text('Ejercicios de cuello'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Hecho'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Pendiente hoy'), findsNothing);
    expect((await CustomReminderRepository(db).all()).single.lastDone, isNotNull);
    await disposeApp(tester);
  });

  testWidgets('anotar los pasos desde el anillo de Hoy', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Pasos'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '1935');
    await tester.tap(find.text('Guardar'));
    // El diálogo anima su salida: su campo no puede quedar sin controller.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('1,9k'), findsOneWidget);
    expect((await db.select(db.dailySteps).get()).single.steps, 1935);
    await disposeApp(tester);
  });

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

  testWidgets('Comidas: tocar lo de ayer no lo repite y "Repetir hoy" avisa si ya hay uno', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final repo = NutritionRepository(db);
    await repo.saveMeal(MealDraft(date: today.subtract(const Duration(days: 1)), slot: MealSlot.desayuno, time: '08:00')
      ..items.add(MealItemDraft(label: 'Huevos de ayer', macros: const Macros(kcal: 400, protein: 30))));
    await repo.saveMeal(MealDraft(date: today, slot: MealSlot.desayuno, time: '07:30')
      ..items.add(MealItemDraft(label: 'Avena', macros: const Macros(kcal: 300, protein: 10))));
    // Tarjetas de desayuno de hoy ("Desayuno · 07:30"); la de ayer dice "Desayuno de ayer".
    int breakfastsToday() => find.textContaining(RegExp(r'^Desayuno · ')).evaluate().length;

    await pumpApp(tester);
    await tester.tap(find.text('Comidas').last);
    await settle(tester);

    // Tocar la fila abre la comida de ayer para corregirla: no la duplica
    // (fue el accidente del 29 sep, §16.7).
    expect(breakfastsToday(), 1);
    await tester.tap(find.textContaining('Desayuno de ayer'));
    await settle(tester);
    await settle(tester);
    expect(find.byType(MealFormScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(breakfastsToday(), 1);

    Future<void> waitDb() async {
      await settle(tester);
      await settle(tester);
    }

    Future<void> repeat() async {
      await tester.tap(find.text('Repetir hoy'));
      await waitDb();
      // Fuera de la franja del desayuno pregunta antes (§9).
      if (find.text('Dejar desayuno').evaluate().isNotEmpty) {
        await tester.tap(find.text('Dejar desayuno'));
        await waitDb();
      }
    }

    await repeat();
    expect(find.text('Ya tienes un desayuno hoy'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(breakfastsToday(), 1, reason: 'cancelar no registra nada');

    await repeat();
    await tester.tap(find.text('Añadir otro'));
    await waitDb();
    expect(find.text('Añadido a hoy'), findsOneWidget);
    expect(breakfastsToday(), 2);
    await disposeApp(tester);
  });

  testWidgets('Comidas muestra la fecha en las tarjetas de otro día', (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    await NutritionRepository(db).saveMeal(MealDraft(date: yesterday, slot: MealSlot.cena, time: '20:00')
      ..items.add(MealItemDraft(label: 'Pasta', macros: const Macros(kcal: 900, protein: 30))));
    await pumpApp(tester);
    await tester.tap(find.text('Comidas').last);
    await settle(tester);
    await tester.tap(find.byTooltip('Día anterior'));
    await settle(tester);

    expect(find.text('Cena · 20:00 · ${weekdayShort(yesterday.weekday)} ${formatShort(yesterday)}'), findsOneWidget);
    expect(find.text('Volver a hoy'), findsOneWidget);
    expect(find.text('Repetir hoy'), findsNothing, reason: '"de ayer" solo se ofrece mirando hoy');
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

/// StepsSync que solo cuenta cuántas veces corrió.
class _CountingSync extends StepsSync {
  _CountingSync(AppDatabase db)
      : super(health: const HealthConnect(), steps: StepsRepository(db), flags: LocalFlags(File('no-se-usa.json')));

  int runs = 0;

  @override
  bool get enabled => true;

  @override
  DateTime? get lastSync => DateTime.now();

  @override
  Future<StepsSyncResult> run({int days = 14, DateTime? now}) async {
    runs++;
    return const StepsSyncResult(StepsSyncOutcome.hecho);
  }
}
