/// Ilustraciones de técnica: modelo de las figuras que genera
/// `tool/figuras.py` en `assets/tecnica/figuras.json`.
///
/// Cada figura trae sus cuadros ya resueltos en primitivas (líneas, círculos,
/// elipses, arcos, polígonos y texto) con colores por rol. La app solo las
/// pinta: la geometría y las posturas viven en el generador.
library;

import 'dart:convert';
import 'dart:ui' show Offset;

import '../domain/search.dart';

enum ArtRole { ink, ghost, muscle, prop, propFill, floor, arrow, guide, label, wrong, bg }

ArtRole _role(Object? v) => ArtRole.values.byName(v as String);

Offset _pt(Object? v) {
  final l = v as List;
  return Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
}

double _d(Object? v, [double fallback = 0]) => v == null ? fallback : (v as num).toDouble();

sealed class ArtItem {
  const ArtItem();

  factory ArtItem.fromJson(Map<String, Object?> j) => switch (j['k']) {
        'line' => ArtLine(
            a: _pt(j['a']),
            b: _pt(j['b']),
            role: _role(j['role']),
            width: _d(j['w'], 1),
            opacity: _d(j['op'], 1),
            dashed: j['dash'] == true,
          ),
        'circle' => ArtCircle(
            center: _pt(j['c']),
            radius: _d(j['r']),
            role: _role(j['role']),
            opacity: _d(j['op'], 1),
            filled: j['fill'] == true,
            stroke: j['stroke'] == null ? null : _role(j['stroke']),
            strokeWidth: _d(j['w'], 1),
            strokeOpacity: _d(j['sop'], 1),
          ),
        'ellipse' => ArtEllipse(
            center: _pt(j['c']),
            rx: _d(j['rx']),
            ry: _d(j['ry']),
            rotationDeg: _d(j['rot']),
            role: _role(j['role']),
            opacity: _d(j['op'], 1),
            stroke: j['stroke'] == null ? null : _role(j['stroke']),
            strokeWidth: _d(j['w'], 1),
            strokeOpacity: _d(j['sop'], 1),
          ),
        'rect' => ArtRect(
            x: _d(j['x']),
            y: _d(j['y']),
            width: _d(j['w']),
            height: _d(j['h']),
            role: _role(j['role']),
            stroke: _role(j['stroke']),
            strokeWidth: _d(j['w2'], 0.6),
          ),
        'poly' => ArtPolygon(points: [for (final p in j['pts'] as List) _pt(p)], role: _role(j['role'])),
        'arc' => ArtArc(
            center: _pt(j['c']),
            radius: _d(j['r']),
            startDeg: _d(j['a0']),
            sweepDeg: _d(j['sweep']),
            role: _role(j['role']),
            width: _d(j['w'], 0.8),
          ),
        'text' => ArtText(
            at: _pt(j['p']),
            text: j['t'] as String,
            size: _d(j['size'], 3.3),
            role: _role(j['role']),
            anchor: j['anchor'] as String? ?? 'start',
          ),
        final k => throw FormatException('Primitiva desconocida: $k'),
      };
}

class ArtLine extends ArtItem {
  const ArtLine({
    required this.a,
    required this.b,
    required this.role,
    required this.width,
    this.opacity = 1,
    this.dashed = false,
  });

  final Offset a, b;
  final ArtRole role;
  final double width, opacity;
  final bool dashed;
}

class ArtCircle extends ArtItem {
  const ArtCircle({
    required this.center,
    required this.radius,
    required this.role,
    this.opacity = 1,
    this.filled = false,
    this.stroke,
    this.strokeWidth = 1,
    this.strokeOpacity = 1,
  });

  final Offset center;
  final double radius, opacity, strokeWidth, strokeOpacity;
  final ArtRole role;
  final bool filled;
  final ArtRole? stroke;
}

class ArtEllipse extends ArtItem {
  const ArtEllipse({
    required this.center,
    required this.rx,
    required this.ry,
    required this.rotationDeg,
    required this.role,
    this.opacity = 1,
    this.stroke,
    this.strokeWidth = 1,
    this.strokeOpacity = 1,
  });

  final Offset center;
  final double rx, ry, rotationDeg, opacity, strokeWidth, strokeOpacity;
  final ArtRole role;
  final ArtRole? stroke;
}

class ArtRect extends ArtItem {
  const ArtRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.role,
    required this.stroke,
    required this.strokeWidth,
  });

  final double x, y, width, height, strokeWidth;
  final ArtRole role, stroke;
}

class ArtPolygon extends ArtItem {
  const ArtPolygon({required this.points, required this.role});

  final List<Offset> points;
  final ArtRole role;
}

class ArtArc extends ArtItem {
  const ArtArc({
    required this.center,
    required this.radius,
    required this.startDeg,
    required this.sweepDeg,
    required this.role,
    required this.width,
  });

  final Offset center;
  final double radius, startDeg, sweepDeg, width;
  final ArtRole role;
}

class ArtText extends ArtItem {
  const ArtText({required this.at, required this.text, required this.size, required this.role, required this.anchor});

  /// Línea base del texto (como en SVG).
  final Offset at;
  final String text;
  final double size;
  final ArtRole role;

  /// 'start', 'middle' o 'end'.
  final String anchor;
}

class ArtFrame {
  const ArtFrame({required this.caption, required this.wrong, required this.items});

  final String caption;

  /// Cuadro "Evita": muestra el error, no la técnica.
  final bool wrong;
  final List<ArtItem> items;
}

class ExerciseArt {
  const ExerciseArt({required this.name, required this.muscles, required this.box, required this.frames});

  factory ExerciseArt.fromJson(Map<String, Object?> j) {
    final box = [for (final v in j['box'] as List) (v as num).toDouble()];
    return ExerciseArt(
      name: j['name'] as String,
      muscles: j['muscles'] as String,
      box: (left: box[0], top: box[1], right: box[2], bottom: box[3]),
      frames: [
        for (final f in (j['frames'] as List).cast<Map<String, Object?>>())
          ArtFrame(
            caption: f['caption'] as String,
            wrong: f['wrong'] == true,
            items: [for (final i in (f['items'] as List).cast<Map<String, Object?>>()) ArtItem.fromJson(i)],
          ),
      ],
    );
  }

  final String name;

  /// "Cuádriceps y glúteo de la pierna de adelante".
  final String muscles;

  /// Recuadro común a todos los cuadros, en unidades del mundo: así los
  /// cuadros de un ejercicio comparten escala y se comparan de un vistazo.
  final ({double left, double top, double right, double bottom}) box;
  final List<ArtFrame> frames;

  double get boxWidth => box.right - box.left;
  double get boxHeight => box.bottom - box.top;
}

/// Catálogo de figuras, buscado por nombre sin mayúsculas ni tildes.
class ExerciseArtCatalog {
  ExerciseArtCatalog(List<ExerciseArt> figures) : _byKey = {for (final f in figures) artKey(f.name): f};

  factory ExerciseArtCatalog.fromJsonString(String source) {
    final data = jsonDecode(source) as Map<String, Object?>;
    return ExerciseArtCatalog([
      for (final f in (data['figures'] as List).cast<Map<String, Object?>>()) ExerciseArt.fromJson(f),
    ]);
  }

  static const asset = 'assets/tecnica/figuras.json';

  final Map<String, ExerciseArt> _byKey;

  ExerciseArt? forExercise(String name) => _byKey[artKey(name)];

  Iterable<ExerciseArt> get all => _byKey.values;
}

/// Clave de un ejercicio; también identifica la foto de referencia.
String artKey(String name) => nameKey(name);
