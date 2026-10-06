/// Maniquí 3D de técnica: posturas de `tool/figuras3d.py` subidas a 3D.
///
/// El generador exporta la postura 2D de perfil (la misma cinemática de las
/// figuras planas) y aquí se levanta a 3D: el lado cercano va a z = +ancho y
/// el lejano a z = -ancho, se interpola entre momentos clave y se pinta con
/// volúmenes sombreados (cápsulas, cascos convexos, cajas) en orden de
/// profundidad. Solo Canvas: sin dependencias nuevas ni motor 3D.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/rendering.dart';

import '../domain/search.dart';

// ---------------------------------------------------------------------------
// Vectores.
// ---------------------------------------------------------------------------

@immutable
class V3 {
  const V3(this.x, this.y, this.z);

  static const zero = V3(0, 0, 0);
  static const zAxis = V3(0, 0, 1);

  final double x, y, z;

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double k) => V3(x * k, y * k, z * k);
  V3 operator -() => V3(-x, -y, -z);

  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(dot(this));

  V3 get unit {
    final l = length;
    return l < 1e-9 ? this : this * (1 / l);
  }

  static V3 lerp(V3 a, V3 b, double t) => a + (b - a) * t;

  /// Punto del plano de perfil a una profundidad.
  static V3 lift(Offset p, double z) => V3(p.dx, p.dy, z);

  @override
  String toString() => 'V3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

double _deg(double rad) => rad * 180 / math.pi;
double _rad(double deg) => deg * math.pi / 180;
Offset _dir(double deg) => Offset(math.cos(_rad(deg)), math.sin(_rad(deg)));
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Interpola ángulos (grados) por el camino corto.
double lerpAngle(double a, double b, double t) => a + ((((b - a) % 360) + 540) % 360 - 180) * t;

// ---------------------------------------------------------------------------
// Modelo: lo que exporta el generador.
// ---------------------------------------------------------------------------

/// Largos de los segmentos, los mismos de `tool/figuras.py`.
class BodyDims {
  const BodyDims({
    this.torso = 18,
    this.upperArm = 10,
    this.forearm = 9,
    this.thigh = 14,
    this.shin = 14,
    this.foot = 5,
    this.headOffset = 5.5,
    this.headRadius = 3.6,
  });

  factory BodyDims.fromJson(Map<String, Object?> j) => BodyDims(
        torso: _num(j['T']),
        upperArm: _num(j['UA']),
        forearm: _num(j['FA']),
        thigh: _num(j['TH']),
        shin: _num(j['SH']),
        foot: _num(j['FT']),
        headOffset: _num(j['HEAD_OFF']),
        headRadius: _num(j['HEAD_R']),
      );

  final double torso, upperArm, forearm, thigh, shin, foot, headOffset, headRadius;

  /// Medio ancho de hombros y de cadera: dónde quedan los lados en z.
  static const shoulderHalf = 4.5;
  static const hipHalf = 3.3;
}

double _num(Object? v, [double fallback = 0]) => v == null ? fallback : (v as num).toDouble();

Offset _pt(Object? v) {
  final l = v as List;
  return Offset(_num(l[0]), _num(l[1]));
}

const limbNames = ['nearLeg', 'farLeg', 'nearArm', 'farArm'];

/// Una extremidad en un momento: los dos ángulos de perfil, el apoyo (si lo
/// hay) y hacia dónde apunta el pie o la mano.
@immutable
class LimbPose {
  const LimbPose({required this.upper, required this.lower, required this.end, this.pin, this.bend = 1, this.grip});

  factory LimbPose.fromJson(Map<String, Object?> j) {
    final a = j['angles'] as List;
    return LimbPose(
      upper: _num(a[0]),
      lower: _num(a[1]),
      end: _num(j['foot'] ?? j['hand'] ?? a[1]),
      pin: j['pin'] == null ? null : _pt(j['pin']),
      bend: (j['bend'] as num?)?.toInt() ?? 1,
      grip: j['grip'] as String?,
    );
  }

  /// Grados: 0 = +x, 90 = abajo (y crece hacia abajo, como en figuras.py).
  final double upper, lower, end;

  /// Punto del mundo donde la mano o el pie se sujeta al animar.
  final Offset? pin;

  /// Lado al que dobla la articulación media al resolver la IK (+1/-1).
  final int bend;

  /// 'bar': la mano envuelve la barra.
  final String? grip;
}

@immutable
class KeyPose {
  const KeyPose({required this.caption, required this.hip, required this.torso, this.gaze = 0, required this.limbs});

  factory KeyPose.fromJson(Map<String, Object?> j) => KeyPose(
        caption: j['caption'] as String,
        hip: _pt(j['hip']),
        torso: _num(j['torso']),
        gaze: _num(j['gaze']),
        limbs: {
          for (final e in (j['limbs'] as Map<String, Object?>).entries)
            e.key: LimbPose.fromJson(e.value as Map<String, Object?>),
        },
      );

  final String caption;
  final Offset hip;

  /// Dirección cadera → cuello, en grados.
  final double torso;

  /// Cabeceo respecto del torso: positivo baja la barbilla.
  final double gaze;
  final Map<String, LimbPose> limbs;
}

/// Zona muscular resaltada: una cara de un segmento, no el cilindro entero.
@immutable
class FigureRegion {
  const FigureRegion({required this.part, this.face = 'all', this.from = 0, this.to = 1, this.width = 90});

  factory FigureRegion.fromJson(Map<String, Object?> j) => FigureRegion(
        part: j['part'] as String,
        face: j['face'] as String? ?? 'all',
        from: _num(j['from'], 0),
        to: _num(j['to'], 1),
        width: _num(j['width'], 90),
      );

  /// 'thigh', 'shin', 'upperArm', 'forearm', 'shoulder' o 'torso'.
  final String part;

  /// 'flexor' (isquios, bíceps), 'extensor' (cuádriceps, tríceps), 'front',
  /// 'back', 'lats' o 'all'.
  final String face;

  /// Tramo del segmento (0 = raíz, 1 = extremo).
  final double from, to;

  /// Medio ancho angular de la zona, en grados.
  final double width;
}

class Figure3D {
  Figure3D({
    required this.name,
    required this.muscles,
    required this.frames,
    this.regions = const [],
    this.props = const [],
    this.gripZ = 5,
    this.elbowOut = 0.25,
    this.pivot,
    this.flex = const {},
    this.dims = const BodyDims(),
    this.initialYaw = 0,
    this.initialPitch = defaultPitch,
    this.variantGrip,
    this.variantLoaded,
  });

  factory Figure3D.fromJson(Map<String, Object?> j, BodyDims dims) => Figure3D(
        name: j['name'] as String,
        muscles: j['muscles'] as String,
        regions: [
          for (final r in (j['regions'] as List? ?? const [])) FigureRegion.fromJson(r as Map<String, Object?>)
        ],
        props: [for (final p in (j['props'] as List? ?? const [])) p as Map<String, Object?>],
        gripZ: _num(j['gripZ'], 5),
        elbowOut: _num(j['elbowOut'], 0.25),
        pivot: j['pivot'] == null ? null : _pt(j['pivot']),
        flex: {
          for (final e in (j['flex'] as Map<String, Object?>? ?? const {}).entries) e.key: (e.value as num).toInt()
        },
        frames: [for (final f in j['frames'] as List) KeyPose.fromJson(f as Map<String, Object?>)],
        dims: dims,
        initialYaw: _num((j['view'] as Map<String, Object?>?)?['yaw'], 0),
        initialPitch: _num((j['view'] as Map<String, Object?>?)?['pitch'], defaultPitch),
        variantGrip: (j['variant'] as Map<String, Object?>?)?['grip'] as String?,
        variantLoaded: (j['variant'] as Map<String, Object?>?)?['loaded'] as bool?,
      );

  final String name;
  final String muscles;
  final List<FigureRegion> regions;
  final List<Map<String, Object?>> props;

  /// Media separación de las manos (agarre), en unidades.
  final double gripZ;

  /// Cuánto salen los codos hacia los lados al doblar (0 = en el plano).
  final double elbowOut;

  /// Punto fijo alrededor del cual gira la cadera al animar (rodillas).
  final Offset? pivot;

  /// Hacia qué lado dobla cada extremidad: fija la cara flexora aunque esté recta.
  final Map<String, int> flex;
  final List<KeyPose> frames;
  final BodyDims dims;

  /// Vista inicial: de perfil, con un giro leve cuando de perfil exacto algo
  /// se esconde (la barra se ve de punta, la pared de canto).
  final double initialYaw, initialPitch;

  /// Variante que dibuja la figura: agarre ('prona') y si lleva lastre
  /// (mochila). null = vale para cualquiera.
  final String? variantGrip;
  final bool? variantLoaded;

  /// ¿La figura enseña la variante que pide la sesión? Sin contexto (null),
  /// sí: desde el catálogo se muestra la figura tal cual.
  bool matches({String? grip, bool? loaded}) {
    if (variantGrip case final g? when grip != null && gripKey(grip) != gripKey(g)) return false;
    if (variantLoaded case final l? when loaded != null && loaded != l) return false;
    return true;
  }

  late final List<Skeleton2D> _keys = [for (final f in frames) solveKeyPose(f, dims)];

  /// Cara de la pared (x) y de qué lado está el cuerpo (+1 si a la derecha).
  late final (double, double)? _wall = () {
    for (final p in props) {
      if (p['type'] == 'wall') {
        final x = _num(p['x']);
        return (x, _keys.first.joints['hip']!.dx >= x ? 1.0 : -1.0);
      }
    }
    return null;
  }();

  /// Esqueleto en un punto del recorrido: 0 = primer momento, 1 = último.
  Skeleton2D skeletonAt(double progress) {
    if (frames.length == 1) return _clearOfWall(_keys.first.grounded());
    final x = progress.clamp(0.0, 1.0) * (frames.length - 1);
    final i = math.min(x.floor(), frames.length - 2);
    final u = x - i;
    var s = _keepWallContact(solveKeyPose(lerpPose(this, frames[i], frames[i + 1], u), dims), i, u);
    // Si los dos momentos apoyan en el suelo, el intermedio también: la
    // interpolación no lo despega ni lo hunde. Con pivote (rodillas fijas)
    // el apoyo ya está resuelto.
    final la = _keys[i].lowest, lb = _keys[i + 1].lowest;
    if (pivot == null && la > -3 && lb > -3) s = s.shiftedY(_lerp(la, lb, u) - s.lowest);
    return _clearOfWall(s.grounded());
  }

  /// Distancia (hacia el cuerpo) a la que un pie cuenta como apoyado en la
  /// pared: ~10 cm.
  static const wallContact = 3.0;

  /// Pies contra la pared entre dos momentos que los tienen apoyados: la
  /// punta se desliza por la pared en vez de seguir los ángulos
  /// interpolados, que la harían atravesarla (del pino en L al vertical la
  /// pierna gira alrededor de la cadera). Se conserva el largo cadera–tobillo
  /// (pierna recta si lo estaba) y el ángulo del pie; la rodilla sale con IK.
  Skeleton2D _keepWallContact(Skeleton2D s, int i, double u) {
    final wall = _wall;
    if (wall == null || u <= 0 || u >= 1) return s;
    final (wx, side) = wall;
    double gap(Offset p) => (p.dx - wx) * side;
    final a = _keys[i], b = _keys[i + 1];
    final j = Map.of(s.joints);
    final hip = j['hip']!;
    for (final sd in const ['near', 'far']) {
      final ta = a.joints['${sd}Toe'], tb = b.joints['${sd}Toe'];
      final ankle0 = j['${sd}Ankle'], knee0 = j['${sd}Knee'], foot = s.ends['${sd}Leg'];
      if (ta == null || tb == null || ankle0 == null || knee0 == null || foot == null) continue;
      if (gap(ta) > wallContact || gap(tb) > wallContact) continue;
      final fd = _dir(foot);
      // La punta toca la pared; el tobillo queda donde el pie lo deja, nunca
      // más cerca de la pared que en los momentos clave.
      final minAnkle = math.min(gap(a.joints['${sd}Ankle']!), gap(b.joints['${sd}Ankle']!));
      final ankleGap = math.max(_lerp(gap(ta), gap(tb), u) - fd.dx * side * dims.foot, minAnkle);
      final ax = wx + side * ankleGap;
      final len = (ankle0 - hip).distance;
      final dx = ax - hip.dx;
      final Offset target;
      if (dx.abs() >= len) {
        // No alcanza: la pierna queda estirada hacia la pared, sin tocarla.
        target = Offset(hip.dx + dx.sign * len, hip.dy);
      } else {
        // Del mismo lado de la cadera (arriba o abajo) que la interpolación.
        final dyNow = ankle0.dy - hip.dy;
        final dyB = b.joints['${sd}Ankle']!.dy - b.joints['hip']!.dy;
        final sign = dyNow.abs() > 1e-6 ? dyNow.sign : (dyB >= 0 ? 1.0 : -1.0);
        target = Offset(ax, hip.dy + sign * math.sqrt(len * len - dx * dx));
      }
      // La rodilla dobla hacia el mismo lado que en la interpolación; recta,
      // hacia el frente del muslo (opuesto a la cara flexora).
      final v = ankle0 - hip, w = knee0 - hip;
      final cross = v.dx * w.dy - v.dy * w.dx;
      final bend = cross.abs() > 1e-6 ? cross.sign.toInt() : -(flex['${sd}Leg'] ?? 1);
      final (knee, ankle) = twoLink(hip, target, dims.thigh, dims.shin, bend);
      j['${sd}Knee'] = knee;
      j['${sd}Ankle'] = ankle;
      j['${sd}Toe'] = ankle + fd * dims.foot;
    }
    return Skeleton2D(joints: j, torso: s.torso, gaze: s.gaze, ends: s.ends, grips: s.grips);
  }

  /// Nada atraviesa la pared, como nada atraviesa el suelo: si algo la
  /// cruza (con su volumen), todo el cuerpo se aparta. Con los apoyos de
  /// [_keepWallContact] no debería pasar; es la red de seguridad.
  Skeleton2D _clearOfWall(Skeleton2D s) {
    final wall = _wall;
    if (wall == null) return s;
    final (wx, side) = wall;
    var worst = 0.0;
    s.joints.forEach((k, p) {
      worst = math.min(worst, (p.dx - wx) * side - jointPad(k, dims));
    });
    return worst < -0.05 ? s.shiftedX(-worst * side) : s;
  }

  /// Recuadro común (x0, y0, x1, y1) de todos los momentos y los props: la
  /// cámara no salta al animar ni al cambiar de página.
  late final Rect frameBox = _computeBox();

  Rect _computeBox() {
    var box = Rect.zero;
    var first = true;
    void grow(Offset p) {
      if (first) {
        box = Rect.fromLTRB(p.dx, p.dy, p.dx, p.dy);
        first = false;
      } else {
        box = box.expandToInclude(Rect.fromLTRB(p.dx, p.dy, p.dx, p.dy));
      }
    }

    for (var k = 0; k <= 8; k++) {
      final s = skeletonAt(k / 8);
      for (final p in s.joints.values) {
        grow(p);
      }
      final h = s.joints['head']!;
      grow(h - Offset(dims.headRadius, dims.headRadius));
      grow(h + Offset(dims.headRadius, dims.headRadius));
    }
    for (final p in props) {
      switch (p['type']) {
        case 'bar':
          grow(Offset(_num(p['x']), _num(p['y']) - 2));
        case 'sofa':
          // Basta el frente del sofá: lo que importa es el hueco de los talones.
          grow(Offset(math.max(_num(p['x1']), _num(p['x2']) - 9), _num(p['seat']) - 4));
        case 'wall':
          grow(Offset(_num(p['x']) - 2, -12));
      }
    }
    // El suelo entra en cuadro solo si algo apoya en él: colgado de la barra,
    // la figura se vería pequeña sobre un suelo vacío.
    final grounded = _keys.any((k) => k.lowest > -4) || props.any((p) => p['type'] != 'bar' && p['type'] != 'backpack');
    grow(Offset(box.left, grounded ? 0.8 : box.bottom + 4));
    return box.inflate(2);
  }
}

/// Catálogo de figuras 3D, buscado por nombre sin mayúsculas ni tildes.
class Figure3DCatalog {
  Figure3DCatalog(List<Figure3D> figures) : _byKey = {for (final f in figures) nameKey(f.name): f};

  factory Figure3DCatalog.fromJsonString(String source) {
    final data = jsonDecode(source) as Map<String, Object?>;
    final dims = BodyDims.fromJson(data['consts'] as Map<String, Object?>);
    return Figure3DCatalog([
      for (final f in (data['figures'] as List).cast<Map<String, Object?>>()) Figure3D.fromJson(f, dims),
    ]);
  }

  static const asset = 'assets/tecnica/figuras3d.json';

  final Map<String, Figure3D> _byKey;

  Figure3D? forExercise(String name) => _byKey[nameKey(name)];

  Iterable<Figure3D> get all => _byKey.values;
}

// ---------------------------------------------------------------------------
// Cinemática de perfil: la misma de figuras.py.
// ---------------------------------------------------------------------------

/// IK de dos segmentos: (articulación media, extremo).
(Offset, Offset) twoLink(Offset root, Offset target, double a, double b, int bend) {
  final dx = target.dx - root.dx, dy = target.dy - root.dy;
  final d = math.sqrt(dx * dx + dy * dy).clamp((a - b).abs() + 0.01, a + b - 0.001);
  final base = math.atan2(dy, dx);
  final alpha = math.acos(((a * a + d * d - b * b) / (2 * a * d)).clamp(-1.0, 1.0));
  final ang = base + bend * alpha;
  final mid = root + Offset(math.cos(ang), math.sin(ang)) * a;
  final e = target - mid;
  final n = e.distance == 0 ? 1.0 : e.distance;
  return (mid, mid + e / n * b);
}

/// Volumen alrededor del centro de una articulación (zapato, mitón, rodilla,
/// cabeza): lo que no debe entrar en la pared.
double jointPad(String joint, BodyDims d) => joint == 'head'
    ? d.headRadius
    : joint.endsWith('Toe')
        ? 0.6
        : joint.endsWith('Ankle')
            ? 0.9
            : joint.endsWith('Hand')
                ? 0.5
                : joint.endsWith('Knee')
                    ? 1.3
                    : 0.0;

/// Agarre normalizado: 'prono' y 'Prona' son el mismo.
String gripKey(String grip) {
  final k = nameKey(grip);
  for (final g in const ['prona', 'supina', 'neutra', 'mixta']) {
    if (k.startsWith(g.substring(0, g.length - 1))) return g;
  }
  return k;
}

/// Postura de perfil resuelta: articulaciones y orientación de pies y manos.
class Skeleton2D {
  Skeleton2D({required this.joints, required this.torso, required this.gaze, required this.ends, required this.grips});

  final Map<String, Offset> joints;
  final double torso, gaze;

  /// Ángulo del pie ('nearLeg') o de los dedos ('nearArm'), en grados.
  final Map<String, double> ends;
  final Map<String, String?> grips;

  /// Punto más bajo (y mayor), contando el volumen de zapatos y manos.
  double get lowest {
    var m = -double.infinity;
    joints.forEach((k, p) {
      final pad = k.endsWith('Toe')
          ? 0.6
          : k.endsWith('Ankle')
              ? 0.9
              : k.endsWith('Hand')
                  ? 0.5
                  : k.endsWith('Knee')
                      ? 1.3
                      : 0.0;
      m = math.max(m, p.dy + pad);
    });
    return m;
  }

  Skeleton2D shiftedY(double dy) => dy == 0 ? this : _shifted(Offset(0, dy));

  Skeleton2D shiftedX(double dx) => dx == 0 ? this : _shifted(Offset(dx, 0));

  Skeleton2D _shifted(Offset d) => Skeleton2D(
        joints: {for (final e in joints.entries) e.key: e.value + d},
        torso: torso,
        gaze: gaze,
        ends: ends,
        grips: grips,
      );

  /// Nada bajo el suelo: si algo lo atraviesa, todo sube.
  Skeleton2D grounded() {
    final l = lowest;
    return l > 0.05 ? shiftedY(-l) : this;
  }
}

Skeleton2D solveKeyPose(KeyPose p, BodyDims d) {
  final neck = p.hip + _dir(p.torso) * d.torso;
  final j = <String, Offset>{'hip': p.hip, 'neck': neck, 'head': neck + _dir(p.torso + p.gaze) * d.headOffset};
  final ends = <String, double>{};
  final grips = <String, String?>{};
  for (final name in limbNames) {
    final l = p.limbs[name];
    if (l == null) continue;
    final leg = name.endsWith('Leg');
    final side = name.startsWith('near') ? 'near' : 'far';
    final root = leg ? p.hip : neck;
    final a = leg ? d.thigh : d.upperArm, b = leg ? d.shin : d.forearm;
    final Offset mid, end;
    if (l.pin case final pin?) {
      (mid, end) = twoLink(root, pin, a, b, l.bend);
    } else {
      mid = root + _dir(l.upper) * a;
      end = mid + _dir(l.lower) * b;
    }
    if (leg) {
      j['${side}Knee'] = mid;
      j['${side}Ankle'] = end;
      j['${side}Toe'] = end + _dir(l.end) * d.foot;
    } else {
      j['${side}Elbow'] = mid;
      j['${side}Hand'] = end;
    }
    ends[name] = l.end;
    grips[name] = l.grip;
  }
  return Skeleton2D(joints: j, torso: p.torso, gaze: p.gaze, ends: ends, grips: grips);
}

/// Momento intermedio entre dos clave. Se interpolan ángulos (los segmentos
/// conservan su largo) y los apoyos comunes se sujetan con IK: las manos no
/// se despegan de la barra.
KeyPose lerpPose(Figure3D fig, KeyPose a, KeyPose b, double t) {
  final Offset hip;
  if (fig.pivot case final pv?) {
    final da = a.hip - pv, db = b.hip - pv;
    final ang = lerpAngle(_deg(da.direction), _deg(db.direction), t);
    hip = pv + _dir(ang) * _lerp(da.distance, db.distance, t);
  } else {
    hip = Offset.lerp(a.hip, b.hip, t)!;
  }
  final limbs = <String, LimbPose>{};
  for (final name in limbNames) {
    final la = a.limbs[name], lb = b.limbs[name];
    if (la == null || lb == null) {
      if ((t < 0.5 ? la : lb) case final only?) limbs[name] = only;
      continue;
    }
    final pa = la.pin, pb = lb.pin;
    limbs[name] = LimbPose(
      upper: lerpAngle(la.upper, lb.upper, t),
      lower: lerpAngle(la.lower, lb.lower, t),
      end: lerpAngle(la.end, lb.end, t),
      pin: pa != null && pb != null ? Offset.lerp(pa, pb, t) : null,
      bend: t < 0.5 ? la.bend : lb.bend,
      grip: t < 0.5 ? la.grip : lb.grip,
    );
  }
  return KeyPose(
    caption: t < 0.5 ? a.caption : b.caption,
    hip: hip,
    torso: lerpAngle(a.torso, b.torso, t),
    gaze: _lerp(a.gaze, b.gaze, t),
    limbs: limbs,
  );
}

// ---------------------------------------------------------------------------
// Paso a 3D.
// ---------------------------------------------------------------------------

/// El cuerpo en 3D: puntos, ejes del torso y la cara flexora de cada segmento.
class Body3D {
  Body3D({
    required this.p,
    required this.up,
    required this.front,
    required this.headUp,
    required this.face,
    required this.flexor,
    required this.endDir,
    required this.grips,
  });

  final Map<String, V3> p;

  /// Eje del torso (cadera → cuello) y hacia dónde mira el pecho.
  final V3 up, front;

  /// Eje de la cabeza y hacia dónde mira la cara.
  final V3 headUp, face;

  /// Normal de la cara flexora de 'nearThigh', 'farUpperArm', etc.
  final Map<String, V3> flexor;

  /// Dirección del pie ('nearFoot') o de los dedos ('nearHand').
  final Map<String, V3> endDir;
  final Map<String, String?> grips;
}

/// IK de dos segmentos en 3D: la articulación media sale hacia `pole`.
V3 ikJoint(V3 root, V3 end, double a, double b, V3 pole) {
  final to = end - root;
  final dir = to.unit;
  final d = to.length.clamp((a - b).abs() + 0.01, a + b - 0.001);
  final cosA = ((a * a + d * d - b * b) / (2 * a * d)).clamp(-1.0, 1.0);
  var perp = pole - dir * pole.dot(dir);
  if (perp.length < 1e-6) perp = dir.cross(V3.zAxis);
  return root + dir * (a * cosA) + perp.unit * (a * math.sqrt(1 - cosA * cosA));
}

/// Normal de la cara flexora del segmento raíz→medio: hacia donde se dobla
/// el segmento siguiente. Recta, se usa `fallback` y se mezcla sin saltos.
V3 flexorNormal(V3 root, V3 mid, V3 end, V3 fallback) {
  final du = (mid - root).unit;
  final w = end - mid;
  final perp = w - du * w.dot(du);
  final fb = (fallback - du * fallback.dot(du)).unit;
  final k = w.length == 0 ? 0.0 : (perp.length / (0.35 * w.length)).clamp(0.0, 1.0);
  if (k == 0) return fb;
  return (fb * (1 - k) + perp.unit * k).unit;
}

Offset _sagittalFlex(Offset d, int flex) => flex > 0 ? Offset(-d.dy, d.dx) : Offset(d.dy, -d.dx);

Body3D liftSkeleton(Skeleton2D s, Figure3D fig) {
  final d = fig.dims;
  final j = s.joints;
  final p = <String, V3>{
    'hip': V3.lift(j['hip']!, 0),
    'neck': V3.lift(j['neck']!, 0),
    'head': V3.lift(j['head']!, 0),
  };
  final u = (j['neck']! - j['hip']!) / d.torso;
  final up = V3(u.dx, u.dy, 0);
  final front = V3(-u.dy, u.dx, 0);
  final hu = _dir(s.torso + s.gaze);
  final headUp = V3(hu.dx, hu.dy, 0);
  final face = V3(-hu.dy, hu.dx, 0);
  final flexor = <String, V3>{};
  final endDir = <String, V3>{};
  for (final (side, sz) in const [('near', 1.0), ('far', -1.0)]) {
    final hip = V3.lift(j['hip']!, sz * BodyDims.hipHalf);
    final sh = V3.lift(j['neck']!, sz * BodyDims.shoulderHalf);
    p['${side}Hip'] = hip;
    p['${side}Shoulder'] = sh;
    final leg = '${side}Leg', arm = '${side}Arm';
    if (j['${side}Knee'] case final knee?) {
      final k = V3.lift(knee, sz * BodyDims.hipHalf);
      final a = V3.lift(j['${side}Ankle']!, sz * BodyDims.hipHalf);
      final toe = V3.lift(j['${side}Toe']!, sz * (BodyDims.hipHalf + 0.3));
      p['${side}Knee'] = k;
      p['${side}Ankle'] = a;
      p['${side}Toe'] = toe;
      final f2 = _sagittalFlex((knee - j['hip']!) / d.thigh, fig.flex[leg] ?? 1);
      final fb = V3(f2.dx, f2.dy, 0);
      flexor['${side}Thigh'] = flexorNormal(hip, k, a, fb);
      flexor['${side}Shin'] = flexorNormal(a, k, hip, flexor['${side}Thigh']!);
      endDir['${side}Foot'] = (toe - a).unit;
    }
    if (j['${side}Elbow'] case final elbow2?) {
      final hand2 = j['${side}Hand']!;
      final hand = V3.lift(hand2, sz * fig.gripZ);
      // Hacia dónde sale el codo: el de perfil, más un poco hacia afuera.
      final mid2 = Offset.lerp(j['neck']!, hand2, d.upperArm / (d.upperArm + d.forearm))!;
      var out2 = elbow2 - mid2;
      final flex2 = _sagittalFlex((elbow2 - j['neck']!) / d.upperArm, fig.flex[arm] ?? 1);
      if (out2.distance < 0.6) out2 = -flex2;
      final pole = V3(out2.dx, out2.dy, 0).unit + V3(0, 0, sz * fig.elbowOut);
      final e = ikJoint(sh, hand, d.upperArm, d.forearm, pole);
      p['${side}Elbow'] = e;
      p['${side}Hand'] = hand;
      // Cara flexora (bíceps): la del pliegue del codo en el plano de perfil.
      // Con el codo abierto hacia afuera, la geometría 3D la mandaría hacia
      // el tronco y el bíceps dejaría de verse de perfil.
      final fb = V3(flex2.dx, flex2.dy, 0);
      final du = (e - sh).unit;
      flexor['${side}UpperArm'] = (fb - du * fb.dot(du)).unit;
      flexor['${side}Forearm'] = flexorNormal(hand, e, sh, flexor['${side}UpperArm']!);
      final hd = _dir(s.ends[arm] ?? 0);
      endDir['${side}Hand'] = V3(hd.dx, hd.dy, 0);
    }
  }
  return Body3D(
    p: p,
    up: up,
    front: front,
    headUp: headUp,
    face: face,
    flexor: flexor,
    endDir: endDir,
    grips: {for (final e in s.grips.entries) e.key.replaceAll('Arm', 'Hand'): e.value},
  );
}

// ---------------------------------------------------------------------------
// Cámara: giro (yaw) alrededor del eje vertical, inclinación (pitch) y una
// perspectiva suave.
// ---------------------------------------------------------------------------

/// Luz de arriba, de la izquierda y de adelante (y hacia abajo).
const lightDir = V3(-0.42054, -0.74763, 0.51399);

/// Inclinación por defecto: de perfil, apenas desde arriba para ver el suelo
/// y separar un poco el lado lejano.
const defaultPitch = 12.0;

/// Giro máximo al arrastrar en pantalla completa.
const maxYaw = 60.0;

class Projected {
  const Projected(this.offset, this.k, this.z);

  final Offset offset;

  /// Píxeles por unidad a esa profundidad.
  final double k;

  /// Profundidad de vista: mayor = más cerca de la cámara.
  final double z;
}

class Camera3D {
  Camera3D({
    required double yawDeg,
    required double pitchDeg,
    required this.center,
    required this.scale,
    required this.size,
    this.distance = 150,
  })  : _cy = math.cos(_rad(yawDeg)),
        _sy = math.sin(_rad(yawDeg)),
        _ce = math.cos(_rad(pitchDeg)),
        _se = math.sin(_rad(pitchDeg)) {
    final zc0 = distance * _ce;
    position = V3(center.x + zc0 * _sy, center.y - distance * _se, center.z + zc0 * _cy);
    final l = view(center + lightDir);
    final n = math.sqrt(l.x * l.x + l.y * l.y);
    light2 = n == 0 ? const Offset(0, -1) : Offset(l.x / n, l.y / n);
  }

  final V3 center;
  final double scale, distance;
  final Size size;
  final double _cy, _sy, _ce, _se;

  /// Dónde está la cámara en el mundo (para saber qué caras se ven).
  late final V3 position;

  /// Dirección de la luz en pantalla: qué borde de cada volumen va iluminado.
  late final Offset light2;

  /// Coordenadas de vista: x a la derecha, y hacia abajo, z hacia la cámara.
  V3 view(V3 p) {
    final x = p.x - center.x, y = p.y - center.y, z = p.z - center.z;
    final xs = x * _cy - z * _sy, zc0 = x * _sy + z * _cy;
    return V3(xs, y * _ce + zc0 * _se, zc0 * _ce - y * _se);
  }

  Projected project(V3 p) {
    final v = view(p);
    final k = distance / (distance - v.z);
    return Projected(Offset(size.width / 2 + v.x * k * scale, size.height / 2 + v.y * k * scale), k * scale, v.z);
  }

  /// Profundidad horizontal (sin la inclinación): cuánto más cerca de la
  /// cámara está un punto, sin que la altura lo confunda.
  double depth(V3 p) => (p.x - center.x) * _sy + (p.z - center.z) * _cy;

  /// ¿La cara con esta normal, en este punto, mira a la cámara?
  bool faces(V3 point, V3 normal) => normal.dot(position - point) > 0;
}

// ---------------------------------------------------------------------------
// Orden de pintado (algoritmo del pintor).
// ---------------------------------------------------------------------------

class DepthPart {
  DepthPart(this.z, this.draw, [this.label = '']);

  final double z;
  final void Function() draw;

  /// Solo para pruebas y depuración.
  final String label;
}

/// De lejos a cerca; los empates conservan el orden de llegada.
List<DepthPart> sortByDepth(List<DepthPart> parts) {
  final idx = [for (var i = 0; i < parts.length; i++) i];
  idx.sort((a, b) {
    final c = parts[a].z.compareTo(parts[b].z);
    return c != 0 ? c : a.compareTo(b);
  });
  return [for (final i in idx) parts[i]];
}

// ---------------------------------------------------------------------------
// Materiales.
// ---------------------------------------------------------------------------

@immutable
class _Mat {
  const _Mat(this.hi, this.mid, this.lo);

  final Color hi, mid, lo;
}

const _skin = _Mat(Color(0xFFFFF1E2), Color(0xFFD9BCA0), Color(0xFF6E5040));
const _skinBack = _Mat(Color(0xFFD8BCA4), Color(0xFFA2826A), Color(0xFF4A3228));
const _muscle = _Mat(Color(0xFFFFC271), Color(0xFFF08A34), Color(0xFF8A3A0E));
const _shorts = _Mat(Color(0xFF7FA8BC), Color(0xFF3F6476), Color(0xFF16252E));
const _shoe = _Mat(Color(0xFF9AA2B0), Color(0xFF5A6170), Color(0xFF22262E));
const _hair = _Mat(Color(0xFF7A5A44), Color(0xFF4A3426), Color(0xFF1E140E));
const _metal = _Mat(Color(0xFFF0E8DE), Color(0xFF8C7E72), Color(0xFF2C241E));
const _pack = _Mat(Color(0xFF6CC0B4), Color(0xFF34766E), Color(0xFF123430));
const _strap = _Mat(Color(0xFF4FA096), Color(0xFF285E58), Color(0xFF0E2A26));
const _soleColor = Color(0xFFF2EADF);
const _ink = Color(0xFF0B0806);

/// Marca de apoyo escondido (el color de las flechas de las figuras planas).
const _contact = Color(0xFF3DD6C6);

/// Lado lejano más oscuro y apagado: no se confunde con el cercano.
Color _tone(Color c, double near) {
  final g = (0.3 * c.red + 0.59 * c.green + 0.11 * c.blue).round();
  final gray = Color.fromARGB(c.alpha, g, g, (g * 1.04).round().clamp(0, 255));
  final desat = Color.lerp(gray, c, 0.62 + 0.38 * near)!;
  final k = 0.62 + 0.38 * near;
  return Color.fromARGB(c.alpha, (desat.red * k).round(), (desat.green * k).round(), (desat.blue * k).round());
}

Color _scaled(Color c, double k, [double alpha = 1]) => Color.fromRGBO(
    (c.red * k).round().clamp(0, 255), (c.green * k).round().clamp(0, 255), (c.blue * k).round().clamp(0, 255), alpha);

/// Degradado de volumen: borde iluminado, brillo, medio tono y sombra.
Paint _shadePaint(Offset from, Offset to, _Mat m, double near) => Paint()
  ..shader = ui.Gradient.linear(from, to, [
    _tone(Color.lerp(m.hi, m.mid, 0.35)!, near),
    _tone(m.hi, near),
    _tone(m.mid, near),
    _tone(m.lo, near),
  ], const [
    0,
    0.22,
    0.5,
    1
  ]);

Paint _outline(Camera3D cam, double near) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeJoin = StrokeJoin.round
  ..strokeWidth = math.max(0.6, (0.09 + 0.15 * near) * cam.scale)
  ..color = _ink.withOpacity(0.5 + 0.3 * near);

// ---------------------------------------------------------------------------
// Primitivas 2D sobre lo proyectado.
// ---------------------------------------------------------------------------

/// Cápsula cónica: dos círculos unidos por sus tangentes exteriores.
Path capsulePath(Offset a, double ra, Offset b, double rb) {
  final d = (b - a).distance;
  final path = Path();
  if (d <= (ra - rb).abs() + 0.01) {
    final (c, r) = ra > rb ? (a, ra) : (b, rb);
    return path..addOval(Rect.fromCircle(center: c, radius: r));
  }
  final phi = math.atan2(b.dy - a.dy, b.dx - a.dx);
  final th = math.acos(((ra - rb) / d).clamp(-1.0, 1.0));
  path.moveTo(a.dx + ra * math.cos(phi + th), a.dy + ra * math.sin(phi + th));
  path.lineTo(b.dx + rb * math.cos(phi + th), b.dy + rb * math.sin(phi + th));
  path.arcTo(Rect.fromCircle(center: b, radius: rb), phi + th, -2 * th, false);
  path.lineTo(a.dx + ra * math.cos(phi - th), a.dy + ra * math.sin(phi - th));
  path.arcTo(Rect.fromCircle(center: a, radius: ra), phi - th, 2 * th - 2 * math.pi, false);
  return path..close();
}

/// Casco convexo (cadena monótona).
List<Offset> convexHull(List<Offset> input) {
  if (input.length < 3) return [...input];
  final pts = [...input]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final lo = <Offset>[], up = <Offset>[];
  for (final p in pts) {
    while (lo.length >= 2 && cross(lo[lo.length - 2], lo.last, p) <= 0) {
      lo.removeLast();
    }
    lo.add(p);
  }
  for (final p in pts.reversed) {
    while (up.length >= 2 && cross(up[up.length - 2], up.last, p) <= 0) {
      up.removeLast();
    }
    up.add(p);
  }
  return [...lo..removeLast(), ...up..removeLast()];
}

Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

// ---------------------------------------------------------------------------
// Torso: secciones elípticas a lo largo de la columna (t: 0 cadera,
// 1 hombros). w = medio ancho (z), d = media profundidad, o = desplazamiento
// hacia el pecho (negativo: hacia la espalda, como los glúteos).
// ---------------------------------------------------------------------------

const _torsoSections = [
  (t: -0.12, w: 3.4, d: 2.5, o: -0.5),
  (t: 0.03, w: 4.1, d: 3.1, o: -0.85),
  (t: 0.33, w: 3.5, d: 2.4, o: 0.05),
  (t: 0.66, w: 4.4, d: 3.0, o: 0.85),
  (t: 0.9, w: 5.0, d: 2.6, o: 0.25),
  (t: 1.04, w: 3.8, d: 2.0, o: 0.0),
];

({double w, double d, double o}) _torsoAt(double t) {
  const s = _torsoSections;
  if (t <= s.first.t) return (w: s.first.w, d: s.first.d, o: s.first.o);
  for (var i = 0; i < s.length - 1; i++) {
    if (t <= s[i + 1].t) {
      final u = (t - s[i].t) / (s[i + 1].t - s[i].t);
      return (w: _lerp(s[i].w, s[i + 1].w, u), d: _lerp(s[i].d, s[i + 1].d, u), o: _lerp(s[i].o, s[i + 1].o, u));
    }
  }
  return (w: s.last.w, d: s.last.d, o: s.last.o);
}

// ---------------------------------------------------------------------------
// La escena.
// ---------------------------------------------------------------------------

/// Pinta una figura en un punto del recorrido (0 = primer momento, 1 = último).
/// Sin `yaw` ni `pitch`, la vista inicial de la figura.
void paintFigure3D(Canvas canvas, Size size, Figure3D fig, double progress, {double? yaw, double? pitch}) =>
    _Scene(canvas, size, fig, fig.skeletonAt(progress), yaw ?? fig.initialYaw, pitch ?? fig.initialPitch).render();

/// Cámara con la que se pinta una figura en un lienzo de ese tamaño.
Camera3D cameraFor(Figure3D fig, Size size, {double yaw = 0, double pitch = defaultPitch}) {
  final box = fig.frameBox;
  final scale = math.min(size.width / (box.width * 1.1 + 8), size.height / (box.height * 1.06 + 8));
  return Camera3D(
    yawDeg: yaw,
    pitchDeg: pitch,
    center: V3(box.center.dx, box.center.dy + 1.5, 0),
    scale: scale,
    size: size,
  );
}

class _Scene {
  _Scene(this.canvas, this.size, this.fig, this.skel, double yaw, double pitch)
      : cam = cameraFor(fig, size, yaw: yaw, pitch: pitch),
        body = liftSkeleton(skel, fig);

  final Canvas canvas;
  final Size size;
  final Figure3D fig;
  final Skeleton2D skel;
  final Camera3D cam;
  final Body3D body;

  late final double _zHip = cam.depth(body.p['hip']!);

  /// 0 = lado lejano, 1 = cercano: decide color y grosor del contorno.
  double nearOf(V3 p) => (0.5 + (cam.depth(p) - _zHip) / 6.5).clamp(0.1, 1.0);

  BodyDims get d => fig.dims;

  void render() {
    _floor();
    _shadows();
    _backProps();
    final parts = <DepthPart>[];
    _bodyParts(parts);
    _sortedProps(parts);
    for (final part in sortByDepth(parts)) {
      part.draw();
    }
    _frontOverlays();
  }

  // --- suelo y sombras -----------------------------------------------------

  void _floor() {
    final box = fig.frameBox;
    final x0 = box.left - 10, x1 = box.right + 10;
    const zr = 20.0;
    final corners = [V3(x0, 0, -zr), V3(x1, 0, -zr), V3(x1, 0, zr), V3(x0, 0, zr)].map(cam.project).toList();
    final c = cam.project(V3((x0 + x1) / 2, 0, 0)).offset;
    final r = corners.map((p) => (p.offset - c).distance).reduce(math.max);
    canvas.drawPath(
      _poly([for (final p in corners) p.offset]),
      Paint()..shader = ui.Gradient.radial(c, r, const [Color(0x8C3A291D), Color(0x003A291D)]),
    );
    final line = Paint()
      ..color = const Color(0x0FFFF6EC)
      ..strokeWidth = 1;
    for (var x = (x0 / 6).ceil() * 6.0; x <= x1; x += 6) {
      canvas.drawLine(cam.project(V3(x, 0, -zr)).offset, cam.project(V3(x, 0, zr)).offset, line);
    }
    for (var z = -zr; z <= zr; z += 5) {
      canvas.drawLine(cam.project(V3(x0, 0, z)).offset, cam.project(V3(x1, 0, z)).offset, line);
    }
  }

  void _shadows() {
    final p = body.p;
    V3 fl(V3 v) => V3(v.x, -0.02, v.z);
    // Sombra difusa del cuerpo aplastado sobre el suelo (luz cenital).
    final hAvg = -(skel.joints['hip']!.dy + skel.joints['neck']!.dy) / 2;
    final layer = Paint()..color = Color.fromRGBO(0, 0, 0, (0.62 - hAvg * 0.006).clamp(0.22, 0.6));
    canvas.saveLayer(Offset.zero & size, layer);
    final fill = Paint()
      ..color = const Color(0xFF000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (0.5 + hAvg * 0.03) * cam.scale);
    void seg(String a, String b, double ra, double rb) {
      if (p[a] == null || p[b] == null) return;
      final pa = cam.project(fl(p[a]!)), pb = cam.project(fl(p[b]!));
      canvas.drawPath(capsulePath(pa.offset, ra * pa.k, pb.offset, rb * pb.k), fill);
    }

    for (final s in const ['near', 'far']) {
      seg('${s}Hip', '${s}Knee', 2.3, 1.6);
      seg('${s}Knee', '${s}Ankle', 1.6, 1.0);
      seg('${s}Ankle', '${s}Toe', 1.2, 1.0);
      seg('${s}Shoulder', '${s}Elbow', 1.5, 1.1);
      seg('${s}Elbow', '${s}Hand', 1.1, 0.9);
    }
    seg('hip', 'neck', 4.2, 4.6);
    final hd = cam.project(fl(p['head']!));
    canvas.drawCircle(hd.offset, d.headRadius * hd.k, fill);
    canvas.restore();

    // Sombras de contacto: un óvalo oscuro y nítido bajo lo que toca el suelo.
    for (final name in const [
      'nearHand',
      'farHand',
      'nearToe',
      'farToe',
      'nearAnkle',
      'farAnkle',
      'nearKnee',
      'farKnee'
    ]) {
      final v = p[name];
      if (v == null || v.y < -3.2) continue;
      final a = ((v.y + 3.2) / 3.0).clamp(0.0, 1.0);
      final c = cam.project(V3(v.x, 0, v.z));
      final rx = cam.project(V3(v.x + 2.2, 0, v.z)).offset - c.offset;
      final rz = cam.project(V3(v.x, 0, v.z + 1.5)).offset - c.offset;
      canvas.drawOval(
        Rect.fromCenter(center: c.offset, width: rx.distance * 2, height: math.max(rz.distance * 2, 2)),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 0.55 * a)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.35 * cam.scale),
      );
    }
  }

  // --- volúmenes -----------------------------------------------------------

  /// Caja con centro y tres semiejes; solo las caras que miran a la cámara.
  void _box(V3 c, List<V3> e, Color color, {double alpha = 1, double edge = 0.5}) {
    for (var k = 0; k < 3; k++) {
      for (final s in const [1.0, -1.0]) {
        final n = e[k] * s;
        final fc = c + n;
        if (!cam.faces(fc, n)) continue;
        final ei = e[(k + 1) % 3], ej = e[(k + 2) % 3];
        final pts = [fc + ei + ej, fc - ei + ej, fc - ei - ej, fc + ei - ej].map((v) => cam.project(v).offset).toList();
        final lam = 0.42 + 0.58 * math.max(0, n.unit.dot(lightDir));
        final path = _poly(pts);
        canvas.drawPath(path, Paint()..color = _scaled(color, lam, alpha));
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.6, 0.1 * cam.scale)
            ..color = _ink.withOpacity(edge * alpha),
        );
      }
    }
  }

  /// Cápsula sombreada; devuelve su contorno para recortar zonas encima.
  Path _capsule(V3 a, V3 b, double ra, double rb, _Mat m, double near, {bool outline = true}) {
    final pa = cam.project(a), pb = cam.project(b);
    final ka = ra * pa.k, kb = rb * pb.k;
    final path = capsulePath(pa.offset, ka, pb.offset, kb);
    final mid = (pa.offset + pb.offset) / 2;
    final paint = _shadePaint(mid + _lit(pb.offset - pa.offset) * math.max(ka, kb),
        mid - _lit(pb.offset - pa.offset) * math.max(ka, kb), m, near);
    canvas.drawPath(path, paint);
    if (outline) canvas.drawPath(path, _outline(cam, near));
    return path;
  }

  /// Normal en pantalla de un eje, del lado de la luz.
  Offset _lit(Offset axis) {
    var n = Offset(-axis.dy, axis.dx);
    final l = n.distance;
    if (l == 0) return cam.light2;
    n = n / l;
    return n.dx * cam.light2.dx + n.dy * cam.light2.dy < 0 ? -n : n;
  }

  void _sphere(V3 c, double r, _Mat m, double near, {bool outline = true}) {
    final p = cam.project(c);
    final rr = r * p.k;
    final focal = p.offset + cam.light2 * rr * 0.42;
    canvas.drawCircle(
      p.offset,
      rr,
      Paint()
        ..shader = ui.Gradient.radial(p.offset, rr, [_tone(m.hi, near), _tone(m.mid, near), _tone(m.lo, near)],
            const [0, 0.55, 1], TileMode.clamp, null, focal, rr * 0.08),
    );
    if (outline) canvas.drawCircle(p.offset, rr, _outline(cam, near));
  }

  /// Zona de una superficie: t en [t0, t1] y, en cada t, los ángulos
  /// `center(t) ± half(t)` alrededor del eje. Se recorta al contorno del
  /// volumen y solo se pinta la parte que mira a la cámara.
  void _patch(
    V3 Function(double t, double th) point,
    V3 Function(double t, double th) normal,
    double t0,
    double t1,
    double Function(double t) center,
    double Function(double t) half,
    Paint paint,
    Path clip,
  ) {
    const rows = 8;
    // Por fila, el tramo visible (de un borde al otro) en ángulos.
    final spans = <(double, double, double)>[];
    for (var r = 0; r <= rows; r++) {
      final t = _lerp(t0, t1, r / rows);
      final c = center(t), h = half(t);
      final full = h >= math.pi - 1e-6;
      final n = math.max(8, (2 * h / _rad(5)).ceil());
      final ths = [for (var i = 0; i <= n; i++) c - h + 2 * h * i / n];
      final vis = [for (final th in ths) cam.faces(point(t, th), normal(t, th))];
      int? first, last;
      if (full) {
        // Circular: se arranca en una muestra oculta para no partir el tramo.
        final start = vis.indexOf(false);
        if (start < 0) continue;
        for (var k = 1; k <= n; k++) {
          final i = (start + k) % n;
          if (vis[i]) {
            first ??= start + k;
            last = start + k;
          } else if (first != null) {
            break;
          }
        }
        if (first == null || last == null || last == first) continue;
        double at(int k) => ths[k % n] + (k >= n ? 2 * math.pi : 0);
        spans.add((t, at(first), at(last)));
      } else {
        for (var i = 0; i <= n; i++) {
          if (vis[i]) {
            first ??= i;
            last = i;
          } else if (first != null) {
            break;
          }
        }
        if (first == null || last == null || last == first) continue;
        spans.add((t, ths[first], ths[last]));
      }
    }
    if (spans.length < 2) return;
    Offset pr(double t, double th) => cam.project(point(t, th)).offset;
    const arc = 8;
    final (ta, a0, a1) = spans.first;
    final (tb, b0, b1) = spans.last;
    final pts = <Offset>[
      for (var k = 0; k <= arc; k++) pr(ta, _lerp(a0, a1, k / arc)),
      for (final (t, _, e) in spans.sublist(1, spans.length - 1)) pr(t, e),
      for (var k = arc; k >= 0; k--) pr(tb, _lerp(b0, b1, k / arc)),
      for (final (t, s0, _) in spans.sublist(1, spans.length - 1).reversed) pr(t, s0),
    ];
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawPath(_poly(pts), paint);
    canvas.restore();
  }

  /// Superficie de una cápsula cónica con su marco: `front` define θ = 0.
  (V3 Function(double, double), V3 Function(double, double)) _limbSurface(V3 a, V3 b, double ra, double rb, V3 front) {
    final dd = (b - a).unit;
    final f = (front - dd * front.dot(dd)).unit;
    final s = dd.cross(f);
    V3 normal(double t, double th) => f * math.cos(th) + s * math.sin(th);
    V3 point(double t, double th) => V3.lerp(a, b, t) + normal(t, th) * _lerp(ra, rb, t);
    return (point, normal);
  }

  double _faceAngle(String face) => switch (face) {
        'extensor' || 'back' => math.pi,
        _ => 0,
      };

  /// Un segmento de extremidad con su ropa y sus zonas musculares.
  void _limb(String side, String part, String a, String b, double ra, double rb) {
    final pa = body.p['$side$a'], pb = body.p['$side$b'];
    if (pa == null || pb == null) return;
    final near = nearOf(V3.lerp(pa, pb, 0.5));
    final clip = _capsule(pa, pb, ra, rb, _skin, near, outline: false);
    final front = body.flexor['$side$part'] ?? body.front;
    final (point, normal) = _limbSurface(pa, pb, ra, rb, front);
    final pp = cam.project(pa).offset, pq = cam.project(pb).offset;
    final r = math.max(ra * cam.project(pa).k, rb * cam.project(pb).k);
    final mid = (pp + pq) / 2;
    final lit = _lit(pq - pp);
    Paint paintOf(_Mat m) => _shadePaint(mid + lit * r, mid - lit * r, m, near);
    if (part == 'UpperArm' && fig.regions.any((r) => r.part == 'shoulder')) {
      // Deltoide: casquete que baja desde el hombro por el tercio de arriba.
      _patch(point, normal, -0.15, 0.36, (_) => math.pi, (t) => _rad(t < 0.2 ? 180 : _lerp(180, 70, (t - 0.2) / 0.16)),
          paintOf(_muscle), clip);
    }
    for (final reg in fig.regions) {
      if (reg.part != part[0].toLowerCase() + part.substring(1)) continue;
      final halfW = reg.face == 'all' ? math.pi : _rad(reg.width);
      _patch(point, normal, reg.from, reg.to, (_) => _faceAngle(reg.face), (_) => halfW, paintOf(_muscle), clip);
    }
    if (part == 'Thigh') {
      // Pantaloneta: marca dónde empieza la pierna y dónde está la cadera.
      _patch(point, normal, -0.2, 0.26, (_) => 0, (_) => math.pi, paintOf(_shorts), clip);
    }
    canvas.drawPath(clip, _outline(cam, near));
  }

  void _torso() {
    final p = body.p;
    final hip = p['hip']!;
    final up = body.up, fr = body.front;
    V3 point(double t, double th) {
      final s = _torsoAt(t);
      return hip + up * (d.torso * t) + fr * (s.o + s.d * math.cos(th)) + V3.zAxis * (s.w * math.sin(th));
    }

    V3 normal(double t, double th) {
      final s = _torsoAt(t);
      return (fr * (math.cos(th) / s.d) + V3.zAxis * (math.sin(th) / s.w)).unit;
    }

    final pts = <Offset>[];
    for (final s in _torsoSections) {
      for (var i = 0; i < 20; i++) {
        pts.add(cam.project(point(s.t, i / 20 * 2 * math.pi)).offset);
      }
    }
    final hull = _poly(convexHull(pts));
    final h = cam.project(hip).offset, nk = cam.project(p['neck']!).offset;
    final lit = _lit(nk - h);
    final c = (h + nk) / 2;
    var mn = double.infinity, mx = -double.infinity;
    for (final q in pts) {
      final v = (q.dx - c.dx) * lit.dx + (q.dy - c.dy) * lit.dy;
      mn = math.min(mn, v);
      mx = math.max(mx, v);
    }
    Paint paintOf(_Mat m) => _shadePaint(c + lit * mx, c + lit * mn, m, 0.95);
    canvas.drawPath(hull, paintOf(_skin));
    // Espalda un tono más oscura que el pecho: de perfil se lee hacia dónde mira.
    _patch(point, normal, -0.2, 1.1, (_) => math.pi, (_) => _rad(90), paintOf(_skinBack), hull);
    for (final reg in fig.regions.where((r) => r.part == 'torso')) {
      if (reg.face == 'lats') {
        // Dorsal: triángulo de la axila a la cintura, en el costado de atrás.
        for (final side in const [1.0, -1.0]) {
          double u(double t) => ((t - reg.from) / (reg.to - reg.from)).clamp(0.0, 1.0);
          _patch(point, normal, reg.from, reg.to, (t) => side * _rad(_lerp(138, 102, u(t))),
              (t) => _rad(_lerp(12, 42, u(t))), paintOf(_muscle), hull);
        }
      } else {
        final halfW = reg.face == 'all' ? math.pi : _rad(reg.width);
        _patch(point, normal, reg.from, reg.to, (_) => _faceAngle(reg.face), (_) => halfW, paintOf(_muscle), hull);
      }
    }
    // Línea del esternón y del abdomen: el frente del torso.
    final sternum = Path();
    var started = false;
    for (var k = 0; k <= 10; k++) {
      final t = _lerp(0.18, 0.92, k / 10);
      final q = point(t, 0);
      if (!cam.faces(q, normal(t, 0))) {
        started = false;
        continue;
      }
      final o = cam.project(q).offset;
      if (started) {
        sternum.lineTo(o.dx, o.dy);
      } else {
        sternum.moveTo(o.dx, o.dy);
        started = true;
      }
    }
    canvas.drawPath(
      sternum,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, 0.12 * cam.scale)
        ..color = _ink.withOpacity(0.35),
    );
    // Pantaloneta: la pelvis se distingue del tronco.
    _patch(point, normal, -0.3, 0.17, (_) => 0, (_) => math.pi, paintOf(_shorts), hull);
    canvas.drawPath(hull, _outline(cam, 1));
  }

  void _head() {
    final p = body.p;
    final head = p['head']!;
    final r = d.headRadius;
    const near = 1.0;
    _capsule(p['neck']! + body.headUp * 0.6, head - body.headUp * 1.5, 1.45, 1.3, _skin, near);
    final face = body.face, hu = body.headUp;
    final nose = head + face * (r * 0.95) - hu * 0.35;
    final noseFront = cam.view(nose).z > cam.view(head).z;
    if (!noseFront) _sphere(nose, 0.7, _skin, near);
    _sphere(head, r, _skin, near, outline: false);
    // Pelo: casquete en la nuca y la coronilla. Se mueve con la cara, así
    // que de perfil se sabe hacia dónde mira la cabeza.
    final hc = cam.project(head);
    final hairAxis = (-face * 0.75 + hu * 0.65).unit;
    final ax = cam.project(head + hairAxis).offset - hc.offset;
    final az = cam.view(head + hairAxis).z - cam.view(head).z;
    final a2 = ax.distance < 1e-6 ? const Offset(0, -1) : ax / ax.distance;
    final shift = (0.6 - 0.8 * az).clamp(0.0, 1.5);
    final hairC = hc.offset + a2 * (r * hc.k * shift);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: hc.offset, radius: r * hc.k)));
    canvas.drawCircle(
      hairC,
      r * hc.k * 1.05,
      Paint()
        ..shader = ui.Gradient.radial(
            hairC + cam.light2 * r * hc.k * 0.4, r * hc.k * 1.3, [_hair.hi, _hair.mid, _hair.lo], const [0, 0.5, 1]),
    );
    canvas.restore();
    canvas.drawCircle(hc.offset, r * hc.k, _outline(cam, near));
    // Ojos y orejas: solo los que miran a la cámara.
    for (final side in const [1.0, -1.0]) {
      final ear = head + V3.zAxis * (side * r * 0.97) - face * 0.35;
      if (cam.faces(ear, V3.zAxis * side)) {
        final e = cam.project(ear);
        canvas.drawOval(Rect.fromCenter(center: e.offset, width: 1.1 * e.k, height: 1.5 * e.k),
            Paint()..color = _tone(_skin.mid, near));
        canvas.drawOval(Rect.fromCenter(center: e.offset, width: 1.1 * e.k, height: 1.5 * e.k), _outline(cam, 0.4));
      }
      final eyeDir = (face * 0.8 + hu * 0.2 + V3.zAxis * (side * 0.5)).unit;
      final eye = head + eyeDir * (r * 0.97);
      if (cam.faces(eye, eyeDir)) {
        final e = cam.project(eye);
        canvas.drawCircle(e.offset, 0.42 * e.k, Paint()..color = const Color(0xFF241A13));
      }
    }
    if (noseFront) _sphere(nose, 0.7, _skin, near);
  }

  /// Zapato en cuña: talón alto, punta afinada y suela clara.
  void _foot(String side) {
    final a = body.p['${side}Ankle'], toe = body.p['${side}Toe'];
    if (a == null || toe == null) return;
    final f = (toe - a).unit;
    // La suela mira al lado contrario del empeine (en el plano de perfil).
    final sole = V3(-f.y, f.x, 0);
    const z = V3.zAxis;
    final near = nearOf(V3.lerp(a, toe, 0.5));
    final ft = d.foot;
    final prof = <(V3, double)>[
      (a - f * 1.3 + sole * 1.1, 0.8), // talón abajo
      (a - f * 1.0 - sole * 0.6, 0.75), // talón arriba
      (a + f * 0.8 - sole * 0.75, 0.95), // empeine
      (a + f * (ft - 0.6) - sole * 0.05, 1.15), // dedos arriba
      (a + f * ft + sole * 0.55, 0.85), // punta
      (a + f * (ft - 0.7) + sole * 1.15, 1.15), // suela delante
      (a - f * 0.9 + sole * 1.25, 0.85), // suela atrás
    ];
    final pts = <Offset>[
      for (final (q, w) in prof) ...[cam.project(q + z * w).offset, cam.project(q - z * w).offset],
    ];
    final hull = _poly(convexHull(pts));
    final h = cam.project(a).offset, t = cam.project(toe).offset;
    final lit = _lit(t - h);
    final r = 1.4 * cam.project(a).k;
    canvas.drawPath(hull, _shadePaint((h + t) / 2 + lit * r, (h + t) / 2 - lit * r, _shoe, near));
    // Suela: banda clara en el costado que mira a la cámara.
    final zs = cam.faces(a, z) ? 1.0 : -1.0;
    final bottom = [prof[6], prof[5], prof[4]];
    final band = <Offset>[
      for (final (q, w) in bottom) cam.project(q + z * (zs * w)).offset,
      for (final (q, w) in bottom.reversed) cam.project(q - sole * 0.55 + z * (zs * w)).offset,
    ];
    canvas.drawPath(_poly(band), Paint()..color = _tone(_soleColor, near));
    canvas.drawPath(hull, _outline(cam, near));
  }

  /// Mano en mitón (dedos juntos y pulgar), o puño cerrado en la barra.
  void _hand(String side, double sz) {
    final w = body.p['${side}Hand'];
    if (w == null) return;
    final near = nearOf(w);
    if (body.grips['${side}Hand'] == 'bar') {
      // Puño alrededor de la barra: ancho a lo largo de ella, con nudillos.
      final a = w + V3.zAxis * 1.15, b = w - V3.zAxis * 1.15;
      final clip = _capsule(a, b, 1.3, 1.3, _skin, near);
      final knuckles = Path();
      for (var k = 0; k <= 3; k++) {
        final q = cam.project(V3.lerp(a, b, k / 3) + const V3(0.9, -0.55, 0));
        knuckles.addOval(Rect.fromCircle(center: q.offset, radius: 0.32 * q.k));
      }
      canvas.save();
      canvas.clipPath(clip);
      canvas.drawPath(
          knuckles,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.5, 0.1 * cam.scale)
            ..color = _ink.withOpacity(0.35));
      canvas.restore();
      return;
    }
    final f = (body.endDir['${side}Hand'] ?? const V3(1, 0, 0)).unit;
    final medial = V3.zAxis * -sz;
    final th = f.cross(medial).unit;
    // Algo más grande que la proporción real: a 360 dp el apoyo tiene que leerse.
    const len = 4.4;
    final prof = <(double, double, double)>[
      (0, 1.05, 0.62),
      (1.2, 1.4, 0.66),
      (len - 0.9, 1.3, 0.52),
      (len, 0.85, 0.4)
    ];
    final pts = <Offset>[
      for (final (l, wd, tk) in prof)
        for (final (sw, st) in const [(1.0, 1.0), (1.0, -1.0), (-1.0, 1.0), (-1.0, -1.0)])
          cam.project(w + f * l + medial * (sw * wd) + th * (st * tk)).offset,
    ];
    final thumbA = w + medial * 1.1 + f * 0.6, thumbB = w + medial * 1.95 + f * 2.2;
    final thumbFront = cam.view(thumbB).z > cam.view(w + f * 1.2).z;
    if (!thumbFront) _capsule(thumbA, thumbB, 0.5, 0.42, _skin, near);
    final hull = _poly(convexHull(pts));
    final h = cam.project(w).offset, t = cam.project(w + f * len).offset;
    final lit = _lit(t - h);
    final r = 1.0 * cam.project(w).k;
    canvas.drawPath(hull, _shadePaint((h + t) / 2 + lit * r, (h + t) / 2 - lit * r, _skin, near));
    canvas.drawPath(hull, _outline(cam, near));
    if (thumbFront) _capsule(thumbA, thumbB, 0.5, 0.42, _skin, near);
  }

  void _bodyParts(List<DepthPart> parts) {
    final p = body.p;
    double zc(V3 v) => cam.view(v).z;
    double zm(String a, String b) => p[a] == null || p[b] == null ? 0 : (zc(p[a]!) + zc(p[b]!)) / 2;
    for (final (side, sz) in const [('near', 1.0), ('far', -1.0)]) {
      parts
        ..add(DepthPart(
            zm('${side}Hip', '${side}Knee'), () => _limb(side, 'Thigh', 'Hip', 'Knee', 2.4, 1.65), '${side}Thigh'))
        ..add(DepthPart(
            zm('${side}Knee', '${side}Ankle'), () => _limb(side, 'Shin', 'Knee', 'Ankle', 1.65, 1.05), '${side}Shin'))
        ..add(DepthPart(zm('${side}Ankle', '${side}Toe') + 0.05, () => _foot(side), '${side}Foot'))
        ..add(DepthPart(zm('${side}Shoulder', '${side}Elbow'),
            () => _limb(side, 'UpperArm', 'Shoulder', 'Elbow', 1.55, 1.15), '${side}UpperArm'))
        ..add(DepthPart(zm('${side}Elbow', '${side}Hand'), () => _limb(side, 'Forearm', 'Elbow', 'Hand', 1.15, 0.85),
            '${side}Forearm'));
      if (p['${side}Hand'] case final hand?) {
        parts.add(DepthPart(zc(hand) + 0.1, () => _hand(side, sz), '${side}Hand'));
      }
      final sh = p['${side}Shoulder']!;
      final delt = fig.regions.any((r) => r.part == 'shoulder');
      parts.add(DepthPart(zc(sh) - 0.2, () {
        _sphere(sh, 1.8, delt ? _muscle : _skin, nearOf(sh));
      }, '${side}Shoulder'));
    }
    final zT = (zc(p['hip']!) + zc(p['neck']!)) / 2;
    parts.add(DepthPart(zT, _torso, 'torso'));
    parts.add(DepthPart(zT + (zc(p['head']!) >= zc(p['hip']!) ? 0.2 : -0.2), _head, 'head'));
  }

  // --- props ---------------------------------------------------------------

  void _backProps() {
    for (final pr in fig.props) {
      switch (pr['type']) {
        case 'wall':
          final x = _num(pr['x']), th = _num(pr['thick'], 3), top = _num(pr['top'], -80), dz = _num(pr['depth'], 22);
          _box(V3(x - th / 2, top / 2, 0), [V3(th / 2, 0, 0), V3(0, -top / 2, 0), V3(0, 0, dz)],
              const Color(0xFF5E4636));
          // Zócalo: ayuda a leer dónde se juntan pared y suelo.
          _box(V3(x + 0.25, -0.6, 0), [const V3(0.25, 0, 0), const V3(0, 0.6, 0), V3(0, 0, dz)],
              const Color(0xFF7A6150));
        case 'sofa':
          _sofa(pr, 1);
        case 'cushion':
          final x1 = _num(pr['x1']), x2 = _num(pr['x2']), h = _num(pr['h'], 1), dz = _num(pr['depth'], 8);
          _box(V3((x1 + x2) / 2, -h / 2, 0), [V3((x2 - x1) / 2, 0, 0), V3(0, h / 2, 0), V3(0, 0, dz)],
              const Color(0xFFB07A4E));
        case 'bar':
          // Marco de la puerta: dos parantes y el dintel, detrás del cuerpo.
          final bx = _num(pr['x']), by = _num(pr['y']), half = _num(pr['half'], 16);
          final top = by - 10;
          // De perfil los dos parantes caen detrás del cuerpo: van tenues.
          for (final s in const [-1.0, 1.0]) {
            _box(V3(bx, top / 2, s * (half + 1.2)), [const V3(2.2, 0, 0), V3(0, -top / 2, 0), const V3(0, 0, 1.2)],
                const Color(0xFF4A382B),
                alpha: 0.22, edge: 0.3);
          }
          _box(V3(bx, top - 1.5, 0), [const V3(2.2, 0, 0), const V3(0, 1.5, 0), V3(0, 0, half + 2.4)],
              const Color(0xFF4A382B));
      }
    }
  }

  void _sofa(Map<String, Object?> pr, double alpha, {bool cut = false}) {
    final x1 = _num(pr['x1']), x2 = _num(pr['x2']);
    final under = _num(pr['under']), seat = _num(pr['seat']), back = _num(pr['back']), bw = _num(pr['backW'], 7);
    final dz = _num(pr['depth'], 19);
    const base = Color(0xFF5C4A66);
    if (cut) {
      // Corte: el frente del sofá, translúcido, por encima de los pies: se
      // ve que los talones quedan trabados debajo.
      final c = V3((x1 + x2) / 2, (seat + under) / 2, 0);
      _box(c, [V3((x2 - x1) / 2, 0, 0), V3(0, (under - seat) / 2, 0), V3(0, 0, dz)], base, alpha: alpha, edge: 0.9);
      return;
    }
    _box(V3((x1 + x2) / 2, (seat + under) / 2, 0),
        [V3((x2 - x1) / 2, 0, 0), V3(0, (under - seat) / 2, 0), V3(0, 0, dz)], base);
    _box(V3(x1 + bw / 2, (back + seat) / 2, 0), [V3(bw / 2, 0, 0), V3(0, (seat - back) / 2, 0), V3(0, 0, dz)],
        const Color(0xFF4E3E58));
    for (final fx in [x1 + 1.5, x2 - 1.5]) {
      for (final fz in [-dz + 1.5, dz - 1.5]) {
        _box(V3(fx, under / 2, fz), [const V3(0.7, 0, 0), V3(0, -under / 2, 0), const V3(0, 0, 0.7)],
            const Color(0xFF3C2C22));
      }
    }
  }

  void _sortedProps(List<DepthPart> parts) {
    double zc(V3 v) => cam.view(v).z;
    for (final pr in fig.props) {
      switch (pr['type']) {
        case 'bar':
          final bx = _num(pr['x']), by = _num(pr['y']), half = _num(pr['half'], 16);
          // La barra en tramos: la mano de adelante queda encima y la de atrás debajo.
          const n = 8;
          for (var i = 0; i < n; i++) {
            final a = V3(bx, by, _lerp(-half, half, i / n)), b = V3(bx, by, _lerp(-half, half, (i + 1) / n));
            parts.add(DepthPart((zc(a) + zc(b)) / 2 - 0.4, () => _capsule(a, b, 0.75, 0.75, _metal, 1), 'bar'));
          }
        case 'backpack':
          final p = body.p;
          final up = body.up, back = -body.front;
          final hip = p['hip']!;
          final c = hip + up * (d.torso * 0.56) + back * 5.2;
          final e = [up * 5.4, back * 2.2, const V3(0, 0, 4.2)];
          parts.add(DepthPart(zc(c), () {
            _box(c, e, _pack.mid);
            final c2 = c + back * 2.5 - up * 1.6;
            _box(c2, [up * 2.6, back * 0.5, const V3(0, 0, 3.0)], _pack.lo);
          }, 'backpack'));
          for (final s in const [1.0, -1.0]) {
            final top = c + up * 5.0 - back * 1.6 + V3(0, 0, s * 2.7);
            final sh = p['neck']! + up * 0.6 + back * 0.3 + V3(0, 0, s * 3.0);
            final fr = hip + up * (d.torso * 0.48) - back * 3.0 + V3(0, 0, s * 3.4);
            for (final (a, b) in [(top, sh), (sh, fr)]) {
              parts.add(
                  DepthPart((zc(a) + zc(b)) / 2 + 0.3, () => _capsule(a, b, 0.48, 0.48, _strap, nearOf(a)), 'strap'));
            }
          }
      }
    }
  }

  void _frontOverlays() {
    for (final pr in fig.props) {
      if (pr['type'] != 'sofa') continue;
      // El corte solo cubre pies y tobillos: lo que queda bajo el sofá.
      final pts = <Offset>[];
      for (final side in const ['near', 'far']) {
        final a = body.p['${side}Ankle'], t = body.p['${side}Toe'], k = body.p['${side}Knee'];
        if (a == null || t == null || k == null) continue;
        for (final q in [a, t, V3.lerp(a, k, 0.35)]) {
          for (final o in const [
            V3(2.4, 0, 0),
            V3(-2.4, 0, 0),
            V3(0, 2.4, 0),
            V3(0, -2.4, 0),
            V3(0, 0, 2),
            V3(0, 0, -2)
          ]) {
            pts.add(cam.project(q + o).offset);
          }
        }
      }
      if (pts.length < 3) continue;
      canvas.save();
      canvas.clipPath(_poly(convexHull(pts)));
      _sofa(pr, 0.42, cut: true);
      canvas.restore();
      // Punto de contacto: el talón empuja hacia arriba contra el sofá.
      final a = body.p['nearAnkle'], t = body.p['nearToe'];
      if (a == null || t == null) continue;
      final f = (t - a).unit;
      final heel = a - f * 1.2 + V3(-f.y, f.x, 0) * 1.25;
      final c = cam.project(heel);
      canvas.drawCircle(c.offset, 0.55 * c.k, Paint()..color = _contact);
      canvas.drawCircle(
          c.offset,
          1.3 * c.k,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, 0.2 * cam.scale)
            ..color = _contact.withOpacity(0.8));
    }
  }
}
