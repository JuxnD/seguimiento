import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/database_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final host = await DatabaseHost.open();
  runApp(
    ProviderScope(
      overrides: [databaseHostProvider.overrideWithValue(host)],
      child: const SeguimientoApp(),
    ),
  );
}
