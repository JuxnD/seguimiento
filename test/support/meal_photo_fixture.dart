import 'dart:convert';
import 'dart:typed_data';

Uint8List fictionalPhoto() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

Map<String, Object> fictionalMeal() => {
      'status': 'success',
      'model': 'gpt-6-luna',
      'meal': {
        'items': [
          {
            'label': 'Arroz cocido',
            'portion': 'Una taza, aproximadamente',
            'kcal': 210,
            'protein': 4,
            'carbs': 46,
            'fat': 1
          },
          {
            'label': 'Pollo',
            'portion': 'Un filete mediano, aproximadamente',
            'kcal': 250,
            'protein': 46,
            'carbs': 0,
            'fat': 7
          },
        ],
        'uncertainties': ['No se puede medir el aceite por la foto.'],
      }
    };
