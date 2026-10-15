"""052 · grupo C: tren superior y banda, con cadenas 3D explícitas.

Cada figura se escribe con puntos del mundo (x adelante, y abajo, z hacia el
lado cercano): dónde está la mano o el pie y hacia dónde sale el codo o la
rodilla. `chain` traduce eso a `reach3`/`pole` relativos al hombro o la cadera
que resuelve la app, y comprueba que ningún segmento se estire. Los apoyos que
no deben moverse al interpolar (manos en el suelo, pies) usan `pin`: alcance
2D fijo más profundidad absoluta, que la app sujeta con IK en cada instante.
"""
from copy import deepcopy as cp
import math

import figuras as flat

ARM = (10, 9)
LEG = (14, 14)
SHOULDER_HALF, HIP_HALF = 4.5, 3.3


def sub(a, b): return [a[i] - b[i] for i in range(3)]
def add(a, b): return [a[i] + b[i] for i in range(3)]
def mul(v, k): return [c * k for c in v]
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def norm(v): return math.sqrt(dot(v, v))
def unit(v): return mul(v, 1 / norm(v))


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def ik3(root, end, a, b, pole):
    """Réplica de `ikJoint` (lib/ui/exercise_figure_3d.dart)."""
    to = sub(end, root)
    u = unit(to)
    d = min(max(norm(to), abs(a - b) + .01), a + b - .001)
    c = max(-1, min(1, (a * a + d * d - b * b) / (2 * a * d)))
    perp = sub(pole, mul(u, dot(pole, u)))
    if norm(perp) < 1e-6:
        perp = cross(u, [0, 0, 1])
    return add(add(root, mul(u, a * c)), mul(unit(perp), a * math.sqrt(1 - c * c)))


def neck(frame):
    n = flat.add(frame['hip'], flat.dirv(frame['torso']), 18)
    if 'shoulderOffset' in frame:
        fwd, lon = frame['shoulderOffset']
        n = flat.add(flat.add(n, flat.dirv(frame['torso'] + 90), fwd), flat.dirv(frame['torso']), lon)
    return n


def root(frame, side, limb):
    sz = 1 if side == 'near' else -1
    z = frame.get('bodyZ', 0)
    if limb == 'Arm':
        n = neck(frame)
        return [n[0], n[1], z + sz * SHOULDER_HALF]
    h = frame['hip']
    return [h[0], h[1], z + sz * HIP_HALF]


def _angles(r, mid, end):
    a1 = math.degrees(math.atan2(mid[1] - r[1], mid[0] - r[0]))
    a2 = math.degrees(math.atan2(end[1] - mid[1], end[0] - mid[0]))
    return [a1, a2]


def chain(frame, side, limb, end, *, pole=None, mid=None, **kw):
    """Extremo en `end` (mundo). `mid` fija la articulación media exacta;
    si no, `pole` es la dirección hacia la que sale. Devuelve la media."""
    r = root(frame, side, limb)
    a, b = ARM if limb == 'Arm' else LEG
    reach = sub(end, r)
    if norm(reach) > a + b - .02:
        raise ValueError(f"{frame['caption']}: {side}{limb} se estira ({norm(reach):.2f})")
    if mid is not None:
        pole = sub(mid, r)
    m = ik3(r, end, a, b, pole)
    spec = dict(angles=_angles(r, m, end), reach3=reach, pole=list(pole), **kw)
    if limb == 'Arm':
        spec.setdefault('hand', spec['angles'][1])
    else:
        spec.setdefault('foot', spec['angles'][1])
        spec.setdefault('bend', -1)
    frame[side + limb] = spec
    return m


def pin(frame, side, limb, end, *, pole, **kw):
    """Apoyo fijo: alcance 2D (la app lo sujeta) y profundidad absoluta."""
    r = root(frame, side, limb)
    a, b = ARM if limb == 'Arm' else LEG
    if norm(sub(end, r)) > a + b - .02:
        raise ValueError(f"{frame['caption']}: {side}{limb} no llega ({norm(sub(end, r)):.2f})")
    spec = dict(reach=[end[0], end[1]], depth=end[2], pole=list(pole), **kw)
    spec['bend'] = -1 if limb == 'Leg' else spec.get('bend', 1)
    if limb == 'Arm':
        spec.setdefault('hand', 0)
    frame[side + limb] = spec
    return ik3(r, end, a, b, pole)


def mirror(v):
    return [v[0], v[1], -v[2]]


def both_arms(frame, hand, *, pole=None, mid=None, **kw):
    """Brazos simétricos: `hand`, `pole` y `mid` son los del lado cercano."""
    chain(frame, 'near', 'Arm', hand, pole=pole, mid=mid, **kw)
    chain(frame, 'far', 'Arm', mirror(hand), pole=None if pole is None else mirror(pole),
          mid=None if mid is None else mirror(mid), **kw)


def standing(caption, hip=(0, -29), torso=-90, legs=None):
    from illustration_catalog import pose, limb
    return pose(caption, hip, torso, legs or limb(), None)


def bisect(g, lo, hi, n=60):
    """Raíz de g en [lo, hi] (g cambia de signo)."""
    glo = g(lo)
    for _ in range(n):
        mid = (lo + hi) / 2
        if (g(mid) > 0) == (glo > 0):
            lo, glo = mid, g(mid)
        else:
            hi = mid
    return (lo + hi) / 2


LEG_STRAIGHT = 27.95


class Plank:
    """Cuerpo recto de tobillos a cabeza apoyado en la punta de los pies.

    `phi` es la elevación del cuerpo (grados); `foot` el ángulo del pie con la
    pierna (90 = neutro). Los dedos quedan fijos en `toe`; con los pies más
    abiertos que la cadera (`feet_z`) la proyección de la pierna se acorta
    para que en 3D siga recta."""

    def __init__(self, toe=(-25.55, -.6), feet_z=None, foot=90):
        self.toe, self.feet_z, self.foot = toe, feet_z, foot
        dz = 0 if feet_z is None else feet_z - HIP_HALF
        self.leg = math.sqrt(LEG_STRAIGHT ** 2 - dz ** 2)

    def joints(self, phi, foot=None):
        foot = self.foot if foot is None else foot
        r = math.radians(phi)
        u = (math.cos(r), -math.sin(r))
        f = math.radians(90 - phi + (foot - 90))   # dirección tobillo→dedos
        fd = (math.cos(f), math.sin(f))
        ankle = (self.toe[0] - 5 * fd[0], self.toe[1] - 5 * fd[1])
        hip = (ankle[0] + self.leg * u[0], ankle[1] + self.leg * u[1])
        neck = (hip[0] + 18 * u[0], hip[1] + 18 * u[1])
        return ankle, hip, neck, math.degrees(f)

    def pose(self, caption, phi, foot=None, body_z=0):
        from illustration_catalog import pose, reach, arm
        ankle, hip, _, fdeg = self.joints(phi, foot)
        legs = []
        for sd, sign in [('near', 1), ('far', -1)]:
            leg = reach(*ankle, foot=fdeg, pole=[0, 1, 0])
            if self.feet_z is not None:
                leg['depth'] = sign * self.feet_z
            legs.append(leg)
        f = pose(caption, hip, -phi, legs[0], legs[1], arm(), arm())
        if body_z:
            f['bodyZ'] = body_z
        return f


def shoulder_dist(neck_xy, hand, dz):
    return math.sqrt((neck_xy[0] - hand[0]) ** 2 + (neck_xy[1] - hand[1]) ** 2 + dz ** 2)


PUSH = {'Flexiones', 'Flexiones con pies elevados', 'Flexiones diamante', 'Flexión a una mano',
        'Flexión arquero', 'Flexión pseudo-planche'}


def push_up(name):
    from illustration_catalog import basic, bench, phase
    elevated = name == 'Flexiones con pies elevados'
    toe = (-25.55, -12.6) if elevated else (-25.55, -.6)
    one = name == 'Flexión a una mano'
    # En pseudo-planche el cuerpo avanza sobre las puntas: tobillo extendido.
    body = Plank(toe, feet_z=12 if one else None, foot=110 if name == 'Flexión pseudo-planche' else 90)
    floor = -.75
    # Ancho de manos (z absoluta), dónde caen respecto del hombro en x en la
    # posición alta, altura del cuello abajo y hacia dónde sale el codo.
    if name == 'Flexiones diamante':
        hz, behind, low, pole = 1.2, 3, -6.5, [-1, -.7, .3]
    elif one:
        hz, behind, low, pole = 0, 2, -7.5, [-1, -.6, .15]
    elif name == 'Flexión arquero':
        hz, behind, low, pole = 13.5, 0, -8.3, [-.6, -1, .3]
    elif name == 'Flexión pseudo-planche':
        hz, behind, low, pole = 6.5, None, -6.5, [-.6, -1, .25]
    elif elevated:
        hz, behind, low, pole = 6, 0, -6, [-.7, -.8, .6]
    else:
        hz, behind, low, pole = 7.5, 0, -6, [-.7, -.8, .6]
    dz = abs(hz - SHOULDER_HALF)
    # Alto: brazos estirados (18,9) con la mano bajo el hombro (o algo atrás).
    if behind is None:
        # Pseudo-planche: manos a la altura de la cintura (7 delante de la
        # cadera); los hombros quedan por delante de las manos todo el recorrido.
        top = bisect(lambda p: shoulder_dist(body.joints(p)[2], (body.joints(p)[1][0] + 7, floor), dz) - 18.9, -20, 40)
        hx = body.joints(top)[1][0] + 7
    else:
        top = bisect(lambda p: shoulder_dist(body.joints(p)[2], (body.joints(p)[2][0] - behind, floor), dz) - 18.9, -20, 40)
        hx = body.joints(top)[2][0] - behind
    hand = [hx, floor, hz]
    if name == 'Flexión arquero':
        side_shift = hz - SHOULDER_HALF - 1
        bottom = bisect(lambda p: body.joints(p)[2][1] - low, -20, 40)
    else:
        bottom = bisect(lambda p: body.joints(p)[2][1] - low, -20, 40)

    def frame(caption, phi, bz=0, lowered=None):
        f = body.pose(caption, phi, body_z=bz)
        f['gaze'] = -6
        if one:
            pin(f, 'near', 'Arm', hand, pole=pole, hand=0)
            # Mano libre apoyada en la zona lumbar, codo hacia arriba y afuera.
            _, hip, nk, _ = body.joints(phi)
            r = math.radians(phi)
            u, n = (math.cos(r), -math.sin(r)), (-math.sin(r), -math.cos(r))
            back = [hip[0] + 4 * u[0] + 3.9 * n[0], hip[1] + 4 * u[1] + 3.9 * n[1], -1.2]
            chain(f, 'far', 'Arm', back, pole=[-.2, -1, -.9], grip='hold')
            return f
        for sd, sign in [('near', 1), ('far', -1)]:
            p = list(pole)
            p[2] *= sign
            if lowered == sd:
                p = [-.8, -1, 0]   # el brazo que va casi recto
            pin(f, sd, 'Arm', [hx, floor, sign * hz], pole=p, hand=0)
        return f
    if name == 'Flexión arquero':
        frames = [frame('Manos muy abiertas, dedos un poco afuera; cuerpo alineado', top),
                  frame('Baja el pecho hacia una mano; el otro brazo casi recto', bottom, side_shift, 'far'),
                  frame('Empuja de vuelta al centro', top),
                  frame('Alterna: baja hacia la otra mano', bottom, -side_shift, 'near'),
                  frame('Vuelve al centro; cadera y hombros paralelos al suelo', top)]
        for f in frames:
            for sd, sign in [('near', 1), ('far', -1)]:
                f[sd + 'Arm']['end3'] = [.9, 0, sign * .45]
    else:
        captions = {
            'Flexiones': ('Manos algo más abiertas que los hombros; cuerpo alineado',
                          'Baja el pecho casi al suelo sin perder la línea', 'Empuja el suelo hasta extender los brazos'),
            'Flexiones con pies elevados': ('Pies en la silla; cuerpo recto, glúteo y abdomen firmes',
                                            'Baja hasta casi tocar el suelo con el pecho', 'Sube hasta estirar los brazos'),
            'Flexiones diamante': ('Manos juntas bajo el pecho; cuerpo alineado',
                                   'Baja el pecho entre las manos, codos atrás', 'Empuja sin hundir la cadera'),
            'Flexión pseudo-planche': ('Manos a la altura de la cintura, dedos afuera; hombros por delante',
                                       'Baja con los codos pegados; los hombros siguen delante de las manos',
                                       'Sube manteniendo la inclinación'),
            'Flexión a una mano': ('Pies bien abiertos; mano bajo el pecho, la otra en la espalda',
                                   'Baja con el codo pegado, cadera y hombros paralelos', 'Sube sin girar el torso'),
        }[name]
        frames = [frame(captions[0], top), frame(captions[1], bottom), frame(captions[2], top)]
        if name == 'Flexiones diamante':
            for f in frames:
                for sd, sign in [('near', 1), ('far', -1)]:
                    f[sd + 'Arm']['end3'] = [.7, 0, -sign * .7]   # índices y pulgares en diamante
        if name == 'Flexión pseudo-planche':
            for f in frames:
                for sd, sign in [('near', 1), ('far', -1)]:
                    f[sd + 'Arm'].update(hand=180, end3=[-.35, 0, sign * .94])
    props = bench(-27, -12, 10) if elevated else []
    e = basic(name, frames, group='Empuje', props=props, yaw=45 if one or name == 'Flexión arquero' else 25, focus='neck')
    e['pivot'] = list(toe)
    return e


def circles(a, ra, b, rb, upper=True):
    """Intersección de dos círculos 2D; `upper` elige la de menor y."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    d = math.hypot(dx, dy)
    along = (ra * ra - rb * rb + d * d) / (2 * d)
    h = math.sqrt(max(0, ra * ra - along * along))
    base = (a[0] + along * dx / d, a[1] + along * dy / d)
    p1 = (base[0] + h * dy / d, base[1] - h * dx / d)
    p2 = (base[0] - h * dy / d, base[1] + h * dx / d)
    return min(p1, p2, key=lambda p: p[1]) if upper else max(p1, p2, key=lambda p: p[1])


def deg(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def lean_plank(caption, lam, hand, *, toe=(-25.55, -.6), hz=6.5, spine=0.):
    """Plancha con brazos bloqueados: el hombro gira alrededor de la mano
    (`lam` grados por delante de la vertical). Los dedos del pie no se
    mueven; el tobillo se extiende lo necesario para que el cuerpo siga
    recto de tobillos a cabeza."""
    from illustration_catalog import pose, reach, arm
    r = math.sqrt(18.9 ** 2 - (hz - SHOULDER_HALF) ** 2)
    t = math.radians(lam)
    shoulder = (hand[0] + r * math.sin(t), hand[1] - r * math.cos(t))
    ankle = circles(toe, 5, shoulder, LEG_STRAIGHT + 18)
    u = ((shoulder[0] - ankle[0]) / (LEG_STRAIGHT + 18), (shoulder[1] - ankle[1]) / (LEG_STRAIGHT + 18))
    hip = (ankle[0] + LEG_STRAIGHT * u[0], ankle[1] + LEG_STRAIGHT * u[1])
    legs = [reach(*ankle, foot=deg(ankle, toe), pole=[0, 1, 0]) for _ in range(2)]
    f = pose(caption, hip, deg(hip, shoulder), legs[0], legs[1], arm(), arm())
    f['gaze'] = -6
    if spine:
        f['spineBend'] = spine
    for sd, sign in [('near', 1), ('far', -1)]:
        pin(f, sd, 'Arm', [hand[0], hand[1], sign * hz], pole=[-1, 0, sign * .2], hand=0)
    return f


def quad_rock(caption, lam, *, hand=(17.5, -.75), hz=5, knee=(0, -1.6), hand_angle=0, grip=''):
    """Cuatro apoyos con codos rectos: rodillas y manos fijas; el hombro gira
    sobre la mano (`lam` > 0: hombros por delante de las manos)."""
    from illustration_catalog import pose, limb
    r = math.sqrt(18.93 ** 2 - (hz - SHOULDER_HALF) ** 2)
    t = math.radians(lam)
    shoulder = (hand[0] + r * math.sin(t), hand[1] - r * math.cos(t))
    hip = circles(shoulder, 18, knee, 14)
    thigh = deg(hip, knee)
    f = pose(caption, hip, deg(hip, shoulder), limb(thigh, 180, foot=180), limb(thigh, 180, foot=180))
    for sd, sign in [('near', 1), ('far', -1)]:
        pin(f, sd, 'Arm', [hand[0], hand[1], sign * hz], pole=[-1, 0, sign * .3], hand=hand_angle, grip=grip)
    return f


def rock(caption, peak, steps=4, **kw):
    """Ida y vuelta densa (los codos siguen rectos entre claves)."""
    out = [quad_rock(caption, peak * i / steps, **kw) for i in range(steps + 1)]
    back = [cp(f) for f in reversed(out[:-1])]
    return out, back


def wrists(name):
    """Muñecas (planche) y Muñecas a cuatro patas: (frames, motions)."""
    from illustration_catalog import phase
    contacts = ['nearHand', 'farHand', 'nearKnee', 'farKnee']
    if name == 'Muñecas a cuatro patas':
        parts = [('1', 'Palmas abajo, dedos al frente: hombros por delante de las manos', 18, 0, ''),
                 ('2', 'Dorsos de la mano en el suelo, dedos hacia las rodillas: muy suave', 7, 180, 'dorsum'),
                 ('3', 'Palmas abajo, dedos hacia las rodillas: suave, sin dolor', -10, 180, '')]
    else:
        parts = [('1', 'Tras los círculos de muñeca: cuatro apoyos, balancéate adelante', 18, 0, ''),
                 ('2', 'Palmas al revés (dedos hacia las rodillas): suave', -10, 180, '')]
    frames, motions = [], []
    for part, caption, peak, angle, grip in parts:
        out, back = rock(caption, peak, hand_angle=angle, grip=grip)
        if frames:
            motions.append(phase('Cambia el apoyo de manos', kind='cut', part=part, seconds=1))
        frames += out + back
        motions += [phase(caption, part=part, contacts=contacts, seconds=.3) for _ in out[1:]]
        motions += [phase('Regresa con los codos rectos', part=part, contacts=contacts, seconds=.3) for _ in back]
    frames.append(cp(frames[0]))
    motions.append(phase('Vuelve al primer apoyo', kind='cut', part='1', seconds=1))
    return frames, motions


def doorframe():
    """Pectoral en el marco: (frames, motions, props). El marco queda al
    costado: brazo abducido 90°, codo a la altura del hombro y antebrazo
    vertical apoyado en el marco. El pie de ese lado va adelante y el pecho
    gira hacia el lado contrario; mano, codo y pies no se mueven."""
    from illustration_catalog import pose, limb, arm, phase, box
    hip_y = -27.4
    shoulder0 = [0, hip_y - 18, SHOULDER_HALF]
    elbow = add(shoulder0, [0, 0, 10])
    hand = add(elbow, [0, -9, 0])
    feet = {'near': [7, -1, HIP_HALF], 'far': [-5, -1, -HIP_HALF]}

    def rolled(v, theta):
        c, s = math.cos(theta), math.sin(theta)
        return [v[0] * c - v[2] * s, v[1], v[2] * c + v[0] * s]
    sweep = []
    for i in range(9):
        k = i / 8
        x, roll = 3.5 * k, -30 * k
        f = pose('Antebrazo en el marco, codo a la altura del hombro; pie de ese lado adelante' if i == 0 else
                 'Da el paso adelante y gira el pecho al lado contrario', (x, hip_y), -90,
                 limb(), limb(), arm(0, -90, hand=-90, grip='hold'), arm(92, 92))
        f['bodyRoll'] = roll
        t = math.radians(roll)
        hip = [x, hip_y, 0]
        sh = add(hip, rolled([0, -18, SHOULDER_HALF], t))
        f['nearArm'].update(reach3=sub(hand, sh), pole=sub(elbow, sh), end3=[0, -1, 0])
        for sd, sign in [('near', 1), ('far', -1)]:
            root_ = add(hip, rolled([0, 0, sign * HIP_HALF], t))
            f[sd + 'Leg'].update(reach3=sub(feet[sd], root_), pole=[1, 0, 0], end3=[1, 0, 0], foot=0)
        sweep.append(f)
    frames = sweep + [cp(sweep[-1])] + [cp(f) for f in reversed(sweep[:-1])]
    frames[len(sweep)]['caption'] = 'Hombro abajo y atrás; si pincha delante del hombro, afloja'
    for f in frames[len(sweep) + 1:]:
        f['caption'] = 'Regresa despacio'
    contacts = ['nearHand', 'nearAnkle', 'farAnkle']
    motions = ([phase('Avanza y gira el pecho', seconds=.3, contacts=contacts) for _ in sweep[1:]] +
               [phase('Respira sin mover los apoyos', kind='hold', seconds=2)] +
               [phase('Regresa con control', seconds=.3, contacts=contacts) for _ in sweep[1:]])
    post_z = elbow[2] + 1
    props = [box([2.2, -33.5, post_z], [2, 67, 3]), box([2.2, -33.5, -post_z], [2, 67, 3]),
             box([2.2, -68, 0], [2, 2, 2 * post_z + 3])]
    return frames, motions, props


def pike(name):
    from illustration_catalog import basic, pose, reach, arm, phase
    ankle = (-9, -3)
    toe_dir = math.degrees(math.asin((-.6 - ankle[1]) / 5))
    hz = 6
    r_arm = math.sqrt(18.9 ** 2 - (hz - SHOULDER_HALF) ** 2)

    def hip_at(alpha):
        a = math.radians(alpha)
        return (ankle[0] + LEG_STRAIGHT * math.sin(a), ankle[1] - LEG_STRAIGHT * math.cos(a))
    # Arriba: V invertida; brazos en línea con el tronco, piernas rectas.
    a_top = 15
    h = hip_at(a_top)
    dy = -.75 - h[1]
    hand = (h[0] + math.sqrt((18 + r_arm) ** 2 - dy ** 2), -.75)
    t_top = deg(h, hand)

    # Abajo: coronilla al suelo un poco delante de las manos (triángulo).
    def crown_gap(alpha):
        hp = hip_at(alpha)
        t = math.asin((-.4 - hp[1]) / 27.1)
        return hp[0] + 27.1 * math.cos(t) - (hand[0] + 4)
    a_low = bisect(crown_gap, 30, 70)
    hl = hip_at(a_low)
    t_low = math.degrees(math.asin((-.4 - hl[1]) / 27.1))

    def at(s, caption):
        alpha = a_top + (a_low - a_top) * s
        f = pose(caption, hip_at(alpha), t_top + (t_low - t_top) * s,
                 reach(*ankle, foot=toe_dir, pole=[1, 0, 0]), reach(*ankle, foot=toe_dir, pole=[1, 0, 0]),
                 arm(), arm())
        for sd, sign in [('near', 1), ('far', -1)]:
            pin(f, sd, 'Arm', [hand[0], hand[1], sign * hz], pole=[-.8, -.4, sign * .6], hand=0)
        return f
    down = [at(i / 4, 'V invertida: brazos y piernas rectos, cadera alta' if i == 0 else
               'Dobla los codos; la cabeza baja delante de las manos') for i in range(5)]
    down[-1]['caption'] = 'Coronilla al suelo delante de las manos; cadera alta'
    up = [cp(f) for f in reversed(down[:-1])]
    for f in up:
        f['caption'] = 'Empuja hasta extender los brazos con la cadera alta'
    frames = down + [cp(down[-1])] + up
    e = basic(name, frames, group='Empuje', yaw=25, focus='neck')
    e['motion'] = ([phase('Baja la cabeza hacia el suelo', seconds=.35) for _ in down[1:]] +
                   [phase('Coronilla al suelo', kind='hold', seconds=.4)] +
                   [phase('Empuja', seconds=.3) for _ in up])
    return e


def dips(name):
    from illustration_catalog import basic, pose, limb, tube
    hand = [4, -40, 5]

    def at(caption, neck_xy, torso, legs, pole):
        hip = flat.add(neck_xy, flat.dirv(torso), -18)
        f = pose(caption, hip, torso, cp(legs), cp(legs))
        for sd, sign in [('near', 1), ('far', -1)]:
            p = list(pole)
            p[2] *= sign
            pin(f, sd, 'Arm', [hand[0], hand[1], sign * hand[2]], pole=p, grip='bar_parallel')
        return f
    dz = hand[2] - SHOULDER_HALF
    top_neck = (5.5, hand[1] - math.sqrt(18.9 ** 2 - 1.5 ** 2 - dz ** 2))
    top = at('Arriba: brazos bloqueados, hombros lejos de las orejas', top_neck, -82,
             limb(94, 160, foot=115), [-1, .2, .1])
    # Abajo: antebrazo casi vertical, brazo horizontal hacia atrás: el hombro
    # a la altura del codo, codos atrás (no abiertos), tronco algo adelante.
    elbow = (hand[0] - 2, hand[1] - math.sqrt(81 - 4))
    low_neck = (elbow[0] + math.sqrt(100 - .25), elbow[1])
    low = at('Baja hasta que el hombro quede a la altura del codo', low_neck, -62,
             limb(102, 165, foot=120), [-1, 0, .05])
    frames = [top, low, cp(top)]
    frames[2]['caption'] = 'Sube empujando hasta bloquear los codos'
    props = [tube([-8, -40, z], [16, -40, z], .8) for z in [-5, 5]]
    props += [tube([x, -40, z], [x, 0, z], .7) for x in [-8, 16] for z in [-5, 5]]
    return basic(name, frames, group='Empuje', props=props, focus='neck',
                 annotations=[dict(joint='nearHand', text='Manos en las barras', corner='tl')])


def table_row(name):
    from illustration_catalog import basic, pose, reach, arm, bench, phase
    # Talones en la silla y manos en el borde: abajo la mano queda sobre el
    # pecho bajo (brazo algo inclinado) para que arriba el borde toque el pecho.
    ankle = (12, -20)
    hand = [-27, -34, 5.5]
    body = LEG_STRAIGHT + 18
    r_arm = math.sqrt(18.87 ** 2 - (hand[2] - SHOULDER_HALF) ** 2)

    def at(caption, neck_xy, pole):
        u = ((neck_xy[0] - ankle[0]) / body, (neck_xy[1] - ankle[1]) / body)
        hip = (ankle[0] + LEG_STRAIGHT * u[0], ankle[1] + LEG_STRAIGHT * u[1])
        f = pose(caption, hip, deg(hip, neck_xy), reach(*ankle, foot=-90, pole=[0, -1, 0]),
                 reach(*ankle, foot=-90, pole=[0, -1, 0]), arm(), arm())
        f['gaze'] = 8
        for sd, sign in [('near', 1), ('far', -1)]:
            p = list(pole)
            p[2] *= sign
            pin(f, sd, 'Arm', [hand[0], hand[1], sign * hand[2]], pole=p, grip='bar', hand=-90)
        return f
    # Abajo: brazos estirados; arriba: pecho al borde, codos bajo el tablero,
    # junto a las costillas (nunca por encima de la mesa).
    low_neck = circles(ankle, body, (hand[0], hand[1]), r_arm, upper=False)
    top_y = -29.5
    top_neck = (ankle[0] - math.sqrt(body ** 2 - (top_y - ankle[1]) ** 2), top_y)
    low = at('Agarra el borde: cuerpo recto de talones a cabeza', low_neck, [1, .3, .4])
    top = at('Lleva el pecho al borde juntando las escápulas', top_neck, [1, 1, .45])
    frames = [low, top, cp(top), cp(low)]
    frames[2]['caption'] = 'Pausa 1 s arriba; codos junto a las costillas'
    frames[3]['caption'] = 'Baja controlado hasta estirar los brazos'
    props = bench(-10, -35, 34, 12) + bench(13, -18.5, 12, 8)
    e = basic(name, frames, group='Tirón', props=props, focus='neck',
              annotations=[dict(joint='nearHand', text='Agarre en el borde', corner='tl')])
    e['pivot'] = list(ankle)
    e['motion'] = [phase('Lleva el pecho al borde', seconds=1), phase('Pausa arriba', kind='hold', seconds=1),
                   phase('Baja controlado', seconds=1.5)]
    return e


def planche_lean(name):
    from illustration_catalog import basic, phase
    hand = (16.2, -5.75)
    out = [lean_plank('Plancha alta sobre las paralelas, brazos bloqueados' if i == 0 else
                      'Inclínate: hombros por delante de las manos, codos rectos', 28 * i / 4, hand,
                      spine=-.35 * i / 4) for i in range(5)]
    back = [cp(f) for f in reversed(out[:-1])]
    for f in back:
        f['caption'] = 'Vuelve sin doblar los codos'
    frames = out + [cp(out[-1])] + back
    frames[len(out)]['caption'] = 'Sostén: glúteo y abdomen firmes, cuerpo en línea'
    e = basic(name, frames, group='Habilidades', props=[dict(type='parallettes')], yaw=25, focus='neck')
    e['motion'] = ([phase('Inclínate adelante', seconds=.3) for _ in out[1:]] +
                   [phase('Sostén la inclinación', kind='hold', seconds=2)] +
                   [phase('Vuelve', seconds=.3) for _ in back])
    return e


OTHER = {'Pike push-up': pike, 'Fondos en barra': dips, 'Remo invertido (mesa)': table_row,
         'Inclinación de planche': planche_lean}


NAMES = {'Dominadas', 'Face pull con banda', 'Separaciones con banda', 'Dislocaciones con banda',
         'Elevaciones laterales con banda', 'Curl con banda',
         'Extensión de tríceps sobre la cabeza con banda', 'Muñecas (planche)'} | PUSH | set(OTHER)


def generate(name):
    from illustration_catalog import pose, limb, arm, reach, basic, phase, legacy
    if name in PUSH:
        return push_up(name)
    if name in OTHER:
        return OTHER[name](name)
    if name == 'Muñecas (planche)':
        frames, motions = wrists(name)
        e = basic(name, frames, group='Movilidad', yaw=25, focus='neck')
        e['motion'] = motions
        return e
    if name == 'Dominadas':
        e = cp({x['name']: x for x in legacy.EXERCISES}['Dominadas'])
        e.pop('variant', None)
        e['props'] = [p for p in e['props'] if p['type'] != 'backpack']
        e['group'], e['focus'] = 'Tirón', 'neck'
        # Desde atrás: se leen los dos codos bajando a la vez, simétricos.
        e.setdefault('view', {})['yaw'] = -80
        bar = (4, -68)
        hand = [bar[0], bar[1], 8.5]   # prono: un poco más ancho que los hombros
        e['gripZ'] = hand[2]
        legs = limb(95, 165, foot=135)

        def hang(caption, neck_at, torso):
            hip = flat.add(neck_at, flat.dirv(torso), -18)
            f = pose(caption, hip, torso, cp(legs), cp(legs))
            f['gaze'] = -5
            # Codos hacia abajo, a las costillas, algo afuera; ambos a la vez.
            both_arms(f, hand, pole=[.1, 1, .9], grip='bar')
            return f
        straight = math.sqrt(18.9 ** 2 - (hand[2] - SHOULDER_HALF) ** 2)
        low = hang('Inicio: colgado, brazos estirados y hombros activos', (4, bar[1] + straight), -90)
        mid = hang('Sube con los dos codos hacia las costillas', (2.2, -58.5), -92)
        top = hang('Barbilla por encima de la barra, cuerpo centrado', (-.4, -66.3), -95)
        down = hang('Baja en 2 s hasta estirar los brazos', (2.2, -58.5), -92)
        e['frames'] = [low, mid, top, cp(top), down, cp(low)]
        e['frames'][5]['caption'] = 'Brazos estirados por completo'
        e['motion'] = [phase('Sube: codos a las costillas', seconds=.6),
                       phase('Barbilla sobre la barra', seconds=.5),
                       phase('Pausa arriba', kind='hold', seconds=.4),
                       phase('Baja en 2 s', seconds=1),
                       phase('Hasta estirar los brazos', seconds=1)]
        return e
    if name == 'Face pull con banda':
        anchor = [32, -51.5, 0]
        start = standing('Banda anclada a la altura de la cara; brazos al frente')
        both_arms(start, [18.2, -49.8, 5.5], pole=[0, .3, 1], grip='handle')
        end = standing('Manos a los lados de la frente; codos altos, a la altura del hombro')
        # Codo afuera y algo atrás, a la altura del hombro: no es un remo.
        both_arms(end, [3, -55, 9.5], pole=[-.25, -.3, 1], grip='handle')
        frames = [start, end, cp(end), cp(start)]
        frames[2]['caption'] = 'Al final, los pulgares apuntan hacia atrás'
        frames[3]['caption'] = 'Vuelve lento a brazos estirados'
        e = basic(name, frames, group='Banda', yaw=55, focus='nearHand',
                  props=[dict(type='band', a=anchor, b='nearHand', depthSorted=True), dict(type='band', a=anchor, b='farHand', depthSorted=True)],
                  muscles='Zona indicada en la guía del ejercicio')
        e['motion'] = [phase('Tira hacia la frente separando las manos', seconds=1.2),
                       phase('Codos altos, pulgares atrás', kind='hold', seconds=1),
                       phase('Vuelve lento', seconds=2)]
        return e
    if name == 'Separaciones con banda':
        start = standing('Brazos rectos al frente, banda a la altura del pecho')
        both_arms(start, [18.6, -44.5, 6], pole=[0, 1, 0], grip='handle', keepReachRadius=True)
        end = standing('Abre en horizontal hasta que la banda toque el pecho')
        both_arms(end, [5.5, -44.5, SHOULDER_HALF + math.sqrt(18.96 ** 2 - 5.5 ** 2 - 2.5 ** 2)], pole=[0, 1, 0], grip='handle', keepReachRadius=True)
        frames = [start, end, cp(end), cp(start)]
        frames[2]['caption'] = 'Brazos en T: junta las escápulas'
        frames[3]['caption'] = 'Vuelve lento al frente'
        e = basic(name, frames, group='Banda', yaw=55, focus='nearHand',
                  props=[dict(type='band', a='nearHand', b='farHand', depthSorted=True)],
                  muscles='Zona indicada en la guía del ejercicio')
        e['motion'] = [phase('Abre los brazos en horizontal', seconds=1.2),
                       phase('Junta las escápulas', kind='hold', seconds=1),
                       phase('Vuelve lento', seconds=2)]
        return e
    if name == 'Dislocaciones con banda':
        wide = 17
        rho = math.sqrt(18.96 ** 2 - (wide - SHOULDER_HALF) ** 2)

        def at(psi, caption):
            f = standing(caption)
            r = math.radians(psi)
            s = root(f, 'near', 'Arm')
            both_arms(f, [s[0] + rho * math.cos(r), s[1] + rho * math.sin(r), wide],
                      pole=[0, 0, 1], grip='handle', keepReachRadius=True)
            return f
        out = [at(70, 'Agarre ancho, brazos estirados al frente'), at(20, 'Sube la banda con los codos rectos'),
               at(-40, 'Sube la banda con los codos rectos'), at(-90, 'Pasa la banda por encima de la cabeza'),
               at(-140, 'Llévala atrás sin doblar los codos'), at(170, 'Llévala atrás sin doblar los codos'),
               at(135, 'Detrás del cuerpo, sólo hasta donde estés cómodo')]
        back = [cp(f) for f in reversed(out[:-1])]
        for f in back:
            f['caption'] = 'Vuelve al frente igual de lento'
        frames = out + [cp(out[-1])] + back
        motion = ([phase('Pasa por encima', seconds=.5) for _ in out[1:]] +
                  [phase('Pausa cómoda', kind='hold', seconds=.6)] +
                  [phase('Vuelve al frente', seconds=.5) for _ in back])
        e = basic(name, frames, group='Calentamiento', yaw=40, focus=None,
                  props=[dict(type='band', a='nearHand', b='farHand', depthSorted=True)],
                  annotations=[dict(joint='nearHand', text='Agarre ancho', corner='tl')])
        e['motion'] = motion
        return e
    if name == 'Elevaciones laterales con banda':
        start = standing('Pisa la banda; codos un poco flexionados')
        both_arms(start, [2, -47 + 18.4, SHOULDER_HALF + 2.6], pole=[-1, 0, .6], grip='handle', keepReachRadius=True)
        top = standing('Sube hacia los lados hasta el hombro, guiando con los codos')
        both_arms(top, [2.5, -46.5, SHOULDER_HALF + 18.52], pole=[-.4, -1, 0], grip='handle', keepReachRadius=True)
        frames = [start, top, cp(top), cp(start)]
        frames[2]['caption'] = 'Codos a la altura de las manos o por encima'
        frames[3]['caption'] = 'Baja en 2 s sin soltar la tensión'
        e = basic(name, frames, group='Banda', yaw=55, focus='nearHand',
                  props=[dict(type='band', a='nearToe', b='nearHand', depthSorted=True), dict(type='band', a='farToe', b='farHand', depthSorted=True)],
                  muscles='Zona indicada en la guía del ejercicio')
        e['motion'] = [phase('Sube hacia los lados', seconds=1.2), phase('Pausa en el hombro', kind='hold', seconds=.5),
                       phase('Baja en 2 s', seconds=2)]
        return e
    if name == 'Curl con banda':
        start = standing('Pisa la banda; codos pegados a los lados, palmas al frente')
        top = standing('Sube las manos hacia los hombros sin mover los codos')
        start['nearArm'] = arm(88, 86, hand=86)
        top['nearArm'] = arm(88, -70, hand=-70)
        for f in (start, top):
            f['farArm'] = cp(f['nearArm'])
            # Cada mano en el plano de su hombro: el codo queda quieto y sólo
            # gira el antebrazo (ángulos sagitales conservados).
            for sd, sign in [('near', 1), ('far', -1)]:
                f[sd + 'Arm'].update(depth=sign * SHOULDER_HALF, pole=[0, 1, 0], planarAngles=True, grip='handle')
        frames = [start, top, cp(top), cp(start)]
        frames[2]['caption'] = 'Manos cerca de los hombros; codos al costado'
        frames[3]['caption'] = 'Baja en 2 segundos'
        e = basic(name, frames, group='Banda', yaw=30, focus='nearHand',
                  props=[dict(type='band', a='nearToe', b='nearHand', depthSorted=True), dict(type='band', a='farToe', b='farHand', depthSorted=True)],
                  muscles='Zona indicada en la guía del ejercicio')
        e['motion'] = [phase('Sube sin mover los codos', seconds=1), phase('Pausa arriba', kind='hold', seconds=.5),
                       phase('Baja en 2 s', seconds=2)]
        return e
    if name == 'Extensión de tríceps sobre la cabeza con banda':
        hip = (0, -27.6)
        legs = (reach(7, -1, foot=0), reach(-7, -1, foot=0))   # paso: pie lejano atrás

        def at(phi, caption):
            f = pose(caption, hip, -90, cp(legs[0]), cp(legs[1]))
            s = root(f, 'near', 'Arm')
            elbow = add(s, [1.5, -9.8, -1.3])
            r = math.radians(phi)
            d = unit([math.sin(r), -math.cos(r), -.08])
            both_arms(f, add(elbow, mul(d, 9)), mid=elbow, grip='handle')
            return f
        up = [at(205, 'Paso: banda bajo el pie de atrás; manos detrás de la cabeza'),
              at(245, 'Codos al techo; extiende sin moverlos'), at(285, 'Codos al techo; extiende sin moverlos'),
              at(325, 'Codos al techo; extiende sin moverlos'), at(376, 'Brazos extendidos por completo')]
        down = [cp(f) for f in reversed(up[:-1])]
        for f in down:
            f['caption'] = 'Baja lento detrás de la cabeza'
        frames = up + [cp(up[-1])] + down
        anchor = [-6.5, -.3, -HIP_HALF]
        e = basic(name, frames, group='Banda', yaw=25, focus='nearHand',
                  props=[dict(type='band', a=anchor, b='nearHand', depthSorted=True), dict(type='band', a=anchor, b='farHand', depthSorted=True)],
                  muscles='Zona indicada en la guía del ejercicio')
        e['motion'] = ([phase('Extiende los codos', seconds=.3) for _ in up[1:]] +
                       [phase('Pausa arriba', kind='hold', seconds=.4)] +
                       [phase('Baja lento', seconds=.5) for _ in down])
        return e
    raise ValueError(name)
