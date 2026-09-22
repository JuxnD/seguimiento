import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/update_service.dart';

const _body = '''
{
  "tag_name": "v1.4.0",
  "html_url": "https://github.com/usuario/seguimiento/releases/tag/v1.4.0",
  "body": "Restauración de respaldo",
  "assets": [
    {"name": "notas.txt", "browser_download_url": "https://x/notas.txt"},
    {"name": "seguimiento-v1.4.0.apk", "browser_download_url": "https://x/seguimiento-v1.4.0.apk"}
  ]
}
''';

void main() {
  group('lectura de la release', () {
    test('toma la etiqueta, las notas y el APK adjunto', () {
      final r = parseRelease(_body)!;
      expect(r.version, 'v1.4.0');
      expect(r.notes, 'Restauración de respaldo');
      expect(r.apkUrl.toString(), endsWith('seguimiento-v1.4.0.apk'));
    });

    test('sin APK adjunto queda solo la página', () {
      final r = parseRelease('{"tag_name":"v2.0.0","html_url":"https://github.com/u/r/releases/tag/v2.0.0"}')!;
      expect(r.apkUrl, isNull);
      expect(r.pageUrl.toString(), contains('v2.0.0'));
    });

    test('respuesta inesperada devuelve null en vez de reventar', () {
      expect(parseRelease('[]'), isNull);
      expect(parseRelease('{"body":"sin tag"}'), isNull);
    });
  });

  group('consulta de actualización', () {
    final apiUrl = Uri.parse('https://api.github.com/repos/usuario/seguimiento/releases/latest');

    UpdateService serviceReturning(http.Response response) =>
        UpdateService(client: MockClient((_) async => response), apiUrl: apiUrl);

    test('anuncia solo si la publicada es más nueva', () async {
      final service = serviceReturning(http.Response(_body, 200));
      expect((await service.check(currentVersion: '1.3.0')).hasUpdate, isTrue);
      expect((await service.check(currentVersion: '1.4.0')).hasUpdate, isFalse);
      expect((await service.check(currentVersion: '2.0.0')).hasUpdate, isFalse);
    });

    test('sin releases publicadas informa, no falla', () async {
      final result = await serviceReturning(http.Response('{}', 404)).check(currentVersion: '1.0.0');
      expect(result.hasUpdate, isFalse);
      expect(result.error, contains('Todavía no hay'));
    });

    test('un error de red se reporta como texto', () async {
      final service = UpdateService(
        client: MockClient((_) => Future.error(Exception('sin internet'))),
        apiUrl: apiUrl,
      );
      final result = await service.check(currentVersion: '1.0.0');
      expect(result.hasUpdate, isFalse);
      expect(result.error, contains('No se pudo consultar'));
    });
  });
}
