import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/active_session_store.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/auto_backup.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/data/repositories/ai_conversation_repository.dart';
import 'package:seguimiento/domain/ai_context.dart';
import 'package:seguimiento/features/settings/health_connect_card.dart';
import 'package:seguimiento/features/settings/settings_screen.dart';
import 'package:seguimiento/features/ai/ai_history_screen.dart';
import '../support/sqlite_host.dart';

void main() {
  setUpAll(useHostSqlite);
  late AppDatabase db;
  setUp(() async {
    db = openInMemoryDatabase();
    await db.select(db.profiles).getSingle();
  });
  void cleanup(WidgetTester tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      var closed = false;
      final closing = db.close().whenComplete(() => closed = true);
      for (var i = 0; i < 100 && !closed; i++) {
        await tester.pump(const Duration(milliseconds: 5));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
      }
      expect(closed, isTrue,
          reason: 'SQLite debe cerrar sin dejar streams vivos');
      await closing;
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  Future<void> settings(WidgetTester tester,
      {List<AutoBackupFile> backups = const [],
      DatabaseHost? host,
      Directory? directory,
      Size size = const Size(1400, 6500),
      double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // Plan 027: restaurar suelta el vínculo del cronómetro; aquí no hay sesión.
          activeSessionStoreProvider.overrideWithValue(ActiveSessionStore(File('${Directory.systemTemp.path}/sin-sesion-027.json'))),
          if (host != null) databaseHostProvider.overrideWithValue(host),
          documentsDirProvider
              .overrideWith((_) => directory ?? Directory.systemTemp),
          autoBackupsProvider.overrideWith((_) => backups),
          healthConnectStateProvider.overrideWith((_) =>
              const HealthConnectState(
                  status: HealthConnectStatus.desconocido,
                  permitted: false,
                  enabled: false)),
          appVersionProvider.overrideWith((_) => '1.22.0'),
          updateCheckProvider
              .overrideWith((_) => const UpdateCheck(currentVersion: '1.22.0')),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const SettingsScreen())));
    await settle(tester);
  }

  testWidgets('inventario incluye IA y explica cifrado y copias automáticas',
      (tester) async {
    cleanup(tester);
    await settings(tester);
    expect(find.textContaining('historial de IA'), findsWidgets);
    expect(find.textContaining('sin cifrar'), findsWidgets);
    expect(
        find.text('Esta app está configurada para excluir sus datos de copias automáticas de Android '
            'y del traslado entre teléfonos. Usa el ZIP. No borra copias previas '
            'ni controla herramientas del fabricante o de terceros.'),
        findsOneWidget);
    expect(find.textContaining('pueden recuperar conversaciones borradas'),
        findsOneWidget);
    await release(tester);
  });

  testWidgets(
      'exportar requiere revisar datos antes de crear o compartir y cancelar es inocuo',
      (tester) async {
    cleanup(tester);
    await settings(tester);
    await tester.tap(find.text('Exportar registros y fotos'));
    await tester.pumpAndSettle();
    expect(find.text('Antes de exportar'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('preguntas, respuestas y contexto')),
        findsOneWidget);
    expect(find.textContaining('sin cifrar'), findsWidgets);
    // Host y plugins no están configurados: llegar a ellos antes de confirmar falla.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Antes de exportar'), findsNothing);
    expect(tester.takeException(), isNull);
    await release(tester);
  });

  testWidgets(
      'borrar IA explica copia actual y anteriores; cancelación conserva conversación',
      (tester) async {
    cleanup(tester);
    final repo = AiConversationRepository(db);
    final id = await tester.runAsync(() => repo.createValidatedConversation(
          snapshot: AiConversationSnapshot(
              kind: AiConversationKind.reportQuestion,
              title: 'Semana ficticia',
              sources: const [
                AiContextSource(
                    id: 'report',
                    title: 'Informe',
                    text: 'Dos sesiones completas.')
              ],
              model: aiQuestionModel,
              contractVersion: aiQuestionContractVersion),
          question: '¿Qué registré?',
          answer: 'Dos sesiones completas.',
          citations: const [
            AiCitation(sourceId: 'report', quote: 'Dos sesiones completas.')
          ],
          turnModel: aiQuestionModel,
          turnContractVersion: aiQuestionContractVersion,
        ));
    await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: AiHistoryScreen())));
    await settle(tester);
    await tester.tap(find.byTooltip('Borrar conversación'));
    await tester.pumpAndSettle();
    expect(find.textContaining('base actual de este teléfono'), findsOneWidget);
    expect(find.textContaining('respaldos anteriores'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async => expect(await repo.read(id!), isNotNull));
    await tester.tap(find.byTooltip('Borrar conversación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar'));
    await settle(tester);
    await tester.runAsync(() async => expect(await repo.read(id!), isNull));
    expect(find.text('Semana ficticia'), findsNothing);
    await release(tester);
  });

  testWidgets(
      'restaurar copia automática revela alcance e IA antes de reemplazar',
      (tester) async {
    cleanup(tester);
    final dir =
        Directory.systemTemp.createTempSync('seguimiento_disclosure_restore_');
    final host = DatabaseHost(File('${dir.path}/seguimiento.sqlite'),
        (file) => AppDatabase(NativeDatabase(file)),
        initial: db);
    final backup = await tester
        .runAsync(() => db.exportTo('${dir.path}/respaldo-2026-10-09.sqlite'));
    await settings(tester, host: host, directory: dir, backups: [
      AutoBackupFile(backup!, DateTime(2026, 10, 9), backup.lengthSync())
    ]);
    await tester.tap(find.text('Restaurar'));
    // ZIP/SQLite IO may take longer under parallel QA: wait for the actual
    // confirmation boundary, never an arbitrary small sleep or skipped assert.
    for (var i = 0;
        i < 300 && find.text('¿Restaurar este respaldo?').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('¿Restaurar este respaldo?'), findsOneWidget);
    expect(find.textContaining('Pueden reaparecer conversaciones'),
        findsOneWidget);
    expect(
        find.textContaining(
            'El cronómetro en curso, los permisos y la licencia no cambian'),
        findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(find.text('¿Restaurar este respaldo?'), findsNothing);
    expect(tester.takeException(), isNull);
    await release(tester);
    await tester.runAsync(() async => dir.deleteSync(recursive: true));
  });

  testWidgets(
      'aviso de exportación legible a 1.6 en teléfono y cancelar accesible',
      (tester) async {
    cleanup(tester);
    await settings(tester, size: const Size(360, 800), scale: 1.6);
    await tester.scrollUntilVisible(
        find.text('Exportar registros y fotos'), 500,
        scrollable: find.byType(Scrollable).first, maxScrolls: 30);
    await tester.ensureVisible(find.text('Exportar registros y fotos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exportar registros y fotos'));
    await tester.pumpAndSettle();
    expect(find.text('Antes de exportar'), findsOneWidget);
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await release(tester);
  });
}
