import 'core_ladders.dart' show coreLadders, hollowHold;

// Plan 052 (§16.27.4): el material del usuario y lo que pide cada ejercicio.
// Un ejercicio con material obligatorio que falta nunca se ofrece como si se
// pudiera hacer: sale del día con una nota (o se muestra su alternativa). Si
// sólo falta lo recomendado, se queda con una nota corta.

/// Estados de un material, tal como se guardan en `equipment_items`.
abstract final class EquipmentStatus {
  static const tengo = 'tengo';
  static const enCompra = 'en_compra';
  static const noTengo = 'no_tengo';
  static const all = [tengo, enCompra, noTengo];

  static String label(String status) => switch (status) {
        EquipmentStatus.tengo => 'Tengo',
        EquipmentStatus.enCompra => 'En compra',
        _ => 'No tengo',
      };
}

/// Claves del material (clave primaria de `equipment_items`).
abstract final class EquipmentKeys {
  static const bar = 'bar';
  static const band = 'band';
  static const scale = 'scale';
  static const mat = 'mat';
  static const parallettes = 'parallettes';
  static const rings = 'rings';
  static const backpack = 'backpack';
}

class EquipmentItem {
  const EquipmentItem(this.key, this.label, this.short,
      {this.defaultStatus, this.weighted = false});

  final String key;

  /// Como se lista en Ajustes: "Colchoneta antideslizante de 6 mm".
  final String label;

  /// Como se nombra en una nota: "falta colchoneta".
  final String short;

  /// Estado sin fila guardada. null: sale de las banderas locales (mini
  /// paralelas y anillas); sin bandera, `no_tengo`. Nunca se inventa que el
  /// usuario tiene algo que no confirmó.
  final String? defaultStatus;

  /// Sí/no y kg (la mochila con peso).
  final bool weighted;
}

const equipmentCatalog = [
  EquipmentItem(EquipmentKeys.bar, 'Barra de dominadas', 'barra',
      defaultStatus: EquipmentStatus.tengo),
  EquipmentItem(EquipmentKeys.band, 'Banda elástica', 'banda elástica',
      defaultStatus: EquipmentStatus.tengo),
  EquipmentItem(EquipmentKeys.scale, 'Báscula', 'báscula',
      defaultStatus: EquipmentStatus.tengo),
  EquipmentItem(
      EquipmentKeys.mat, 'Colchoneta antideslizante de 6 mm', 'colchoneta',
      defaultStatus: EquipmentStatus.noTengo),
  EquipmentItem(EquipmentKeys.parallettes, 'Mini paralelas', 'mini paralelas'),
  EquipmentItem(EquipmentKeys.rings, 'Anillas', 'anillas'),
  EquipmentItem(EquipmentKeys.backpack, 'Mochila con peso', 'mochila con peso',
      defaultStatus: EquipmentStatus.noTengo, weighted: true),
];

EquipmentItem? equipmentItem(String key) =>
    equipmentCatalog.where((i) => i.key == key).firstOrNull;

/// Estado de `key` en `statuses`; sin dato, su valor por omisión (o
/// `no_tengo` si depende de una bandera que no llegó).
String equipmentStatusOf(String key, Map<String, String> statuses) =>
    statuses[key] ??
    equipmentItem(key)?.defaultStatus ??
    EquipmentStatus.noTengo;

/// Lo que un ejercicio pide de un material. `required`: sin él no se hace;
/// si no, es recomendado. `alternative`: qué hacer sin él (el ejercicio se
/// queda con esa nota en lugar de salir del día).
class EquipmentNeed {
  const EquipmentNeed(this.key, {this.required = false, this.alternative});

  final String key;
  final bool required;
  final String? alternative;
}

const _matRecommended = EquipmentNeed(EquipmentKeys.mat);
const _matRequired = EquipmentNeed(EquipmentKeys.mat, required: true);
const _parallettes = EquipmentNeed(EquipmentKeys.parallettes, required: true);
const _bar = EquipmentNeed(EquipmentKeys.bar, required: true);
const _band = EquipmentNeed(EquipmentKeys.band, required: true);
const _rings = EquipmentNeed(EquipmentKeys.rings, required: true);
const _backpack = EquipmentNeed(EquipmentKeys.backpack,
    alternative: 'Sin mochila con peso: hazlo sin carga.');

/// Requisitos declarados por nombre de ejercicio (nombres reales de
/// seed_plan.dart, plan_v32_template.dart y las escaleras).
const exerciseEquipment = <String, List<EquipmentNeed>>{
  // Pino: la cabeza queda a centímetros del piso.
  'Pino pecho a la pared': [_matRequired],
  // Bloque de core en el suelo.
  hollowHold: [_matRecommended],
  'Hollow rocks': [_matRecommended],
  'Plancha lateral': [_matRecommended],
  // Bloque de planche (además, sólo entra con las mini paralelas).
  'Inclinación de planche': [_parallettes],
  'Flexión pseudo-planche': [_parallettes],
  'Tuck planche': [_parallettes],
  'Support hold en paralelas': [_parallettes],
  // Barra.
  'Dominadas': [_bar],
  'Colgarse de la barra': [_bar],
  'Elevación de piernas colgado': [_bar],
  'Toes-to-bar': [_bar],
  'Scap pull-up': [
    EquipmentNeed(EquipmentKeys.bar,
        required: true,
        alternative: 'Sin barra: deslizamientos en la pared en lugar de scap pull-ups.')
  ],
};

/// Peldaños de las escaleras de core (dragon flag, V-up, plancha inversa):
/// todos en el suelo.
final Set<String> _floorLadderExercises = {
  for (final ladder in coreLadders)
    for (final step in ladder.steps) step.exercise,
};

/// Lo que pide `exercise`. `variantKey`: la variante física del plan (el
/// support en anillas conserva el nombre "en paralelas").
List<EquipmentNeed> equipmentNeeds(String exercise, {String? variantKey}) {
  if (variantKey == 'support_rings') return const [_rings];
  final lower = exercise.toLowerCase();
  final needs = <EquipmentNeed>[
    ...?exerciseEquipment[exercise],
    if (_floorLadderExercises.contains(exercise)) _matRecommended,
    if (lower.contains('pike') && lower.contains('elevad')) _matRecommended,
    if (lower.contains('con banda') || lower.contains('pallof')) _band,
    if (lower.contains('con mochila')) _backpack,
  ];
  // Un material una vez; obligatorio gana a recomendado.
  final byKey = <String, EquipmentNeed>{};
  for (final need in needs) {
    final seen = byKey[need.key];
    if (seen == null || (need.required && !seen.required)) {
      byKey[need.key] = need;
    }
  }
  return byKey.values.toList();
}

/// Resultado de mirar un ejercicio contra el material.
class EquipmentCheck {
  const EquipmentCheck({this.missingRequired = const [], this.notes = const []});

  /// Material obligatorio que no está (`tengo`) y sin alternativa.
  final List<EquipmentItem> missingRequired;

  /// Notas para el ejercicio: alternativa o "Mejor con …".
  final List<String> notes;

  bool get blocked => missingRequired.isNotEmpty;
}

EquipmentCheck checkEquipment(String exercise, Map<String, String> statuses,
    {String? variantKey}) {
  final missing = <EquipmentItem>[];
  final notes = <String>[];
  for (final need in equipmentNeeds(exercise, variantKey: variantKey)) {
    if (equipmentStatusOf(need.key, statuses) == EquipmentStatus.tengo) {
      continue;
    }
    final item = equipmentItem(need.key);
    if (item == null) continue;
    if (need.alternative != null) {
      notes.add(need.alternative!);
    } else if (need.required) {
      missing.add(item);
    } else {
      notes.add('Mejor con ${item.short}.');
    }
  }
  return EquipmentCheck(missingRequired: missing, notes: notes);
}

/// "Pino pecho a la pared pendiente: falta colchoneta (en compra)."
String equipmentPendingNote(String exercise, List<EquipmentItem> missing,
        Map<String, String> statuses) =>
    '$exercise pendiente: falta ${missing.map((i) => equipmentStatusOf(i.key, statuses) == EquipmentStatus.enCompra ? '${i.short} (en compra)' : i.short).join(' y ')}.';

/// Material de una prueba pendiente (`requires`, separado por comas).
List<String> equipmentRequires(String? raw) => [
      for (final key in (raw ?? '').split(','))
        if (key.trim().isNotEmpty) key.trim()
    ];
