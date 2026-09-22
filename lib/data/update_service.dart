import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../domain/version.dart';

/// Una versión publicada en GitHub Releases.
class AppRelease {
  const AppRelease({required this.version, required this.notes, this.apkUrl, required this.pageUrl});

  final String version;
  final String notes;

  /// APK adjunto a la release, si lo hay.
  final Uri? apkUrl;
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
  final assets = decoded['assets'];
  if (assets is List) {
    for (final a in assets) {
      if (a is Map<String, dynamic>) {
        final name = a['name'];
        final url = a['browser_download_url'];
        if (name is String && url is String && name.toLowerCase().endsWith('.apk')) {
          apk = Uri.tryParse(url);
          break;
        }
      }
    }
  }
  return AppRelease(
    version: tag,
    notes: (decoded['body'] as String?)?.trim() ?? '',
    apkUrl: apk,
    pageUrl: Uri.parse(page),
  );
}
