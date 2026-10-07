"""Ilustraciones de técnica: posturas y dibujo.

Fuente única de las figuras. Genera `assets/tecnica/figuras.json`, que la app
pinta con un CustomPainter (lib/ui/exercise_figure.dart), y sirve también para
el mockup en SVG. Correr tras cambiar una postura:

    python tool/figuras.py

Mundo: unidades arbitrarias, y hacia abajo, suelo en y = 0. Ángulos en grados:
0 = derecha, 90 = abajo, -90 = arriba, 180 = izquierda. Cada extremidad se da
por ángulos o por el punto que debe alcanzar (IK de dos segmentos; `bend`
+1/-1 elige hacia dónde dobla la articulación). "near" es el lado cercano (se
dibuja pleno) y "far" el lejano (atenuado).
"""
import json
import math
import os

T, UA, FA, TH, SH, FT = 18, 10, 9, 14, 14, 5
HEAD_OFF, HEAD_R = 5.5, 3.6


def dirv(a):
    r = math.radians(a)
    return math.cos(r), math.sin(r)


def add(p, v, k=1.0):
    return (p[0] + v[0] * k, p[1] + v[1] * k)


def two_link(root, spec, a, b):
    """(articulación media, extremo) de una extremidad de dos segmentos."""
    if 'angles' in spec:
        a1, a2 = spec['angles']
        j = add(root, dirv(a1), a)
        return j, add(j, dirv(a2), b)
    px, py = spec['reach']
    s = spec.get('bend', 1)
    dx, dy = px - root[0], py - root[1]
    d = math.hypot(dx, dy)
    d = min(max(d, abs(a - b) + 0.01), a + b - 0.001)
    base = math.atan2(dy, dx)
    alpha = math.acos((a * a + d * d - b * b) / (2 * a * d))
    ang = base + s * alpha
    j = (root[0] + a * math.cos(ang), root[1] + a * math.sin(ang))
    ex, ey = px - j[0], py - j[1]
    n = math.hypot(ex, ey) or 1
    return j, (j[0] + ex / n * b, j[1] + ey / n * b)


def solve(frame, view='side'):
    hip = tuple(frame['hip'])
    tlen = 6 if view == 'top' else T
    neck = add(hip, dirv(frame['torso']), tlen)
    head = add(neck, dirv(frame['torso']), HEAD_OFF)
    joints = {'hip': hip, 'neck': neck, 'head': head}
    segs = {}
    for side in ('near', 'far'):
        leg = frame.get(side + 'Leg')
        if leg:
            knee, ankle = two_link(hip, leg, TH, SH)
            joints[side + 'Knee'], joints[side + 'Ankle'] = knee, ankle
            segs[side + 'Thigh'] = (hip, knee)
            segs[side + 'Shin'] = (knee, ankle)
            if leg.get('foot') is not None:
                toe = add(ankle, dirv(leg['foot']), FT)
                joints[side + 'Toe'] = toe
                segs[side + 'Foot'] = (ankle, toe)
        arm = frame.get(side + 'Arm')
        if arm:
            elbow, hand = two_link(neck, arm, UA, FA)
            joints[side + 'Elbow'], joints[side + 'Hand'] = elbow, hand
            segs[side + 'UpperArm'] = (neck, elbow)
            segs[side + 'Forearm'] = (elbow, hand)
    segs['torso'] = (hip, neck)
    return {'joints': joints, 'segs': segs}


# ---------------------------------------------------------------------------
# Posturas. `marks` son las anotaciones: ángulo en una articulación, línea
# guía punteada, texto, cota con medida y punto de apoyo.
# ---------------------------------------------------------------------------

EXERCISES = [
    {
        'name': 'Sentadilla búlgara',
        'muscles': 'Cuádriceps y glúteo de la pierna de adelante',
        'highlight': ['nearThigh', 'glute'],
        'props': [{'type': 'bench', 'x': -34, 'y': -12, 'w': 16, 'h': 12}],
        'frames': [
            {'caption': 'Arriba', 'hip': (0, -27.5), 'torso': -80,
             'nearLeg': {'reach': (2, 0), 'bend': -1, 'foot': 0},
             'farLeg': {'reach': (-22, -12.6), 'bend': -1, 'foot': 178},
             'nearArm': {'reach': (4.5, -27), 'bend': 1}, 'farArm': {'reach': (2, -27.5), 'bend': 1},
             'arrow': ((-8, -34), (-8, -22)),
             'marks': [{'t': 'label', 'at': (-26, 6.8), 'text': 'banco ≈40 cm', 'anchor': 'middle'},
                       {'t': 'label', 'at': (4, 6.8), 'text': 'peso aquí', 'anchor': 'middle'}]},
            {'caption': 'Abajo: muslo paralelo', 'hip': (-8, -15), 'torso': -68, 'ghost': True,
             'nearLeg': {'reach': (2, 0), 'bend': -1, 'foot': 0},
             'farLeg': {'reach': (-24, -12.6), 'bend': -1, 'foot': 178},
             'nearArm': {'reach': (-0.5, -14), 'bend': 1}, 'farArm': {'reach': (-2.5, -14.5), 'bend': 1},
             'marks': [{'t': 'angle', 'at': 'nearKnee', 'a': 'hip', 'b': 'nearAnkle', 'label': '90°'}]},
        ],
    },
    {
        'name': 'Pike push-up',
        'muscles': 'Hombros (deltoides) y tríceps',
        'highlight': ['nearUpperArm', 'farUpperArm'],
        'props': [],
        'frames': [
            {'caption': 'Arriba: V invertida', 'hip': (11.8, -25.4), 'torso': 43,
             'nearLeg': {'reach': (0, 0), 'bend': 1, 'foot': 10},
             'farLeg': {'reach': (-1.5, 0), 'bend': 1, 'foot': 10},
             'nearArm': {'reach': (36, 0), 'bend': 1}, 'farArm': {'reach': (37, 0), 'bend': 1},
             'arrow': ((31, -22), (31, -11)),
             'marks': [{'t': 'label', 'at': 'hip', 'text': 'cadera alta', 'dy': -5, 'anchor': 'middle'}]},
            {'caption': 'Abajo: coronilla al suelo', 'hip': (15, -24.5), 'torso': 56, 'ghost': True,
             'nearLeg': {'reach': (0, 0), 'bend': 1, 'foot': 10},
             'farLeg': {'reach': (-1.5, 0), 'bend': 1, 'foot': 10},
             'nearArm': {'reach': (36, 0), 'bend': 1}, 'farArm': {'reach': (37, 0), 'bend': 1},
             'marks': [{'t': 'dot', 'at': (29.3, 0.2)}]},
            {'caption': 'Evita: cadera baja (sería una flexión)', 'wrong': True, 'hip': (19, -13), 'torso': 12,
             'nearLeg': {'reach': (0, 0), 'bend': 1, 'foot': 10},
             'farLeg': {'reach': (-1.5, 0), 'bend': 1, 'foot': 10},
             'nearArm': {'reach': (36, 0), 'bend': 1}, 'farArm': {'reach': (37, 0), 'bend': 1}},
        ],
    },
    {
        'name': 'Elevación de piernas colgado',
        'textScale': 1.55,
        'muscles': 'Abdomen y flexores de cadera',
        'highlight': ['torso', 'nearThigh'],
        'props': [{'type': 'bar', 'x1': -8, 'x2': 22, 'y': -68}],
        'frames': [
            {'caption': 'Inicio: hombros activos', 'hip': (4, -31), 'torso': -90,
             'nearLeg': {'reach': (4.5, -3), 'bend': -1, 'foot': 70},
             'farLeg': {'reach': (3.5, -3), 'bend': -1, 'foot': 70},
             'nearArm': {'reach': (4, -68), 'bend': 1}, 'farArm': {'reach': (5, -68), 'bend': 1},
             'arrow': ((13, -8), (25, -26))},
            {'caption': 'Arriba sin balanceo, baja lento', 'hip': (6, -32), 'torso': -95, 'ghost': True,
             'nearLeg': {'reach': (34, -34), 'bend': -1, 'foot': -80},
             'farLeg': {'reach': (33, -33.5), 'bend': -1, 'foot': -80},
             'nearArm': {'reach': (4, -68), 'bend': 1}, 'farArm': {'reach': (5, -68), 'bend': 1},
             'marks': [{'t': 'angle', 'at': 'hip', 'a': 'neck', 'b': 'nearKnee', 'label': '90°'}]},
        ],
    },
    {
        'name': 'Hollow body hold',
        'muscles': 'Abdomen (todo el core)',
        'highlight': ['torso'],
        'props': [],
        'frames': [
            {'caption': 'Más fácil: rodillas recogidas', 'hip': (0, -2), 'torso': 190,
             'nearLeg': {'reach': (14, -12), 'bend': -1, 'foot': -20},
             'farLeg': {'reach': (13, -11.5), 'bend': -1, 'foot': -20},
             'nearArm': {'reach': (-35.5, -10.5), 'bend': 1}, 'farArm': {'reach': (-35, -10), 'bend': 1},
             'marks': [{'t': 'dot', 'at': (0, 0.2)}, {'t': 'label', 'at': (0, 6.8), 'text': 'lumbar pegada', 'anchor': 'middle'}]},
            {'caption': 'Completo: brazos y piernas largos', 'hip': (0, -2), 'torso': 190,
             'nearLeg': {'reach': (27.4, -7.8), 'bend': 1, 'foot': -10},
             'farLeg': {'reach': (27, -7.3), 'bend': 1, 'foot': -10},
             'nearArm': {'reach': (-36, -10), 'bend': 1}, 'farArm': {'reach': (-35.5, -9.6), 'bend': 1},
             'marks': [{'t': 'dot', 'at': (0, 0.2)}]},
            {'caption': 'Evita: la lumbar se despega', 'wrong': True, 'hip': (0, -6.5), 'torso': 186,
             'nearLeg': {'reach': (27.4, -3), 'bend': 1, 'foot': -5},
             'farLeg': {'reach': (27, -2.6), 'bend': 1, 'foot': -5},
             'nearArm': {'reach': (-36, -9), 'bend': 1}, 'farArm': {'reach': (-35.5, -8.6), 'bend': 1},
             'marks': [{'t': 'dim', 'from': (0, 0), 'to': (0, -4.2), 'label': 'hueco'}]},
        ],
    },
    {
        # Peldaño 1 de la escalera del dragon flag (§19.10).
        'name': 'Encogimiento inverso',
        'muscles': 'Abdomen bajo, control de la pelvis',
        'highlight': ['torso'],
        'props': [],
        'frames': [
            {'caption': 'Inicio: rodillas sobre la cadera', 'hip': (0, -2), 'torso': 181,
             'nearLeg': {'reach': (13.5, -16), 'bend': -1, 'foot': 0},
             'farLeg': {'reach': (13, -15.5), 'bend': -1, 'foot': 0},
             'nearArm': {'reach': (1.5, -1), 'bend': -1}, 'farArm': {'reach': (1, -1.2), 'bend': -1},
             'arrow': ((19, -20), (10, -28)),
             'marks': [{'t': 'angle', 'at': 'nearKnee', 'a': 'hip', 'b': 'nearAnkle', 'label': '90°'}]},
            {'caption': 'Arriba: la cadera despega; baja en 3 s', 'hip': (1.5, -5.5), 'torso': 170, 'ghost': True,
             'nearLeg': {'reach': (3, -29), 'bend': -1, 'foot': -20},
             'farLeg': {'reach': (2.5, -28.5), 'bend': -1, 'foot': -20},
             'nearArm': {'reach': (1.5, -1), 'bend': -1}, 'farArm': {'reach': (1, -1.2), 'bend': -1},
             'marks': [{'t': 'dim', 'from': (7, 0), 'to': (7, -3.2), 'label': 'despega'}]},
            {'caption': 'Evita: arquear la lumbar al bajar', 'wrong': True, 'hip': (0, -6.5), 'torso': 186,
             'nearLeg': {'reach': (27.4, -3), 'bend': 1, 'foot': -5},
             'farLeg': {'reach': (27, -2.6), 'bend': 1, 'foot': -5},
             'nearArm': {'reach': (1.5, -1), 'bend': -1}, 'farArm': {'reach': (1, -1.2), 'bend': -1},
             'marks': [{'t': 'dim', 'from': (0, 0), 'to': (0, -4.2), 'label': 'hueco'}]},
        ],
    },
    {
        # Peldaño 1 de la escalera del V-up (§19.10).
        'name': 'Tuck-up',
        'muscles': 'Abdomen completo, flexores de cadera',
        'highlight': ['torso', 'nearThigh'],
        'props': [],
        'frames': [
            {'caption': 'Inicio: posición hollow', 'hip': (0, -2), 'torso': 190,
             'nearLeg': {'reach': (27.4, -7.8), 'bend': 1, 'foot': -10},
             'farLeg': {'reach': (27, -7.3), 'bend': 1, 'foot': -10},
             'nearArm': {'reach': (-36, -10), 'bend': 1}, 'farArm': {'reach': (-35.5, -9.6), 'bend': 1},
             'arrow': ((-22, -16), (-12, -26)),
             'marks': [{'t': 'dot', 'at': (0, 0.2)}, {'t': 'label', 'at': (0, 6.8), 'text': 'lumbar pegada', 'anchor': 'middle'}]},
            {'caption': 'Arriba: pecho y rodillas juntos, sobre los glúteos', 'hip': (0, -3), 'torso': -128, 'ghost': True,
             'nearLeg': {'reach': (16, -12), 'bend': -1, 'foot': 10},
             'farLeg': {'reach': (15.5, -11.5), 'bend': -1, 'foot': 10},
             'nearArm': {'reach': (11, -13.5), 'bend': 1}, 'farArm': {'reach': (10.5, -13), 'bend': 1},
             'marks': [{'t': 'dot', 'at': (0, 0.2)}]},
            {'caption': 'Evita: arquear la espalda al volver', 'wrong': True, 'hip': (0, -6.5), 'torso': 186,
             'nearLeg': {'reach': (27.4, -3), 'bend': 1, 'foot': -5},
             'farLeg': {'reach': (27, -2.6), 'bend': 1, 'foot': -5},
             'nearArm': {'reach': (-36, -9), 'bend': 1}, 'farArm': {'reach': (-35.5, -8.6), 'bend': 1},
             'marks': [{'t': 'dim', 'from': (0, 0), 'to': (0, -4.2), 'label': 'hueco'}]},
        ],
    },
    {
        'name': 'Plancha lateral',
        'muscles': 'Oblicuos y core lateral',
        'highlight': ['torso'],
        'props': [],
        'frames': [
            {'caption': 'Bien: línea recta, codo bajo el hombro', 'hip': (27.3, -7.4), 'torso': -13.2,
             'nearLeg': {'reach': (0, -1.5), 'bend': 1}, 'farLeg': {'reach': (0.5, -2.3), 'bend': 1},
             'nearArm': {'reach': (53.8, -1.5), 'bend': 1}, 'farArm': {'reach': (27, -11), 'bend': -1},
             'marks': [{'t': 'dash', 'from': 'nearAnkle', 'to': 'head', 'extend': 3}]},
            {'caption': 'Evita: cadera caída', 'wrong': True, 'hip': (27, -3), 'torso': -25.5,
             'nearLeg': {'reach': (0, -1.5), 'bend': 1}, 'farLeg': {'reach': (0.5, -2.3), 'bend': 1},
             'nearArm': {'reach': (52.3, -1.5), 'bend': 1}, 'farArm': {'reach': (27, -6.5), 'bend': -1},
             'marks': [{'t': 'dash', 'from': 'nearAnkle', 'to': 'head', 'extend': 3}]},
        ],
    },
    {
        'name': 'Estiramiento de flexor de cadera (caballero)',
        'muscles': 'Flexor de cadera de la pierna de atrás',
        'highlight': ['nearThigh', 'glute'],
        'props': [],
        'frames': [
            {'caption': 'Inicio: rodilla atrás en el suelo', 'hip': (0, -15.5), 'torso': -90,
             'nearLeg': {'reach': (-15, -1.5), 'bend': -1, 'foot': 180},
             'farLeg': {'reach': (16, 0), 'bend': -1, 'foot': 0},
             'nearArm': {'reach': (2, -17.5), 'bend': 1}, 'farArm': {'reach': (-1, -17.5), 'bend': 1},
             'arrow': ((2, -8.5), (10, -8.5))},
            {'caption': 'Cadera al frente, glúteo apretado', 'hip': (5, -15), 'torso': -92, 'ghost': True,
             'nearLeg': {'reach': (-12, -1.5), 'bend': -1, 'foot': 180},
             'farLeg': {'reach': (16, 0), 'bend': -1, 'foot': 0},
             'nearArm': {'reach': (6.5, -17), 'bend': 1}, 'farArm': {'reach': (3.5, -17), 'bend': 1},
             'marks': [{'t': 'dash', 'from': 'hip', 'to': 'neck', 'extend': 4},
                       {'t': 'label', 'at': 'neck', 'text': 'espalda sin arquear', 'dx': 3, 'dy': -8, 'anchor': 'start'}]},
        ],
    },
    {
        'name': '90/90 de cadera',
        'muscles': 'Rotadores y glúteos de ambas caderas',
        'view': 'top',
        'highlight': ['glute'],
        'props': [],
        'frames': [
            {'caption': 'Visto desde arriba: dos ángulos de 90°', 'hip': (0, 0), 'torso': -90,
             'nearLeg': {'angles': (-30, -120)}, 'farLeg': {'angles': (160, 70)},
             'marks': [{'t': 'angle', 'at': 'nearKnee', 'a': 'hip', 'b': 'nearAnkle', 'label': '90°'},
                       {'t': 'angle', 'at': 'farKnee', 'a': 'hip', 'b': 'farAnkle', 'label': '90°'},
                       {'t': 'label', 'at': (0, -27), 'text': '▲ frente', 'anchor': 'middle'}]},
            {'caption': 'Gira las rodillas al otro lado, lento', 'hip': (0, 0), 'torso': -90,
             'nearLeg': {'angles': (20, 110)}, 'farLeg': {'angles': (210, -60)},
             'marks': [{'t': 'label', 'at': (0, -27), 'text': '▲ frente', 'anchor': 'middle'}]},
        ],
    },
    {
        'name': 'Rotación torácica en cuatro apoyos',
        'muscles': 'Espalda alta y oblicuos',
        'highlight': ['torso'],
        'props': [],
        'frames': [
            {'caption': 'Codo hacia el suelo', 'hip': (0, -15.5), 'torso': -10,
             'nearLeg': {'reach': (-14, -1.5), 'bend': -1, 'foot': 180},
             'farLeg': {'reach': (-13.5, -1.5), 'bend': -1, 'foot': 180},
             'farArm': {'reach': (18, 0), 'bend': 1}, 'nearArm': {'angles': (90, -60)},
             'arrow': ((12, -23), (12, -37))},
            {'caption': 'Codo al techo, la cadera no se mueve', 'hip': (0, -15.5), 'torso': -10, 'ghost': True,
             'nearLeg': {'reach': (-14, -1.5), 'bend': -1, 'foot': 180},
             'farLeg': {'reach': (-13.5, -1.5), 'bend': -1, 'foot': 180},
             'farArm': {'reach': (18, 0), 'bend': 1}, 'nearArm': {'angles': (-90, 60)},
             'marks': [{'t': 'dot', 'at': 'hip'}, {'t': 'label', 'at': 'hip', 'text': 'quieta', 'dy': -5, 'anchor': 'middle'}]},
        ],
    },
    {
        'name': 'Movilidad de tobillo contra la pared',
        'muscles': 'Pantorrilla (sóleo) y tobillo de adelante',
        'highlight': ['nearShin'],
        'props': [{'type': 'wall', 'x': 24.5, 'y1': -45}],
        'frames': [
            {'caption': 'Pie a 10 cm de la pared', 'hip': (4, -15.5), 'torso': -90,
             'nearLeg': {'reach': (16, 0), 'bend': -1, 'foot': 0},
             'farLeg': {'reach': (-11, -1.5), 'bend': -1, 'foot': 180},
             'nearArm': {'reach': (23, -27), 'bend': 1}, 'farArm': {'reach': (23, -28), 'bend': 1},
             'arrow': ((18, -21), (23, -21)),
             'marks': [{'t': 'dim', 'from': (21, 3), 'to': (24.5, 3), 'label': '10 cm'}]},
            {'caption': 'Rodilla a la pared, talón abajo', 'hip': (10, -15.5), 'torso': -90, 'ghost': True,
             'nearLeg': {'reach': (16, 0), 'bend': -1, 'foot': 0},
             'farLeg': {'reach': (-5, -1.5), 'bend': -1, 'foot': 180},
             'nearArm': {'reach': (23, -26), 'bend': 1}, 'farArm': {'reach': (23, -27), 'bend': 1},
             'marks': [{'t': 'dot', 'at': (16, 0.2)}, {'t': 'label', 'at': (15, 6.8), 'text': 'talón abajo', 'anchor': 'middle'}]},
        ],
    },
    {
        'name': 'Colgado pasivo',
        'textScale': 1.55,
        'muscles': 'Hombros y dorsales se estiran',
        'highlight': ['nearUpperArm', 'farUpperArm'],
        'props': [{'type': 'bar', 'x1': -8, 'x2': 18, 'y': -68}],
        'frames': [
            {'caption': 'Suelta hombros y espalda, respira lento', 'hip': (4, -31), 'torso': -90,
             'nearLeg': {'reach': (4.5, -1.5), 'bend': -1, 'foot': 70},
             'farLeg': {'reach': (3.5, -1.5), 'bend': -1, 'foot': 70},
             'nearArm': {'reach': (3.5, -68), 'bend': 1}, 'farArm': {'reach': (5, -68), 'bend': 1},
             'marks': [{'t': 'label', 'at': (9, -61), 'text': 'agarre: ancho', 'anchor': 'start'},
                       {'t': 'label', 'at': (9, -55), 'text': 'de hombros', 'anchor': 'start'},
                       {'t': 'label', 'at': (9, -4), 'text': 'pies pueden', 'anchor': 'start'},
                       {'t': 'label', 'at': (9, 2), 'text': 'rozar el suelo', 'anchor': 'start'}]},
        ],
    },
    {
        'name': 'Dominadas',
        'textScale': 1.55,
        'muscles': 'Dorsales, bíceps y espalda alta',
        'highlight': ['nearUpperArm', 'farUpperArm', 'torso'],
        'props': [{'type': 'bar', 'x1': -8, 'x2': 18, 'y': -68}],
        'frames': [
            {'caption': 'Abajo: brazos extendidos', 'hip': (4, -31), 'torso': -90,
             'nearLeg': {'reach': (6, -4), 'bend': 1, 'foot': 70},
             'farLeg': {'reach': (5, -4), 'bend': 1, 'foot': 70},
             'nearArm': {'reach': (4, -68), 'bend': 1}, 'farArm': {'reach': (5, -68), 'bend': 1},
             'arrow': ((14, -40), (14, -56))},
            {'caption': 'Arriba: barbilla sobre la barra', 'hip': (4, -49), 'torso': -90, 'ghost': True,
             'nearLeg': {'reach': (6, -22), 'bend': 1, 'foot': 70},
             'farLeg': {'reach': (5, -22), 'bend': 1, 'foot': 70},
             'nearArm': {'reach': (6.5, -68), 'bend': 1}, 'farArm': {'reach': (7.5, -68), 'bend': 1},
             'marks': [{'t': 'label', 'at': (12, -73.5), 'text': 'barbilla arriba', 'anchor': 'start'}]},
        ],
    },
    {
        'name': 'Flexiones',
        'muscles': 'Pecho, tríceps y hombros',
        'highlight': ['nearUpperArm', 'farUpperArm'],
        'props': [],
        'frames': [
            {'caption': 'Arriba: manos bajo los hombros', 'hip': (25.6, -11.3), 'torso': -23.7,
             'nearLeg': {'reach': (0, -1), 'bend': 1, 'foot': 60},
             'farLeg': {'reach': (-0.5, -1), 'bend': 1, 'foot': 60},
             'nearArm': {'reach': (42.1, 0), 'bend': 1}, 'farArm': {'reach': (43, 0), 'bend': 1},
             'arrow': ((52, -20), (52, -9)),
             'marks': [{'t': 'dash', 'from': 'nearAnkle', 'to': 'head', 'extend': 3}]},
            {'caption': 'Abajo: pecho casi al suelo, en bloque', 'hip': (27.9, -3.4), 'torso': -5.6, 'ghost': True,
             'nearLeg': {'reach': (0, -1), 'bend': 1, 'foot': 60},
             'farLeg': {'reach': (-0.5, -1), 'bend': 1, 'foot': 60},
             'nearArm': {'reach': (43, 0), 'bend': 1}, 'farArm': {'reach': (43.8, 0), 'bend': 1}},
            {'caption': 'Evita: cadera hundida', 'wrong': True, 'hip': (25, -4.5), 'torso': -30,
             'nearLeg': {'reach': (0, -1), 'bend': 1, 'foot': 60},
             'farLeg': {'reach': (-0.5, -1), 'bend': 1, 'foot': 60},
             'nearArm': {'reach': (41.5, 0), 'bend': 1}, 'farArm': {'reach': (42.4, 0), 'bend': 1},
             'marks': [{'t': 'dash', 'from': 'nearAnkle', 'to': 'head', 'extend': 3}]},
        ],
    },
    {
        'name': 'Sentadillas',
        'muscles': 'Cuádriceps y glúteos',
        'highlight': ['nearThigh', 'glute'],
        'props': [],
        'frames': [
            {'caption': 'Arriba', 'hip': (0, -27.8), 'torso': -88,
             'nearLeg': {'reach': (2, 0), 'bend': -1, 'foot': 0},
             'farLeg': {'reach': (3, 0), 'bend': -1, 'foot': 0},
             'nearArm': {'reach': (19.5, -46), 'bend': 1}, 'farArm': {'reach': (18.5, -46.5), 'bend': 1},
             'arrow': ((-9, -33), (-9, -20))},
            {'caption': 'Abajo: cadera bajo la rodilla', 'hip': (-8, -11), 'torso': -60, 'ghost': True,
             'nearLeg': {'reach': (2, 0), 'bend': -1, 'foot': 0},
             'farLeg': {'reach': (3, 0), 'bend': -1, 'foot': 0},
             'nearArm': {'reach': (19.9, -28), 'bend': 1}, 'farArm': {'reach': (18.9, -28.5), 'bend': 1},
             'marks': [{'t': 'dash', 'from': (-14, -13.5), 'to': (10, -13.5)},
                       {'t': 'label', 'at': (-4, 6.8), 'text': 'talones apoyados', 'anchor': 'middle'}]},
        ],
    },
]


# ---------------------------------------------------------------------------
# Dibujo: cada cuadro se convierte en primitivas (líneas, círculos, elipses,
# arcos, polígonos y texto) con colores por rol. La app y el SVG pintan las
# mismas primitivas; los roles se traducen a la paleta del tema.
# ---------------------------------------------------------------------------

TEXT_SIZE = 3.3


def resolve(frame_solved, p, dx=0.0, dy=0.0):
    pt = frame_solved['joints'][p] if isinstance(p, str) else p
    return (pt[0] + dx, pt[1] + dy)


def text_extent(text, at, anchor, ts=TEXT_SIZE):
    w = len(text) * ts * 0.52
    x0 = at[0] - (w / 2 if anchor == 'middle' else (w if anchor == 'end' else 0))
    return (x0, at[1] - ts), (x0 + w, at[1] + 1)


def raw_bounds(ex):
    view = ex.get('view', 'side')
    ts = TEXT_SIZE * ex.get('textScale', 1)
    pts = []
    for f in ex['frames']:
        s = solve(f, view)
        for a, b in s['segs'].values():
            pts += [a, b]
        h = s['joints']['head']
        pts += [(h[0] - HEAD_R, h[1] - HEAD_R), (h[0] + HEAD_R, h[1] + HEAD_R)]
        if 'arrow' in f:
            pts += list(f['arrow'])
        for m in f.get('marks', []):
            if m['t'] == 'label':
                at = resolve(s, m['at'], m.get('dx', 0), m.get('dy', 0))
                pts += list(text_extent(m['text'], at, m.get('anchor', 'start'), ts))
            elif m['t'] in ('dash', 'dim'):
                pts += [resolve(s, m['from']), resolve(s, m['to'])]
                if m['t'] == 'dim':
                    a, b = resolve(s, m['from']), resolve(s, m['to'])
                    if abs(b[0] - a[0]) >= abs(b[1] - a[1]):
                        pts += list(text_extent(m['label'], ((a[0] + b[0]) / 2, max(a[1], b[1]) + 4.5), 'middle', ts))
                    else:
                        pts += list(text_extent(m['label'], (a[0] - 2.4, (a[1] + b[1]) / 2), 'end', ts))
    for p in ex['props']:
        if p['type'] == 'bench':
            pts += [(p['x'], p['y']), (p['x'] + p['w'], p['y'] + p['h'])]
        elif p['type'] == 'bar':
            pts += [(p['x1'] - 1, p['y'] - 9), (p['x2'] + 1, p['y'] + 1)]
        elif p['type'] == 'wall':
            pts += [(p['x'] + 4, p['y1'])]
    if view == 'side':
        pts.append((pts[0][0], 3.2))
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    pad = 4
    return [min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad]


def L(a, b, role, w, op=1.0, dash=False):
    return {'k': 'line', 'a': a, 'b': b, 'role': role, 'w': w, 'op': op, 'dash': dash}


def muscle(a, b, ry, op):
    cx, cy = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    ln = math.hypot(b[0] - a[0], b[1] - a[1])
    rot = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
    return [
        {'k': 'ellipse', 'c': (cx, cy), 'rx': ln * 0.44 + 1.1, 'ry': ry + 1.1, 'rot': rot, 'role': 'muscle', 'op': 0.22 * op},
        {'k': 'ellipse', 'c': (cx, cy), 'rx': ln * 0.44, 'ry': ry, 'rot': rot, 'role': 'muscle', 'op': 0.95 * op},
    ]


MUSCLE_RY = {'Thigh': 1.9, 'Shin': 1.5, 'UpperArm': 1.45, 'Forearm': 1.2, 'torso': 2.6, 'Foot': 1.0}
ORDER = ['farThigh', 'farShin', 'farFoot', 'farUpperArm', 'farForearm', 'torso',
         'nearThigh', 'nearShin', 'nearFoot', 'nearUpperArm', 'nearForearm']


def figure_items(s, hl, view, role='ink', faded=1.0):
    """El cuerpo: segmentos, músculos resaltados, manos y cabeza."""
    items = []
    segs, j = s['segs'], s['joints']
    far_op = 1.0 if view == 'top' else 0.42
    for name in ORDER:
        if name not in segs or (view == 'top' and name == 'torso'):
            continue
        a, b = segs[name]
        op = (far_op if name.startswith('far') else 1.0) * faded
        items.append(L(a, b, role, 2.3, op))
        if name in hl and role == 'ink':
            key = 'torso' if name == 'torso' else name.replace('near', '').replace('far', '')
            items += muscle(a, b, MUSCLE_RY[key], op)
    for side in ('far', 'near'):
        if side + 'Hand' in j:
            op = (far_op if side == 'far' else 1.0) * faded
            items.append({'k': 'circle', 'c': j[side + 'Hand'], 'r': 1.25, 'role': role, 'op': op, 'fill': True})
    if view == 'top':
        hip = j['hip']
        items.append({'k': 'ellipse', 'c': hip, 'rx': 9, 'ry': 4.6, 'rot': 0, 'role': 'bg', 'op': 1.0,
                      'stroke': role, 'w': 2.0, 'sop': faded})
        if 'glute' in hl and role == 'ink':
            for gx in (-4.6, 4.6):
                items.append({'k': 'circle', 'c': (hip[0] + gx, hip[1] + 1.2), 'r': 2.3, 'role': 'muscle', 'op': 1.0, 'fill': True})
        items.append({'k': 'circle', 'c': hip, 'r': HEAD_R, 'role': 'bg', 'op': 1.0, 'fill': True, 'stroke': role, 'w': 1.8, 'sop': faded})
        return items
    if 'glute' in hl and role == 'ink':
        hip, neck = j['hip'], j['neck']
        rot = math.degrees(math.atan2(neck[1] - hip[1], neck[0] - hip[0]))
        items.append({'k': 'ellipse', 'c': hip, 'rx': 3.2, 'ry': 2.6, 'rot': rot, 'role': 'muscle', 'op': 0.95})
    items.append({'k': 'circle', 'c': j['head'], 'r': HEAD_R, 'role': 'bg', 'op': 1.0, 'fill': role != 'ghost',
                  'stroke': role, 'w': 1.8, 'sop': faded})
    return items


def prop_items(p, box):
    if p['type'] == 'bench':
        x, y, w, h = p['x'], p['y'], p['w'], p['h']
        return [
            {'k': 'rect', 'x': x, 'y': y, 'w': w, 'h': 2.4, 'role': 'propFill', 'stroke': 'prop', 'w2': 0.7},
            L((x + 2, y + 2.4), (x + 2, 0), 'prop', 1.2),
            L((x + w - 2, y + 2.4), (x + w - 2, 0), 'prop', 1.2),
            L((x + 2, y + 7), (x + w - 2, y + 7), 'prop', 0.6),
        ]
    if p['type'] == 'bar':
        y = p['y']
        return [L((p['x1'], y - 8), (p['x1'], y + 1), 'prop', 1.1),
                L((p['x2'], y - 8), (p['x2'], y + 1), 'prop', 1.1),
                L((p['x1'], y), (p['x2'], y), 'prop', 1.9)]
    if p['type'] == 'wall':
        x, y1 = p['x'], p['y1']
        items = [{'k': 'rect', 'x': x, 'y': y1, 'w': 3.2, 'h': -y1 + 0.9, 'role': 'propFill', 'stroke': 'prop', 'w2': 0.6}]
        yy = y1 + 3
        while yy < -1:
            items.append(L((x + 0.4, yy + 2.2), (x + 2.8, yy), 'prop', 0.45))
            yy += 3.5
        return items
    return []


def arrow_items(a, b, role='arrow'):
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    l1 = (b[0] - 3 * math.cos(ang - 0.45), b[1] - 3 * math.sin(ang - 0.45))
    l2 = (b[0] - 3 * math.cos(ang + 0.45), b[1] - 3 * math.sin(ang + 0.45))
    back = (b[0] - 2.2 * math.cos(ang), b[1] - 2.2 * math.sin(ang))
    return [L(a, back, role, 1.1), {'k': 'poly', 'pts': [b, l1, l2], 'role': role}]


def mark_items(m, s, ts=TEXT_SIZE):
    t = m['t']
    if t == 'dash':
        a, b = resolve(s, m['from']), resolve(s, m['to'])
        e = m.get('extend', 0)
        if e:
            ln = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
            ux, uy = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
            a, b = (a[0] - ux * e, a[1] - uy * e), (b[0] + ux * e, b[1] + uy * e)
        return [L(a, b, 'guide', 0.7, 0.9, dash=True)]
    if t == 'label':
        at = resolve(s, m['at'], m.get('dx', 0), m.get('dy', 0))
        return [{'k': 'text', 'p': at, 't': m['text'], 'size': ts, 'role': 'label', 'anchor': m.get('anchor', 'start')}]
    if t == 'dot':
        return [{'k': 'circle', 'c': resolve(s, m['at']), 'r': 1.3, 'role': 'arrow', 'op': 1.0, 'fill': True}]
    if t == 'angle':
        c, a, b = resolve(s, m['at']), resolve(s, m['a']), resolve(s, m['b'])
        a0 = math.degrees(math.atan2(a[1] - c[1], a[0] - c[0]))
        a1 = math.degrees(math.atan2(b[1] - c[1], b[0] - c[0]))
        sweep = (a1 - a0 + 540) % 360 - 180
        mid = math.radians(a0 + sweep / 2)
        r = 4.2
        k = ts / TEXT_SIZE
        lp = (c[0] + 8.6 * k * math.cos(mid), c[1] + 8.6 * k * math.sin(mid) + 1.2 * k)
        return [{'k': 'arc', 'c': c, 'r': r * k, 'a0': a0, 'sweep': sweep, 'role': 'guide', 'w': 0.8 * k},
                {'k': 'text', 'p': lp, 't': m['label'], 'size': ts, 'role': 'guide', 'anchor': 'middle'}]
    if t == 'dim':
        a, b = resolve(s, m['from']), resolve(s, m['to'])
        horizontal = abs(b[0] - a[0]) >= abs(b[1] - a[1])
        items = [L(a, b, 'guide', 0.7)]
        if horizontal:
            items += [L((a[0], a[1] - 1.4), (a[0], a[1] + 1.4), 'guide', 0.7), L((b[0], b[1] - 1.4), (b[0], b[1] + 1.4), 'guide', 0.7)]
            mid = ((a[0] + b[0]) / 2, max(a[1], b[1]) + 4.5)
            anchor = 'middle'
        else:
            items += [L((a[0] - 1.4, a[1]), (a[0] + 1.4, a[1]), 'guide', 0.7), L((b[0] - 1.4, b[1]), (b[0] + 1.4, b[1]), 'guide', 0.7)]
            mid = (a[0] - 2.4, (a[1] + b[1]) / 2 + 1.2)
            anchor = 'end'
        items.append({'k': 'text', 'p': mid, 't': m['label'], 'size': ts, 'role': 'guide', 'anchor': anchor})
        return items
    raise ValueError(t)


def frame_items(ex, i, box):
    f = ex['frames'][i]
    view = ex.get('view', 'side')
    s = solve(f, view)
    items = []
    x0, y0, x1, y1 = box
    if view == 'side':
        items.append(L((x0 + 2, 0.9), (x1 - 2, 0.9), 'floor', 0.8))
        x = x0 + 4
        while x < x1 - 3:
            items.append(L((x, 1.0), (x - 1.6, 2.8), 'floor', 0.45))
            x += 3.2
    for p in ex['props']:
        items += prop_items(p, box)
    if f.get('ghost') and i > 0:
        prev = solve(ex['frames'][i - 1], view)
        items += figure_items(prev, [], view, role='ghost', faded=1.0)
    hl = set(f.get('highlight', ex['highlight']))
    items += figure_items(s, hl, view)
    if 'arrow' in f:
        items += arrow_items(*f['arrow'])
    for m in f.get('marks', []):
        items += mark_items(m, s, TEXT_SIZE * ex.get('textScale', 1))
    if f.get('wrong'):
        cx, cy = x1 - 5, y0 + 5
        items += [{'k': 'circle', 'c': (cx, cy), 'r': 3.4, 'role': 'wrong', 'op': 1.0, 'fill': True},
                  L((cx - 1.5, cy - 1.5), (cx + 1.5, cy + 1.5), 'bg', 1.1),
                  L((cx - 1.5, cy + 1.5), (cx + 1.5, cy - 1.5), 'bg', 1.1)]
    return items


def build(ex):
    box = raw_bounds(ex)
    return {
        'name': ex['name'],
        'muscles': ex['muscles'],
        'box': [round(v, 2) for v in box],
        'frames': [{'caption': f['caption'], 'wrong': bool(f.get('wrong')), 'items': _round(frame_items(ex, i, box))}
                   for i, f in enumerate(ex['frames'])],
    }


def _round(v):
    if isinstance(v, float):
        return round(v, 2)
    if isinstance(v, (list, tuple)):
        return [_round(x) for x in v]
    if isinstance(v, dict):
        return {k: _round(x) for k, x in v.items()}
    return v


# ---------------------------------------------------------------------------
# SVG (para el mockup y para revisar a ojo).
# ---------------------------------------------------------------------------

PALETTE = {'ink': '#FFF6EC', 'ghost': '#FFF6EC', 'muscle': '#F08A34', 'prop': '#7A6150', 'propFill': '#241A13',
           'floor': '#4A3526', 'arrow': '#3DD6C6', 'guide': '#FFC271', 'label': '#C9B8A8', 'wrong': '#FF6B5B',
           'bg': '#150F0B'}
ROLE_OP = {'ghost': 0.16}


def _f(v):
    return f'{v:.2f}'.rstrip('0').rstrip('.')


def to_svg(fig, frame, w, h):
    x0, y0, x1, y1 = fig['box']
    out = [f'<svg viewBox="{_f(x0)} {_f(y0)} {_f(x1 - x0)} {_f(y1 - y0)}" width="{w}" height="{h}" '
           f'xmlns="http://www.w3.org/2000/svg" aria-hidden="true" style="display: block">']
    for it in frame['items']:
        role = it['role']
        col = PALETTE[role]
        op = it.get('op', 1.0) * ROLE_OP.get(role, 1.0)
        k = it['k']
        if k == 'line':
            dash = ' stroke-dasharray="1.6 1.3"' if it['dash'] else ''
            out.append(f'<line x1="{_f(it["a"][0])}" y1="{_f(it["a"][1])}" x2="{_f(it["b"][0])}" y2="{_f(it["b"][1])}" '
                       f'stroke="{col}" stroke-width="{it["w"]}" stroke-linecap="round" stroke-opacity="{_f(op)}"{dash}></line>')
        elif k in ('circle', 'ellipse'):
            fill = col if (k == 'ellipse' or it.get('fill')) else 'none'
            stroke = ''
            if 'stroke' in it:
                sop = it.get('sop', 1.0) * ROLE_OP.get(it['stroke'], 1.0)
                stroke = f' stroke="{PALETTE[it["stroke"]]}" stroke-width="{it["w"]}" stroke-opacity="{_f(sop)}"'
            if k == 'circle':
                out.append(f'<circle cx="{_f(it["c"][0])}" cy="{_f(it["c"][1])}" r="{it["r"]}" fill="{fill}" '
                           f'fill-opacity="{_f(op)}"{stroke}></circle>')
            else:
                out.append(f'<ellipse cx="0" cy="0" rx="{_f(it["rx"])}" ry="{_f(it["ry"])}" fill="{fill}" fill-opacity="{_f(op)}"{stroke} '
                           f'transform="translate({_f(it["c"][0])} {_f(it["c"][1])}) rotate({_f(it["rot"])})"></ellipse>')
        elif k == 'rect':
            out.append(f'<rect x="{_f(it["x"])}" y="{_f(it["y"])}" width="{_f(it["w"])}" height="{_f(it["h"])}" rx="0.8" '
                       f'fill="{col}" stroke="{PALETTE[it["stroke"]]}" stroke-width="{it["w2"]}"></rect>')
        elif k == 'poly':
            pts = ' '.join(f'{_f(p[0])},{_f(p[1])}' for p in it['pts'])
            out.append(f'<polygon points="{pts}" fill="{col}"></polygon>')
        elif k == 'arc':
            c, r = it['c'], it['r']
            a0, sw = math.radians(it['a0']), math.radians(it['sweep'])
            p0 = (c[0] + r * math.cos(a0), c[1] + r * math.sin(a0))
            p1 = (c[0] + r * math.cos(a0 + sw), c[1] + r * math.sin(a0 + sw))
            out.append(f'<path d="M {_f(p0[0])} {_f(p0[1])} A {r} {r} 0 0 {1 if sw > 0 else 0} {_f(p1[0])} {_f(p1[1])}" '
                       f'fill="none" stroke="{col}" stroke-width="{it["w"]}"></path>')
        elif k == 'text':
            anchor = {'start': 'start', 'middle': 'middle', 'end': 'end'}[it['anchor']]
            t = it['t'].replace('&', '&amp;').replace('<', '&lt;')
            out.append(f'<text x="{_f(it["p"][0])}" y="{_f(it["p"][1])}" font-size="{it["size"]}" fill="{col}" '
                       f'text-anchor="{anchor}" font-family="Figtree, system-ui, sans-serif" font-weight="600">{t}</text>')
    out.append('</svg>')
    return ''.join(out)


def all_figures():
    return [build(ex) for ex in EXERCISES]


if __name__ == '__main__':
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    target = os.path.join(root, 'assets', 'tecnica', 'figuras.json')
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, 'w', encoding='utf-8') as fh:
        json.dump({'version': 1, 'figures': all_figures()}, fh, ensure_ascii=False, separators=(',', ':'))
    print(f'{len(EXERCISES)} figuras → {os.path.relpath(target, root)}')
