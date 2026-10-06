"""Figuras 3D de técnica: posturas clave para el maniquí de la app.

Reutiliza la cinemática de `tool/figuras.py` (mismos largos de segmento y la
misma IK de dos segmentos) y exporta, en vez de primitivas ya dibujadas, la
postura de cada momento clave: cadera, ángulo del torso y, por extremidad,
los dos ángulos resueltos, el punto de apoyo (si lo hay) y la orientación del
pie o la mano. La app (lib/ui/exercise_figure_3d.dart) la sube a 3D, la
interpola y la pinta con luz. Correr tras cambiar una postura:

    python tool/figuras3d.py

Mundo igual que figuras.py: y hacia abajo, suelo en y = 0, ángulos en grados
(0 = derecha, 90 = abajo). El torso "mira" hacia (-u.y, u.x), con u el
vector cadera -> cuello: de pie mirando a +x.

Escala: el cuerpo mide ~55 unidades, así que 1 unidad ≈ 3,2 cm.
"""
import json
import math
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import figuras as fg  # noqa: E402

# Altura del centro de la mano o el tobillo cuando apoya: el volumen (mitón,
# zapato) queda sobre el suelo y no lo atraviesa.
HAND_ON_FLOOR = -0.75

EXERCISES = [
    {
        'name': 'Pino pecho a la pared',
        'muscles': 'Hombros (deltoides) y tríceps; el core sostiene la línea',
        # Deltoides = la tapa del hombro; tríceps = la cara de atrás del brazo.
        'regions': [{'part': 'shoulder'},
                    {'part': 'upperArm', 'face': 'extensor', 'from': 0.12, 'to': 0.92, 'width': 75}],
        'props': [{'type': 'wall', 'x': 0, 'thick': 3, 'top': -80, 'depth': 24}],
        # Un poco desde atrás: se ve la pared de frente y que la espalda (y la
        # nuca) dan a la sala, o sea que el pecho mira a la pared.
        'view': {'yaw': 15},
        'gripZ': 5.0,
        # El pliegue del codo mira a +x en toda la entrada (de plancha a pino).
        'flex': {'nearArm': -1, 'farArm': -1},
        'frames': [
            {'caption': 'Inicio: plancha con los pies en la base de la pared',
             'hip': (28.83, -14.15), 'torso': -18, 'gaze': 25,
             'nearLeg': {'angles': (162, 162), 'foot': 100},
             'farLeg': {'angles': (162, 162), 'foot': 100},
             'nearArm': {'reach': (45.95, HAND_ON_FLOOR), 'bend': 1, 'hand': 0},
             'farArm': {'reach': (45.95, HAND_ON_FLOOR), 'bend': 1, 'hand': 0}},
            {'caption': 'Medio: pies arriba en la pared, cuerpo en L',
             'hip': (29.3, -37.7), 'torso': 90, 'gaze': -15,
             'nearLeg': {'angles': (180, 180), 'foot': 90},
             'farLeg': {'angles': (180, 180), 'foot': 90},
             'nearArm': {'reach': (29.3, HAND_ON_FLOOR), 'bend': 1, 'hand': 0},
             'farArm': {'reach': (29.3, HAND_ON_FLOOR), 'bend': 1, 'hand': 0}},
            {'caption': 'Final: pecho a la pared, manos a 10–20 cm',
             'hip': (3.65, -37.65), 'torso': 85.7, 'gaze': -10,
             'nearLeg': {'angles': (-94.2, -94.2), 'foot': -94},
             'farLeg': {'angles': (-94.2, -94.2), 'foot': -94},
             'nearArm': {'reach': (5.0, HAND_ON_FLOOR), 'bend': 1, 'hand': 0},
             'farArm': {'reach': (5.0, HAND_ON_FLOOR), 'bend': 1, 'hand': 0}},
        ],
    },
    {
        'name': 'Nórdico (isquios)',
        'muscles': 'Isquiotibiales (parte de atrás del muslo)',
        'regions': [{'part': 'thigh', 'face': 'flexor', 'from': 0.18, 'to': 0.94, 'width': 80}],
        # El sofá tapa el tobillo: se pinta en corte para ver los talones
        # trabados debajo. El cojín va bajo las rodillas.
        'props': [{'type': 'sofa', 'x1': -40, 'x2': -10.5, 'under': -3.5, 'seat': -15, 'back': -31,
                   'backW': 7, 'depth': 19},
                  {'type': 'cushion', 'x1': -4.5, 'x2': 5, 'h': 1.0, 'depth': 8}],
        # Las rodillas no se mueven: la cadera gira alrededor de ellas.
        'pivot': (0, -2.4),
        'gripZ': 5.5,
        'frames': [
            {'caption': 'Inicio: de rodillas, talones bajo el sofá',
             'hip': (0, -16.4), 'torso': -90, 'gaze': 0,
             'nearLeg': {'angles': (90, 178), 'foot': 180},
             'farLeg': {'angles': (90, 178), 'foot': 180},
             'nearArm': {'reach': (6.0, -27.2), 'bend': 1, 'hand': -60},
             'farArm': {'reach': (5.6, -27.6), 'bend': 1, 'hand': -60}},
            {'caption': 'Medio: baja en bloque, lento (3–5 s)',
             'hip': (9.9, -12.3), 'torso': -45, 'gaze': 10,
             'nearLeg': {'angles': (135, 178), 'foot': 180},
             'farLeg': {'angles': (135, 178), 'foot': 180},
             'nearArm': {'reach': (32.0, -9.5), 'bend': 1, 'hand': 60},
             'farArm': {'reach': (31.6, -9.9), 'bend': 1, 'hand': 60}},
            {'caption': 'Final: las manos frenan en el suelo',
             'hip': (13.16, -7.19), 'torso': -20, 'gaze': 15,
             'nearLeg': {'angles': (160, 178), 'foot': 180},
             'farLeg': {'angles': (160, 178), 'foot': 180},
             'nearArm': {'reach': (33.0, HAND_ON_FLOOR), 'bend': 1, 'hand': 0},
             'farArm': {'reach': (33.0, HAND_ON_FLOOR), 'bend': 1, 'hand': 0}},
        ],
    },
    {
        # Lunes del plan v3.1: dominada prona con mochila.
        'name': 'Dominadas',
        'muscles': 'Dorsal ancho; ayudan bíceps y espalda alta',
        # Solo el dorsal: el bíceps mira hacia el antebrazo y, con los codos
        # abiertos, casi nunca da a la cámara; resaltarlo no se vería.
        'regions': [{'part': 'torso', 'face': 'lats', 'from': 0.28, 'to': 0.9}],
        'props': [{'type': 'bar', 'x': 4, 'y': -68, 'half': 16},
                  {'type': 'backpack'}],
        # Variante que dibuja: la app la muestra solo si la sesión pide esto
        # (o si se abre sin contexto); si no, la figura plana.
        'variant': {'grip': 'prona', 'loaded': True},
        'gripZ': 7.0,
        # De perfil exacto la barra se ve de punta: un poco desde adelante se
        # ve la barra, los puños que la envuelven y la barbilla por encima.
        'view': {'yaw': 14},
        # Agarre prono: los codos salen hacia los lados al subir.
        'elbowOut': 0.9,
        'frames': [
            {'caption': 'Inicio: colgado, brazos estirados',
             'hip': (4, -31.2), 'torso': -90, 'gaze': -5,
             'nearLeg': {'angles': (88, 180), 'foot': 145},
             'farLeg': {'angles': (92, 178), 'foot': 145},
             'nearArm': {'reach': (4, -68), 'bend': 1, 'grip': 'bar'},
             'farArm': {'reach': (4, -68), 'bend': 1, 'grip': 'bar'}},
            {'caption': 'Medio: codos hacia las costillas',
             'hip': (2.0, -41.5), 'torso': -93, 'gaze': -10,
             'nearLeg': {'angles': (86, 178), 'foot': 145},
             'farLeg': {'angles': (90, 176), 'foot': 145},
             'nearArm': {'reach': (4, -68), 'bend': 1, 'grip': 'bar'},
             'farArm': {'reach': (4, -68), 'bend': 1, 'grip': 'bar'}},
            {'caption': 'Final: barbilla por encima de la barra',
             'hip': (0.5, -49.6), 'torso': -95, 'gaze': -12,
             'nearLeg': {'angles': (84, 176), 'foot': 145},
             'farLeg': {'angles': (88, 174), 'foot': 145},
             'nearArm': {'reach': (4, -68), 'bend': 1, 'grip': 'bar'},
             'farArm': {'reach': (4, -68), 'bend': 1, 'grip': 'bar'}},
        ],
    },
]


def _ang(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def _wrap(a):
    return (a + 180) % 360 - 180


def export_frame(f):
    """Postura resuelta: ángulos de cada segmento y puntos de apoyo."""
    s = fg.solve(f)
    j = s['joints']
    out = {'caption': f['caption'], 'hip': list(f['hip']), 'torso': f['torso'], 'gaze': f.get('gaze', 0), 'limbs': {}}
    for side in ('near', 'far'):
        for limb, mid, end, root in (('Leg', 'Knee', 'Ankle', 'hip'), ('Arm', 'Elbow', 'Hand', 'neck')):
            spec = f.get(side + limb)
            if not spec:
                continue
            m, e = j[side + mid], j[side + end]
            a1, a2 = _ang(j[root], m), _ang(m, e)
            item = {'angles': [a1, a2]}
            if 'reach' in spec:
                # Apoyo: la extremidad se sujeta ahí al animar (IK).
                item['pin'] = list(e)
                item['bend'] = spec.get('bend', 1)
            if limb == 'Leg':
                item['foot'] = spec.get('foot', a2)
            else:
                item['hand'] = spec.get('hand', a2)
                if spec.get('grip'):
                    item['grip'] = spec['grip']
            out['limbs'][side + limb] = item
    return out, s


def flex_signs(ex, frames):
    """Hacia qué lado dobla cada extremidad (+1/-1): define la cara flexora
    (bíceps, isquios) aunque en algún cuadro esté recta."""
    out = dict(ex.get('flex', {}))
    for limb in ('nearLeg', 'farLeg', 'nearArm', 'farArm'):
        if limb in out:
            continue
        best = 0.0
        for fr in frames:
            if limb in fr['limbs']:
                a1, a2 = fr['limbs'][limb]['angles']
                d = _wrap(a2 - a1)
                if abs(d) > abs(best):
                    best = d
        out[limb] = 1 if best >= 0 else -1
    return out


def check(ex, solved):
    """Avisos: algo bajo el suelo o un apoyo que la IK no alcanza."""
    problems = []
    for i, (f, s) in enumerate(zip(ex['frames'], solved)):
        for name, p in s['joints'].items():
            if p[1] > 0.05:
                problems.append(f"{ex['name']} cuadro {i}: {name} bajo el suelo (y={p[1]:.2f})")
        for side in ('near', 'far'):
            for limb, end in (('Leg', 'Ankle'), ('Arm', 'Hand')):
                spec = f.get(side + limb)
                if spec and 'reach' in spec:
                    e = s['joints'][side + end]
                    err = math.hypot(e[0] - spec['reach'][0], e[1] - spec['reach'][1])
                    if err > 0.4:
                        problems.append(f"{ex['name']} cuadro {i}: {side}{limb} no llega (falta {err:.2f})")
            leg = f.get(side + 'Leg')
            if leg and leg.get('foot') is not None:
                a = s['joints'][side + 'Ankle']
                toe = fg.add(a, fg.dirv(leg['foot']), fg.FT)
                if toe[1] > 0.05:
                    problems.append(f"{ex['name']} cuadro {i}: punta del pie {side} bajo el suelo (y={toe[1]:.2f})")
    return problems


def build(ex):
    frames, solved = [], []
    for f in ex['frames']:
        fr, s = export_frame(f)
        frames.append(fr)
        solved.append(s)
    return {
        'name': ex['name'],
        'muscles': ex['muscles'],
        'regions': ex['regions'],
        'props': ex['props'],
        'gripZ': ex.get('gripZ', 5.0),
        'elbowOut': ex.get('elbowOut', 0.25),
        'view': {'yaw': 0, 'pitch': 12, **ex.get('view', {})},
        'pivot': list(ex['pivot']) if ex.get('pivot') else None,
        'flex': flex_signs(ex, frames),
        **({'variant': ex['variant']} if ex.get('variant') else {}),
        'frames': frames,
    }, check(ex, solved)


def main():
    figures, problems = [], []
    for ex in EXERCISES:
        fig, probs = build(ex)
        figures.append(fig)
        problems += probs
    if problems:
        print('\n'.join(problems))
        sys.exit(1)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    target = os.path.join(root, 'assets', 'tecnica', 'figuras3d.json')
    consts = {'T': fg.T, 'UA': fg.UA, 'FA': fg.FA, 'TH': fg.TH, 'SH': fg.SH, 'FT': fg.FT,
              'HEAD_OFF': fg.HEAD_OFF, 'HEAD_R': fg.HEAD_R}
    with open(target, 'w', encoding='utf-8') as fh:
        json.dump({'version': 1, 'consts': consts, 'figures': fg._round(figures)}, fh,
                  ensure_ascii=False, separators=(',', ':'))
    print(f'{len(figures)} figuras 3D → {os.path.relpath(target, root)}')


if __name__ == '__main__':
    main()
