import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/body/body_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meals/meals_screen.dart';
import '../features/report/report_screen.dart';
import '../features/training/training_screen.dart';
import 'providers.dart';
import '../ui/theme.dart';

class SeguimientoApp extends StatelessWidget {
  const SeguimientoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seguimiento',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildGymTheme(),
      darkTheme: buildGymTheme(),
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Android 13+ no manda nada sin permiso explícito.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = ref.read(notificationServiceProvider);
      if (!await service.hasPermission()) await service.requestPermission();
    });
  }

  static const _tabs = [
    HomeScreen(),
    TrainingScreen(),
    MealsScreen(),
    BodyScreen(),
    ReportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Deja programados los recordatorios y los mantiene al día.
    ref.watch(reminderSyncProvider);
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Hoy'),
          NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Entreno'),
          NavigationDestination(
              icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'Comidas'),
          NavigationDestination(
              icon: Icon(Icons.straighten_outlined), selectedIcon: Icon(Icons.straighten), label: 'Cuerpo'),
          NavigationDestination(
              icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Informe'),
        ],
      ),
    );
  }
}
