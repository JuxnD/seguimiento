import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import '../domain/nutrition.dart';
import 'repositories/nutrition_repository.dart';
import 'ai_gateway.dart';

/// Reencodifica los píxeles: elimina EXIF/ubicación y limita resolución/peso.
/// No conserva el original ni crea un archivo en la carpeta de respaldos.
Future<Uint8List> prepareMealPhoto(Uint8List original) async {
  if (original.isEmpty || original.length > 8 * 1024 * 1024) {
    throw const AiError('Elige una foto de hasta 8 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(original);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 40000000) {
      throw const AiError(
          'La foto es demasiado grande. Elige una de menor resolución.');
    }
    for (final limit in [1024, 640]) {
      final scale =
          math.min(1.0, limit / math.max(descriptor.width, descriptor.height));
      final codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()));
      try {
        final frame = await codec.getNextFrame();
        try {
          final data =
              await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (data != null && data.lengthInBytes <= MealPhotoAi.maxPhotoBytes) {
            return data.buffer
                .asUint8List(data.offsetInBytes, data.lengthInBytes);
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    throw const AiError('No se pudo reducir la foto. Elige otra.');
  } on AiError {
    rethrow;
  } on Object {
    throw const AiError('No se pudo leer la foto. Elige una imagen válida.');
  } finally {
    descriptor?.dispose();
    buffer.dispose();
  }
}

class PhotoFoodEstimate {
  const PhotoFoodEstimate(this.label, this.portion, this.macros);
  final String label, portion;
  final Macros macros;

  MealItemDraft toDraft(double multiplier) => MealItemDraft(
      label: label,
      quantity: multiplier,
      quantityUnit: 'porción',
      macros: macros.scale(multiplier));
}

class PhotoMealEstimate {
  const PhotoMealEstimate(this.items, this.uncertainties);
  final List<PhotoFoodEstimate> items;
  final List<String> uncertainties;
}

/// Un POST sin reintentos. Solo imagen elegida + activación; nunca la base.
class MealPhotoAi {
  MealPhotoAi(this.client, {this.timeout = const Duration(seconds: 50)});
  final http.Client client;
  final Duration timeout;
  static const maxPhotoBytes = 2 * 1024 * 1024;
  static final endpoint =
      Uri.parse('https://www.control360i.co/app/seguimiento/comida');

  Future<PhotoMealEstimate> analyze(
      Uint8List photo, String hwid, String license) async {
    if (photo.isEmpty || photo.length > maxPhotoBytes) {
      throw const AiError('La foto supera el tamaño permitido. Elige otra.');
    }
    try {
      final response = await postAiJson(
          client,
          endpoint,
          {
            'hwid': hwid,
            'license_key': license,
            'mime': 'image/png',
            'photo_base64': base64Encode(photo)
          },
          timeout: timeout);
      if (response.statusCode != 200) {
        throw AiError(switch (response.statusCode) {
          401 ||
          403 =>
            'Activa la IA de este teléfono desde Informe → Analizar con IA.',
          429 =>
            'Se alcanzó el límite diario de consultas de IA. Inténtalo mañana.',
          413 => 'La foto es demasiado grande. Elige otra.',
          404 ||
          503 =>
            'El análisis de fotos no está disponible ahora. Puedes registrar la comida a mano.',
          _ =>
            'No se pudo analizar la foto. Puedes reintentar o registrar a mano.',
        });
      }
      return parse(response.body);
    } on FormatException {
      throw const AiError(
          'La propuesta no pasó la validación. No se guardó ninguna comida.');
    }
  }

  static PhotoMealEstimate parse(String body) {
    final data = jsonDecode(body);
    if (data is! Map || data['model'] != 'gpt-6-luna' || data['meal'] is! Map) {
      throw const FormatException();
    }
    final meal = data['meal'] as Map;
    final raw = meal['items'], doubts = meal['uncertainties'];
    if (raw is! List ||
        raw.length > 8 ||
        doubts is! List ||
        doubts.length > 6) {
      throw const FormatException();
    }
    String text(dynamic value, int max) {
      if (value is! String ||
          value.trim().isEmpty ||
          value.runes.length > max) {
        throw const FormatException();
      }
      return value.trim();
    }

    double number(dynamic value, double max) {
      if (value is! num || !value.isFinite || value < 0 || value > max) {
        throw const FormatException();
      }
      return value.toDouble();
    }

    final items = raw.map((r) {
      if (r is! Map) throw const FormatException();
      final m = Macros(
          kcal: number(r['kcal'], 2000),
          protein: number(r['protein'], 200),
          carbs: number(r['carbs'], 400),
          fat: number(r['fat'], 200));
      // No aceptar macros imposibles. Es un control de coherencia, no exactitud.
      if (m.kcal <= 0 ||
          (m.kcal - (4 * m.protein + 4 * m.carbs + 9 * m.fat)).abs() >
              math.max(100, m.kcal * .35)) {
        throw const FormatException();
      }
      return PhotoFoodEstimate(
          text(r['label'], 80), text(r['portion'], 180), m);
    }).toList();
    if (Macros.sum(items.map((i) => i.macros)).kcal > 5000 ||
        (items.isEmpty && doubts.isEmpty)) {
      throw const FormatException();
    }
    return PhotoMealEstimate(items, doubts.map((v) => text(v, 300)).toList());
  }
}
