import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:drift/native.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/database_host.dart';
import 'package:seguimiento/data/backup_archive.dart';
import 'package:seguimiento/data/repositories/body_repository.dart';
import 'package:seguimiento/data/weekly_ai.dart';
import 'package:seguimiento/features/report/weekly_ai_screen.dart';
import 'package:seguimiento/ui/theme.dart';

void main() {
  const qaLicense = String.fromEnvironment('SEGUIMIENTO_QA_LICENSE');
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'activación nativa: identidad estable, licencia cifrada y olvidable; UI no envía sola',
      (tester) async {
    final activation = AiActivation();
    final (hwid, _) = await activation.read();
    expect(hwid, matches(RegExp(r'^SEG-[A-F0-9]{32}$')));
    const license = 'AAAA-BBBB-CCCC-DDDD';
    await activation.save(license);
    final (same, stored) = await activation.read();
    expect(same, hwid);
    expect(stored, license);
    final support = await getApplicationSupportDirectory();
    final encrypted =
        File('${support.parent.path}/no_backup/ai-activation.json');
    expect(await encrypted.exists(), isTrue);
    final raw = await encrypted.readAsString();
    expect(raw, isNot(contains(license)));
    expect(raw, contains('secret'));
    await activation.save('');
    final (after, empty) = await activation.read();
    expect(after, hwid);
    expect(empty, isEmpty);
    await tester.pumpWidget(MaterialApp(
        theme: buildGymTheme(),
        home: const WeeklyAiScreen(
            report: 'Semana ficticia\nPeso: sin registro')));
    await tester.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, 'Enviar y analizar');
    await tester.scrollUntilVisible(send, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('consulta sintética desde Android al gateway publicado',
      (tester) async {
    final activation = AiActivation();
    final (hwid, _) = await activation.read();
    const report =
        'Informe ficticio de QA\nProteína: promedio 100 g; meta mínima 130 g.\nPeso: sin registro.\nSueño: sin registro.\n';
    final client = http.Client();
    try {
      final notes = await WeeklyAi(client).analyze(report, hwid, qaLicense);
      expect(notes, isNotEmpty);
      for (final note in notes) {
        expect(report, contains(note.quote));
      }
    } finally {
      client.close();
    }
  }, skip: qaLicense.isEmpty);
  testWidgets(
      'Android: ZIP real transporta registros y ambas fotos entre espacios sintéticos',
      (tester) async {
    final root =
        await Directory.systemTemp.createTemp('seguimiento-native-backup-');
    final aDir = await Directory('${root.path}/A').create();
    final bDir = await Directory('${root.path}/B').create();
    final a = DatabaseHost(File('${aDir.path}/seguimiento.sqlite'),
        (f) => AppDatabase(NativeDatabase(f)));
    final b = DatabaseHost(File('${bDir.path}/seguimiento.sqlite'),
        (f) => AppDatabase(NativeDatabase(f)));
    try {
      await BodyRepository(a.db).addWeight(DateTime(2026, 10, 1), 72);
      await BodyRepository(b.db).addWeight(DateTime(2026, 10, 2), 73);
      for (final path in ['fotos/frente.jpg', 'fotos/ejercicios/flexion.jpg']) {
        final photo = File('${aDir.path}/$path');
        await photo.parent.create(recursive: true);
        await photo.writeAsBytes([1, 3, 5, 7]);
      }
      await a.db.customStatement(
          "INSERT INTO progress_photos (date,angle,relative_path) VALUES ('2026-10-01','frente','fotos/frente.jpg')");
      await a.db.customStatement(
          "INSERT INTO exercise_photos (name_key,relative_path) VALUES ('flexion','fotos/ejercicios/flexion.jpg')");
      final output = await BackupArchive(host: a, documents: aDir)
          .exportTo('${root.path}/portable.zip');
      await BackupArchive(host: b, documents: bDir).restoreFrom(output.file);
      expect((await BodyRepository(b.db).watchWeights().first).single.kg, 72);
      for (final path in ['fotos/frente.jpg', 'fotos/ejercicios/flexion.jpg']) {
        expect(await File('${bDir.path}/$path').readAsBytes(), [1, 3, 5, 7]);
      }
    } finally {
      await a.db.close();
      await b.db.close();
      await root.delete(recursive: true);
    }
  });
}
