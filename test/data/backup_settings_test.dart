import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/app/providers.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/health_connect.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/features/settings/health_connect_card.dart';
import 'package:seguimiento/features/settings/settings_screen.dart';

import '../support/sqlite_host.dart';

// Solo el diálogo del sistema se sustituye: ZIP, SQLite, archivos, pantalla,
// confirmación y renovación de repositorios usan la implementación real.
class _SelectedFile extends FilePicker {
  _SelectedFile(this.file);
  final File file;
  @override
  Future<FilePickerResult?> pickFiles(
          {String? dialogTitle,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Function(FilePickerStatus)? onFileLoading,
          bool allowCompression = true,
          int compressionQuality = 30,
          bool allowMultiple = false,
          bool withData = false,
          bool withReadStream = false,
          bool lockParentWindow = false,
          bool readSequential = false}) async =>
      FilePickerResult([PlatformFile(name: file.uri.pathSegments.last, path: file.path, size: file.lengthSync())]);
}

void main() {
  setUpAll(() {
    useHostSqlite();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  for (final confirm in [false, true]) {
    testWidgets('Ajustes recorre ZIP y ${confirm ? 'confirma restauración' : 'cancela sin tocar datos'}',
        (tester) async {
      late Directory root;
      late DatabaseHost a;
      late DatabaseHost b;
      late File package;
      await tester.runAsync(() async {
        root = Directory.systemTemp.createTempSync('seguimiento_backup_settings_');
        final dirA = Directory('${root.path}/A')..createSync();
        final dirB = Directory('${root.path}/B')..createSync();
        a = DatabaseHost(File('${dirA.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
        b = DatabaseHost(File('${dirB.path}/seguimiento.sqlite'), (f) => AppDatabase(NativeDatabase(f)));
        await BodyRepository(a.db).addWeight(DateTime(2026, 10, 1), 72);
        await BodyRepository(b.db).addWeight(DateTime(2026, 10, 2), 73);
        File('${dirA.path}/fotos/primera.jpg')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1, 2, 3]);
        await a.db.customStatement(
            "INSERT INTO progress_photos (date, angle, relative_path) VALUES ('2026-10-01', 'frente', 'fotos/primera.jpg')");
        package = (await BackupArchive(host: a, documents: dirA).exportTo('${root.path}/transportado.zip')).file;
      });
      FilePicker.platform = _SelectedFile(package);
      tester.view.physicalSize = const Size(1400, 7000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseHostProvider.overrideWithValue(b),
          documentsDirProvider.overrideWith((_) => b.file.parent),
          autoBackupsProvider.overrideWith((_) => []),
          healthConnectStateProvider.overrideWith((_) =>
              const HealthConnectState(status: HealthConnectStatus.desconocido, permitted: false, enabled: false)),
          appVersionProvider.overrideWith((_) => '0.0.0'),
          updateCheckProvider.overrideWith((_) => const UpdateCheck(currentVersion: '0.0.0')),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Exportar registros y fotos'), findsOneWidget);
      expect(find.textContaining('Solo contienen registros, sin fotos.'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('Restaurar desde un respaldo')));
      for (var i = 0; i < 150 && find.text('¿Restaurar este respaldo?').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('¿Restaurar este respaldo?'), findsOneWidget);
      expect(find.textContaining('las 1 fotos del ZIP'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text(confirm ? 'Restaurar' : 'Cancelar')));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
        if (find.text('¿Restaurar este respaldo?').evaluate().isEmpty &&
            find.text('Restaurando respaldo').evaluate().isEmpty &&
            find.widgetWithText(OutlinedButton, 'Restaurar desde un respaldo').evaluate().isNotEmpty &&
            tester
                    .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Restaurar desde un respaldo'))
                    .onPressed !=
                null) {
          break;
        }
      }
      final container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)), listen: false);
      expect(container.read(databaseGenerationProvider), confirm ? 1 : 0);
      await tester.runAsync(() async {
        expect((await BodyRepository(b.db).watchWeights().first).map((w) => w.kg), [confirm ? 72 : 73]);
        expect(File('${b.file.parent.path}/fotos/primera.jpg').existsSync(), confirm);
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(() async {
        await a.db.close();
        await b.db.close();
        root.deleteSync(recursive: true);
      });
    });
  }
}
