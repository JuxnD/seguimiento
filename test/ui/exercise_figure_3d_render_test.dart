import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/features/training/technique_sheet.dart';
import 'package:seguimiento/ui/exercise_art.dart';
import 'package:seguimiento/ui/exercise_figure.dart';
import 'package:seguimiento/ui/exercise_figure_3d.dart';
import 'package:seguimiento/ui/exercise_figure_3d_view.dart';
import 'package:seguimiento/ui/theme.dart';

/// Renders para revisar a ojo el maniquí 3D (no es una prueba de oro: no
/// compara píxeles). Solo corre si se pide una carpeta de salida:
///
///     FIG3D_OUT=/ruta/carpeta flutter test test/ui/exercise_figure_3d_render_test.dart
///
/// Escribe, por ejercicio, los tres momentos a 1080 px de ancho (360 dp a
/// densidad 3, como un teléfono) y vistas giradas, y la hoja de técnica
/// completa. Para el texto usa la Roboto que trae el SDK de Flutter
/// (`FLUTTER_ROOT`); sin ella el texto sale en cajas.
void main() {
  final out = Platform.environment['FIG3D_OUT'];
  final catalog = Figure3DCatalog.fromJsonString(File(Figure3DCatalog.asset).readAsStringSync());

  testWidgets('renders del maniquí 3D', (tester) async {
    final dir = Directory(out!)..createSync(recursive: true);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final shots = <(String, double, double?, double?, Size)>[];
    for (final (i, fig) in catalog.all.indexed) {
      final slug = '${i + 1}-${fig.name.split(' ').first.toLowerCase().replaceAll('ó', 'o')}';
      for (final (k, name) in const ['inicio', 'medio', 'final'].indexed) {
        shots.add(('$slug-$k-$name', k / 2, null, null, const Size(344, 260)));
      }
      shots.add(('$slug-z-giro45', 0.5, 45, 18, const Size(344, 260)));
      shots.add(('$slug-x-frente', 0.5, 90, 5, const Size(344, 260)));
      shots.add(('$slug-x-perfil', 0.5, 0, 0, const Size(344, 260)));
      shots.add(('$slug-z-giro-60', 1, -60, 18, const Size(344, 260)));
      for (final (k, t) in const [0.25, 0.6, 0.75, 0.9].indexed) {
        shots.add(('$slug-y-anim$k', t, null, null, const Size(344, 260)));
      }
    }
    for (final (name, progress, yaw, pitch, size) in shots) {
      final fig = catalog.all.elementAt(int.parse(name.split('-').first) - 1);
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              width: size.width,
              height: size.height,
              color: const Color(0xFF0B0806),
              child: CustomPaint(painter: _Painter(fig, progress, yaw, pitch)),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull, reason: name);
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  }, skip: out == null);

  testWidgets('hoja de técnica en un teléfono', (tester) async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? '';
    final fonts = '$root/bin/cache/artifacts/material_fonts';
    if (Directory(fonts).existsSync()) {
      Future<void> load(String family, List<String> files) async {
        final loader = FontLoader(family);
        for (final f in files) {
          loader.addFont(Future.value(ByteData.sublistView(File('$fonts/$f').readAsBytesSync())));
        }
        await loader.load();
      }

      await tester.runAsync(() async {
        await load('Roboto', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
        // Los estilos sin familia caen en la fuente de pruebas: también Roboto.
        await load('FlutterTest', ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']);
        await load('MaterialIcons', ['materialicons-regular.otf']);
      });
    }
    final dir = Directory(out!)..createSync(recursive: true);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final art2d = ExerciseArtCatalog.fromJsonString(File(ExerciseArtCatalog.asset).readAsStringSync());
    final theme = buildGymTheme();
    for (final (slug, exercise) in const [
      ('1-pino', 'Pino pecho a la pared'),
      ('2-nordico', 'Nórdico (isquios)'),
      ('3-dominadas', 'Dominadas'),
      ('4-flexiones-2d', 'Flexiones')
    ]) {
      final key = GlobalKey();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          figure3dProvider.overrideWith((ref) => catalog),
          exerciseArtProvider.overrideWith((ref) => art2d),
          exercisePhotoProvider.overrideWith((ref, _) => Stream.value(null)),
          documentsDirProvider.overrideWith((ref) => Directory.systemTemp),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
            home: Scaffold(
              backgroundColor: theme.colorScheme.surface,
              body: SafeArea(child: TechniqueContent(exercise: exercise)),
            ),
          ),
        ),
      ));
      await tester.pump();
      Future<void> shot(String name) async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      await shot('hoja-$slug');
      if (slug == '2-nordico') {
        await tester.drag(find.byKey(const ValueKey('figura3d-momentos')), const Offset(-320, 0));
        await tester.pumpAndSettle();
        await shot('hoja-$slug-pagina2');
        await tester.tap(find.byKey(const ValueKey('figura3d-1')));
        await tester.pumpAndSettle();
        await shot('hoja-$slug-ampliada');
        await tester.drag(find.byKey(const ValueKey('figura3d-giro')), const Offset(-90, 30));
        await tester.pumpAndSettle();
        await shot('hoja-$slug-ampliada-girada');
      }
    }
  }, skip: out == null);
}

class _Painter extends CustomPainter {
  _Painter(this.fig, this.progress, this.yaw, this.pitch);

  final Figure3D fig;
  final double progress;
  final double? yaw, pitch;

  @override
  void paint(Canvas canvas, Size size) => paintFigure3D(canvas, size, fig, progress, yaw: yaw, pitch: pitch);

  @override
  bool shouldRepaint(_Painter oldDelegate) => true;
}
