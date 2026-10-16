import 'package:flutter_test/flutter_test.dart';
import 'package:seguimiento/data/database.dart';
import 'package:seguimiento/data/repositories/watch_repository.dart';
import 'package:seguimiento/data/update_service.dart';
import 'package:seguimiento/domain/watch_capture.dart';
import '../support/sqlite_host.dart';

/// Plan 058 (§16.17): INNOVA sólo escribe pasos en Health Connect; pulso,
/// kcal y duración vienen de su captura o a mano. Textos de captura
/// ficticios con la forma del registro del 6 oct del traspaso.
void main() {
  setUpAll(useHostSqlite);

  test('captura con etiquetas: actividad, inicio, duración, pulso y kcal', () {
    final r = parseWatchText('''
Capacitación gratuita
5:17 p. m.
Duración
31:16
Frecuencia cardíaca media
100 lpm
Frecuencia cardíaca máx.
124 lpm
Calorías
248 kcal
''');
    expect(r.kind, 'Capacitación gratuita');
    expect(r.startTime, '17:17');
    expect(r.durationSec, 31 * 60 + 16);
    expect((r.avgHr, r.maxHr), (100, 124));
    expect(r.kcal, 248);
    expect(watchReadingProblem(r), isNull);
  });

  test('captura sin etiquetas: «134 / 154 lpm» es medio / máximo', () {
    final r = parseWatchText('Caminar 12:56 p. m. 10:19 134 / 154 lpm 49 kcal 2.071 pasos 1,2 km');
    expect(r.kind, 'Caminar');
    expect(r.startTime, '12:56');
    expect(r.durationSec, 10 * 60 + 19);
    expect((r.avgHr, r.maxHr), (134, 154));
    expect(r.kcal, 49);
    expect(r.steps, 2071);
    expect(r.distanceM, 1200);
  });

  test('presión y SpO₂ del reloj', () {
    final r = parseWatchText('Presión arterial\n122/76 mmHg\nSpO₂\n97 %');
    expect((r.systolic, r.diastolic, r.spo2), (122, 76, 97));
    expect(r.hasVitals, isTrue);
    expect(r.hasActivity, isFalse);
  });

  test('lo que no se lee queda vacío; lo imposible se rechaza', () {
    expect(parseWatchText('foto sin datos').isEmpty, isTrue);
    expect(watchReadingProblem(WatchReading(avgHr: 150, maxHr: 120)),
        contains('máximo es menor'));
    expect(watchReadingProblem(WatchReading(systolic: 120)),
        contains('dos números'));
    expect(watchReadingProblem(WatchReading(spo2: 40)), contains('SpO₂'));
  });

  test('zona y carga por pulso con el máximo estimado', () {
    final max = estimatedMaxHr(DateTime(2000, 1, 1), DateTime(2026, 10, 16));
    expect(max, 208 - (0.7 * 26).round());
    expect(hrZone(100, max), 1);
    expect(hrZone(160, max), 4);
    final trimp = banisterTrimp(
        durationSec: 31 * 60, avgHr: 100, restHr: 60, maxHr: 190);
    expect(trimp, closeTo(31 * (40 / 130) * 0.64 * 1.806, 0.5));
    expect(banisterTrimp(durationSec: 600, avgHr: 100, restHr: null, maxHr: 190),
        isNull, reason: 'sin pulso en reposo no se inventa');
  });

  test('se guarda la actividad unida a la sesión y la presión aparte', () async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final repo = WatchRepository(db);
    final r = parseWatchText(
        'Caminar 10:19 134 / 154 lpm 49 kcal\nPresión 122/76 mmHg');
    final id = await repo.saveReading(r,
        date: DateTime(2026, 10, 6), source: 'captura');
    expect(id, isNotNull);
    final vitals = await repo.watchVitals().first;
    expect((vitals.single.systolic, vitals.single.source), (122, 'reloj'));
    expect(() => repo.saveReading(WatchReading(avgHr: 300),
        date: DateTime(2026, 10, 6), source: 'manual'), throwsFormatException);
  });

  test('actualizar: el manifiesto trae el SHA-256 y sólo se baja de GitHub', () {
    final release = parseRelease('''
{"tag_name":"v1.30.0","html_url":"https://github.com/JuxnD/seguimiento/releases/tag/v1.30.0","body":"",
 "assets":[
  {"name":"MyPrime-1.30.0+44.apk","browser_download_url":"https://github.com/JuxnD/seguimiento/releases/download/v1.30.0/MyPrime-1.30.0+44.apk"},
  {"name":"MyPrime-1.30.0+44.manifest.json","browser_download_url":"https://github.com/JuxnD/seguimiento/releases/download/v1.30.0/MyPrime-1.30.0+44.manifest.json"}
 ]}''')!;
    expect(release.apkName, 'MyPrime-1.30.0+44.apk');
    expect(release.manifestUrl.toString(), endsWith('.manifest.json'));
    expect(UpdateInstaller.trustedHost(release.apkUrl!), isTrue);
    expect(UpdateInstaller.trustedHost(Uri.parse('https://evil.example/app.apk')),
        isFalse);
    expect(UpdateInstaller.trustedHost(Uri.parse('http://github.com/x.apk')),
        isFalse, reason: 'sin https no');
  });
}
