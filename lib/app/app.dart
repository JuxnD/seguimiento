import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/body/body_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meals/meals_screen.dart';
import '../features/onboarding/app_entry.dart';
import '../features/report/report_screen.dart';
import '../features/training/training_screen.dart';
import '../data/local_flags.dart';
import 'providers.dart';
import '../ui/theme.dart';

class SeguimientoApp extends StatelessWidget {
  const SeguimientoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Prime',
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
      // Plan 022: el alta pendiente no monta HomeShell ni sus efectos.
      home: const AppEntry(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;
  static const _widgetChannel = MethodChannel('seguimiento/widget');

  void _openToday() {
    if (!mounted) return;
    ref.read(todayProvider.notifier).refresh();
    ref.invalidate(dashboardProvider);
    setState(() => _index = 0);
  }

  Future<void> _consumeWidgetOpen() async {
    try {
      if (await _widgetChannel.invokeMethod<bool>('consumeOpenToday') == true) {
        _openToday();
      }
    } on MissingPluginException {
      /* Plataforma sin widget. */
    } on PlatformException {/* No impide abrir la app. */}
  }

  /// Mientras la app está abierta, los pasos del reloj se traen solos cada
  /// tanto: Innova los escribe en Health Connect cuando sincroniza.
  Timer? _stepsTimer;
  static const _stepsEvery = Duration(minutes: 2);

  void _startStepsTimer() {
    _stepsTimer?.cancel();
    _stepsTimer =
        Timer.periodic(_stepsEvery, (_) => ref.read(syncStepsProvider)());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openToday') _openToday();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _askNotificationsOnce();
      _consumeWidgetOpen();
      _autoBackup();
      ref.read(syncStepsProvider)();
      _startStepsTimer();
    });
  }

  @override
  void dispose() {
    _stepsTimer?.cancel();
    _widgetChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de segundo plano puede ser otro día: Hoy, Comidas y los avisos
  /// tienen que enterarse.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(todayProvider.notifier).refresh();
      ref.invalidate(dashboardProvider);
      // Los pasos del reloj llegan a Health Connect mientras la app duerme.
      ref.read(syncStepsProvider)();
      _startStepsTimer();
    } else if (state == AppLifecycleState.paused) {
      // En segundo plano no: Android no deja leer Health Connect sin permiso
      // de fondo, y gastaría batería para nada.
      _stepsTimer?.cancel();
    }
  }

  /// Respaldo semanal en segundo plano, después de pintar: nunca frena el
  /// arranque ni lanza.
  Future<void> _autoBackup() async {
    final backup = await ref.read(autoBackupProvider.future);
    if (await backup.runIfDue() != null) ref.invalidate(autoBackupsProvider);
  }

  /// Android 13+ no manda nada sin permiso explícito. Se pide **una** vez; si
  /// se niega, Recordatorios muestra cómo activarlo, sin insistir en cada
  /// arranque.
  Future<void> _askNotificationsOnce() async {
    final flags = ref.read(localFlagsProvider);
    if (flags.get<bool>(FlagKeys.notificationsAsked) == true) return;
    final service = ref.read(notificationServiceProvider);
    try {
      if (!await service.hasPermission()) await service.requestPermission();
    } finally {
      await flags.set(FlagKeys.notificationsAsked, true);
    }
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
          NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today),
              label: 'Hoy'),
          NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Entreno'),
          NavigationDestination(
              icon: Icon(Icons.restaurant_outlined),
              selectedIcon: Icon(Icons.restaurant),
              label: 'Comidas'),
          NavigationDestination(
              icon: Icon(Icons.straighten_outlined),
              selectedIcon: Icon(Icons.straighten),
              label: 'Cuerpo'),
          NavigationDestination(
              icon: Icon(Icons.description_outlined),
              selectedIcon: Icon(Icons.description),
              label: 'Informe'),
        ],
      ),
    );
  }
}
