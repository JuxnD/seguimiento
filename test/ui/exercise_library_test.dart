import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/features/training/technique_sheet.dart';
import 'package:seguimiento/features/training/exercise_library_screen.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import 'package:seguimiento/ui/theme.dart';
import '../support/test_fonts.dart';

void main() {
  final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());
  final out = Platform.environment['ILLUSTRATION_OUT'];
  late GlobalKey captureKey;
  Future<void> mount(WidgetTester tester, {double scale = 1, Size size = const Size(360, 800)}) async {
    captureKey = GlobalKey();
    await loadTestFonts(tester);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final theme = buildGymTheme();
    ButtonStyle? fontButton(ButtonStyle? style) => style?.copyWith(
        textStyle: WidgetStateProperty.resolveWith(
            (states) => (style.textStyle?.resolve(states) ?? const TextStyle()).copyWith(fontFamily: 'Roboto')));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          figure3dProvider.overrideWith((ref) async => catalog),
          exercisePhotoProvider.overrideWith((ref, _) => Stream.value(null)),
          documentsDirProvider.overrideWith((ref) => Directory.systemTemp),
        ],
        child: RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
                theme: theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
                  appBarTheme: theme.appBarTheme
                      .copyWith(titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto')),
                  filledButtonTheme: FilledButtonThemeData(style: fontButton(theme.filledButtonTheme.style)),
                  outlinedButtonTheme: OutlinedButtonThemeData(style: fontButton(theme.outlinedButtonTheme.style)),
                  textButtonTheme: TextButtonThemeData(style: fontButton(theme.textButtonTheme.style)),
                  chipTheme:
                      theme.chipTheme.copyWith(labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: 'Roboto')),
                  inputDecorationTheme: theme.inputDecorationTheme
                      .copyWith(labelStyle: theme.inputDecorationTheme.labelStyle?.copyWith(fontFamily: 'Roboto')),
                ),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
                home: const ExerciseLibraryScreen()))));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (out == null) return;
    final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('buscar sin tildes, consultar ambos lados y ampliar sin crear sesión', (tester) async {
    await mount(tester);
    await capture(tester, 'biblioteca-movil');
    await tester.enterText(find.byType(TextField), 'plancha lateral');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Plancha lateral'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Plancha lateral'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Lado derecho'));
    await tester.pumpAndSettle();
    final moments = tester.widget<Figure3DMoments>(find.byType(Figure3DMoments));
    expect(moments.figure.mirrored, isTrue);
    await capture(tester, 'guia-movil');
    await tester.tap(find.byKey(const ValueKey('figura3d-0')));
    await tester.pumpAndSettle();
    expect(find.byType(Figure3DFullScreen), findsOneWidget);
    await tester.tap(find.text('Ver apoyos'));
    await tester.pump();
    await capture(tester, 'apoyos-movil');
    expect(tester.takeException(), isNull);
  });
  testWidgets('la variante supina con mochila se refleja en la figura consultada', (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'dominadas');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Dominadas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Supina'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Con mochila'));
    await tester.pumpAndSettle();
    final figure = tester.widget<Figure3DMoments>(find.byType(Figure3DMoments)).figure;
    expect(figure.frames.first.limbs['nearArm']!.grip, 'bar_supina');
    expect(figure.props.any((p) => p['type'] == 'backpack'), isTrue);
  });
  testWidgets('búsqueda vacía explica el resultado; texto ampliado conserva consulta', (tester) async {
    await mount(tester, scale: 1.6);
    await tester.enterText(find.byType(TextField), 'sin coincidencia');
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay coincidencias'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nordico');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Nórdico (isquios)'));
    await tester.pumpAndSettle();
    await capture(tester, 'texto-grande');
    expect(tester.takeException(), isNull);
  });
  testWidgets('biblioteca en tableta mantiene figuras y búsqueda', (tester) async {
    await mount(tester, size: const Size(900, 800));
    await capture(tester, 'biblioteca-tableta');
    expect(find.byType(ListTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
