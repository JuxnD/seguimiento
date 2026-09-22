import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/body/body_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meals/meals_screen.dart';
import '../features/report/report_screen.dart';
import '../features/training/training_screen.dart';

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
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(isDense: true),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    TrainingScreen(),
    MealsScreen(),
    BodyScreen(),
    ReportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
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
