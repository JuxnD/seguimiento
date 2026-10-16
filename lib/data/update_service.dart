import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../domain/version.dart';

/// Una versión publicada en GitHub Releases.
class AppRelease {
  const AppRelease(
      {required this.version,
      required this.notes,
      this.apkUrl,
      this.apkName,
      this.manifestUrl,
      required this.pageUrl});

  final String version;
  final String notes;

  /// APK adjunto a la release, si lo hay.
  final Uri? apkUrl;
  final String? apkName;

  /// Plan 058 (ADR 0018): el manifiesto publicado con el APK; trae su SHA-256.
  /// Sin manifiesto no se instala desde la app (se abre la descarga).
  final Uri? manifestUrl;
  final Uri pageUrl;
}

class UpdateCheck {
  const UpdateCheck({required this.currentVersion, this.release, this.error});

  final String currentVersion;

  /// Solo si es más nueva que la instalada.
  final AppRelease? release;

  /// Mensaje para mostrar cuando la consulta falló (sin conexión, repo privado…).
  final String? error;

  bool get hasUpdate => release != null;
}

/// Consulta la última release pública del repositorio configurado.
/// No descarga ni instala nada: eso lo decide el usuario abriendo el enlace.
class UpdateService {
  /// `apiUrl` solo se pasa en pruebas; en la app sale de `lib/config.dart`.
  UpdateService({http.Client? client, Uri? apiUrl})
      : _client = client ?? http.Client(),
        _apiUrl = apiUrl;

  final http.Client _client;
  final Uri? _apiUrl;

  Future<UpdateCheck> check({required String currentVersion}) async {
    if (_apiUrl == null && !updatesConfigured) {
      return UpdateCheck(
        currentVersion: currentVersion,
        error: 'Falta configurar el repositorio de GitHub (ver docs/actualizaciones.md).',
      );
    }
    try {
      final res = await _client.get(
        _apiUrl ?? latestReleaseApi,
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 404) {
        return UpdateCheck(currentVersion: currentVersion, error: 'Todavía no hay ninguna versión publicada.');
      }
      if (res.statusCode != 200) {
        return UpdateCheck(currentVersion: currentVersion, error: 'GitHub respondió ${res.statusCode}.');
      }
      final release = parseRelease(res.body);
      if (release == null) {
        return UpdateCheck(currentVersion: currentVersion, error: 'No se entendió la respuesta de GitHub.');
      }
      return UpdateCheck(
        currentVersion: currentVersion,
        release: isNewerVersion(release.version, currentVersion) ? release : null,
      );
    } on Object catch (e) {
      return UpdateCheck(currentVersion: currentVersion, error: 'No se pudo consultar: $e');
    }
  }

  void close() => _client.close();
}

/// Separado del transporte para poder probarlo sin red.
AppRelease? parseRelease(String body) {
  final Object? decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return null;
  final tag = decoded['tag_name'];
  final page = decoded['html_url'];
  if (tag is! String || page is! String) return null;

  Uri? apk;
  String? apkName;
  Uri? manifest;
  final assets = decoded['assets'];
  if (assets is List) {
    for (final a in assets) {
      if (a is Map<String, dynamic>) {
        final name = a['name'];
        final url = a['browser_download_url'];
        if (name is! String || url is! String) continue;
        final lower = name.toLowerCase();
        if (apk == null && lower.endsWith('.apk')) {
          apk = Uri.tryParse(url);
          apkName = name;
        } else if (manifest == null && lower.endsWith('.manifest.json')) {
          manifest = Uri.tryParse(url);
        }
      }
    }
  }
  return AppRelease(
    version: tag,
    notes: (decoded['body'] as String?)?.trim() ?? '',
    apkUrl: apk,
    apkName: apkName,
    manifestUrl: manifest,
    pageUrl: Uri.parse(page),
  );
}

/// Abre la descarga del APK y cierra la app (§16.13). Lo hace `MainActivity.kt`
/// por el canal `seguimiento/sistema`: url_launcher abre el navegador dentro de
/// la tarea de la app, y entonces el instalador y su "Abrir" dejaban dos
/// "Seguimiento" en recientes. El instalador lo sigue abriendo el usuario
/// desde la descarga: la app no instala nada (ADR 0006).
class UpdateLauncher {
  const UpdateLauncher();

  static const _channel = MethodChannel('seguimiento/sistema');

  /// true si se abrió; entonces la tarea de la app ya se está cerrando. false
  /// si no hubo con qué abrirlo o no hay Android debajo: quien llama decide.
  Future<bool> openApkDownload(Uri url) async {
    try {
      return await _channel.invokeMethod<bool>('openApkDownload', {'url': '$url'}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// Plan 058 (ADR 0018, pedido del owner el 16 oct): «Actualizar» descarga el
/// APK dentro de la app, comprueba su SHA-256 contra el manifiesto de la
/// misma release y abre el instalador del sistema. Android sigue pidiendo
/// confirmar y rechaza un APK firmado con otra llave.
class UpdateInstaller {
  UpdateInstaller({http.Client? client, required this.cacheDir})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// La carpeta de caché de la app (`getTemporaryDirectory()` en Android).
  final Directory cacheDir;

  static const _channel = MethodChannel('seguimiento/sistema');

  /// Sólo descarga del repositorio de la app en GitHub.
  static bool trustedHost(Uri url) =>
      url.scheme == 'https' &&
      (url.host == 'github.com' ||
          url.host == 'objects.githubusercontent.com' ||
          url.host == 'release-assets.githubusercontent.com');

  /// El SHA-256 que declara el manifiesto de la release.
  Future<String> expectedSha(Uri manifestUrl) async {
    if (!trustedHost(manifestUrl)) {
      throw const UpdateException('El manifiesto no viene de GitHub.');
    }
    final res = await _client.get(manifestUrl).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw UpdateException('No se pudo leer el manifiesto (${res.statusCode}).');
    }
    final decoded = jsonDecode(res.body);
    final sha = decoded is Map ? decoded['sha256'] : null;
    if (sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw const UpdateException('El manifiesto no trae un SHA-256 válido.');
    }
    return sha;
  }

  /// Descarga el APK a cache/updates y comprueba su SHA-256. Borra lo que no
  /// coincida. `onProgress(recibidos, total)`.
  Future<File> download(AppRelease release,
      {void Function(int received, int? total)? onProgress}) async {
    final apk = release.apkUrl, manifest = release.manifestUrl;
    if (apk == null || manifest == null) {
      throw const UpdateException('La versión no trae APK con manifiesto.');
    }
    if (!trustedHost(apk)) {
      throw const UpdateException('El APK no viene de GitHub.');
    }
    final sha = await expectedSha(manifest);
    final dir = Directory('${cacheDir.path}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final name = (release.apkName ?? 'MyPrime-${release.version}.apk')
        .replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
    final file = File('${dir.path}/$name');
    final response = await _client.send(http.Request('GET', apk));
    if (response.statusCode != 200) {
      throw UpdateException('La descarga falló (${response.statusCode}).');
    }
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, response.contentLength);
      }
    } finally {
      await sink.close();
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != sha) {
      file.deleteSync();
      throw const UpdateException(
          'El archivo descargado no coincide con el publicado: no se instala.');
    }
    return file;
  }

  /// ¿Android ya deja a My Prime instalar apps?
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre el ajuste «Instalar apps desconocidas» de My Prime.
  static Future<bool> openInstallPermission() async {
    try {
      return await _channel.invokeMethod<bool>('openInstallPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Abre el instalador del sistema con el APK verificado.
  static Future<bool> install(File apk) async {
    try {
      return await _channel.invokeMethod<bool>('installApk', {'path': apk.path}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  void close() => _client.close();
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}
