Map<String, Object?> estimateItem(String label,
        {String kind = 'estimated',
        int? id,
        double? quantity = 250,
        String? unit = 'g',
        String? question}) =>
    {
      'kind': kind,
      'label': label,
      'food_id': id,
      'quantity': kind == 'unresolved' ? null : quantity,
      'unit': kind == 'unresolved' ? null : unit,
      'portion':
          kind == 'estimated' ? '$quantity $unit; receta aproximada' : null,
      'kcal': kind == 'estimated' ? 500 : null,
      'protein': kind == 'estimated' ? 20 : null,
      'carbs': kind == 'estimated' ? 70 : null,
      'fat': kind == 'estimated' ? 16 : null,
      'question': kind == 'unresolved' ? question ?? '¿Cuánto comiste?' : null,
      'assumptions': kind == 'estimated'
          ? ['Receta y aceite desconocidos; revisar']
          : <String>[],
    };

Map<String, dynamic> estimateResult(
        List<Map<String, Object?>> items, List<(String, int)> segments) =>
    {
      'items': items,
      'coverage': [
        for (final (text, index) in segments)
          {'text': text, 'item_index': index}
      ],
      'uncertainties': ['La preparación cambia las cifras.'],
    };
