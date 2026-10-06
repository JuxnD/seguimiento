import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class AiNote {
  const AiNote(this.kind, this.text, this.quote);
  final String kind, text, quote;
}

/// El servidor recibe solo el informe elegido, nunca SQLite ni fotos.
class WeeklyAi {
  WeeklyAi(this.client, {this.timeout = const Duration(seconds: 50)});
  static final endpoint =
      Uri.parse('https://www.control360i.co/app/seguimiento/analizar');
  final http.Client client;
  final Duration timeout;

  Future<List<AiNote>> analyze(
      String report, String hwid, String license) async {
    if (utf8.encode(report).length > 48000 || report.trim().isEmpty) {
      throw const AiError(
          'El informe está vacío o es demasiado largo. Elige un rango menor.');
    }
    try {
      final response = await client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: jsonEncode(
                {'hwid': hwid, 'license_key': license, 'report': report}),
          )
          .timeout(timeout);
      if (response.bodyBytes.length > 32000) {
        throw const AiError('La respuesta excede el tamaño permitido.');
      }
      if (response.statusCode != 200) {
        throw AiError(switch (response.statusCode) {
          401 ||
          403 =>
            'La licencia no está activa para este teléfono. Revisa la activación en Control360i.',
          429 => 'Se alcanzó el límite de consultas. Inténtalo mañana.',
          503 => 'El servicio de IA aún no está habilitado en Control360i.',
          _ =>
            'El servicio no pudo completar la consulta. Tu informe sigue disponible.',
        });
      }
      return parse(response.body, report);
    } on TimeoutException {
      client.close();
      throw const AiError(
          'La consulta tardó demasiado. No se cambió ningún registro.');
    } on http.ClientException {
      throw const AiError(
          'No se pudo conectar. Tu informe sigue disponible sin internet.');
    } on FormatException {
      throw const AiError(
          'La respuesta no pudo verificarse contra tu informe.');
    }
  }

  static List<AiNote> parse(String body, String report) {
    final data = jsonDecode(body);
    if (data is! Map || data['model'] != 'gpt-6-luna' || data['notes'] is! List) {
      throw const FormatException();
    }
    final raw = data['notes'] as List;
    if (raw.isEmpty || raw.length > 6) throw const FormatException();
    return raw.map((n) {
      if (n is! Map ||
          n['kind'] is! String ||
          n['text'] is! String ||
          n['quote'] is! String) {
        throw const FormatException();
      }
      final kind = n['kind'] as String,
          text = n['text'] as String,
          quote = n['quote'] as String;
      if (!['observation', 'missing', 'question'].contains(kind) ||
          text.trim().isEmpty ||
          text.length > 350 ||
          RegExp(r'\d').hasMatch(text) ||
          quote.trim().isEmpty ||
          quote.length > 500 ||
          !report.contains(quote)) {
        throw const FormatException();
      }
      return AiNote(kind, text, quote);
    }).toList();
  }
}

class AiError implements Exception {
  const AiError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// La licencia revocable se cifra con Android Keystore y no entra al respaldo.
class AiActivation {
  static const channel = MethodChannel('seguimiento/ia');
  Future<(String, String)> read() async {
    final value = await channel.invokeMapMethod<String, String>('read');
    return (value!['hwid']!, value['license'] ?? '');
  }

  Future<void> save(String license) =>
      channel.invokeMethod<void>('save', {'license': license});
}
