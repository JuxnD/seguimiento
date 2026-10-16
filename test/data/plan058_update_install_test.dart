import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seguimiento/data/update_service.dart';

/// Plan 058 (ADR 0018): «Actualizar» sólo deja instalar el APK cuyo SHA-256
/// coincide con el manifiesto publicado junto a él en GitHub.
void main() {
  const apkUrl =
      'https://github.com/qa/ficticio/releases/download/v1.30.0/MyPrime-1.30.0+44.apk';
  const manifestUrl =
      'https://github.com/qa/ficticio/releases/download/v1.30.0/MyPrime-1.30.0+44.manifest.json';
  final bytes = utf8.encode('apk ficticio para la prueba');
  final good = sha256.convert(bytes).toString();

  AppRelease release({String apk = apkUrl, String manifest = manifestUrl}) =>
      parseRelease(jsonEncode({
        'tag_name': 'v1.30.0',
        'html_url': 'https://github.com/qa/ficticio/releases/tag/v1.30.0',
        'body': '',
        'assets': [
          {'name': 'MyPrime-1.30.0+44.apk', 'browser_download_url': apk},
          {'name': 'MyPrime-1.30.0+44.manifest.json', 'browser_download_url': manifest},
        ],
      }))!;

  MockClient client(String sha) => MockClient((request) async {
        if (request.url.toString() == manifestUrl) {
          // Misma forma que el manifiesto real de la 1.29.0.
          return http.Response(jsonEncode({'artifact': 'MyPrime-1.30.0+44.apk', 'sha256': sha}), 200);
        }
        if (request.url.toString() == apkUrl) return http.Response.bytes(bytes, 200);
        return http.Response('', 404);
      });

  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('upd058'));
  tearDown(() => cache.deleteSync(recursive: true));

  test('con el SHA del manifiesto queda el APK listo en cache/updates', () async {
    final progress = <int>[];
    final file = await UpdateInstaller(client: client(good), cacheDir: cache)
        .download(release(), onProgress: (r, _) => progress.add(r));
    expect(file.parent.path, endsWith('updates'));
    expect(file.readAsBytesSync(), bytes);
    expect(progress.last, bytes.length);
  });

  test('si el SHA no coincide, borra el archivo y no instala', () async {
    final installer = UpdateInstaller(client: client('0' * 64), cacheDir: cache);
    await expectLater(installer.download(release()), throwsA(isA<UpdateException>()));
    expect(Directory('${cache.path}/updates').listSync(), isEmpty);
  });

  test('manifiesto sin SHA válido o fuera de GitHub: no descarga', () async {
    await expectLater(
        UpdateInstaller(client: client('no-es-un-sha'), cacheDir: cache).download(release()),
        throwsA(isA<UpdateException>()));
    await expectLater(
        UpdateInstaller(client: client(good), cacheDir: cache)
            .download(release(apk: 'https://evil.example/MyPrime.apk')),
        throwsA(isA<UpdateException>()));
    await expectLater(
        UpdateInstaller(client: client(good), cacheDir: cache)
            .download(release(manifest: 'https://evil.example/m.json')),
        throwsA(isA<UpdateException>()));
  });
}
