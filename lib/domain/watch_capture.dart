import 'dart:math' as math;

/// Plan 058 (§16.17): lo que se lee de una captura de la app INNOVA (o se
/// escribe a mano). INNOVA sólo escribe pasos en Health Connect; el pulso,
/// las kcal y la duración de cada actividad vienen de aquí. Todo campo es
/// opcional: lo que no se leyó queda vacío, nunca se inventa.
class WatchReading {
  WatchReading({
    this.kind,
    this.startTime,
    this.durationSec,
    this.avgHr,
    this.maxHr,
    this.kcal,
    this.steps,
    this.distanceM,
    this.systolic,
    this.diastolic,
    this.spo2,
  });

  /// «Caminar», «Capacitación gratuita»… tal como lo nombra el reloj.
  String? kind;

  /// `HH:mm` de inicio.
  String? startTime;
  int? durationSec;
  int? avgHr;
  int? maxHr;
  int? kcal;
  int? steps;
  int? distanceM;
  int? systolic;
  int? diastolic;
  int? spo2;

  bool get hasActivity =>
      durationSec != null ||
      avgHr != null ||
      maxHr != null ||
      kcal != null ||
      steps != null ||
      distanceM != null;

  bool get hasVitals => systolic != null || spo2 != null;

  bool get isEmpty => !hasActivity && !hasVitals && kind == null;
}

/// Rangos plausibles: lo que cae fuera no se acepta (un error de lectura no
/// debe llegar a la base).
String? watchReadingProblem(WatchReading r) {
  bool out(int? v, int min, int max) => v != null && (v < min || v > max);
  if (out(r.avgHr, 30, 230)) return 'Pulso medio fuera de rango (30–230)';
  if (out(r.maxHr, 30, 240)) return 'Pulso máximo fuera de rango (30–240)';
  if (r.avgHr != null && r.maxHr != null && r.maxHr! < r.avgHr!) {
    return 'El pulso máximo es menor que el medio';
  }
  if (out(r.durationSec, 1, 6 * 3600)) return 'Duración fuera de rango';
  if (out(r.kcal, 0, 5000)) return 'kcal fuera de rango';
  if (out(r.steps, 0, 100000)) return 'Pasos fuera de rango';
  if (out(r.distanceM, 0, 100000)) return 'Distancia fuera de rango';
  if (out(r.systolic, 70, 250) || out(r.diastolic, 40, 150)) {
    return 'Presión fuera de rango';
  }
  if ((r.systolic == null) != (r.diastolic == null)) {
    return 'La presión lleva los dos números (alta / baja)';
  }
  if (r.systolic != null && r.diastolic! >= r.systolic!) {
    return 'La presión baja debe ser menor que la alta';
  }
  if (out(r.spo2, 70, 100)) return 'SpO₂ fuera de rango (70–100 %)';
  return null;
}

final _ampm = RegExp(r'^\s*([ap])\.?\s?m\.?', caseSensitive: false);
final _clock = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?');

int? _int(String s) => int.tryParse(s.replaceAll(RegExp(r'[.,\s]'), ''));

/// Primer número entero de `line` (admite separador de miles «2.071»).
int? _firstNumber(String line) {
  final m = RegExp(r'\d{1,3}(?:[.,]\d{3})+|\d+').firstMatch(line);
  return m == null ? null : _int(m.group(0)!);
}

/// Lee el texto reconocido de una captura del reloj. Busca por etiqueta
/// (media, máx., kcal, pasos, duración, presión, SpO₂) y, sin etiqueta, por
/// unidad (lpm, kcal, km). Lo dudoso se deja vacío para confirmarlo a mano.
WatchReading parseWatchText(String text) {
  final r = WatchReading();
  final lines = [
    for (final l in text.split(RegExp(r'[\r\n]+')))
      if (l.trim().isNotEmpty) l.trim()
  ];
  String lower(String s) => s.toLowerCase();
  String? nextLine(int i) => i + 1 < lines.length ? lines[i + 1] : null;

  // Tipo de actividad.
  const kinds = [
    'Capacitación gratuita',
    'Entrenamiento libre',
    'Caminar',
    'Caminata',
    'Correr',
    'Ciclismo',
    'Fútbol',
    'Senderismo',
    'Bicicleta',
  ];
  for (final k in kinds) {
    if (lower(text).contains(lower(k))) {
      r.kind = k;
      break;
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final l = lower(line);
    final next = nextLine(i);
    int? labeled() => _firstNumber(line.replaceAll(RegExp(r'\d{1,2}:\d{2}'), '')) ??
        (next == null ? null : _firstNumber(next));

    // Presión «122/76 mmHg».
    final bp = RegExp(r'(\d{2,3})\s*/\s*(\d{2,3})').firstMatch(line);
    if (bp != null &&
        (l.contains('mmhg') || l.contains('presi') || l.contains('tensi'))) {
      r.systolic ??= int.parse(bp.group(1)!);
      r.diastolic ??= int.parse(bp.group(2)!);
      continue;
    }
    if (l.contains('spo') || l.contains('oxígeno') || l.contains('oxigeno') ||
        l.contains('saturaci')) {
      final m = RegExp(r'(\d{2,3})\s*%').firstMatch('$line ${next ?? ''}');
      r.spo2 ??= m == null ? null : int.parse(m.group(1)!);
      continue;
    }
    // Pulso «134 / 154» con unidad de pulso: medio / máximo.
    final pair = RegExp(r'(\d{2,3})\s*/\s*(\d{2,3})\s*(lpm|ppm|bpm)')
        .firstMatch(l);
    if (pair != null) {
      r.avgHr ??= int.parse(pair.group(1)!);
      r.maxHr ??= int.parse(pair.group(2)!);
      continue;
    }
    final isHr = l.contains('lpm') ||
        l.contains('ppm') ||
        l.contains('bpm') ||
        l.contains('pulso') ||
        l.contains('cardíaca') ||
        l.contains('cardiaca') ||
        l.contains('frecuencia');
    if (isHr && (l.contains('máx') || l.contains('max'))) {
      r.maxHr ??= labeled();
      continue;
    }
    if (isHr &&
        (l.contains('medi') || l.contains('prom') || l.contains('avg') ||
            l.contains('average'))) {
      r.avgHr ??= labeled();
      continue;
    }
    if (l.contains('kcal') || l.contains('calor')) {
      r.kcal ??= labeled();
      continue;
    }
    if (l.contains('pasos') || l.contains('steps')) {
      r.steps ??= labeled();
      continue;
    }
    final km = RegExp(r'(\d+(?:[.,]\d+)?)\s*km').firstMatch(l);
    if (km != null) {
      r.distanceM ??=
          (double.parse(km.group(1)!.replaceAll(',', '.')) * 1000).round();
      continue;
    }
    if (l.contains('duraci') || l.contains('tiempo')) {
      final m = _clock.firstMatch('$line ${next ?? ''}');
      if (m != null) r.durationSec ??= _clockSeconds(m);
      continue;
    }
  }

  // Hora de inicio: «9:28 a. m.»; duración sin etiqueta: el primer m:ss que
  // no es una hora del día.
  for (final m in _clock.allMatches(text)) {
    final rest = text.substring(m.end);
    final ampm = _ampm.firstMatch(rest);
    if (ampm != null) {
      if (r.startTime == null) {
        var h = int.parse(m.group(1)!) % 12;
        if (lower(ampm.group(1)!) == 'p') h += 12;
        r.startTime = '${h.toString().padLeft(2, '0')}:${m.group(2)}';
      }
    } else {
      r.durationSec ??= _clockSeconds(m);
    }
  }

  // Por unidad, aunque todo venga en una sola línea del reconocedor.
  r.kcal ??= _unit(text, r'kcal');
  r.steps ??= _unit(text, r'pasos|steps');
  if (r.distanceM == null) {
    final km = RegExp(r'(\d+(?:[.,]\d+)?)\s*km', caseSensitive: false)
        .firstMatch(text);
    if (km != null) {
      r.distanceM =
          (double.parse(km.group(1)!.replaceAll(',', '.')) * 1000).round();
    }
  }

  // Pulso sin etiqueta: los números con «lpm»; el menor es el medio.
  if (r.avgHr == null || r.maxHr == null) {
    final hrs = [
      for (final m
          in RegExp(r'(\d{2,3})\s*(lpm|ppm|bpm)', caseSensitive: false)
              .allMatches(text))
        int.parse(m.group(1)!)
    ];
    if (hrs.length >= 2) {
      r.avgHr ??= hrs.reduce(math.min);
      r.maxHr ??= hrs.reduce(math.max);
    } else if (hrs.length == 1) {
      r.avgHr ??= hrs.single;
    }
  }
  return r;
}

/// El número justo antes de la unidad («49 kcal», «2.071 pasos»).
int? _unit(String text, String unit) {
  final m = RegExp(r'(\d{1,3}(?:[.,]\d{3})+|\d+)\s*(?:' + unit + ')',
          caseSensitive: false)
      .firstMatch(text);
  return m == null ? null : _int(m.group(1)!);
}

int _clockSeconds(RegExpMatch m) {
  final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
  final c = m.group(3);
  return c == null ? a * 60 + b : a * 3600 + b * 60 + int.parse(c);
}

/// Pulso máximo estimado (§16.17): 208 − 0,7 × edad.
int? estimatedMaxHr(DateTime? birthDate, DateTime today) {
  if (birthDate == null) return null;
  var age = today.year - birthDate.year;
  if (today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day)) {
    age--;
  }
  if (age < 10 || age > 100) return null;
  return (208 - 0.7 * age).round();
}

/// Zona (1–5) de un pulso según el % del máximo: <60, 60–70, 70–80, 80–90,
/// ≥90. No usa las etiquetas de INNOVA («Suave», «Animado»): no dice cómo
/// las calcula.
int? hrZone(int? hr, int? maxHr) {
  if (hr == null || maxHr == null || maxHr <= 0) return null;
  final pct = hr / maxHr;
  if (pct < .6) return 1;
  if (pct < .7) return 2;
  if (pct < .8) return 3;
  if (pct < .9) return 4;
  return 5;
}

/// Carga por pulso (TRIMP de Banister): minutos × HRr × 0,64 × e^(1,92·HRr),
/// con HRr = (medio − reposo) / (máximo − reposo). Escala distinta a RPE × min:
/// se muestra al lado, no reemplaza la carga del día (los umbrales de
/// §19.17 están en RPE × min).
double? banisterTrimp(
    {required int? durationSec,
    required int? avgHr,
    required int? restHr,
    required int? maxHr}) {
  if (durationSec == null || avgHr == null || restHr == null || maxHr == null) {
    return null;
  }
  if (maxHr <= restHr || avgHr <= restHr) return null;
  final hrr = ((avgHr - restHr) / (maxHr - restHr)).clamp(0.0, 1.0);
  return durationSec / 60 * hrr * 0.64 * math.exp(1.92 * hrr);
}
