import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/app.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/auto_backup.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/notification_service.dart';
import 'package:seguimiento/data/repositories/profile_repository.dart';
import 'package:seguimiento/data/repositories/reminder_repository.dart';
import 'package:seguimiento/data/repositories/steps_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/reminders.dart';
import 'package:seguimiento/features/onboarding/app_entry.dart';
import 'package:seguimiento/features/onboarding/onboarding_screen.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/ready_profile.dart';
import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

/// Espía de notificaciones: cuenta permisos y programaciones.
class _Notifications extends NotificationService {
  _Notifications() : super(FlutterLocalNotificationsPlugin());

  int permissionChecks = 0;
  int permissionRequests = 0;
  final schedules = <List<PlannedNotification>>[];

  @override
  Future<void> init() async {}

  @override
  Future<bool> hasPermission() async {
    permissionChecks++;
    return false;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<bool> canScheduleExact() async => true;

  @override
  Future<void> applySchedule(List<PlannedNotification> planned) async => schedules.add(planned);
}

class _Steps extends StepsSync {
  _Steps(AppDatabase db)
      : super(health: const HealthConnect(), steps: StepsRepository(db), flags: LocalFlags(File('no-se-usa.json')));

  int runs = 0;

  @override
  bool get enabled => false;

  @override
  Future<StepsSyncResult> run({int days = 14, DateTime? now}) async {
    runs++;
    return const StepsSyncResult(StepsSyncOutcome.hecho);
  }
}

class _Backup extends AutoBackup {
  _Backup(DatabaseHost host, LocalFlags flags, Directory dir) : super(host: host, flags: flags, dir: dir);

  int runs = 0;

  @override
  Future<File?> runIfDue({DateTime? now}) async {
    runs++;
    return null;
  }
}

void main() {
  // Sin suprimir el aviso de Drift (plan 024): bases múltiples quedan visibles.
  setUpAll(useHostSqlite);

  late Directory dir;
  late AppDatabase db;
  late DatabaseHost host;
  late _Notifications notifications;
  late _Steps steps;
  late _Backup backup;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('seguimiento_022_ui');
    db = openInMemoryDatabase();
    host = DatabaseHost(File('${dir.path}/no-se-usa.sqlite'), (_) => openInMemoryDatabase(), initial: db);
    notifications = _Notifications();
    steps = _Steps(db);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows puede retener un archivo; no afecta la prueba.
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Map<String, int> effects() => {
        'permiso': notifications.permissionChecks + notifications.permissionRequests,
        'avisos': notifications.schedules.length,
        'pasos': steps.runs,
        'respaldo': backup.runs,
      };

  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await ReminderRepository(db).ensureDefaults();
    final flags = LocalFlags(File('${dir.path}/flags.json'));
    backup = _Backup(host, flags, Directory('${dir.path}/respaldos'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseHostProvider.overrideWithValue(host),
        localFlagsProvider.overrideWithValue(flags),
        activeSessionStoreProvider.overrideWithValue(ActiveSessionStore(File('${dir.path}/sesion.json'))),
        notificationServiceProvider.overrideWithValue(notifications),
        stepsSyncProvider.overrideWithValue(steps),
        documentsDirProvider.overrideWith((ref) => dir),
        appVersionProvider.overrideWith((ref) => '0.0.0'),
        updateCheckProvider.overrideWith((ref) => const UpdateCheck(currentVersion: '0.0.0')),
        autoBackupProvider.overrideWith((ref) => backup),
        autoBackupsProvider.overrideWith((ref) => const []),
      ],
      child: const SeguimientoApp(),
    ));
    container = ProviderScope.containerOf(tester.element(find.byType(AppEntry)));
    await settle(tester);
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('pendiente: sólo el alta, sin efectos; confirmar monta Hoy sin rutina y corre los efectos una vez',
      (tester) async {
    await pumpApp(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(find.text('Hoy'), findsNothing);
    expect(effects(), {'permiso': 0, 'avisos': 0, 'pasos': 0, 'respaldo': 0});
    // Sin shell no hay temporizador de pasos ni avisos: pasan minutos y nada.
    await tester.pump(const Duration(minutes: 3));
    await settle(tester);
    expect(effects(), {'permiso': 0, 'avisos': 0, 'pasos': 0, 'respaldo': 0});
    // Sin metas del dueño ni valores precargados en nutrición.
    expect(find.text('Definir ahora'), findsOneWidget);
    expect(find.widgetWithText(TextField, '130'), findsNothing);
    expect(find.widgetWithText(TextField, '5000'), findsOneWidget, reason: 'pasos 5.000 editables');

    await tester.tap(find.text('Más adelante'));
    await tester.pump();
    await tester.tap(find.text('Confirmar mi perfil'));
    await settle(tester);
    expect(find.text('¿Confirmar tu perfil?'), findsOneWidget);
    expect(find.textContaining('Proteína mínima: sin meta'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await settle(tester);
    await settle(tester);

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Sin rutina configurada'), findsOneWidget);
    expect(find.text('Configurar mi rutina'), findsOneWidget);
    expect(find.text('Día de descanso. La racha no se rompe.'), findsNothing, reason: 'sin plan no es descanso');
    expect(find.textContaining('Activar desde el'), findsNothing, reason: 'no se ofrece el v3.1 del dueño');
    expect(find.textContaining('Correcciones del traspaso'), findsNothing);
    final after = effects();
    expect((after['permiso']! > 0, after['pasos'], after['respaldo'], after['avisos']! > 0), (true, 1, 1, true),
        reason: 'los efectos del arranque corren al pasar a ready');
    final status = await ProfileRepository(db).setupStatus();
    expect(status.ready, isTrue);
    expect(await db.select(db.goalVersions).get(), hasLength(6));
    expect(await db.select(db.planVersions).get(), isEmpty, reason: 'no se crea rutina por tabla vacía');
    await disposeApp(tester);
  });

  testWidgets('cancelar la confirmación y empezar de nuevo dejan el alta pendiente', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Definir ahora'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Proteína mínima'), '120');
    await tester.tap(find.text('Confirmar mi perfil'));
    await settle(tester);
    await tester.tap(find.text('Seguir editando'));
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    await tester.tap(find.text('Empezar de nuevo'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '120'), findsNothing);
    expect(find.text('Proteína mínima'), findsNothing, reason: 'la elección de nutrición también se reinicia');
    expect((await ProfileRepository(db).setupStatus()).pending, isTrue);
    expect(await db.select(db.goalVersions).get(), isEmpty);
    expect(effects(), {'permiso': 0, 'avisos': 0, 'pasos': 0, 'respaldo': 0});
    await disposeApp(tester);
  });

  testWidgets('listo → pendiente con la app abierta (restaurar): vuelve al alta y retira los avisos', (tester) async {
    await asExistingUser(db);
    await pumpApp(tester);
    expect(find.byType(HomeShell), findsOneWidget);
    final stepsBefore = steps.runs;
    // Lo que deja un ZIP de un alta pendiente: perfil nuevo, sin metas.
    // (Escrituras Drift: notifican a los streams como lo haría la base nueva.)
    await db.delete(db.goalVersions).go();
    await db.update(db.profiles).write(const ProfilesCompanion(
        profileOrigin: Value(ProfileOrigin.newInstall),
        setupState: Value(SetupState.pending),
        setupConfirmedAt: Value(null)));
    container.read(databaseGenerationProvider.notifier).state++;
    await settle(tester);
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(notifications.schedules.last, isEmpty, reason: 'los avisos del perfil anterior se retiran');
    await tester.pump(const Duration(minutes: 3));
    await settle(tester);
    expect(steps.runs, stepsBefore, reason: 'el temporizador de pasos murió con el shell');
    await disposeApp(tester);
  });

  testWidgets('un origen inválido muestra el error y no monta el shell', (tester) async {
    await db.customStatement("UPDATE profiles SET profile_origin = 'owner'");
    await pumpApp(tester);
    expect(find.byType(SetupErrorScreen), findsOneWidget);
    expect(find.textContaining('Origen de perfil desconocido'), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(effects(), {'permiso': 0, 'avisos': 0, 'pasos': 0, 'respaldo': 0});
    await disposeApp(tester);
  });

  // 360 dp con texto ×1, ×1.6 y ×2, sin recortar el escalado: ni desbordes
  // ni excepciones. Las capturas quedan en build/022-capturas (ignorado).
  for (final scale in [1.0, 1.6, 2.0]) {
    for (final expanded in [false, true]) {
      testWidgets('alta a 360 dp, texto ×$scale${expanded ? ', nutrición abierta' : ''}', (tester) async {
        tester.view.physicalSize = Size(360, expanded ? 3400 : 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadTestFonts(tester);
        final base = buildGymTheme();
        final theme = base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
          appBarTheme: base.appBarTheme.copyWith(
            titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: base.filledButtonTheme.style!.copyWith(
              textStyle: WidgetStatePropertyAll(
                  base.filledButtonTheme.style!.textStyle!.resolve({})!.copyWith(fontFamily: 'Roboto')),
            ),
          ),
        );
        const key = ValueKey('captura-alta');
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const OnboardingScreen(),
            ),
          ),
        ));
        await settle(tester);
        if (expanded) {
          await tester.tap(find.text('Definir ahora'));
          await settle(tester);
        }
        expect(tester.takeException(), isNull);
        final title = tester
            .widget<RichText>(find.descendant(of: find.text('Configura tu perfil'), matching: find.byType(RichText)));
        expect(title.textScaler, TextScaler.linear(scale), reason: 'sin clamp del texto grande');
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final out = Directory('build/022-capturas')..createSync(recursive: true);
            await File('${out.path}/alta-$scale${expanded ? '-nutricion' : ''}.png')
                .writeAsBytes(png!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        await tester.pumpWidget(const SizedBox());
        await db.close();
      });
    }
  }
}
