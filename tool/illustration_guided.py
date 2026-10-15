"""Plan v3.2 guided poses, using the shared catalog rig and renderer.

Names and physical choices are explicit. A guide progression is never selected
from load/repetitions. Geometry units are illustrative, not user measurements.
"""
from copy import deepcopy as cp
import math

NAMES = '''Respiración 90/90|Gato-camello|Libro abierto|Muñecas a cuatro patas|Deslizamientos en la pared|Zancada del mundo|Rodilla a la pared|Sentadilla profunda|Pie corto|Pike sentado|Pancake|Dorsal en la cama|Pectoral en el marco de la puerta|Sóleo en la pared|Scap pull-up|Y-T prono|Abducción de cadera de lado|Copenhague|Sóleo sentado con mochila|Tibial en la pared|Rotación externa con banda|Support hold en paralelas|Sprint lanzado|Intervalos 15/15|Sentadilla isométrica en la pared|Nórdico inverso|Bajada lateral del escalón|Aterrizaje clavado|Mesa invertida|Plancha inversa sobre antebrazos|Plancha inversa sobre las manos|Plancha inversa a una pierna|Plancha inversa con pies elevados'''.split('|')
VARIANTS = {
    'Tibial en la pared': ('tibialis_wall_close', 'tibialis_wall_far', 'tibialis_wall_loaded'),
    'Y-T prono': ('prone_y_t_floor', 'prone_y_t_bed_edge', 'prone_y_t_loaded'),
    'Copenhague': ('copenhagen_short', 'copenhagen_long'),
    'Sóleo sentado con mochila': ('seated_soleus_bilateral', 'seated_soleus_unilateral'),
    'Support hold en paralelas': ('support_parallels', 'support_rings', 'support_protraction'),
    'Rotación externa con banda': ('band_rotation_side', 'band_rotation_90_90'),
    'Aterrizaje clavado': ('landing_bilateral', 'landing_unilateral', 'landing_lateral'),
}


def generate(name, variant=None):
    from illustration_catalog import pose, limb, arm, reach, basic, phase, box, bench, tube, squat, generate as existing

    def result(frames, motions=None, props=None, yaw=35, pitch=12, per_side=False, **extra):
        # A world ankle target does not define the sole angle. Guided floor
        # supports explicitly keep the foot horizontal unless authored otherwise.
        for frame in frames:
            for side in ['nearLeg', 'farLeg']:
                if 'reach' in frame[side]: frame[side].setdefault('foot', 0)
        e = basic(name, frames, group='Plan v3.2', props=props, yaw=yaw)
        e['view']['pitch'] = pitch
        e['source'] = 'Plan v3.2 §19.14/19.15/19.17 y contrato034; guion específico'
        e['perSide'] = per_side
        e['motion'] = motions or [phase('Recorrido controlado') for _ in frames[1:]]
        e.update(extra)
        return e

    def cycle(a, b, *, contacts=(), hold=2, **kwargs):
        finish = cp(a); finish['caption'] = 'Regresa con control · '+a['caption']
        return result([a, b, cp(b), finish],
                      [phase(b['caption'], contacts=contacts), phase('Sostén y respira', kind='hold', seconds=hold),
                       phase('Regresa con control', contacts=contacts)], **kwargs)

    def quadruped(caption, torso=-13.3):
        return pose(caption, (0, -15.6), torso, limb(90, 180, foot=180), limb(90, 180, foot=180),
                    reach(17.5, -.75, hand=0), reach(17.5, -.75, hand=0))

    if name == 'Respiración 90/90':
        a = pose('Pantorrillas sobre la cama; cadera y rodillas a 90°', (0, -4.5), 180,
                 limb(-90, 0), limb(-90, 0), arm(0, 0), arm(0, 0))
        b = cp(a); b.update(caption='Inhala: barriga y costados se expanden suavemente', breath=.35)
        c = cp(a); c['caption'] = 'Exhala: deja bajar las costillas'
        return result([a, b, c, cp(a)],
                      [phase('Inhala', seconds=4), phase('Exhala', seconds=6), phase('Reposo', kind='hold', seconds=1)],
                      props=bench(10, -17.2, width=25, depth=12), yaw=15)
    if name == 'Gato-camello':
        a = quadruped('Manos bajo hombros; rodillas bajo cadera')
        b = cp(a); b.update(caption='Exhala: redondea desde pelvis hacia cabeza', spineBend=-1.2, gaze=25)
        c = cp(a); c.update(caption='Inhala: abre el pecho sin mover los apoyos', spineBend=1.2, gaze=-20)
        contacts = ['nearHand', 'farHand', 'nearKnee', 'farKnee']
        return result([a, b, cp(b), c, cp(c), cp(a)],
                      [phase('Redondea', contacts=contacts), phase('Pausa redondeado', kind='hold', seconds=3),
                       phase('Extiende suavemente', contacts=contacts), phase('Pausa abierto', kind='hold', seconds=3),
                       phase('Vuelve a neutro', contacts=contacts)], yaw=10)
    if name == 'Libro abierto':
        # 052: de lado (bodyRoll 90: pecho a la cámara, lado cercano abajo),
        # rodillas juntas a 90° y brazos al frente. El brazo de arriba barre por
        # arriba hasta el suelo del otro lado mientras el pecho gira; la mirada
        # lo sigue. Cadera, rodillas y pies se quedan en su sitio.
        hip = (0, -5)
        def side(roll, k, caption):
            th = math.radians(roll)
            f = pose(caption, hip, 180)
            f['bodyRoll'] = roll
            def root(half):   # raíz rodada alrededor del eje del tronco (-x)
                return (0, hip[1] + half*math.sin(th), half*math.cos(th))
            for sd, sign, ky in [('near', 1, -1.7), ('far', -1, -6.7)]:
                r = root(sign*3.3)
                kz = r[2] + math.sqrt(max(0, 14**2 - (ky - r[1])**2))
                ankle = (14, ky, kz)
                f[sd+'Leg'].update(reach3=[ankle[0]-r[0], ankle[1]-r[1], ankle[2]-r[2]],
                                   pole=[0, ky-r[1], kz-r[2]], end3=[1, 0, .3])
            def shoulder(half):
                r = root(half); return (-18, r[1], r[2])
            ns = shoulder(4.5)
            f['nearArm'].update(reach3=[0, -.75-ns[1], 18.9-ns[2]], pole=[0, -1, 0], end3=[0, 0, 1])
            fs = shoulder(-4.5)
            start = (0, -2.6-fs[1], 17.6-fs[2])
            # Barrido por arriba: al frente → techo → suelo del otro lado.
            reach_floor = math.sqrt(max(0, 18.9**2 - (-.9-fs[1])**2))
            path = [start, (0, -18.9, 0), (0, -.9-fs[1], -reach_floor)]
            seg = min(1, int(k*2)); w = k*2 - seg
            a0, a1 = path[seg], path[min(2, seg+1)]
            v = [a0[i]*(1-w) + a1[i]*w for i in range(3)]
            n = math.sqrt(sum(c*c for c in v)); L = math.sqrt(sum(c*c for c in a0))*(1-w) + math.sqrt(sum(c*c for c in a1))*w
            f['farArm'].update(reach3=[c*L/n for c in v], pole=[1, -.3, 0], end3=[0, 0, 1] if k < .5 else [0, 0, -1])
            f['gaze'] = -40*k
            return f
        keys = [side(90 - 35*i/6, i/6, 'Abre el brazo de arriba al otro lado; síguelo con la mirada') for i in range(7)]
        keys[0]['caption'] = 'De lado: rodillas juntas a 90°, brazos juntos al frente'
        keys[-1]['caption'] = 'Abierto: mano al suelo del otro lado, pecho girado; pausa 2 s'
        back = [dict(cp(f), caption='Vuelve despacio; las rodillas no se separan') for f in reversed(keys[:-1])]
        frames = keys + [cp(keys[-1])] + back
        motions = ([phase('Abre el libro', seconds=.35) for _ in keys[1:]] + [phase('Pausa 2 s', kind='hold', seconds=2)]
                   + [phase('Vuelve despacio', seconds=.45) for _ in back])
        return result(frames, motions, yaw=105, pitch=40, per_side=True)
    if name in ('Libro abierto', 'Abducción de cadera de lado'):
        # Body roll turns the same skeleton onto its side. Explicit world
        # reaches keep the upper limb movement independent from the pelvis.
        a = pose('De lado; pelvis estable', (0, -4.5), 180,
                 limb(0, 0, foot=0), limb(45, -45, foot=0), arm(90, 90), arm(90, 90))
        a['bodyRoll'] = -90
        if name == 'Libro abierto':
            a['nearLeg'] = limb(90, 0, foot=0); a['farLeg'] = limb(90, 0, foot=0)
            a['caption'] = 'Rodillas juntas a 90°; brazos juntos al frente'
            for sd in ['near', 'far']:
                a[sd+'Arm'].update(reach3=[0, 0, 18.9], pole=[0, -1, 0], end3=[0, 0, 1])
            b = cp(a); b['caption'] = 'Abre el brazo de arriba; sigue la mano con la mirada'
            b['nearArm'].update(reach3=[0, -12, -14.6], pole=[-1, 0, 0], end3=[0, 0, -1])
            b['gaze'] = -15
        else:
            a['caption'] = 'Pierna inferior doblada; superior recta y punta al frente'
            a['farArm'].update(reach3=[-18.98,-.75,0],pole=[0,-1,0],end3=[-1,0,0])
            a['nearArm'].update(reach3=[8,4,16],pole=[0,-1,0],end3=[1,0,0])
            a['nearLeg'].update(reach3=[28, 0, 0], pole=[0, 0, 1], end3=[1, 0, 0], keepReachRadius=True)
            b = cp(a); b['caption'] = 'Eleva la pierna recta sin rodar la pelvis'
            angle = math.radians(25)
            b['nearLeg']['reach3'] = [28*math.cos(angle), -28*math.sin(angle), 0]
        return cycle(a, b, yaw=35, pitch=35, per_side=True)
    if name == 'Muñecas a cuatro patas':
        frames, motions = [], []
        for part, angle, grip, caption in [('1', 0, '', 'Palmas abajo; dedos hacia delante'),
                                            ('2', 0, 'dorsum', 'Dorsos apoyados; balanceo muy suave'),
                                            ('3', 180, '', 'Palmas abajo; dedos hacia las rodillas')]:
            a = quadruped(caption)
            for sd in ['near', 'far']:
                a[sd+'Arm'].update(hand=angle, grip=grip)
            b = cp(a); b.update(torso=-5, caption='Lleva suavemente los hombros hacia delante')
            if frames: motions.append(phase('Cambia el apoyo de manos', kind='cut', part=part, seconds=1))
            frames.extend([a, b, cp(a)])
            motions.extend([phase('Balancea', part=part, contacts=['nearHand','farHand','nearKnee','farKnee']),
                            phase('Regresa', part=part, contacts=['nearHand','farHand','nearKnee','farKnee'])])
        frames.append(cp(frames[0])); motions.append(phase('Vuelve a palmas delante',kind='cut',part='1',seconds=1))
        return result(frames, motions, yaw=25)
    if name == 'Deslizamientos en la pared':
        a = pose('Espalda junto a pared; brazos en W')
        b = cp(a); b['caption'] = 'Desliza las manos a una Y; lumbar estable'
        for sd, sign in [('near',1), ('far',-1)]:
            a[sd+'Arm'].update(reach3=[-2,-4,sign*13],pole=[0,1,sign],end3=[0,-1,0])
            b[sd+'Arm'].update(reach3=[-2,-15,sign*11],pole=[0,1,sign],end3=[0,-1,0])
        return cycle(a,b,props=[dict(type='wall',x=-3,top=-72,depth=25,thick=1)],yaw=70)
    if name == 'Zancada del mundo':
        # 052: pies fijos en el mundo; la rodilla de atrás siempre estirada y
        # en el aire. 1) codo hacia el empeine por dentro del pie delantero;
        # 2) gira el pecho (bodyRoll) y lleva ese brazo al techo; 3) manos al
        # suelo junto al pie, cadera atrás y rodilla delantera extendida.
        front_foot=(15,-1,9); back_foot=(-25.5,-3.5,-3.3)
        def world(hip, torso, roll, targets, caption):
            t=math.radians(torso); u=(math.cos(t),math.sin(t),0)
            c,s_=math.cos(math.radians(roll)),math.sin(math.radians(roll))
            def side(base, half):   # raíz rodada: base + R(0,0,half)
                return (base[0]+half*s_*u[1], base[1]-half*s_*u[0], half*c)
            neck=(hip[0]+18*u[0],hip[1]+18*u[1])
            f=pose(caption,hip,torso)
            if roll: f['bodyRoll']=roll
            for limb_name,(target,pole,end) in targets.items():
                sd=limb_name[:-3] if limb_name.endswith('Leg') else limb_name[:-3]
                sign=1 if limb_name.startswith('near') else -1
                root=side(hip,sign*3.3) if limb_name.endswith('Leg') else side(neck,sign*4.5)
                f[limb_name].update(reach3=[target[i]-root[i] for i in range(3)],pole=pole,end3=end)
            return f
        def legs(): return {'nearLeg':(front_foot,[1,-1,.3],[1,0,.1]),
                            'farLeg':(back_foot,[1,0,0],[math.cos(math.radians(40)),math.sin(math.radians(40)),0])}
        lunge_hip=(0.5,-13.5)
        floor_near=((17,-.75,3.5),[0,1,0],[1,0,0]); floor_far=((17,-.75,-4),[0,1,0],[1,0,0])
        a=world(lunge_hip,-12,0,{**legs(),'nearArm':floor_near,'farArm':floor_far},
                'Zancada larga: rodilla de atrás estirada y en el aire; manos al suelo')
        b=world(lunge_hip,4,0,{**legs(),'nearArm':((17,-1.2,5),[-.5,1,0],[1,0,0]),'farArm':floor_far},
                'Codo hacia el empeine, por dentro del pie delantero (3 s)')
        def opened(k, caption):
            roll=45*k
            f=world(lunge_hip,-12+16*(1-k),roll,{**legs(),'farArm':floor_far},caption)
            t=math.radians(f['torso']); u=(math.cos(t),math.sin(t))
            c,s_=math.cos(math.radians(roll)),math.sin(math.radians(roll))
            neck=(lunge_hip[0]+18*u[0],lunge_hip[1]+18*u[1])
            sh=(neck[0]+4.5*s_*u[1],neck[1]-4.5*s_*u[0],4.5*c)
            # El brazo abre por el lado (+z) hasta el techo, sin cruzar el pecho.
            down=(17-sh[0],-1.2-sh[1],5-sh[2]); dl=math.sqrt(sum(v*v for v in down))
            a0,a1,w=((down[0]/dl,down[1]/dl,down[2]/dl),(0,0,1),k*2) if k<=.5 else ((0,0,1),(0,-1,0),k*2-1)
            vec=[a0[i]*(1-w)+a1[i]*w for i in range(3)]
            n=math.sqrt(sum(v*v for v in vec)); L=dl+(18.9-dl)*k
            f['nearArm'].update(reach3=[v*L/n for v in vec],pole=[.3*(1-k),1-2*k,-.4],end3=[0,-1,0] if k>.5 else [-1,0,0])
            f['gaze']=-35*k
            return f
        turn=[opened(i/4,'Gira el pecho y lleva ese brazo al techo (3 s)') for i in range(1,5)]
        unturn=[opened(i/4,'Vuelve: mano al suelo junto al pie') for i in (3,2,1)]
        # Isquios: cadera atrás y arriba; ambas rodillas estiradas.
        fx,fy=front_foot[0],front_foot[1]; bx,by=back_foot[0],back_foot[1]
        rf=math.sqrt(27.7**2-(front_foot[2]-3.3)**2); rb=27.7
        d=math.dist((fx,fy),(bx,by)); al=(rb**2-rf**2+d**2)/(2*d); h=math.sqrt(rb**2-al**2)
        ex,ey=(fx-bx)/d,(fy-by)/d
        ham_hip=(bx+al*ex+h*ey, by+al*ey-h*ex)
        ham=world(ham_hip,30,0,{'nearLeg':(front_foot,[1,-1,.3],[.6,-.8,.1]),'farLeg':legs()['farLeg'],
                                'nearArm':((19,-.75,4),[0,1,0],[1,0,0]),'farArm':((19,-.75,-3),[0,1,0],[1,0,0])},
                  'Manos al suelo; cadera atrás y rodilla delantera extendida (3 s)')
        frames=[a,b,cp(b),*turn,cp(turn[-1]),*unturn,cp(a),ham,cp(ham),cp(a)]
        frames[-1]['caption']='Vuelve a la zancada; repite'
        motions=([phase('Codo al empeine',seconds=1.5),phase('Pausa 3 s',kind='hold',seconds=3)]
                 +[phase('Gira y brazo al techo',seconds=.5) for _ in turn]+[phase('Pausa 3 s',kind='hold',seconds=3)]
                 +[phase('Mano al suelo',seconds=.4) for _ in range(len(unturn)+1)]
                 +[phase('Cadera atrás, rodilla delantera recta',seconds=1.8),phase('Pausa 3 s',kind='hold',seconds=3),
                   phase('Vuelve a la zancada',seconds=1.8)])
        return result(frames,motions,per_side=True,yaw=30,pitch=14)
    if name == 'Rodilla a la pared':
        a=pose('Medio arrodillado; talón delantero apoyado',(-4,-15.6),-90,
               reach(12,-1),limb(90,180,foot=180),arm(40,40),arm(90,90))
        b=cp(a); b.update(hip=(0,-15.6),caption='Rodilla hacia pared; no levantes el talón')
        # Posterior knee remains at x=-4 while the hip advances.
        dy=math.sqrt(14**2-4**2)
        b['hip']=(0,-1.6-dy); b['farLeg']=limb(math.degrees(math.atan2(dy,-4)),180,foot=180)
        return cycle(a,b,contacts=['nearAnkle'],props=[dict(type='wall',x=19,top=-52,depth=14,thick=1)],per_side=True,yaw=15)
    if name == 'Sentadilla profunda':
        a=squat('Pies abiertos, talones apoyados')
        b=squat('Baja profundo; pecho alto y codos entre rodillas',True)
        b['hip']=(-8,-10)
        for f in (a,b):
            for sd,sign in [('near',1),('far',-1)]:
                f[sd+'Leg'].update(depth=sign*7,pole=[1,0,sign])
        b['nearArm']=arm(70,-70); b['farArm']=arm(70,-70)
        return cycle(a,b,contacts=['nearAnkle','farAnkle'],yaw=65)
    if name == 'Pie corto':
        a=pose('Pie descalzo apoyado; dedos largos')
        a['footArch']=0
        b=cp(a); b.update(caption='Eleva suavemente el arco sin encoger los dedos',footArch=.6)
        return cycle(a,b,contacts=['nearAnkle','farAnkle'],barefoot=True,focus='nearFoot',per_side=True,yaw=0,pitch=0,
                     annotations=[dict(joint='footArch',text='Arco',corner='bl')])
    if name == 'Pancake':
        # 052: piernas abiertas y rectas con rodillas al techo; manos en la
        # nuca y codos abiertos. Good mornings: bisagra de cadera con la
        # espalda larga y el cuello neutro; la última vez se queda abajo.
        def seated(caption, torso):
            f=pose(caption,(0,-5),torso,limb(0,0,foot=-60),limb(0,0,foot=-60))
            for sd,sign in [('near',1),('far',-1)]:
                f[sd+'Leg'].update(reach3=[28*math.cos(math.pi/5),0,sign*28*math.sin(math.pi/5)],
                                   pole=[0,-1,0],end3=[0,-1,0],keepReachRadius=True)
                t=math.radians(torso); u=(math.cos(t),math.sin(t)); fr=(-u[1],u[0])
                # Mano en la nuca: arriba del hombro, un poco atrás y al centro.
                f[sd+'Arm'].update(reach3=[6*u[0]-5*fr[0],6*u[1]-5*fr[1],-sign*3.0],
                                   pole=[.3*u[0]-fr[0]*.2,.3*u[1]-fr[1]*.2,sign],end3=[-u[0],-u[1],0])
            f['gaze']=0
            return f
        up=seated('Piernas abiertas y rectas, rodillas al techo; manos en la nuca, codos abiertos',-90)
        down=seated('Bisagra desde la cadera: espalda larga, cuello neutro',-48)
        frames=[up,down,cp(up),cp(down),dict(cp(down),caption='Quédate abajo y respira, sin redondear'),
                dict(cp(up),caption='Sube con la espalda larga')]
        hold=['hip','nearAnkle','farAnkle']
        motions=[phase('Good morning',contacts=hold,seconds=1.5),phase('Sube',contacts=hold,seconds=1.5),
                 phase('Good morning',contacts=hold,seconds=1.5),phase('Quédate abajo',kind='hold',seconds=3),
                 phase('Sube con control',contacts=hold,seconds=1.5)]
        return result(frames,motions,yaw=115,pitch=18)
    if name == 'Pike sentado':
        a=pose('Siéntate con piernas rectas y espalda larga',(0,-5),-90,
               limb(0,0,foot=-60),limb(0,0,foot=-60),arm(45,45),arm(45,45))
        b=cp(a); b.update(torso=-45,caption='Inclínate desde la cadera; conserva las rodillas rectas')
        return cycle(a,b,contacts=['hip','nearAnkle','farAnkle'],yaw=15)
    if name == 'Dorsal en la cama':
        # 052: cadena cerrada. Rodillas fijas en el suelo y codos fijos en el
        # borde de la cama, manos juntas arriba. La cadera va hacia los
        # talones; al pasar la línea brazos-tronco el pecho y la cabeza bajan
        # entre los brazos, y al exhalar bajan un poco más.
        elbow=(19,-17.5)
        def kneel(thigh, low):
            r=math.radians(thigh)
            hip=(-14*math.cos(r),-1.6-14*math.sin(r))
            dx,dy=elbow[0]-hip[0],elbow[1]-hip[1]
            distance=min(math.hypot(dx,dy),27.999)
            along=(18**2-10**2+distance**2)/(2*distance)
            offset=math.sqrt(max(0,18**2-along**2))*(-1 if low else 1)
            d=math.hypot(dx,dy)
            neck=(hip[0]+along*dx/d+offset*dy/d, hip[1]+along*dy/d-offset*dx/d)
            torso=math.degrees(math.atan2(neck[1]-hip[1],neck[0]-hip[0]))
            f=pose('',hip,torso,limb(thigh,180,foot=180),limb(thigh,180,foot=180))
            for sd,sign in [('near',1),('far',-1)]:
                f[sd+'Arm'].update(reach3=[elbow[0]-neck[0],elbow[1]-8.2-neck[1],-sign*3.7],
                                  pole=[elbow[0]-neck[0],elbow[1]-neck[1],0],end3=[0,-1,0])
            # Cabeza entre los brazos: la mirada cae hacia el suelo.
            f['gaze']=max(0.0,min(35.0,(neck[1]-(elbow[1]+2))*7))
            return f
        # Muslo con el que tronco y brazo quedan en línea (distancia 28).
        cross=52.208
        lean=[kneel(90-(90-cross)*(1-(1-i/8)**2),False) for i in range(9)]           # cadera atrás
        sink=[kneel(cross+(61-cross)*(i/5)**1.5,True) for i in range(1,6)]          # el pecho baja
        exhale=[kneel(61+4*i/3,True) for i in range(1,4)]        # exhala: un poco más
        lean[0]['caption']='De rodillas; codos en el borde de la cama y manos juntas'
        for f in lean[1:]: f['caption']='Cadera hacia los talones'
        for f in sink: f['caption']='Deja caer pecho y cabeza entre los brazos'
        for f in exhale: f['caption']='Al exhalar baja un poco más, sin arquear la lumbar'
        go=lean+sink
        frames=go+[cp(go[-1])]+exhale+[cp(exhale[-1])]+[cp(f) for f in reversed(go[:-1])]
        back=len(go)-1
        for f in frames[-back:]: f['caption']='Vuelve despacio a la posición inicial'
        motions=([phase('Cadera atrás',seconds=.2) for _ in lean[1:]]
                 +[phase('Pecho entre los brazos',seconds=.25) for _ in sink]
                 +[phase('Respira',kind='hold',seconds=1.5)]
                 +[phase('Exhala y baja un poco más',seconds=.4) for _ in exhale]
                 +[phase('Sostén',kind='hold',seconds=1.5)]
                 +[phase('Regresa',seconds=.15) for _ in range(back)])
        return result(frames,motions,props=bench(elbow[0]+3,elbow[1]+1.4,width=15,depth=12),yaw=15,gripZ=4.5)
    if name == 'Pectoral en el marco de la puerta':
        # Rotate around the supported shoulder, closing each world-space
        # chain. The hand, elbow and staggered feet stay at their supports.
        sweep=[]
        for i in range(9):
            angle=20*i/8; theta=math.radians(angle)
            x=4.5*math.sin(theta); z=4.5*(1-math.cos(theta))
            f=pose('Antebrazo al marco; adelanta la pierna de ese lado' if i==0 else
                   'Gira suavemente el pecho hacia el lado contrario',
                   (x,-28),-90,reach(3,-1),reach(-3,-1),reach(10,-55,hand=-90),arm(90,90))
            f.update(bodyRoll=angle,bodyZ=z)
            f['nearArm'].update(reach3=[10,-9,0],pole=[1,0,0],end3=[0,-1,0])
            for side,sign,target_x in [('near',1,3),('far',-1,-3)]:
                root_x=x-sign*3.3*math.sin(theta)
                root_z=z+sign*3.3*math.cos(theta)
                f[side+'Leg'].update(reach3=[target_x-root_x,27,sign*3.3-root_z],
                                    pole=[1,0,0],end3=[1,0,0])
            sweep.append(f)
        frames=sweep+[cp(sweep[-1])]+[cp(f) for f in reversed(sweep[:-1])]
        contacts=['nearHand','nearAnkle','farAnkle']
        motions=[phase('Gira el pecho',seconds=.3,contacts=contacts) for _ in sweep[1:]]
        motions+=[phase('Respira sin mover los apoyos',kind='hold',seconds=2)]
        motions+=[phase('Regresa con control',seconds=.3,contacts=contacts) for _ in sweep[1:]]
        return result(frames,motions,props=[box([12,-32,4.5],[2,64,2]),box([12,-64,0],[2,2,18])],per_side=True,yaw=55)
    if name == 'Sóleo en la pared':
        a=pose('Manos a la pared; ambos talones apoyados',(-10,-25),-80,
               reach(-17,-1),reach(2,-1),reach(9,-37,hand=-90),reach(9,-37,hand=-90))
        b=cp(a); b.update(hip=(-7,-21),caption='Dobla ambas rodillas; talón posterior fijo')
        return cycle(a,b,contacts=['nearAnkle','farAnkle','nearHand','farHand'],
                     props=[dict(type='wall',x=10,top=-60,depth=14,thick=1)],per_side=True,yaw=15)
    if name == 'Scap pull-up':
        a=cp(existing('Colgado pasivo')['frames'][0]); b=cp(existing('Colgarse de la barra')['frames'][0])
        a['caption']='Colgado pasivo; codos rectos'; b['caption']='Baja los hombros; el cuerpo sube sin doblar codos'
        return cycle(a,b,contacts=['nearHand','farHand'],props=cp(existing('Colgado pasivo')['props']),yaw=35)
    if name == 'Y-T prono':
        a=pose('Boca abajo; frente en toalla y pulgares hacia arriba',(0,-4.5),0,
               limb(180,180,foot=180),limb(180,180,foot=180),arm(0,0),arm(0,0))
        frames=[a]
        for label,x,z in [('Y',13,13),('T',0,18.7)]:
            b=cp(a); b['caption']='Eleva en '+label+' sin levantar la cabeza'
            for sd,sign in [('near',1),('far',-1)]:
                b[sd+'Arm'].update(reach3=[x,-2,sign*z],pole=[0,1,0],end3=[0,-1,0])
            frames.extend([b,cp(b),cp(a)])
        props=[box([25,-.7,0],[9,1.4,12])]
        if variant in ('prone_y_t_bed_edge','prone_y_t_loaded'):
            # The same prone rig rests on the bed; free arms can descend
            # alongside its narrow edge instead of stopping at the floor.
            for i,f in enumerate(frames):
                f['hip']=(0,-19.5)
                if i in (0,3,6):
                    for sd,sign in [('near',1),('far',-1)]:
                        f[sd+'Arm'].update(reach3=[4,17,sign*7],pole=[1,0,sign],end3=[0,-1,0])
                    f['caption']='Boca abajo en el borde; brazos libres junto a la cama'
            props=bench(-3,-15,width=65,depth=6)+[box([25,-15.7,0],[9,1.4,12])]
            if variant=='prone_y_t_loaded':
                props += [dict(type='guidedHandWeight',joint=sd+'Hand') for sd in ['near','far']]
                for f in frames: f['caption']+=' · carga ligera en ambas manos'
        return result(frames,[phase('Eleva en Y'),phase('Pausa Y',kind='hold'),phase('Baja'),
                              phase('Eleva en T'),phase('Pausa T',kind='hold'),phase('Baja')],
                      props=props,yaw=45,pitch=45)
    # 034 specifications continue below; unsupported names must fail closed.
    return _plan034(name, variant, result, cycle)


def _plan034(name, variant, result, cycle):
    from illustration_catalog import pose, limb, arm, reach, phase, box, bench, tube, squat, generate as existing
    if name == 'Copenhague':
        # 052: plancha lateral real. bodyRoll=90 pone el pecho hacia la
        # cámara (+z) y el lado cercano abajo. Codo bajo el hombro con el
        # antebrazo al frente; rodilla (palanca corta) o tobillo (larga) de la
        # pierna de arriba en el borde de la cama; la de abajo, libre bajo la
        # cama. La pelvis baja y sube rotando alrededor del hombro de apoyo.
        long = variant == 'copenhagen_long'
        shoulder = (-18.0, -11.2)          # hombro de apoyo, fijo sobre el codo
        bed_top = -18.5 if long else -17.4
        lever = 28 if long else 14         # cadera de arriba → apoyo en la cama
        support_y = bed_top - (0.9 if long else 1.3)
        def side(t_deg):
            t = math.radians(t_deg)
            u = (math.cos(t), math.sin(t)); n = (u[1], -u[0])   # n: hacia el lado de abajo
            hip = (shoulder[0] - 18*u[0] - 4.5*n[0], shoulder[1] - 18*u[1] - 4.5*n[1])
            top_hip = (hip[0] - 3.3*n[0], hip[1] - 3.3*n[1])
            low_hip = (hip[0] + 3.3*n[0], hip[1] + 3.3*n[1])
            dy = support_y - top_hip[1]
            support = (top_hip[0] + math.sqrt(lever**2 - dy**2), support_y)
            f = pose('Eleva o baja la pelvis; apoyos inmóviles', hip, t_deg)
            f['bodyRoll'] = 90
            top = [support[0]-top_hip[0], support[1]-top_hip[1], 0]
            if long:
                f['farLeg'].update(reach3=top, pole=[0, -1, .3], end3=[1, -.2, 0])
            else:
                # Rodilla en el borde; la pantorrilla descansa sobre la cama hacia atrás.
                f['farLeg'].update(reach3=[top[0], top[1], -14], pole=top, end3=[0, 0, -1])
            ankle = (low_hip[0] + 21, -5.0 + 0.6*(hip[1] + 12.5))
            low = [ankle[0]-low_hip[0], ankle[1]-low_hip[1], 1.5]
            k = 27.6/math.sqrt(sum(c*c for c in low))
            f['nearLeg'].update(reach3=[c*k for c in low], pole=[1, 0, .2], end3=[1, .3, 0])
            # Antebrazo al frente, perpendicular al cuerpo; codo bajo el hombro.
            f['nearArm'].update(reach3=[0, 10, 9], pole=[0, 1, 0], end3=[0, 0, 1])
            # Brazo de arriba relajado a lo largo del costado.
            f['farArm'].update(reach3=[-18.8*u[0] - 1.5*n[0], -18.8*u[1] - 1.5*n[1], 1.5],
                               pole=[0, -.3, -1], end3=[-u[0], -u[1], 0])
            f['gaze'] = 0
            return f, support
        sweep = [side(192 - 18*i/8)[0] for i in range(9)]
        sweep[0]['caption'] = ('Codo bajo el hombro; '+('tobillo' if long else 'rodilla')
                               +' de arriba en el borde de la cama; pelvis abajo')
        for f in sweep[1:]: f['caption'] = 'Eleva la pelvis: cuerpo en línea, pecho al frente'
        sweep[-1]['caption'] = 'Pelvis alineada; sostén sin girarte'
        frames = sweep+[cp(sweep[-1])]+[cp(f) for f in reversed(sweep[:-1])]
        for f in frames[len(sweep)+1:]: f['caption'] = 'Baja la pelvis con control'
        motions = ([phase('Eleva la pelvis', seconds=.15) for _ in sweep[1:]]+[phase('Sostén', kind='hold', seconds=2)]
                   +[phase('Baja con control', seconds=.15) for _ in sweep[1:]])
        support = side(183)[1]
        bed_x = support[0] + (2 if long else 5)
        width = 12 if long else 16
        props = [box([bed_x, bed_top + 1, -6], [width, 2, 26]),
                 box([bed_x - width/2 + 1, bed_top/2, -18], [1.5, -bed_top, 1.5]),
                 box([bed_x + width/2 - 1, bed_top/2, -18], [1.5, -bed_top, 1.5]),
                 box([bed_x + width/2 - 1, bed_top/2, 6], [1.5, -bed_top, 1.5])]
        return result(frames, motions, props=props, per_side=True, yaw=20, pitch=30)
    if name == 'Sóleo sentado con mochila':
        a=pose('Sentado; mochila sobre muslos, antepiés apoyados',(0,-15),-90,
               limb(0,90,foot=0),limb(0,90,foot=0),arm(60,20),arm(60,20))
        b=cp(a); b['caption']='Eleva '+('un talón' if variant=='seated_soleus_unilateral' else 'ambos talones')+' sin despegar el antepié'
        for sd in (['near'] if variant=='seated_soleus_unilateral' else ['near','far']):
            # The toe is fixed at (19,-1); ankle follows a radius5 arc.
            angle=math.radians(35)
            b[sd+'Leg']=reach(19-5*math.cos(angle),-1-5*math.sin(angle),foot=35)
        sweep=[]
        for i in range(9):
            f=cp(a); angle=math.radians(35*i/8)
            for sd in (['near'] if variant=='seated_soleus_unilateral' else ['near','far']):
                f[sd+'Leg']=reach(19-5*math.cos(angle),-1-5*math.sin(angle),foot=35*i/8,bend=-1)
            f['caption']=a['caption'] if i==0 else b['caption']; sweep.append(f)
        frames=sweep+[cp(sweep[-1])]+[cp(f) for f in reversed(sweep[:-1])]
        motions=[phase('Eleva el talón',seconds=.3) for _ in sweep[1:]]+[phase('Pausa arriba',kind='hold',seconds=1)]+[phase('Baja',seconds=.3) for _ in sweep[1:]]
        return result(frames,motions,props=bench(-4,-13.5,width=17,depth=10)+[dict(type='guidedThighPack',unilateral=variant=='seated_soleus_unilateral')],per_side=variant=='seated_soleus_unilateral',yaw=25)
    if name == 'Tibial en la pared':
        distance=7 if variant in (None,'tibialis_wall_close') else 14
        hip_y=-1-math.sqrt(28**2-distance**2)
        angle=math.degrees(math.atan2(-1-hip_y,distance))
        a=pose('Espalda y glúteos a pared; piernas rectas, talones firmes',(0,hip_y),-90,
               limb(angle,angle,foot=0),limb(angle,angle,foot=0))
        b=cp(a); b['caption']='Levanta las puntas; conserva los talones en el suelo'
        b['nearLeg']['foot']=-35; b['farLeg']['foot']=-35
        props=[dict(type='wall',x=-3,top=-62,depth=14,thick=1)]
        if variant=='tibialis_wall_far':
            for f in (a,b): f['caption']+=' · pies más lejos de la pared'
        if variant=='tibialis_wall_loaded':
            props.append(dict(type='guidedFootPack',joint='nearToe'))
            a['nearLeg']['foot']=-35; b['nearLeg']['foot']=-55
            b['farLeg']['foot']=0
            a['caption']='Punta elevada; asa de mochila colgada del pie, talón firme'
            b['caption']='Eleva la punta con la mochila; baja con control'
        return cycle(a,b,contacts=['nearAnkle','farAnkle'],props=props,per_side=variant=='tibialis_wall_loaded',yaw=25)
    if name == 'Rotación externa con banda':
        a=pose('Codos al costado a 90°; banda entre manos')
        b=cp(a); b['caption']='Abre las manos; los codos conservan su sitio'
        overhead=variant=='band_rotation_90_90'
        for f,opened in [(a,False),(b,True)]:
            for sd,sign in [('near',1),('far',-1)]:
                # Explicit endpoint and pole keep the elbow as the hinge.
                if overhead:
                    f[sd+'Arm'].update(reach3=[9 if not opened else 0,-9 if opened else 0,sign*10],
                                      pole=[0,0,sign],end3=[0,-1,0])
                else:
                    f[sd+'Arm'].update(reach3=[9*math.cos(math.radians(55 if opened else 5)),10,
                                              sign*9*math.sin(math.radians(55 if opened else 5))],
                                      pole=[0,1,0],end3=[1,0,0])
        if overhead: a['caption']='Brazos a altura de hombro; codos a 90°'; b['caption']='Rota los antebrazos hacia arriba sin mover los codos'
        sweep=[]
        for i in range(9):
            f=cp(a); theta=math.radians(90*i/8 if overhead else 5+50*i/8)
            for sd,sign in [('near',1),('far',-1)]:
                f[sd+'Arm']['reach3']=([9*math.cos(theta),-9*math.sin(theta),sign*10] if overhead else
                                       [9*math.cos(theta),10,sign*9*math.sin(theta)])
            f['caption']=a['caption'] if i==0 else b['caption']; sweep.append(f)
        frames=sweep+[cp(sweep[-1])]+[cp(f) for f in reversed(sweep[:-1])]
        motions=[phase('Rota hacia fuera',seconds=.3) for _ in sweep[1:]]+[phase('Pausa',kind='hold',seconds=1)]+[phase('Regresa',seconds=.3) for _ in sweep[1:]]
        return result(frames,motions,props=[dict(type='band',a='nearHand',b='farHand',depthSorted=True)],yaw=70)
    if name == 'Support hold en paralelas':
        a=pose('Manos sobre apoyos; codos rectos',(0,-30),-90,
               limb(90,90),limb(90,90),arm(90,90,hand=0,grip='bar_parallel'),arm(90,90,hand=0,grip='bar_parallel'))
        b=cp(a); b['caption']='Pies libres; empuja los apoyos y sostén con hombros abajo'
        b['nearLeg']=limb(105,155,foot=0); b['farLeg']=limb(105,155,foot=0)
        if variant=='support_protraction':
            b['hip']=(-1,-30); b['shoulderOffset']=(1,0); b['spineBend']=-.6
            b['caption']='Empuja las barras; separa escápulas con codos rectos'
        # Hands remain y=-29: bars/rings are at that same height.
        if variant=='support_rings':
            props=[]
            for z in [-5,5]:
                for i in range(24):
                    angles=[2*math.pi*i/24,2*math.pi*(i+1)/24]
                    points=[[2.2*math.cos(t),-26.8+2.2*math.sin(t),z] for t in angles]
                    props.append(tube(*points,.35))
                props.append(tube([0,-70,z],[0,-29,z],.25))
            a['caption']='Manos en anillas; codos rectos'
        else:
            props=[tube([-9,-29,z],[9,-29,z],.65) for z in [-5,5]]
            props += [tube([x,-29,z],[x,0,z],.6) for x in [-7,7] for z in [-5,5]]
        return cycle(a,b,contacts=['nearHand','farHand'],props=props,yaw=35)
    if name == 'Sprint lanzado':
        e=existing('Aceleración 10–20 m')
        for f in e['frames']: f['caption']='Tramo lanzado · '+f['caption']
        return result(e['frames'],e['motion'],yaw=35)
    if name == 'Intervalos 15/15':
        # Misma zancada real de Aceleración; el ritmo lo marca el reloj.
        e=existing('Aceleración 10–20 m')
        for f in e['frames']: f['caption']='15 s rápido · '+f['caption']
        return result(e['frames'],e['motion'],yaw=35)
    if name == 'Sentadilla isométrica en la pared':
        a=pose('Espalda a pared; pies adelantados',(-3,-23),-90,reach(13,-1),reach(13,-1))
        b=cp(a); b.update(hip=(-3,-15),caption='Desliza la espalda y sostén con rodillas flexionadas')
        return cycle(a,b,contacts=['nearAnkle','farAnkle'],props=[dict(type='wall',x=-6,top=-62,depth=15,thick=1)],yaw=15)
    if name == 'Nórdico inverso':
        def kneeling(angle,caption):
            knee=(0,-1.6); r=math.radians(angle)
            hip=(knee[0]-14*math.cos(r),knee[1]-14*math.sin(r))
            f=pose(caption,hip,angle+180,limb(angle,180,foot=180),limb(angle,180,foot=180),arm(45,150),arm(45,150))
            return f
        return cycle(kneeling(90,'Arrodillado; cadera y tronco alineados'),
                     kneeling(68,'Inclina el bloque hacia atrás desde las rodillas'),
                     contacts=['nearKnee','farKnee'],props=[box([0,-.3,0],[10,.6,18])],yaw=15,pivot=(0,-1.6))
    if name == 'Bajada lateral del escalón':
        a=pose('Un pie en el escalón; pierna libre al lado',(0,-34),-90,reach(0,-7),reach(0,-7),arm(30,30),arm(30,30))
        a['nearLeg']['depth']=6; a['farLeg']['depth']=-9
        b=cp(a); b.update(hip=(-3,-25),caption='Baja el talón libre al lado; rodilla de apoyo sigue el pie')
        b['farLeg']=reach(0,-1,depth=-9)
        return cycle(a,b,contacts=['nearAnkle'],props=[box([2,-3,6],[13,6,10])],per_side=True,yaw=70)
    if name == 'Aterrizaje clavado':
        a=squat('Prepara el impulso',True)
        b=squat('Vuelo: pies libres',jump=True)
        c=squat('Aterriza flexionando; después mantente estable',True)
        if variant in ('landing_unilateral','landing_lateral'):
            for f in (a,b,c): f['farLeg']=limb(-20,90,foot=0)
            a['caption']='Prepara el impulso sobre una pierna'
            c['caption']='Aterriza sobre la misma pierna y estabiliza'
        if variant=='landing_lateral':
            b['bodyZ']=4; c['bodyZ']=8
            c['caption']='Aterriza a un lado sobre una pierna y estabiliza'
        return result([a,b,c,cp(c),cp(a)],
                      [phase('Impulso',ground='flight'),phase('Aterrizaje',ground='flight'),
                       phase('Estabiliza',kind='hold',seconds=3),phase('Nueva demostración',kind='cut',seconds=1)],
                      per_side=variant in ('landing_unilateral','landing_lateral'),yaw=55)
    if name.startswith('Plancha inversa') or name=='Mesa invertida':
        base=cp(existing('Plancha inversa con patada')['frames'][0])
        props=[]
        if name=='Mesa invertida':
            a=pose('Sentado; palmas atrás y pies cerca',(0,-5),-140,reach(18,-1),reach(18,-1),reach(-16,-.75,hand=0),reach(-16,-.75,hand=0))
            b=pose('Eleva la pelvis; rodillas flexionadas',(2,-19.75),180,reach(18,-1),reach(18,-1),reach(-16,-.75,hand=0),reach(-16,-.75,hand=0))
        elif name=='Plancha inversa sobre antebrazos':
            angle=math.asin(10.1/46)
            neck=(27-46*math.cos(angle),-11.1)
            hip=(neck[0]+18*math.cos(angle),neck[1]+18*math.sin(angle))
            a=pose('Antebrazos y talones apoyados; cuerpo alineado',hip,180+math.degrees(angle),
                   limb(math.degrees(angle),math.degrees(angle),foot=-90),
                   limb(math.degrees(angle),math.degrees(angle),foot=-90),arm(90,0,hand=0),arm(90,0,hand=0))
            return result([a,cp(a),cp(a)],[phase('Sostén sobre antebrazos',kind='hold'),phase('Respira sin perder la línea',kind='hold')],yaw=25)
        else:
            b=base; b['caption']='Sostén la línea de hombros a talones'
            a=cp(b); a['hip']=(a['hip'][0],-5); a['torso']=-150
            a['caption']='Palmas atrás; prepara los talones'
            if name=='Plancha inversa a una pierna':
                a=cp(b); b=cp(b); b['farLeg']=limb(-20,-20,foot=-110)
                b['caption']='Eleva una pierna sin girar la pelvis'
            elif name=='Plancha inversa con pies elevados':
                angle=math.asin(9.75/46)
                neck=(27-46*math.cos(angle),-19.75)
                hip=(neck[0]+18*math.cos(angle),neck[1]+18*math.sin(angle))
                b=pose('Talones sobre soporte; cuerpo alineado',hip,180+math.degrees(angle),
                       limb(math.degrees(angle),math.degrees(angle),foot=-90),
                       limb(math.degrees(angle),math.degrees(angle),foot=-90),
                       arm(90,90,hand=0),arm(90,90,hand=0))
                a=cp(b); a.update(hip=(hip[0],-5),torso=-150,caption='Prepara los apoyos antes de elevar la pelvis')
                for side in ['near','far']:
                    a[side+'Leg']=reach(27,-10,foot=-90,bend=-1)
                    a[side+'Arm']=reach(neck[0],-.75,hand=0)
                props=bench(29,-9,width=10,depth=10)
        return cycle(a,b,props=props,per_side=name=='Plancha inversa a una pierna',yaw=25)
    raise ValueError('Falta guion físico específico: '+name)
