import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/exercise_photo_repository.dart';
import 'package:seguimiento/domain/mobility.dart';
import 'package:seguimiento/ui/exercise_art.dart';
import 'package:seguimiento/ui/exercise_figure.dart';

import '../support/sqlite_host.dart';

/// Ilustraciones de técnica: el asset que genera `tool/figuras.py`.
void main() {
  final catalog = ExerciseArtCatalog.fromJsonString(File(ExerciseArtCatalog.asset).readAsStringSync());

  test('cada ejercicio del plan y de la movilidad tiene figura', () {
    const plan = [
      'Dominadas',
      'Flexiones',
      'Sentadillas',
      'Sentadilla búlgara',
      'Pike push-up',
      'Elevación de piernas colgado',
      'Hollow body hold',
      'Plancha lateral',
    ];
    for (final name in [...plan, ...mobilityNight.exercises.map((e) => e.name)]) {
      final art = catalog.forExercise(name);
      expect(art, isNotNull, reason: 'falta la figura de $name');
      expect(art!.frames, isNotEmpty);
      expect(art.muscles, isNotEmpty);
      expect(art.boxWidth, greaterThan(0));
    }
  });

  test('se busca sin mayúsculas ni tildes', () {
    expect(catalog.forExercise('  sentadilla BULGARA ')?.name, 'Sentadilla búlgara');
    expect(catalog.forExercise('Burpees'), isNull);
  });

  test('los errores a evitar van marcados', () {
    final plank = catalog.forExercise('Plancha lateral')!;
    expect(plank.frames.map((f) => f.wrong), [false, true]);
    expect(plank.frames.last.caption, startsWith('Evita'));
  });

  testWidgets('todas las figuras se pintan sin errores', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    for (final art in catalog.all) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ExerciseArtFrames(art: art))),
      ));
      expect(tester.takeException(), isNull, reason: art.name);
      expect(find.textContaining(art.muscles), findsOneWidget);
      for (final frame in art.frames) {
        expect(find.text(frame.caption), findsOneWidget);
      }
    }
  });

  group('foto de referencia', () {
    setUpAll(useHostSqlite);

    test('se guarda, se reemplaza borrando la anterior y se quita', () async {
      final dir = Directory.systemTemp.createTempSync('seguimiento_foto_ejercicio');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows puede tener el archivo tomado.
        }
      });
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final repo = ExercisePhotoRepository(db, () async => dir);
      final first = File('${dir.path}/captura.PNG')..writeAsBytesSync([1, 2, 3]);
      final second = File('${dir.path}/otra.jpg')..writeAsBytesSync([4, 5]);

      await repo.save('Sentadilla búlgara', first);
      final row1 = (await repo.watch('sentadilla bulgara').first)!;
      expect(row1.relativePath, contains('sentadilla-bulgara'));
      expect(row1.relativePath, endsWith('.png'));
      expect(ExercisePhotoRepository.fileIn(dir, row1).readAsBytesSync(), [1, 2, 3]);

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await repo.save('Sentadilla búlgara', second);
      final row2 = (await repo.watch('Sentadilla búlgara').first)!;
      expect(row2.relativePath, isNot(row1.relativePath));
      expect(ExercisePhotoRepository.fileIn(dir, row1).existsSync(), isFalse, reason: 'la anterior se borra');
      expect((await db.select(db.exercisePhotos).get()), hasLength(1));

      await repo.remove('Sentadilla búlgara');
      expect(await repo.watch('Sentadilla búlgara').first, isNull);
      expect(ExercisePhotoRepository.fileIn(dir, row2).existsSync(), isFalse);
    });

    test('una ruta fuera de la carpeta de fotos no se borra', () async {
      final dir = Directory.systemTemp.createTempSync('seguimiento_foto_fuera');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows puede tener el archivo tomado.
        }
      });
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      final victim = File('${dir.path}/seguimiento.sqlite')..writeAsBytesSync([9]);
      await db.into(db.exercisePhotos).insert(
            ExercisePhotosCompanion.insert(nameKey: 'flexiones', relativePath: '../seguimiento.sqlite'),
          );
      await ExercisePhotoRepository(db, () async => Directory('${dir.path}/app')).remove('Flexiones');
      expect(victim.existsSync(), isTrue);
      expect(await db.select(db.exercisePhotos).get(), isEmpty);
    });
  });
}
