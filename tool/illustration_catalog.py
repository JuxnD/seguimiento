"""Catálogo pedagógico completo. Poses editables; no imágenes remotas.

Reusa la cinemática y las poses comprobadas, y especifica el movimiento y el
equipo de cada entrada. Los planos frontal/oblicuo declaran alcance/polo 3D.
No hay figura genérica para un nombre desconocido: la generación falla.
"""
from copy import deepcopy as cp
from pathlib import Path
import json
import math
import re
import sys

sys.dont_write_bytecode = True
import figuras as flat
import figuras3d as legacy

ROOT = Path(__file__).resolve().parents[1]


def limb(a=90, b=90, foot=0, **kw):
    return dict(angles=[a, b], foot=foot, bend=kw.pop("bend", -1), **kw)


def arm(a=90, b=90, **kw):
    return dict(angles=[a, b], hand=kw.pop('hand', b), **kw)


def reach(x, y, **kw):
    return dict(reach=[x, y], bend=kw.pop("bend", 1), **kw)


def pose(caption, hip=(0, -29), torso=-90, nl=None, fl=None, na=None, fa=None):
    result = dict(caption=caption, hip=hip, torso=torso,
                nearLeg=nl or limb(), farLeg=fl or cp(nl) or limb(),
                nearArm=na or arm(), farArm=fa or cp(na) or arm())
    for key in ['nearLeg','farLeg']:
        if 'reach' in result[key]: result[key]['bend'] = -1
    return result


def box(center, size, color='equipment', alpha=1):
    return dict(type='box', center=center, size=size, color=color, alpha=alpha)


def bench(x=24, y=-12.5, width=12, depth=9):
    return [box([x, y + 1, 0], [width, 2, depth * 2]),
            box([x - width / 3, y / 2, -depth + 1], [1.5, -y, 1.5]),
            box([x + width / 3, y / 2, depth - 1], [1.5, -y, 1.5])]


def tube(a, b, radius=.55):
    return dict(type='tube', a=a, b=b, radius=radius)


def basic(name, frames, *, group, props=None, yaw=25, muscles='', focus=None, annotations=None):
    return dict(name=name, frames=frames, props=props or [], regions=[],
                group=group, muscles=muscles, view=dict(yaw=yaw, pitch=10),
                focus=focus, annotations=annotations or [], source='guía local + especificación por ejercicio')


def plank(phi, caption, *, hands=None, variant=None, toe_y=-.6):
    # Apoyo en los dedos, talón elevado; tibia y pie forman un ángulo neutral.
    peak=math.degrees(math.asin((19.75+toe_y)/math.hypot(46,5))-math.atan2(5,46))
    phi = peak if phi >= 24 else peak-12.27
    if variant == 'archer' and phi > 16:
        phi = math.degrees(math.asin((math.sqrt(19**2 - 13.5**2)+.75+toe_y)/math.hypot(46,5))-math.atan2(5,46))
    r = math.radians(phi)
    ax, ay = -25.55-5*math.sin(r), toe_y-5*math.cos(r)
    hx, hy = ax + 28 * math.cos(r), ay - 28 * math.sin(r)
    nx, ny = hx + 18 * math.cos(r), hy - 18 * math.sin(r)
    na, fa = reach(16.4, -.75, hand=0), reach(16.4, -.75, hand=0)
    if variant == 'diamond':
        na.update(depth=1.0); fa.update(depth=-1.0)
    if variant == 'archer':
        spread = math.sqrt(max(0, 19**2 - (-.75-ny)**2))
        body_z = spread - 13.5
        na.update(reach3=[0, -.75 - ny, 13.5-body_z], pole=[-1, 0, 1])
        fa.update(reach3=[0, -.75 - ny, -spread], pole=[0, 0, -1])
    if variant == 'one':
        na.update(reach3=[16.4 - nx, -.75 - ny, 0], pole=[-1, 0, 0])
        fa = arm(150, -110, hand=-110, reach3=[-13,-1.5,5.3], pole=[-1,1,-1], grip='hold')
    if variant == 'pseudo':
        na = reach(nx - 7, -.75, hand=0)
        fa = cp(na)
    result = pose(caption, (hx, hy), -phi,
                  reach(ax, ay, foot=90-phi), reach(ax, ay, foot=90-phi), na, fa)
    if variant == 'archer': result['bodyZ'] = body_z
    return result


def squat(caption, low=False, jump=False, x=0):
    if jump:
        return pose(caption, (x, -40), na=arm(-110, -100), fa=arm(-110, -100))
    if low:
        return pose(caption, (x - 8, -17), -65,
                    reach(x, -1, foot=0), reach(x, -1, foot=0),
                    arm(-10, -10), arm(-10, -10))
    return pose(caption, (x, -29))


def seated(caption, angle=-15, wide=False, torso=-65):
    # El torso se inclina ligeramente; el suelo está bajo glúteos y palmas.
    # En straddle las palmas apoyan delante: inclinar el tronco permite
    # alcanzar el suelo sin alargar los brazos ni despegar los glúteos.
    if wide:
        torso = -50
    legs = limb(angle, angle, foot=angle)
    if wide:
        elevation = math.radians(angle)
        spread = math.radians(30)
        legs.update(reach3=[28 * math.cos(elevation) * math.cos(spread),
                           28 * math.sin(elevation),
                           28 * math.cos(elevation) * math.sin(spread)],
                    pole=[0, -1, 0], end3=[math.cos(spread), 0, math.sin(spread)],
                    keepReachRadius=True)
    other = cp(legs)
    if wide:
        other['reach3'][2] *= -1
        other['end3'][2] *= -1
    hip = (0, -5)
    neck = flat.add(hip, flat.dirv(torso), 18)
    hands = reach(neck[0] - 3, -.75, hand=0)
    return pose(caption, hip, torso, legs, other, hands, cp(hands))


def supine(caption, legs, *, torso=180, hip=(0, -5), arms=None):
    return pose(caption, hip, torso, legs[0], legs[1],
                arms or arm(0, 0, hand=0), cp(arms) if arms else arm(0, 0, hand=0))


def reference_names():
    names = set()
    for path, pattern in [
        ('lib/data/catalog_updates.dart', r"name: '([^']+)'"),
        ('lib/data/exercise_details.dart', r"^  '([^']+)': ExerciseDetail"),
        ('lib/domain/mobility.dart', r"name: '([^']+)'"),
    ]:
        names.update(re.findall(pattern, (ROOT / path).read_text(encoding='utf-8'), re.M))
    names -= {'Movilidad nocturna', 'Recuperación de piernas'}
    names.update(e['name'] for e in flat.EXERCISES)
    return sorted(names)


def band(name):
    start, end = pose('Colócate: torso estable'), pose('Realiza el recorrido sin mover el torso')
    props, group, focus = [], 'Banda', 'nearHand'
    if name == 'Elevaciones laterales con banda':
        start['nearArm'].update(reach3=[0, 18.8, 0], pole=[1, 0, 0])
        start['farArm'].update(reach3=[0, 18.8, 0], pole=[1, 0, 0])
        end['nearArm'].update(reach3=[0, 0, 18.8], pole=[0, -1, 0])
        end['farArm'].update(reach3=[0, 0, -18.8], pole=[0, -1, 0])
        end['caption'] = 'Eleva los brazos hacia los lados, hasta el hombro'
        props = [dict(type='band', a='nearToe', b='nearHand'), dict(type='band', a='farToe', b='farHand')]
    elif name == 'Separaciones con banda':
        for sd in ('near', 'far'):
            start[sd + 'Arm'].update(reach3=[18, 0, 0], pole=[0, -1, 0])
        end['nearArm'].update(reach3=[0, 0, 18.8], pole=[0, -1, 0])
        end['farArm'].update(reach3=[0, 0, -18.8], pole=[0, -1, 0])
        end['caption'] = 'Abre la banda a la altura del pecho'
        props = [dict(type='band', a='nearHand', b='farHand')]
    elif name == 'Pallof press con banda':
        start['nearArm'] = reach(6, -39, hand=0, depth=1)
        start['farArm'] = reach(6, -39, hand=0, depth=-1)
        end['nearArm'] = reach(17, -41, hand=0, depth=1)
        end['farArm'] = reach(17, -41, hand=0, depth=-1)
        start['caption'] = 'Banda anclada a un lado; manos junto al pecho'
        end['caption'] = 'Aleja las manos sin girar pecho ni cadera'
        props = [dict(type='band', a=[0, -40, 28], b='nearHand')]
    elif name == 'Face pull con banda':
        start['nearArm'] = reach(18, -43, hand=0, depth=6)
        start['farArm'] = reach(18, -43, hand=0, depth=-6)
        end['nearArm'] = reach(4, -49, hand=-90, depth=9)
        end['farArm'] = reach(4, -49, hand=-90, depth=-9)
        end['caption'] = 'Tira hacia la cara: manos separadas, codos abiertos'
        props = [dict(type='band', a=[34, -46, 0], b='nearHand'), dict(type='band', a=[34, -46, 0], b='farHand')]
    elif name == 'Remo con banda':
        for sd in ('near', 'far'):
            start[sd + 'Arm'] = reach(18, -40, hand=0)
            end[sd + 'Arm'] = reach(3, -32, hand=0)
        end['caption'] = 'Lleva las manos hacia las costillas; codos atrás'
        props = [dict(type='band', a=[36, -38, 0], b='nearHand'), dict(type='band', a=[36, -38, 0], b='farHand')]
    elif name == 'Curl con banda':
        end['nearArm'] = arm(90, -65, hand=-65)
        end['farArm'] = arm(90, -65, hand=-65)
        # Each hand stays in its shoulder's sagittal plane. The generic grip
        # width/elbow flare is for free grips, not an anchored curl elbow.
        for frame in (start,end):
            for sd,sign in [('near',1),('far',-1)]:
                frame[sd+'Arm'].update(depth=sign*4.5,pole=[0,1,0],planarAngles=True)
        end['caption'] = 'Dobla los codos; deja el brazo junto al torso'
        props = [dict(type='band', a='nearToe', b='nearHand'), dict(type='band', a='farToe', b='farHand')]
    elif name == 'Extensión de tríceps sobre la cabeza con banda':
        start['nearArm'] = arm(-98, 135, hand=90)
        start['farArm'] = arm(-98, 135, hand=90)
        end['nearArm'] = arm(-96, -96, hand=-90)
        end['farArm'] = arm(-96, -96, hand=-90)
        end['caption'] = 'Estira los codos manteniendo el brazo arriba'
        props = [dict(type='band', a=[-2, -1, 0], b='nearHand'), dict(type='band', a=[-2, -1, 0], b='farHand')]
    else:
        raise ValueError(name)
    for frame in [start, end]:
        frame['nearArm']['grip'] = 'handle'
        frame['farArm']['grip'] = 'handle'
    finish = cp(start); finish['caption'] = 'Vuelve despacio a la posición inicial'
    return basic(name, [start, end, finish], group=group, props=props, yaw=55, focus=focus,
                 muscles='Zona indicada en la guía del ejercicio')


def _generate_base(name):
    existing = {e['name']: e for e in legacy.EXERCISES}
    old = {e['name']: e for e in flat.EXERCISES}
    if name == 'Círculos de hombros':
        frames=[]
        for offset,caption in [((0,0),'Brazos relajados: mueve los hombros, no los brazos'),
                               ((0,1.2),'1. Arriba: sube suavemente los hombros'),
                               ((-.8,0),'2. Atrás: llévalos atrás sin sacar el pecho'),
                               ((0,-.8),'3. Abajo: baja hombros y deja el cuello largo'),
                               ((.8,0),'4. Frente: pásalos al frente sin sacar pecho')]:
            f=pose(caption);f['shoulderOffset']=offset;frames.append(f)
        frames.append(dict(cp(frames[0]),caption='Vuelve al inicio; repite el círculo en sentido contrario'))
        ex=basic(name,frames,group='Calentamiento',yaw=35,focus='neck',
                 annotations=[dict(joint='nearShoulder',text='1. Arriba\n2. Atrás\n3. Abajo\n4. Frente',corner='tl')])
        ex['regions']=[dict(part='shoulder')]
        ex['gripZ']=4.5
        return ex
    if name == 'Retracciones escapulares':
        frames=[]
        for rise,caption in [(0,'Cuelga de la barra: codos rectos, pies libres'),
                             (1.2,'Baja los hombros: el cuerpo sube un poco, sin doblar codos'),
                             (0,'Vuelve al colgado sin balancearte')]:
            f=pose(caption,(0,-34-rise),na=arm(-90,-90,hand=-90,grip='bar'),fa=arm(-90,-90,hand=-90,grip='bar'))
            f['shoulderOffset']=(0,-rise);frames.append(f)
        ex=basic(name,frames,group='Calentamiento',props=[dict(type='bar',x=0,y=-71,half=15)],yaw=30,focus='neck',
                 annotations=[dict(joint='nearShoulder',text='Hombros lejos de las orejas',corner='tl')])
        ex['regions']=[dict(part='shoulder')]
        ex['gripZ']=4.5
        return ex
    if name == 'Flexiones escapulares':
        base=plank(24,'Colócate en plancha: palmas y dedos de los pies apoyados')
        origin=flat.solve(base)['joints']['neck']
        frames=[]
        for angle,caption in [(base['torso'],'Plancha alta: codos rectos'),
                              (base['torso']+2,'Deja bajar un poco el pecho entre los hombros'),
                              (base['torso']-4,'Empuja el suelo: el pecho sube, codos sin doblarse'),
                              (base['torso'],'Vuelve; conserva la cadera estable')]:
            f=cp(base);f['torso']=angle;f['caption']=caption
            neck=flat.add(f['hip'],flat.dirv(angle),18)
            delta=(origin[0]-neck[0],origin[1]-neck[1])
            front,up=flat.dirv(angle+90),flat.dirv(angle)
            f['shoulderOffset']=(sum(a*b for a,b in zip(delta,front)),sum(a*b for a,b in zip(delta,up)))
            f['nearArm']=arm(90,90,hand=0);f['farArm']=cp(f['nearArm']);frames.append(f)
        ex=basic(name,frames,group='Calentamiento',yaw=25,focus='neck',
                 annotations=[dict(joint='nearShoulder',text='Escápulas: recorrido pequeño',corner='tl')])
        ex['regions']=[dict(part='shoulder')]
        ex['gripZ']=4.5
        return ex
    if name == 'Balanceos de pierna':
        vectors=[([0,28,0],[1,0,0],'Una mano en la pared; el otro pie sostiene el cuerpo'),
                 ([28*math.cos(math.radians(55)),28*math.sin(math.radians(55)),0],
                  [math.cos(math.radians(-35)),math.sin(math.radians(-35)),0],'Pierna móvil relajada y pie libre: balancea delante, sin patear'),
                 ([28*math.cos(math.radians(115)),28*math.sin(math.radians(115)),0],
                  [math.cos(math.radians(25)),math.sin(math.radians(25)),0],'Balancea atrás sin arquear la espalda'),
                 ([0,28,0],[1,0,0],'Vuelve al centro antes del balanceo lateral'),
                 ([0,28*math.cos(math.radians(30)),14],[1,0,0],'Abre la pierna hacia el lado; el pie de apoyo no se mueve'),
                 ([5,math.sqrt(28**2-5**2-7**2),-7],[1,0,0],'Cruza suavemente por delante, no detrás del apoyo'),
                 ([0,28,0],[1,0,0],'Vuelve al centro; cambia de pierna')]
        frames=[]
        for vector,end,caption in vectors:
            # Mobile leg is relaxed: slight knee flexion leaves the foot clear.
            vector=[component * 27.5 / 28 for component in vector]
            f=pose(caption,nl=limb(90,90,reach3=vector,pole=[1,0,0],end3=end,keepReachRadius=True),
                   fl=limb(90,90,foot=0),na=arm(),
                   fa=arm(160,160,reach3=[0,4,-12],pole=[1,-1,0],end3=[0,-1,0],grip='hold'))
            frames.append(f)
        return basic(name,frames,group='Calentamiento',yaw=35,
                     props=[box([0,-32,-18],[50,64,2],alpha=.28)],focus='hip',
                     annotations=[dict(joint='nearAnkle',text='Pierna móvil',corner='tr'),
                                  dict(joint='farToe',text='Pie de apoyo',corner='bl'),
                                  dict(joint='farHand',text='Mano en pared lateral',corner='tl')])
    if name == 'Puente de glúteo':
        # Shoulder pivot and both foot contacts stay fixed. Solve the upper
        # position where shoulder→hip→knee are collinear, shin length14.
        theta=math.acos(2281/math.hypot(2432,192))-math.atan2(192,2432)
        frames=[]
        for angle,caption in [(0,'Boca arriba: pies planos, rodillas dobladas'),
                              (theta,'Sube la pelvis: hombros, cadera y rodillas alineados'),
                              (0,'Baja despacio; conserva los pies y hombros apoyados')]:
            hip=(-18+18*math.cos(angle),-4-18*math.sin(angle))
            a=math.degrees(math.asin(3.25/19))
            f=pose(caption,hip,180-math.degrees(angle),reach(20,-1,foot=0),reach(20,-1,foot=0),
                   arm(a,a,hand=0),arm(a,a,hand=0))
            f['gaze']=math.degrees(angle);frames.append(f)
        ex=basic(name,frames,group='Calentamiento',yaw=30,focus='hip',
                 annotations=[dict(joint='neck',text='Hombros apoyados',corner='tl'),
                              dict(joint='nearToe',text='Pies planos',corner='br')])
        ex['pivot']=(-18,-4)
        ex['gripZ']=4.5
        return ex
    if name == 'Dislocaciones con banda':
        frames=[]
        radius=math.sqrt(19**2-14**2)
        for angle,caption in [(35,'Banda al frente: agarre ancho y codos rectos'),
                              (-90,'Pasa por arriba; la banda queda libre sobre la cabeza'),
                              (-215,'Lleva atrás sólo hasta donde resulte cómodo, sin forzar'),
                              (-90,'Regresa por arriba manteniendo el agarre ancho'),
                              (35,'Vuelve al frente; no es una luxación del hombro')]:
            target=flat.add((0,0),flat.dirv(angle),radius)
            elbow,hand=flat.two_link((0,0),dict(reach=target,bend=1),10,9)
            angles=(legacy._ang((0,0),elbow),legacy._ang(elbow,hand))
            f=pose(caption,na=arm(*angles,depth=18.5,end3=[0,0,1],grip='handle'),
                   fa=arm(*angles,depth=-18.5,end3=[0,0,-1],grip='handle'))
            frames.append(f)
        return basic(name,frames,group='Calentamiento',yaw=40,
                     props=[dict(type='band',a='nearHand',b='farHand')],focus=None,
                     annotations=[dict(joint='nearHand',text='Agarre ancho',corner='tl')])
    if name in existing:
        e = cp(existing[name]); e['group'] = 'Tirón' if name == 'Dominadas' else 'Piernas' if name.startswith('Nórdico') else 'Empuje'
        e['focus'] = 'hip' if name.startswith('Nórdico') else 'nearHand' if name.startswith('Pino') else 'neck'
        if name == 'Dominadas':
            e.pop('variant', None)
            e['props'] = [p for p in e['props'] if p['type'] != 'backpack']
            # Oblique view separates both elbows; geometry/grips stay intact.
            e.setdefault('view', {})['yaw'] = 35
        return e
    if name == 'Colgarse de la barra':
        e = cp(existing['Dominadas']); e.pop('variant', None)
        e['name'] = name; e['group'] = 'Tirón'; e['focus'] = None
        e['props'] = [p for p in e['props'] if p['type'] != 'backpack']
        e['frames'] = [cp(e['frames'][0]), cp(e['frames'][0])]
        e['frames'][0]['caption'] = 'Colócate: manos en la barra, pies libres'
        e['frames'][1]['caption'] = 'Sostén y respira, sin balancearte'
        # Active shoulders lift the trunk while straight arms and bar stay
        # fixed; a local shoulder offset preserves the arm root in world space.
        for f in e['frames']:
            f['hip'] = (4, -32.2)
            f['shoulderOffset'] = (0, -1)
        e['annotations'] = [dict(joint='nearShoulder',text='Hombros ligeramente activos',corner='tl')]
        return e
    if name in {'Separaciones con banda','Elevaciones laterales con banda','Pallof press con banda','Face pull con banda','Remo con banda','Curl con banda','Extensión de tríceps sobre la cabeza con banda'}:
        return band(name)
    if name == 'Plancha lateral':
        angle = 14.5
        hip_y = -.9 - 28*math.sin(math.radians(angle)) - 3.3*math.cos(math.radians(angle))
        f = pose('Colócate: antebrazo bajo el hombro, pies apilados',(0,hip_y),-angle,
                 limb(180-angle,180-angle,foot=90-angle),limb(180-angle,180-angle,foot=90-angle),
                 arm(90,0,reach3=[9,10.58,0],pole=[0,1,0],end3=[1,0,0]),
                 arm(-90,-90,reach3=[0,-18.8,0],pole=[1,0,0],end3=[0,-1,0]))
        f['bodyRoll']=-90
        return basic(name,[f,dict(cp(f),caption='Sostén: hombros y cadera apilados, pelvis elevada')],group='Core',yaw=180)
    if name == 'Colgado pasivo':
        e=cp(existing['Dominadas']); e['name']=name; e.pop('variant',None); e['props']=[p for p in e['props'] if p['type']!='backpack']
        f=cp(e['frames'][0]); f['caption']='Cierra las manos sobre la barra y deja caer el peso'
        e['frames']=[f,dict(cp(f),caption='Respira sin balancearte; conserva el agarre')]; e['group']='Movilidad'
        return e
    if name == 'Elevación de piernas colgado':
        e=cp(existing['Dominadas']); e.pop('variant',None);e['name']=name;e['group']='Core'
        e['props']=[p for p in e['props'] if p['type']!='backpack'];e['focus']='hip'
        a=cp(e['frames'][0]);a['caption']='Manos en la barra, hombros activos, pies libres'
        b=cp(a);b['caption']='Eleva las piernas sin balancearte; manos fijas'
        for sd in ['near','far']:
            a[sd+'Leg']=limb(90,90,foot=0)
            b[sd+'Leg']=limb(0,0,foot=-90)
        e['frames']=[a,b,dict(cp(a),caption='Baja lentamente, sin balancear el cuerpo')]
        return e
    if name == 'Tuck-up':
        a=pose('Boca arriba: piernas alargadas',(0,-4),180,limb(-10,-10),limb(-10,-10),arm(0,0),arm(0,0))
        b=pose('Recoge rodillas y pecho sobre los glúteos',(0,-4),-130,limb(-80,20),limb(-80,20),arm(0,0),arm(0,0))
        return basic(name,[a,b,dict(cp(a),caption='Alarga de nuevo, sin dejar caer la espalda')],group='Core')
    if name == 'Flexiones':
        return basic(name,[plank(24,'Palmas y dedos de los pies apoyados, cuerpo recto'),plank(12,'Baja el pecho, sin dejar caer la cadera'),plank(24,'Empuja hasta estirar los brazos')],group='Empuje',focus='neck')
    if name in old and name != '90/90 de cadera':
        e = cp(old[name]); e['frames'] = [f for f in e['frames'] if not f.get('wrong')]
        if len(e['frames']) == 1:
            e['frames'].append(dict(cp(e['frames'][0]), caption='Sostén la postura y conserva los apoyos'))
        e['group'] = 'Movilidad' if name in {'Rotación torácica en cuatro apoyos','Movilidad de tobillo contra la pared','Estiramiento de flexor de cadera (caballero)','Colgado pasivo'} else 'Piernas' if name in {'Sentadilla búlgara','Sentadillas'} else 'Empuje' if name in {'Pike push-up','Flexiones'} else 'Core'
        if e['props']:
            e['props'] = [p for p in e['props'] if p.get('type') in {'wall','bar','sofa','cushion'}] + (bench(-24, -12.5) if name == 'Sentadilla búlgara' else [])
        for prop in e['props']:
            if prop.get('type') == 'wall':
                prop['top'] = prop.pop('y1', -62)
                prop.setdefault('thick', 2)
                prop.setdefault('depth', 16)
        if name == 'Movilidad de tobillo contra la pared':
            for prop in e['props']:
                if prop.get('type') == 'wall': prop['x'] = 25.5
        e['regions'] = []; e['view'] = dict(yaw=25, pitch=10)
        for f in e['frames']:
            if name == 'Hollow body hold':
                for sd in ['near','far']: f[sd+'Leg']['bend'] = -1
            for sd in ['near','far']:
                spec=f.get(sd+'Arm',{})
                if spec.get('reach',[None,None])[1] == 0: spec['reach'] = [spec['reach'][0], -.75]
                if name == 'Flexiones':
                    spec['hand']=0
                if name == 'Pike push-up': spec['pole'] = [1,-.2,.15 if sd=='near' else -.15]
                if name == 'Pike push-up':
                    f[sd+'Leg']['reach']=[f[sd+'Leg']['reach'][0],-1.75]

        e['focus'] = None if len(e['frames']) < 2 else 'hip'
        return e
    if name in {'Flexiones diamante','Flexión a una mano','Flexión arquero','Flexión pseudo-planche','Flexiones con pies elevados'}:
        variant = {'Flexiones diamante':'diamond','Flexión a una mano':'one','Flexión arquero':'archer','Flexión pseudo-planche':'pseudo'}.get(name)
        frames = [plank(24, 'Colócate: cuerpo alineado', variant=variant), plank(12, 'Baja el cuerpo de forma controlada', variant=variant), plank(24, 'Empuja y recupera la posición', variant=variant)]
        props = []
        if name == 'Flexiones con pies elevados':
            frames=[plank(24,'Dedos de los pies en el banco; cuerpo recto',toe_y=-8.6),plank(12,'Baja el pecho con las manos fijas',toe_y=-8.6),plank(24,'Empuja hasta estirar los brazos',toe_y=-8.6)]
            props=bench(-27,-8,10)
        return basic(name, frames, group='Empuje', props=props, yaw=45 if variant in {'one','archer','diamond'} else 20, focus='neck')
    if name == 'Inclinación de planche':
        frames = [plank(24,'Colócate: brazos extendidos'), plank(24,'Lleva los hombros por delante de las manos',variant='pseudo'), plank(24,'Vuelve sin doblar los codos')]
        return basic(name,frames,group='Habilidades',focus='neck')
    if name == 'Muñecas (planche)':
        frames = [pose('Manos en el suelo: dedos al frente',(0,-16),0,limb(90,180,foot=180),limb(90,180,foot=180),reach(18,-.75,hand=0),reach(18,-.75,hand=0)), pose('Avanza un poco; conserva la palma apoyada',(3,-16),0,limb(103,180,foot=180),limb(103,180,foot=180),reach(18,-.75,hand=0),reach(18,-.75,hand=0))]
        return basic(name,frames,group='Movilidad',focus='neck')
    if name == 'Tuck planche':
        f = pose('Brazos rectos: rodillas recogidas y pies libres',(0,-20.5),-8,limb(45,-140,foot=130),limb(45,-140,foot=130),reach(12,-5,hand=0),reach(12,-5,hand=0))
        return basic(name,[f,dict(cp(f),caption='Sostén con hombros adelantados sobre las manos')],group='Habilidades',props=[dict(type='parallettes')],yaw=30)
    if name == 'Rollout con toalla':
        first = pose('Rodillas apoyadas, manos sobre la toalla',(0,-16.4),-10,limb(90,180,foot=180),limb(90,180,foot=180),reach(18.8,-.75,hand=0),reach(18.8,-.75,hand=0))
        end = pose('Desliza las manos: espalda sin arquear',(13.52,-6.02),-15,limb(165,180,foot=180),limb(165,180,foot=180),reach(47,-.75,hand=0),reach(47,-.75,hand=0))
        finish = cp(first); finish['caption'] = 'Recoge el cuerpo usando el abdomen'
        return basic(name,[first,end,finish],group='Core',props=[dict(type='towel')],focus='nearHand')
    if name == 'Remo invertido (mesa)':
        def row(c,angle):
            r=math.radians(angle)
            hip=(19-28*math.cos(r),-17-28*math.sin(r))
            return pose(c,hip,180+angle,reach(19,-17,foot=-90),reach(19,-17,foot=-90),reach(-27,-35,grip='bar',hand=-90),reach(-27,-35,grip='bar',hand=-90))
        props = bench(-10,-35,34,12)+bench(20,-17,12,8)
        return basic(name,[row('Agarra el borde: cuerpo recto, talones en la silla',0),row('Lleva el pecho al borde, sin soltar las manos',15),row('Estira los brazos de nuevo',0)],group='Tirón',props=props,focus='neck',annotations=[dict(joint='nearHand',text='Agarre en el borde',corner='tl')])
    if name == 'Fondos en barra':
        def dip(c,h,angle):
            return pose(c,(2,h),angle,limb(80,160,foot=70),limb(80,160,foot=70),reach(4,-40,grip='bar_parallel'),reach(4,-40,grip='bar_parallel'))
        props=[tube([-8,-40,z],[16,-40,z],.8) for z in [-5,5]]
        props += [tube([x,-40,z],[x,0,z],.7) for x in [-8,16] for z in [-5,5]]
        return basic(name,[dip('Arriba: brazos rectos, pies libres',-39,-90),dip('Baja doblando los codos, manos fijas',-27,-80),dip('Empuja hasta estirar los brazos',-39,-90)],group='Empuje',props=props,focus='neck',annotations=[dict(joint='nearHand',text='Manos en las barras',corner='tl')])
    if name == 'Peso muerto a una pierna con mochila':
        first=pose('De pie: una pierna sostiene el peso',nl=limb(),fl=limb(80,140,foot=50))
        end=pose('Cadera atrás, pierna libre atrás, espalda larga',(0,-27),-12,reach(0,-1,foot=0),limb(180,180,foot=180),arm(80,80,hand=90),arm(80,80,hand=90))
        last=cp(first);last['caption']='Vuelve a erguirte sin girar la cadera'
        return basic(name,[first,end,last],group='Piernas',props=[dict(type='heldPack',single=True)],focus='hip')
    if name == 'Puente de glúteo a una pierna':
        def bridge(c,h):
            return pose(c,(0,h),-165,reach(20,-1,foot=0),limb(-40,-40,foot=0),arm(0,0,hand=0),arm(0,0,hand=0))
        return basic(name,[bridge('Boca arriba: un pie apoyado y la otra pierna elevada',-5),bridge('Eleva la cadera; conserva la pelvis nivelada',-15),bridge('Baja de forma controlada',-5)],group='Piernas',focus='hip')
    if name == 'Gemelos a una pierna en escalón':
        a=pose('Apoya el antepié en el borde del escalón',(0,-32),nl=limb(90,90,foot=0),fl=limb(60,160,foot=150))
        b=cp(a);b['hip']=(0,-36);b['nearLeg']['foot']=55;b['caption']='Eleva el talón, sin rebote'
        return basic(name,[a,b,dict(cp(a),caption='Baja el talón despacio')],group='Piernas',props=[box([5,-1.5,0],[10,3,20])],focus='nearAnkle')
    if name in {'Carga de maleta con mochila','Carga abrazada al pecho'}:
        a=pose('Colócate de pie: costillas sobre la pelvis')
        b=pose('Camina sin inclinarte hacia la carga',nl=limb(75,100),fl=limb(105,120))
        props=[dict(type='heldPack',single=True)]
        if name=='Carga abrazada al pecho':
            for f in [a,b]:
                f['nearArm']=reach(6,-37,hand=-90,grip='handle');f['farArm']=reach(6,-37,hand=-90,grip='handle')
            props=[dict(type='chestPack')]
        return basic(name,[a,b,dict(cp(a),caption='Conserva la misma postura en cada paso')],group='Piernas',props=props,focus=None,yaw=50)
    if name == 'Calentamiento tipo FIFA 11+':
        jogging=pose('1: Trote suave',(0,-27),-80,limb(-15,90),reach(0,-1,foot=0),arm(130,35),arm(-45,-110))
        opened=cp(jogging);opened['caption']='2: Abre la cadera con la rodilla elevada';opened['nearLeg'].update(reach3=[2,12,12],pole=[1,-1,1])
        lateral=squat('3: Desplázate de lado y gira con control',True)
        core=plank(24,'4: Plancha frontal')
        side=cp(generate('Plancha lateral')['frames'][0]);side['caption']='5: Plancha lateral, por ambos lados'
        nordic=cp(existing['Nórdico (isquios)']['frames'][1]);nordic['caption']='6: Nórdico suave';nordic['props']=cp(existing['Nórdico (isquios)']['props'])
        single=cp(generate('Progresión de pistol')['frames'][1]);single['caption']='7: Sentadilla a una pierna con apoyo'
        jump=squat('8: Saltos verticales cortos',jump=True)
        skate=cp(generate('Salto de patinador')['frames'][1]);skate['caption']='9: Saltos laterales cortos'
        run=cp(generate('Aceleración 10–20 m')['frames'][1]);run['caption']='10: Aceleraciones progresivas; luego cambia de dirección'
        return basic(name,[jogging,opened,lateral,core,side,nordic,single,jump,skate,run],group='Condición',yaw=30)
    if name in {'Salto vertical','Salto largo','Sentadilla con salto','Salto de patinador','Aceleración 10–20 m','Rodillas arriba','Burpees','Calentamiento tipo FIFA 11+'}:
        if name=='Burpees':
            crouch=pose('Lleva las manos al suelo',(-8,-9),-15,reach(0,-1,foot=0),reach(0,-1,foot=0),reach(13,-.75,hand=0),reach(13,-.75,hand=0))
            return basic(name,[squat('Colócate de pie'),crouch,plank(24,'Pasa a plancha'),dict(cp(crouch),caption='Recoge los pies junto a las manos'),squat('Salta y aterriza con control',jump=True)],group='Condición',focus='hip')
        if name in {'Aceleración 10–20 m','Rodillas arriba','Calentamiento tipo FIFA 11+'}:
            a=pose('Paso inicial: cadera estable',(0,-27),-80,limb(-15,90,foot=0),reach(0,-1,foot=0),arm(110,-20),arm(-40,80))
            b=pose('Alterna piernas y brazos',(0,-27),-80,reach(0,-1,foot=0),limb(-15,90,foot=0),arm(-40,80),arm(110,-20))
            title='Carrera suave: ejemplo de la primera parte, no el programa completo' if name=='Calentamiento tipo FIFA 11+' else 'Alterna piernas y brazos'
            a['caption']=title
            if name == 'Aceleración 10–20 m':
                a['torso']=-65;b['torso']=-65;b['hip']=(4,-27)
                a['nearArm']=arm(125,35);a['farArm']=arm(60,-30)
                b['nearArm']=arm(60,-30);b['farArm']=arm(125,35)
                a['caption']='Inclínate desde los tobillos e inicia la carrera'
                b['caption']='Avanza: brazo contrario a la pierna'
            else:
                a['torso']=-90;b['torso']=-90
                a['caption']='Torso vertical: sube una rodilla hacia la cadera'
                b['caption']='Alterna la rodilla manteniéndote en el sitio'
            return basic(name,[a,b,dict(cp(a),caption='Continúa alternando con control')],group='Condición',yaw=35,focus=None)
        if name=='Salto largo':
            a=squat('Flexiona cadera y rodillas; brazos atrás',True)
            a['nearArm']=arm(140,140);a['farArm']=arm(140,140)
            b=pose('Impúlsate hacia delante con ambos pies',(20,-32),-50,limb(45,20,foot=25),limb(45,20,foot=25),arm(-15,-15),arm(-15,-15))
            c=squat('Aterriza más adelante: flexiona ambas rodillas',True,x=36)
            return basic(name,[a,b,c],group='Condición',focus='hip')
        if name=='Salto de patinador':
            a=squat('Apoya una pierna, la otra queda libre',True)
            a['farLeg']=limb(140,80,foot=-10)
            b=cp(a);b['nearLeg'],b['farLeg']=cp(a['farLeg']),cp(a['nearLeg']);b['caption']='Salta al otro lado; aterriza sobre la otra pierna'
            a['nearLeg'].update(reach3=[0,16,6],pole=[1,0,0]);b['farLeg'].update(reach3=[0,16,-6],pole=[1,0,0])
            return basic(name,[a,b,dict(cp(a),caption='Estabiliza antes del siguiente salto')],group='Condición',yaw=80,focus=None)
        travel=18 if name=='Salto largo' else 0
        return basic(name,[squat('Flexiona cadera y rodillas',True),squat('Impúlsate con ambos pies',jump=True,x=travel/2),squat('Aterriza suave y estabiliza',True,x=travel)],group='Condición',focus='hip')
    if name in {'Elevaciones en pike sentado','Elevaciones en straddle','Barca / V-sit','L-sit'}:
        if name=='L-sit':
            a=pose('Manos en las paralelas: brazos estirados',(0,-6),-90,limb(0,0),limb(0,0),arm(90,90,hand=0),arm(90,90,hand=0))
            return basic(name,[a,dict(cp(a),caption='Sostén las piernas rectas, sin encoger los hombros')],group='Habilidades',props=[dict(type='parallettes')],yaw=25,focus=None)
        wide=name=='Elevaciones en straddle'
        a=seated('Siéntate: manos al lado de los muslos',0,wide)
        b=seated('Eleva las piernas sin impulsarte',-20,wide)
        if name=='Barca / V-sit':
            a=pose('Entrada: sentado, piernas delante y brazos libres',(0,-5),-105,limb(0,0),limb(0,0),arm(-20,-20),arm(-20,-20))
            b=pose('Sostén: equilibrio sobre glúteos, brazos libres; respira',(0,-5),-120,limb(-35,-35),limb(-35,-35),arm(-20,-20),arm(-20,-20))
            return basic(name,[a,b,dict(cp(a),caption='Salida: baja las piernas con control')],group='Core',yaw=15,focus=None)
        return basic(name,[a,b,dict(cp(a),caption='Baja lentamente; las manos permanecen firmes')],group='Core',yaw=50 if wide else 15,focus=None)
    if name in {'Hollow rocks','Plancha inversa con patada','Progresión de pistol','Toes-to-bar'}:
        if name=='Toes-to-bar':
            e=cp(existing['Dominadas']);e['name']=name;e['group']='Core';e.pop('variant',None);e['props']=[p for p in e['props'] if p['type']!='backpack']
            e['frames']=[cp(e['frames'][0]) for _ in range(3)]
            for i,f in enumerate(e['frames']):
                f['caption']=['Colgado: hombros activos','Eleva las piernas, sin balancearte','Lleva los pies hacia la barra'][i]
                for sd in ('near','far'):
                    f[sd+'Leg']=limb(90-i*80,90-i*80,foot=0)
            end=e['frames'][-1];end['hip']=(18,-39);end['torso']=-145
            for sd in ['near','far']: end[sd+'Leg']=reach(4,-63,foot=-90,bend=-1)
            return e
        if name=='Hollow rocks':
            e=cp(old['Hollow body hold']);e['name']=name;e['group']='Core';e['regions']=[];e['view']=dict(yaw=10,pitch=5)
            source=[f for f in e['frames'] if not f.get('wrong')][-1]
            for sd in ['near','far']: source[sd+'Leg']['bend']=-1
            base,_=legacy.export_frame(source)
            e['frames']=[]
            for angle,caption in [(-6,'Balancea hacia los hombros, conserva la forma'),(6,'Balancea hacia la pelvis, sin doblar la cadera'),(-6,'Vuelve en bloque, no te impulses con las piernas')]:
                f=dict(caption=caption,hip=(8*math.cos(math.radians(angle))-8,-3+8*math.sin(math.radians(angle))),torso=base['torso']+angle)
                for key,spec in base['limbs'].items():
                    f[key]=dict(angles=[a+angle for a in spec['angles']],**{('foot' if 'Leg' in key else 'hand'):spec.get('foot',spec.get('hand',0))+angle})
                e['frames'].append(f)
            return e
        if name=='Progresión de pistol':
            a=pose('Una pierna de apoyo; otra al frente',nl=limb(),fl=limb(0,0),na=arm(0,0),fa=arm(0,0))
            b=pose('Baja sobre la pierna de apoyo; usa ayuda si la necesitas',(-10,-15),-65,reach(0,-1,foot=0),limb(0,0),arm(0,0),arm(0,0))
            return basic(name,[a,b,dict(cp(a),caption='Empuja el suelo y vuelve a subir')],group='Piernas',focus='hip')
        # Brazos rectos con manos fijas; no recortar un alcance imposible.
        lo,hi=0.0,40.0
        for _ in range(40):
            mid=(lo+hi)/2;r=math.radians(mid)
            dist=math.hypot(47-46*math.cos(r),46*math.sin(r)+.25)
            if dist>18.99:hi=mid
            else:lo=mid
        r=math.radians((lo+hi)/2)
        hip=(27-28*math.cos(r),-1-28*math.sin(r))
        a=pose('Palmas detrás, brazos rectos, pelvis elevada',hip,180+math.degrees(r),reach(27,-1,foot=-90),reach(27,-1,foot=-90),reach(-20,-.75,hand=180),reach(-20,-.75,hand=180))
        b=cp(a);b['farLeg']=limb(-20,-20,foot=-110);b['caption']='Eleva una pierna; manos y talón de apoyo no se mueven'
        return basic(name,[a,b,dict(cp(a),caption='Apoya la pierna y alterna')],group='Core',focus='hip')
    if name in {'Escaladores','Vela','Negativo de dragon flag recogido','Negativo de dragon flag a una pierna','Negativo de dragon flag','Dragon flag','V-up a una pierna','V-up','V-up con bajada lenta'}:
        if name=='Escaladores':
            a=plank(24,'Colócate en plancha: hombros sobre manos');b=cp(a)
            b['nearLeg']=limb(-25,110,foot=0);b['caption']='Lleva una rodilla hacia el pecho, sin levantar la cadera'
            c=cp(a);c['farLeg']=limb(-25,110,foot=0);c['caption']='Alterna la rodilla, manos fijas'
            return basic(name,[a,b,c],group='Condición',focus=None)
        if name.startswith('V-up'):
            a=supine('Boca arriba: brazos y piernas alargados',[limb(0,0),limb(0,0)],arms=arm(180,180,hand=180))
            b=pose('Acerca el torso y las piernas en una V',(0,-5),-135,limb(-40,-40),limb(0,0) if name=='V-up a una pierna' else limb(-40,-40),arm(-30,-30),arm(-30,-30))
            return basic(name,[a,b,dict(cp(a),caption='Baja de forma controlada, sin dejar caer la espalda')],group='Core',focus=None)
        bent=name=='Negativo de dragon flag recogido'
        single=name=='Negativo de dragon flag a una pierna'
        def dragon(c,angle):
            pivot=(-18,-4)
            hip=(pivot[0]+18*math.cos(math.radians(angle)),pivot[1]-18*math.sin(math.radians(angle)))
            legs=limb(-angle,45 if bent else -angle,foot=-45 if bent else -angle)
            far=limb(-angle,45 if single or bent else -angle,foot=-45 if single or bent else -angle)
            f=pose(c,hip,180-angle,legs,far,reach(-31,-9,grip='bar',hand=180),reach(-31,-9,grip='bar',hand=180))
            f['gaze']=angle  # Cabeza horizontal: los hombros pivotan, la cabeza no.
            return f
        if name=='Vela':
            a=supine('Boca arriba: recoge las rodillas',[limb(-60,60),limb(-60,60)])
            b=dragon('Sube la pelvis; el peso va en hombros, no en el cuello',80)
            for sd in ['near','far']: a[sd+'Arm']=reach(-31,-9,grip='bar',hand=180)
            a['hip']=(0,-4)
            e=basic(name,[a,b,dict(cp(a),caption='Desenrolla la espalda despacio')],group='Core',props=[tube([-31,-9,-10],[-31,-9,10])]+[tube([-31,-9,z],[-31,0,z]) for z in [-10,10]]+[box([-3,-.5,0],[62,1,20]),box([-14.5,-1.8,0],[11,1.6,16])],focus='hip',yaw=-35,annotations=[dict(joint='nearShoulder',text='Hombros en la colchoneta',corner='br'),dict(joint='nearHand',text='Sujeción detrás de la cabeza',corner='tl')])
            e['pivot']=(-18,-4);return e
        e=basic(name,[dragon('Hombros apoyados y manos sujetas detrás',75),dragon('Baja en bloque, sin arquear la zona lumbar',40),dragon('Detén el descenso antes de perder la línea',15)],group='Core',props=[tube([-31,-9,-10],[-31,-9,10])]+[tube([-31,-9,z],[-31,0,z]) for z in [-10,10]]+[box([-3,-.5,0],[62,1,20]),box([-14.5,-1.8,0],[11,1.6,16])],focus='hip',yaw=-35,annotations=[dict(joint='nearShoulder',text='Hombros en la colchoneta',corner='br'),dict(joint='nearHand',text='Sujeción detrás de la cabeza',corner='tl')])
        e['pivot']=(-18,-4);return e
    if name in {'Rodillas al pecho','Isquios con banda','Glúteo en figura 4','Flexor de cadera de rodillas','Cuádriceps','Gemelo contra la pared','Piernas en la pared','90/90 de cadera'}:
        if name=='Flexor de cadera de rodillas':
            e=cp(old['Estiramiento de flexor de cadera (caballero)']);e['name']=name;e['group']='Movilidad';e['regions']=[];e['view']=dict(yaw=25,pitch=10)
            return e
        if name=='90/90 de cadera':
            a=pose('Sentado: una rodilla delante y otra al lado',(0,-4),-75,limb(0,90),limb(180,90),reach(10,-3.5,hand=0),reach(1.8,-3.5,hand=0))
            a['nearLeg'].update(reach3=[14,2.5,-14],pole=[1,0,0],end3=[0,0,-1])
            a['farLeg'].update(reach3=[-14,2.5,-14],pole=[0,0,-1],end3=[-1,0,0])
            b=cp(a);b['caption']='Inclina el torso hacia la pierna de delante, sin forzar'
            b['torso']=-60
            c=cp(a);c['caption']='Gira ambas rodillas al otro lado, sin levantar los glúteos'
            c['nearLeg']['reach3']=[14,2.5,14];c['farLeg']['reach3']=[-14,2.5,14]
            c['nearLeg']['end3']=[0,0,1];c['farLeg']['pole']=[0,0,1]
            e=basic(name,[a,b,c],group='Movilidad',yaw=65,focus=None);e['view']['pitch']=50
            return e
        if name=='Rodillas al pecho':
            a=supine('Boca arriba: rodillas dobladas',[limb(-70,90),limb(-70,90)])
            b=supine('Abraza las rodillas y respira despacio',[limb(-130,30),limb(-130,30)])
            knee=flat.solve(b)['joints']['nearKnee']
            b['nearArm']=reach(*knee,hand=90,grip='handle',bend=-1);b['farArm']=reach(*knee,hand=90,grip='handle',bend=-1)
            return basic(name,[a,b],group='Movilidad',focus=None)
        if name=='Isquios con banda':
            a=supine('Boca arriba: banda en la planta de un pie',[limb(-55,-55),limb(0,0)],arms=arm(-20,-20))
            b=supine('Eleva la pierna estirada con tensión suave',[limb(-80,-80),limb(0,0)],arms=arm(-20,-20))
            return basic(name,[a,b],group='Movilidad',props=[dict(type='band',a='nearToe',b='nearHand')],focus=None)
        if name=='Glúteo en figura 4':
            a=supine('Cruza el tobillo sobre la rodilla opuesta',[limb(-45,130),limb(-60,80)])
            a['nearLeg'].update(reach3=[7,-12.12,-6.6],pole=[0,0,1],end3=[0,0,-1])
            b=cp(a);b['caption']='Acerca la pierna de apoyo al pecho, pelvis apoyada';b['farLeg']=limb(-95,60,foot=0)
            b['nearLeg']['reach3']=[-1.22,-13.95,-6.6]
            b['nearArm']=reach(-3,-13,hand=90,bend=-1);b['farArm']=reach(-3,-13,hand=90,bend=-1)
            e=basic(name,[a,b],group='Movilidad',yaw=-35,focus=None);e['view']['pitch']=50
            return e
        if name=='Cuádriceps':
            a=pose('Busca apoyo; sujeta el tobillo con la otra mano',torso=-100,nl=limb(90,-105,foot=165),fl=limb(),na=reach(-3.1,-28,hand=90,grip='hold'),fa=reach(17,-43,hand=-90))
            b=cp(a);b['caption']='Talón hacia glúteo: la rodilla sigue hacia el suelo'
            return basic(name,[a,b],group='Movilidad',yaw=-25,props=[dict(type='wall',x=18,top=-62,depth=12,thick=2)],focus=None,annotations=[dict(joint='nearAnkle',text='Talón hacia el glúteo',corner='bl'),dict(joint='nearKnee',text='Rodilla hacia abajo',corner='tr')])
        if name=='Gemelo contra la pared':
            a=pose('Manos en la pared: una pierna queda detrás',(-12,-26),-75,reach(-20,-1,foot=0),reach(0,-1,foot=0),reach(12,-40,hand=-90),reach(12,-40,hand=-90))
            b=cp(a);b['caption']='Acerca el pecho; el talón trasero no se despega';b['torso']=-65
            return basic(name,[a,b],group='Movilidad',props=[dict(type='wall',x=13,top=-64,depth=12,thick=2)],focus=None)
        a=supine('Glúteos cerca de la pared, espalda en el suelo',[limb(-90,-90,foot=180),limb(-90,-90,foot=180)])
        b=cp(a);b['caption']='Apoya las piernas en la pared y respira'
        return basic(name,[a,b],group='Movilidad',props=[dict(type='wall',x=2,top=-48,depth=12,thick=2)],focus=None)
    raise ValueError('Falta especificación explícita: '+name)


def phase(label, *, kind='interpolate', ground='preserve', contacts=(), part='', seconds=2.4):
    return dict(label=label, kind=kind, ground=ground, contacts=list(contacts), part=part, seconds=seconds)


def generate(name):
    """Opt-in authored timelines; unselected legacy specifications stay intact."""
    e = _generate_base(name)
    if name == 'Barca / V-sit':
        a,b,c = e['frames']
        e['frames'] = [a,b,cp(b),c]
        e['motion'] = [phase('Entrada'),phase('Sostén y respira',kind='hold',seconds=3),phase('Salida')]
    elif name == '90/90 de cadera':
        a,b,c = e['frames']
        # Transfer through knees-up, rather than linear interpolation of
        # opposite poles (which goes through the zero vector).
        middle = cp(a); middle['caption'] = 'Cambio de lado: rodillas arriba, pelvis apoyada'
        for sd,sign in [('near',1),('far',-1)]:
            middle[sd+'Leg'].update(reach3=[sign*14,2.5,0],pole=[0,-1,0],end3=[sign,0,0])
        c['caption']='Otro lado: ambas rodillas hacia el suelo, sin forzar'
        finish=cp(c);finish['torso']=-60;finish['caption']='Inclina el torso hacia la otra pierna'
        e['frames']=[a,b,cp(a),middle,c,finish,cp(c),cp(middle),cp(a)]
        e['motion']=[phase(label, contacts=['hip']) for label in
                     ['Inclina','Vuelve al centro','Eleva las rodillas','Cambia de lado',
                      'Inclina al otro lado','Vuelve al centro','Eleva las rodillas','Regresa']]
    elif name == 'Aceleración 10–20 m':
        # One stride in world coordinates. Grounded toes retain their world
        # anchors; the next stride starts through an explicit reset cut.
        frames=[]
        for x,sd,caption in [(0,'near','Apoyo: brazo contrario a la pierna'),
                             (4,'near','Impulsa el cuerpo hacia delante'),
                             (8,'far','Cambia el apoyo; la otra pierna avanza'),
                             (12,'far','Impulsa con la otra pierna')]:
            f=pose(caption,(x,-26),-65,nl=limb(30,130),fl=limb(30,130),
                   na=arm(125,35),fa=arm(60,-30))
            f[sd+'Leg']=reach(0 if sd=='near' else 10,-1,foot=0)
            if sd=='far':f['nearArm'],f['farArm']=f['farArm'],f['nearArm']
            frames.append(f)
        frames.append(cp(frames[0]));frames[-1]['caption']='Nuevo tramo: vuelve a la salida de la demostración'
        e['frames']=frames
        e['motion']=[phase('Primer impulso',contacts=['nearAnkle']),
                     phase('Cambio de apoyo'),phase('Impulso con la otra pierna',contacts=['farAnkle']),
                     phase('Nuevo tramo',kind='cut',seconds=.8)]
    elif name == 'Burpees':
        standing,crouch,plank_frame,collect,jump=e['frames']
        for f in (crouch,collect):
            f['nearArm']=reach(16.4,-.75,hand=0)
            f['farArm']=reach(16.4,-.75,hand=0)
        jump['caption']='Vuelo: manos y pies libres'
        landing=squat('Aterriza: flexiona cadera y rodillas',True)
        e['frames']=[standing,crouch,plank_frame,collect,standing,jump,landing,cp(standing)]
        e['motion']=[phase('Manos al suelo'),phase('Extiende las piernas',contacts=['nearHand','farHand']),
                     phase('Recoge los pies',contacts=['nearHand','farHand']),phase('Prepárate para saltar'),
                     phase('Despegue',ground='flight'),phase('Aterrizaje',ground='flight'),phase('Vuelve de pie')]
    elif name == 'Calentamiento tipo FIFA 11+':
        # Ten named parts, each animated within its own exercise. A cut is
        # an announced change of task, never a morph between unrelated bodies.
        originals=e['frames']
        preparation = generate('Burpees')['frames']
        plank_part = basic('Plancha frontal',
                           [cp(preparation[1]),cp(preparation[2]),cp(preparation[2]),cp(preparation[1])],
                           group='Core')
        plank_part['frames'][0]['caption']='Entrada: manos al suelo'
        plank_part['frames'][1]['caption']='Plancha: cuerpo alineado, manos y pies apoyados'
        plank_part['frames'][2]['caption']='Sostén: respira sin perder los apoyos'
        plank_part['frames'][3]['caption']='Salida: recoge los pies'
        plank_part['motion']=[phase('Entra a la plancha',contacts=['nearHand','farHand']),
                              phase('Sostén la plancha',kind='hold',seconds=3),
                              phase('Sal de la plancha',contacts=['nearHand','farHand'])]
        side_part=generate('Plancha lateral')
        side_part['motion']=[phase('Sostén lateral',kind='hold',seconds=3)
                             for _ in side_part['frames'][1:]]
        def lateral_step(z, near_z, near_y, far_z, far_y, caption):
            f=pose(caption,(0,-24),-80,na=arm(-20,-20),fa=arm(-20,-20))
            f['bodyZ']=z
            for sd,sign,foot_z,foot_y in [('near',1,near_z,near_y),('far',-1,far_z,far_y)]:
                f[sd+'Leg'].update(reach3=[0,foot_y+24,foot_z-z-sign*3.3],pole=[1,0,0],end3=[1,0,0])
            return f
        outward=[
            lateral_step(0,3.3,-1,-3.3,-1,'Prepara el paso lateral'),
            lateral_step(1,7.3,-5,-3.3,-1,'Despega el pie que abre el paso'),
            lateral_step(3,11.3,-1,-3.3,-1,'Apoya más al lado sin cruzar los pies'),
            lateral_step(6,11.3,-1,-3.3,-1,'Transfiere el peso con ambos pies apoyados'),
            lateral_step(7,11.3,-1,.7,-5,'Despega el pie que sigue'),
            lateral_step(8,11.3,-1,4.7,-1,'Junta la base sin cruzar los pies'),
        ]
        supports=[['farAnkle'],['farAnkle'],['nearAnkle','farAnkle'],['nearAnkle'],['nearAnkle']]
        step_part=basic('Paso lateral',[*outward,cp(outward[-1]),*[cp(f) for f in reversed(outward[:-1])]],group='Condición')
        step_part['motion']=([phase('Paso lateral: '+outward[i+1]['caption'],contacts=s) for i,s in enumerate(supports)]
                             +[phase('Cambia de dirección con control',kind='hold',seconds=1)]
                             +[phase('Regresa de lado',contacts=s) for s in reversed(supports)])
        def lateral_landing(side, z, caption):
            f=pose(caption,(0,-17),-75,nl=limb(90,90,foot=0),fl=limb(90,90,foot=0),
                   na=arm(40,-20),fa=arm(135,40))
            f['bodyZ']=z
            for sd,sign in [('near',1),('far',-1)]:
                target=[0,16,sign*6] if sd==side else [-10,10,sign*2]
                f[sd+'Leg'].update(reach3=target,pole=[1,0,0],end3=[1,0,0])
            return f
        right=lateral_landing('near',6,'Apoyo en una pierna: la otra queda libre')
        left=lateral_landing('far',-6,'Aterriza al otro lado sobre la otra pierna')
        airborne=cp(right);airborne['hip']=(0,-27);airborne['bodyZ']=0
        airborne['caption']='Vuelo lateral: ambos pies libres, cadera viaja al otro lado'
        airborne['nearLeg']['reach3']=[0,16,3]
        airborne['farLeg']['reach3']=[-4,14,-3]
        back_airborne=cp(airborne)
        back_airborne['nearLeg']['reach3']=[-4,14,3]
        back_airborne['farLeg']['reach3']=[0,16,-3]
        back_airborne['caption']='Salta de regreso: ambos pies libres'
        skate_part=basic('Salto lateral corto',[right,airborne,left,back_airborne,cp(right)],group='Condición')
        skate_part['motion']=[phase(label,ground='flight') for label in
                              ['Impulsa hacia el otro lado','Aterriza con control',
                               'Impulsa de regreso','Estabiliza el apoyo']]
        part_specs=[generate('Aceleración 10–20 m'), None, step_part,
                    plank_part, side_part,
                    generate('Nórdico (isquios)'), generate('Progresión de pistol'),
                    generate('Sentadilla con salto'), skate_part,
                    generate('Aceleración 10–20 m')]
        frames=[];motions=[]
        for i,spec in enumerate(part_specs):
            title=originals[i]['caption']
            if spec is None:
                start=cp(originals[i]);end=cp(start)
                if i==1:
                    start['nearLeg'].update(reach3=[14,0,0],pole=[1,-1,0])
                    end['nearLeg'].update(reach3=[8,0,12],pole=[1,-1,1])
                spec=basic(title,[start,end,cp(start)],group='Condición')
            fs=cp(spec['frames'])
            # Skip a running demonstration's reset; next part owns its cut.
            ms=cp(spec.get('motion', [phase('Recorrido') for _ in fs[1:]]))
            if i in (7,8):
                for p in ms: p['ground']='flight'
            if spec.get('pivot'):
                for p in ms: p['pivot']=list(spec['pivot'])
            if ms and ms[-1]['kind']=='cut': fs.pop();ms.pop()
            for f in fs:
                f['caption']=title+' · '+f['caption'];f['props']=cp(spec['props'])
            if frames:motions.append(phase('Siguiente parte: '+title,kind='cut',part=str(i+1),seconds=1))
            frames.extend(fs)
            motions.extend([dict(p,part=str(i+1)) for p in ms])
        e['frames']=frames;e['motion']=motions
        e['frames'].append(cp(frames[0]))
        e['motion'].append(phase('Reiniciar recorrido: parte 1',kind='cut',part='1',seconds=1))
    elif name == 'Vela':
        a,b,c=e['frames'];e['frames']=[a,b,cp(b),c]
        e['motion']=[phase('Entrada a la vertical'),phase('Sostén vertical',kind='hold',seconds=3),phase('Salida controlada')]
    elif 'dragon flag' in name.lower():
        e['motion']=[phase('Desciende en bloque') for _ in e['frames'][1:]]
        if name=='Dragon flag':
            e['frames'] += [cp(e['frames'][1]),cp(e['frames'][0])]
            e['motion'] += [phase('Sube en bloque'),phase('Vuelve a la vertical')]
        else:
            e['frames'].append(cp(e['frames'][0]))
            e['motion'].append(phase('Preparación de otro descenso',kind='cut',seconds=1))
    if 'motion' in e:
        assert len(e['motion']) == len(e['frames'])-1, name
    return e


def export(ex):
    for prop in list(ex['props']):
        if prop.get('type') == 'band' and isinstance(prop.get('a'), list):
            x,y,z=prop['a'];ex['props'].append(box([x,y/2,z],[2,-y,2]))
    out, projection_warnings = legacy.build(ex)
    # El chequeo legado sólo ve XY: los alcances/frontales/roll se validan
    # contra el cuerpo real 3D en illustration_geometry_test y audit_test.
    per_side = ex['name'] == 'Balanceos de pierna' or any(word in ex['name'].lower() for word in ['una pierna','una mano','búlgara','pistol','plancha lateral','maleta','pallof','caballero','90/90','rotación torácica','tobillo','cuádriceps','gemelo contra','isquios con','figura 4','flexor de cadera de'])
    out['perSide'] = per_side
    out['annotations'] = ex.get('annotations',[])
    if 'motion' in ex:
        out['motion'] = ex['motion']
    out.update(continuous=ex['name'] not in {'90/90 de cadera','Hollow body hold','Calentamiento tipo FIFA 11+','Salto vertical','Salto largo','Salto de patinador','Aceleración 10–20 m','Rodillas arriba','Burpees','Sentadilla con salto'},group=ex.get('group','Otros'),focus=ex.get('focus'),source=ex.get('source','guía local; revisión candidata'))
    if 'motion' in ex: out['continuous'] = True
    for raw, target in zip(ex['frames'],out['frames']):
        for key in ['bodyZ','bodyRoll','props']:
            if key in raw: target[key] = raw[key]
        for name in ('nearArm','farArm','nearLeg','farLeg'):
            spec=raw.get(name)
            if spec:
                target['limbs'][name].update({k:spec[k] for k in ('depth','pole','end3','reach3','keepReachRadius','planarAngles') if k in spec})
                if 'reach3' in spec: target['limbs'][name].pop('pin',None)
                if 'angles' in spec:
                    delta=math.sin(math.radians(spec['angles'][1]-spec['angles'][0]))
                    target['limbs'][name]['bend'] = -1 if delta >= 0 else 1
    return out


def main():
    names=reference_names()
    specs=[generate(name) for name in names]
    details=(ROOT/'lib/data/exercise_details.dart').read_text(encoding='utf-8')
    muscles=dict(re.findall(r"^  '([^']+)': ExerciseDetail\(\s*muscles: '([^']+)'",details,re.M))
    for e in specs:
        e['muscles']=muscles.get(e['name'],e.get('muscles',''))
    figures=[export(e) for e in specs]
    consts={'T':flat.T,'UA':flat.UA,'FA':flat.FA,'TH':flat.TH,'SH':flat.SH,'FT':flat.FT,'HEAD_OFF':flat.HEAD_OFF,'HEAD_R':flat.HEAD_R}
    target=ROOT/'assets/tecnica/figuras3d.json'
    target.write_text(json.dumps(dict(version=2,consts=consts,figures=flat._round(figures)),ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    print(f'{len(figures)} figuras con especificación propia → {target}')


if __name__=='__main__':
    main()
