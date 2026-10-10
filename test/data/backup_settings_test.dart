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
      final deadline = Stopwatch()..start();
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
      expect(find.textContaining('Contienen la base y el historial de IA, sin fotos ni licencia.'), findsOneWidget);
      expect(find.textContaining('Una por semana, sin cifrar dentro de la app'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('Restaurar desde un respaldo')));
      for (var i = 0; i < 150 && find.text('¿Restaurar este respaldo?').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('¿Restaurar este respaldo?'), findsOneWidget);
      expect(find.textContaining('las 1 fotos del ZIP'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)), listen: false);
      await tester.runAsync(() => tester.tap(find.text(confirm ? 'Restaurar' : 'Cancelar')));
      var completed = false;
      // Espera la frontera real, no un número de frames: SQLite y las fotos
      // siguen trabajando fuera del reloj falso. El timeout del test conserva
      // sus 30 s; reservamos 5 s para releer datos y cerrar los recursos.
      while (deadline.elapsed < const Duration(seconds: 25)) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
        expect(tester.takeException(), isNull);
        final errors = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .where((text) => text.startsWith('Error:') || text.startsWith('No se pudo'));
        expect(errors, isEmpty, reason: 'La restauración debe terminar sin error visible');
        final snacks = tester
            .widgetList<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)))
            .map((w) => w.data ?? '')
            .toList();
        if (confirm && snacks.isNotEmpty) {
          expect(snacks, ['Registros y 1 fotos restaurados']);
        }
        // OutlinedButton.icon es un subtipo: byType(OutlinedButton) no lo
        // encuentra y convertiría la espera en un bucle fijo inadvertido.
        final restoreButtons = tester
            .widgetList<OutlinedButton>(find.ancestor(
                of: find.text('Restaurar desde un respaldo'),
                matching: find.byWidgetPredicate((w) => w is OutlinedButton)))
            .toList();
        completed = find.text('¿Restaurar este respaldo?').evaluate().isEmpty &&
            container.read(databaseGenerationProvider) == (confirm ? 1 : 0) &&
            find.text('Restaurando respaldo').evaluate().isEmpty &&
            restoreButtons.length == 1 &&
            restoreButtons.single.onPressed != null &&
            (!confirm || find.text('Registros y 1 fotos restaurados').evaluate().isNotEmpty);
        if (completed) break;
      }
      expect(completed, isTrue, reason: 'La operación debe cerrar su UI y renovar la base antes de releer');
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
