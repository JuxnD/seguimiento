import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const _maxAiResponseBytes = 32 * 1024;
final _assistEndpoint =
    Uri.parse('https://www.control360i.co/app/seguimiento/asistir');

/// Cuota que informa el gateway. `resetAt` se interpreta como UTC.
class AiQuota {
  const AiQuota({required this.remaining, required this.limit, this.resetAt});

  final int remaining;
  final int limit;
  final DateTime? resetAt;

  static AiQuota? tryParse(dynamic value) {
    if (value is! Map ||
        value['remaining'] is! int ||
        value['limit'] is! int ||
        (value['remaining'] as int) < 0 ||
        (value['limit'] as int) < 0 ||
        (value['remaining'] as int) > (value['limit'] as int)) {
      return null;
    }
    DateTime? reset;
    final rawReset = value['reset_at'];
    if (rawReset is! String) return null;
    reset = DateTime.tryParse(rawReset)?.toUtc();
    if (reset == null) return null;
    return AiQuota(
        remaining: value['remaining'] as int,
        limit: value['limit'] as int,
        resetAt: reset);
  }
}

/// Errores de IA con texto apto para mostrar; nunca incluye el cuerpo remoto.
class AiError implements Exception {
  const AiError(this.message, {this.code, this.quota});
  final String message;
  final String? code;
  final AiQuota? quota;

  @override
  String toString() => message;
}

/// Cliente del contrato v2. El host y el path son fijos y no admite reintentos.
class AiGatewayClient {
  AiGatewayClient(this.client, {this.timeout = const Duration(seconds: 50)});

  final http.Client client;
  final Duration timeout;
  AiQuota? lastQuota;

  Future<AiStatus> status({
    required String hwid,
    required String license,
  }) async {
    try {
      final result = await assist(
        task: 'status',
        input: const {},
        hwid: hwid,
        license: license,
      );
      return AiStatus(
        enabled: result['enabled'] == true,
        message: result['enabled'] == true
            ? 'IA habilitada para este teléfono.'
            : 'La IA aún no está habilitada para esta licencia.',
        quota: lastQuota,
      );
    } on AiError catch (error) {
      return AiStatus(
          message: error.message,
          quota: error.quota ?? lastQuota,
          enabled: false);
    } on Object {
      return const AiStatus(message: 'No se pudo consultar el estado.');
    }
  }

  Future<Map<String, dynamic>> assist({
    required String task,
    required Map<String, Object?> input,
    required String hwid,
    required String license,
  }) async {
    final response = await _postAiJson(
      client,
      _assistEndpoint,
      {
        'contract': 2,
        'task': task,
        'input': input,
        'hwid': hwid,
        'license_key': license,
      },
      timeout,
    );
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded.keys.every((key) => key is String)) {
        data = Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      data = null;
    }

    final quota = AiQuota.tryParse(data?['quota']);
    if (response.statusCode != 200) {
      if (response.statusCode == 429 && quota != null) lastQuota = quota;
      final code =
          data?['error'] is Map ? (data!['error'] as Map)['code'] : null;
      throw AiError(
          _messageForStatus(response.statusCode,
              code: code is String ? code : null),
          code: code is String ? code : null,
          quota: quota);
    }
    if (data == null ||
        data['status'] != 'success' ||
        data['contract'] != 2 ||
        data['task'] != task ||
        data['model'] != 'gpt-6-luna' ||
        data['result'] is! Map) {
      throw const AiError(
          'La respuesta no pasó la verificación. Puedes continuar sin IA.');
    }
    if (quota != null) lastQuota = quota;
    return Map<String, dynamic>.from(data['result'] as Map);
  }
}

class AiStatus {
  const AiStatus({required this.message, this.enabled = false, this.quota});

  final String message;
  final bool enabled;
  final AiQuota? quota;
}

/// Un solo transporte para las rutas v1 y v2. La ruta siempre la decide el
/// consumidor; el cliente v2 publica únicamente el endpoint fijo de asist.
Future<http.Response> postAiJson(
        http.Client client, Uri endpoint, Map<String, Object?> body,
        {Duration timeout = const Duration(seconds: 50)}) =>
    _postAiJson(client, endpoint, body, timeout);

Future<http.Response> _postAiJson(http.Client client, Uri endpoint,
    Map<String, Object?> body, Duration timeout) async {
  try {
    Future<http.Response> sendAndRead() async {
      final encoded = jsonEncode(body);
      final http.BaseRequest request;
      // El alojamiento pierde php://input cuando su buffer de 16 KiB necesita
      // un temporal. Un campo multipart conserva el JSON completo sin subir
      // archivos ni reintentar una consulta que podría consumir cuota.
      if (utf8.encode(encoded).length >= 16 * 1024) {
        request = http.MultipartRequest('POST', endpoint)
          ..fields['payload'] = encoded;
      } else {
        request = http.Request('POST', endpoint)
          ..headers['Content-Type'] = 'application/json'
          ..body = encoded;
      }
      request.headers['Accept'] = 'application/json';
      final streamed = await client.send(request);
      final length = int.tryParse(streamed.headers['content-length'] ?? '');
      if (length != null && length > _maxAiResponseBytes) {
        await streamed.stream.listen(null).cancel();
        throw const AiError('La respuesta excede el tamaño permitido.');
      }
      final bytes = <int>[];
      await for (final chunk in streamed.stream) {
        if (bytes.length + chunk.length > _maxAiResponseBytes) {
          throw const AiError('La respuesta excede el tamaño permitido.');
        }
        bytes.addAll(chunk);
      }
      return http.Response.bytes(bytes, streamed.statusCode,
          headers: streamed.headers, request: request);
    }

    return await sendAndRead().timeout(timeout);
  } on TimeoutException {
    client.close();
    throw const AiError(
        'La consulta tardó demasiado. No se cambió ningún registro.');
  } on http.ClientException {
    throw const AiError(
        'No se pudo conectar. La función local sigue disponible.');
  }
}

String _messageForStatus(int status, {String? code}) => switch (status) {
      401 ||
      403 =>
        'La licencia no está activa para este teléfono. Revisa la activación en Control360i.',
      413 => 'La entrada supera el tamaño permitido.',
      429 =>
        'Se alcanzó el límite de consultas. Inténtalo después del reinicio indicado.',
      503 when code == 'service_not_configured' =>
        'El servicio de IA aún no está habilitado en Control360i.',
      503 =>
        'El servicio de IA no está disponible ahora. Puedes continuar sin IA.',
      _ =>
        'El servicio no pudo completar la consulta. Tus datos siguen disponibles.'
    };
