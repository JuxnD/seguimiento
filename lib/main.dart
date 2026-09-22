import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/database_host.dart';
import 'data/repositories/exercise_repository.dart';
import 'data/repositories/plan_repository.dart';
import 'data/seed_plan.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final host = await DatabaseHost.open();
  // Primera apertura: deja el plan y las metas listos para registrar.
  await seedIfEmpty(host.db, PlanRepository(host.db, ExerciseRepository(host.db)));
  runApp(
    ProviderScope(
      overrides: [databaseHostProvider.overrideWithValue(host)],
      child: const SeguimientoApp(),
    ),
  );
}
