import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/local_flags.dart';
import 'package:seguimiento/data/repositories/dashboard_repository.dart';
import 'package:seguimiento/data/repositories/exercise_repository.dart';
import 'package:seguimiento/data/repositories/plan_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/enums.dart';
import 'package:seguimiento/domain/nutrition.dart';
import 'package:seguimiento/features/home/home_screen.dart';
import 'package:seguimiento/features/plan/plan_edit_screen.dart';
import 'package:seguimiento/features/training/technique_sheet.dart';
import 'package:seguimiento/ui/exercise_art.dart';
import 'package:seguimiento/ui/exercise_figure.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import 'package:seguimiento/ui/theme.dart';

import '../support/sqlite_host.dart';
import '../support/test_fonts.dart';

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 10, 12);
}

void main() {
  setUpAll(useHostSqlite);

  final art = ExerciseArtCatalog.fromJsonString(
      File(ExerciseArtCatalog.asset).readAsStringSync());
  final figures = Figure3DCatalog.fromJsonString(
      File(Figure3DCatalog.asset).readAsStringSync());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> mount(WidgetTester tester, Widget screen,
      {List<Override> overrides = const [], double scale = 1.5}) async {
    await loadTestFonts(tester);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = buildGymTheme();
    ButtonStyle? fontButton(ButtonStyle? style) => style?.copyWith(
          textStyle: WidgetStateProperty.resolveWith((states) =>
              (style.textStyle?.resolve(states) ?? const TextStyle())
                  .copyWith(fontFamily: 'Roboto')),
        );
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        key: UniqueKey(),
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          appBarTheme: theme.appBarTheme.copyWith(
              titleTextStyle: theme.appBarTheme.titleTextStyle
                  ?.copyWith(fontFamily: 'Roboto')),
          filledButtonTheme: FilledButtonThemeData(
              style: fontButton(theme.filledButtonTheme.style)),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: fontButton(theme.outlinedButtonTheme.style)),
          textButtonTheme: TextButtonThemeData(
              style: fontButton(theme.textButtonTheme.style)),
          chipTheme: theme.chipTheme.copyWith(
              labelStyle:
                  theme.chipTheme.labelStyle?.copyWith(fontFamily: 'Roboto')),
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
              labelStyle: theme.inputDecorationTheme.labelStyle
                  ?.copyWith(fontFamily: 'Roboto')),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const SizedBox(),
        initialRoute: '/tested',
        routes: {
          '/tested': (_) => RepaintBoundary(
              key: const ValueKey('experience-shot'), child: screen)
        },
      ),
    ));
    await settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final out = Platform.environment['EXPERIENCE_OUT'];
    if (out == null) return;
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('experience-shot')));
    await tester.runAsync(() async {
      final dir = Directory(out)..createSync(recursive: true);
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Finder field(String label) => find
      .byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      )
      .first;

  Future<void> enter(WidgetTester tester, String label, String value) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), value);
    await tester.pump();
  }

  testWidgets(
      'editor guarda y reabre sostén, RIR, lado y notas sin cambiar la versión anterior',
      (tester) async {
    final db = openInMemoryDatabase();
    final repo = PlanRepository(db, ExerciseRepository(db));
    final original = PlanDraft.empty(DateTime(2026, 10, 12));
    original.days.first
      ..type = DayType.bloques
      ..exercises.add(PlanExerciseDraft(
          name: 'Plancha lateral',
          holdSecMin: 20,
          holdSecMax: 30,
          rirMin: 1,
          rirMax: 2,
          perSide: true,
          notes: 'Nota anterior',
          variant: 'A',
          supersetGroup: 'core'));
    final id = await repo.saveAsNewVersion(original);
    final draft = await repo.load(id)
      ..validFrom = DateTime(2026, 10, 19);
    await mount(tester, PlanEditScreen(draft: draft),
        overrides: [databaseProvider.overrideWithValue(db)]);
    expect(field('Sostén mín (s)'), findsOneWidget);
    await enter(tester, 'Sostén mín (s)', '35');
    await enter(tester, 'Sostén máx (s)', '50');
    await enter(tester, 'RIR mín', '0');
    await enter(tester, 'RIR máx', '3');
    await tester.ensureVisible(find.text('Por lado'));
    await tester.tap(find.text('Por lado'));
    await enter(tester, 'Notas del ejercicio', 'Nota personal nueva');
    await shot(tester, 'editor-notas');
    await tester.tap(find.text('Guardar versión'));
    await settle(tester);
    final versions = await repo.versions();
    expect(versions, hasLength(2));
    final saved =
        (await repo.load(versions.last.id)).days.first.exercises.single;
    expect([
      saved.holdSecMin,
      saved.holdSecMax,
      saved.rirMin,
      saved.rirMax,
      saved.perSide,
      saved.notes
    ], [
      35,
      50,
      0,
      3,
      false,
      'Nota personal nueva'
    ]);
    expect([saved.variant, saved.supersetGroup], ['A', 'core']);
    final previous = (await repo.load(id)).days.first.exercises.single;
    expect([
      previous.holdSecMin,
      previous.holdSecMax,
      previous.rirMin,
      previous.rirMax,
      previous.perSide,
      previous.notes
    ], [
      20,
      30,
      1,
      2,
      true,
      'Nota anterior'
    ]);
    await mount(
        tester, PlanEditScreen(draft: await repo.load(versions.last.id)),
        overrides: [databaseProvider.overrideWithValue(db)]);
    await tester.ensureVisible(field('Sostén mín (s)'));
    final input = tester.widget<EditableText>(find.descendant(
        of: field('Sostén mín (s)'), matching: find.byType(EditableText)));
    expect(input.controller.text, '35');
    for (final (label, value) in [
      ('Sostén máx (s)', '50'),
      ('RIR mín', '0'),
      ('RIR máx', '3'),
      ('Notas del ejercicio', 'Nota personal nueva')
    ]) {
      await tester.ensureVisible(field(label));
      expect(
          tester
              .widget<EditableText>(find.descendant(
                  of: field(label), matching: find.byType(EditableText)))
              .controller
              .text,
          value);
    }
    await shot(tester, 'editor-reabierto');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'editor rechaza rangos de sostén y RIR inválidos antes de escribir',
      (tester) async {
    final db = openInMemoryDatabase();
    final repo = PlanRepository(db, ExerciseRepository(db));
    final draft = PlanDraft.empty(DateTime(2026, 10, 12));
    draft.days.first
      ..type = DayType.bloques
      ..exercises.add(PlanExerciseDraft(name: 'Sostén'));
    await mount(tester, PlanEditScreen(draft: draft),
        overrides: [databaseProvider.overrideWithValue(db)]);
    await enter(tester, 'Sostén mín (s)', '0');
    await tester.tap(find.text('Guardar versión'));
    await settle(tester);
    expect(await repo.versions(), isEmpty);
    await enter(tester, 'Sostén mín (s)', '40');
    await enter(tester, 'Sostén máx (s)', '20');
    await tester.tap(find.text('Guardar versión'));
    await settle(tester);
    expect(await repo.versions(), isEmpty);
    await enter(tester, 'Sostén máx (s)', '50');
    await enter(tester, 'RIR mín', '6');
    await tester.tap(find.text('Guardar versión'));
    await settle(tester);
    expect(await repo.versions(), isEmpty);
    await enter(tester, 'RIR mín', '3');
    await enter(tester, 'RIR máx', '1');
    await tester.tap(find.text('Guardar versión'));
    await settle(tester);
    expect(await repo.versions(), isEmpty);
    await enter(tester, 'RIR máx', '4');
    await tester.tap(find.text('Guardar versión'));
    await settle(tester);
    expect(await repo.versions(), hasLength(1),
        reason: 'el caso válido sí cruza editor y SQLite');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'guía conserva pasos y claves personales, deduplica y distingue búsqueda de video',
      (tester) async {
    const sharedStep =
        'Baja en 2 segundos hasta estirar los brazos por completo.';
    await mount(
        tester,
        const Scaffold(
            body: TechniqueContent(
          exercise: 'Dominadas',
          loaded: false,
          cues: ['Mi clave personal', ' Mi clave personal ', sharedStep],
          mediaUrl: 'https://www.youtube.com/results?search_query=dominadas',
        )),
        overrides: [
          exerciseArtProvider.overrideWith((ref) => art),
          figure3dProvider.overrideWith((ref) => figures),
          exercisePhotoProvider.overrideWith((ref, _) => Stream.value(null)),
          documentsDirProvider.overrideWith((ref) => Directory.systemTemp),
        ]);
    // Contar los hijos reales de la lista evita confundir un texto que salió
    // del caché con uno que se eliminó. La visibilidad se comprueba al navegar.
    Iterable<String> textContent(Widget widget) sync* {
      if (widget is Text && widget.data != null) yield widget.data!;
      if (widget is SingleChildRenderObjectWidget && widget.child != null) {
        yield* textContent(widget.child!);
      }
      if (widget is ProxyWidget) yield* textContent(widget.child);
      if (widget is MultiChildRenderObjectWidget) {
        for (final child in widget.children) {
          yield* textContent(child);
        }
      }
    }

    final children = (tester
            .widget<ListView>(find.byType(ListView))
            .childrenDelegate as SliverChildListDelegate)
        .children;
    final texts = children.expand(textContent).toList();
    expect(texts.where((text) => text == sharedStep), hasLength(1),
        reason: 'el paso fijo no se repite como clave personal');
    expect(texts.where((text) => text == 'Mi clave personal'), hasLength(1),
        reason: 'las claves personales duplicadas se muestran una sola vez');
    await tester.scrollUntilVisible(find.text(sharedStep), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text(sharedStep).hitTestable(), findsOneWidget,
        reason: 'el paso conservado es accesible al recorrer la guía');
    await tester.scrollUntilVisible(find.text('Claves personales'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    expect(find.text('Claves personales').hitTestable(), findsOneWidget);
    expect(find.text('Mi clave personal').hitTestable(), findsOneWidget);
    await shot(tester, 'guia-claves');
    await tester.scrollUntilVisible(find.text('Buscar demostración'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Ver video de referencia'), findsNothing);
    await shot(tester, 'guia-busqueda');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin guía fija muestra claves únicas y conserva el video exacto',
      (tester) async {
    await mount(
        tester,
        const Scaffold(
            body: TechniqueContent(
          exercise: 'Ejercicio propio',
          cues: [' Una clave ', 'Una clave', ''],
          mediaUrl: 'https://www.youtube.com/watch?v=referencia',
        )),
        overrides: [
          exerciseArtProvider.overrideWith((ref) => art),
          figure3dProvider.overrideWith((ref) => figures),
          exercisePhotoProvider.overrideWith((ref, _) => Stream.value(null)),
          documentsDirProvider.overrideWith((ref) => Directory.systemTemp),
        ]);
    expect(find.text('Una clave'), findsOneWidget);
    expect(find.text('Claves personales'), findsNothing);
    expect(find.text('Ver video de referencia'), findsOneWidget);
    expect(find.text('Buscar demostración'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Hoy muestra CTA antes de la rutina larga y conserva expansión y día completo',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('seguimiento_experiencia');
    final db = openInMemoryDatabase();
    final flags = LocalFlags(File('${dir.path}/flags.json'));
    final date = DateTime(2026, 10, 12);
    TodayDashboard dashboard({int sessions = 0, bool planB = false}) =>
        TodayDashboard(
          date: date,
          weekIndex: 7,
          dayType: DayType.trenSuperior,
          planVersion: 3,
          planSummary: null,
          mainExercises: [for (var i = 1; i <= 12; i++) 'Ejercicio $i'],
          blockExercises: const ['Core A: mantener', 'Core B: alternar'],
          targetRounds: null,
          roundsDone: null,
          sessionsToday: sessions,
          streak: 14,
          macros: const Macros(),
          proteinMin: 130,
          proteinMax: 160,
          kcalTarget: 2100,
          roundsRecord: null,
          measurement: null,
          planB: planB,
        );
    Future<void> home({int sessions = 0, bool planB = false}) =>
        mount(tester, const HomeScreen(), overrides: [
          databaseProvider.overrideWithValue(db),
          localFlagsProvider.overrideWithValue(flags),
          todayProvider.overrideWith(_FixedToday.new),
          dashboardProvider.overrideWith(
              (ref) => dashboard(sessions: sessions, planB: planB)),
          activeSessionProvider.overrideWith((ref) => null),
          updateCheckProvider.overrideWith(
              (ref) => const UpdateCheck(currentVersion: '1.19.0')),
          morningDoneProvider.overrideWith((ref, _) => false),
        ]);
    await home();
    expect(find.text('Empezar tren superior').hitTestable(), findsOneWidget);
    await shot(tester, 'hoy-inicio');
    expect(find.text('• Ejercicio 12'), findsNothing);
    expect(find.text('Registro de la mañana: peso, pulso, sueño y molestias'),
        findsOneWidget);
    await tester.tap(find.text('Ver rutina'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('• Ejercicio 12'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('• Ejercicio 12'), findsOneWidget);
    expect(find.text('Además (A y B se alternan por semana):'), findsOneWidget);
    await shot(tester, 'hoy-rutina');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await home(sessions: 1);
    expect(find.text('Día completo').hitTestable(), findsOneWidget);
    expect(find.text('Empezar tren superior'), findsNothing);
    expect(find.text('Otra sesión'), findsOneWidget);
    await shot(tester, 'hoy-completo');
    await tester.pumpWidget(const SizedBox());
    await home(planB: true);
    expect(find.text('Plan B: solo torso'), findsOneWidget);
    expect(find.text('Empezar plan B'), findsOneWidget);
    await shot(tester, 'hoy-planb');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
