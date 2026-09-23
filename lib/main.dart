import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/startup_error.dart';
import 'data/active_session_store.dart';
import 'data/database_host.dart';
import 'data/local_flags.dart';
import 'data/notification_service.dart';
import 'data/repositories/exercise_repository.dart';
import 'data/repositories/plan_repository.dart';
import 'data/repositories/reminder_repository.dart';
import 'data/seed_foods.dart';
import 'data/seed_plan.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DatabaseHost? host;
  try {
    host = await DatabaseHost.open();
    // Primera apertura: deja el plan y las metas listos para registrar.
    await seedIfEmpty(host.db, PlanRepository(host.db, ExerciseRepository(host.db)));
    await seedFoodsIfEmpty(host.db);
    await ReminderRepository(host.db).ensureDefaults();
    final flags = await LocalFlags.open();
    final activeSession = await ActiveSessionStore.open();

    // Sin notificaciones la app sirve igual: un fallo aquí no debe impedir
    // abrirla.
    final notifications = NotificationService();
    try {
      await notifications.init();
    } on Object catch (e) {
      debugPrint('Notificaciones no disponibles: $e');
    }

    runApp(
      ProviderScope(
        overrides: [
          databaseHostProvider.overrideWithValue(host),
          localFlagsProvider.overrideWithValue(flags),
          activeSessionStoreProvider.overrideWithValue(activeSession),
          notificationServiceProvider.overrideWithValue(notifications),
        ],
        child: const SeguimientoApp(),
      ),
    );
  } on Object catch (e, st) {
    // Sin esto, un fallo al abrir la base deja una pantalla en blanco. Aquí se
    // explica qué pasó y, si la base abrió, se puede exportar para no perderla.
    debugPrint('Error al arrancar: $e\n$st');
    runApp(StartupErrorApp(error: e, host: host));
  }
}
