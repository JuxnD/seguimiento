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
        # 052: codos rectos; el balanceo lleva los hombros por delante de las
        # manos (rodillas y manos fijas, cadena cerrada resuelta por clave).
        from illustration_upper import wrists
        frames, motions = wrists(name)
        return result(frames, motions, yaw=25)
    if name == 'Deslizamientos en la pared':
        a = pose('Espalda junto a pared; brazos en W')
        b = cp(a); b['caption'] = 'Desliza las manos a una Y; lumbar estable'
        for sd, sign in [('near',1), ('far',-1)]:
            a[sd+'Arm'].update(reach3=[-2,-4,sign*13],pole=[0,1,sign],end3=[0,-1,0])
            b[sd+'Arm'].update(reach3=[-2,-15,sign*11],pole=[0,1,sign],end3=[0,-1,0])
        return cycle(a,b,props=[dict(type='wall',x=-3,top=-72,depth=25,thick=1)],yaw=70)
    if name == 'Zancada del mundo':
        a=pose('Zancada larga; rodilla posterior libre', (0,-18),0,
               reach(15,-1),reach(-22.25,-1),reach(18,-.75,hand=0),reach(7,-.75,hand=0))
        b=cp(a); b['caption']='Acerca el codo por dentro del pie delantero'; b['nearArm']=arm(45,145)
        c=cp(a); c['caption']='Gira el pecho y lleva el brazo hacia arriba'; c['nearArm']=arm(-90,-90)
        d=cp(a); d.update(hip=(-10,-13.6),torso=0,caption='Cadera atrás; extiende la rodilla delantera')
        d['nearLeg']=reach(15,-1); d['nearArm']=reach(7,-.75,hand=0)
        return result([a,b,cp(b),c,cp(c),d,cp(d),cp(a)],
                      [phase('Acerca el codo'),phase('Pausa',kind='hold'),phase('Abre el pecho'),phase('Pausa',kind='hold'),
                       phase('Extiende delante'),phase('Pausa',kind='hold'),phase('Vuelve a zancada')],per_side=True)
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
    if name in ('Pike sentado','Pancake'):
        a=pose('Siéntate con piernas rectas y espalda larga',(0,-5),-90,
               limb(0,0,foot=-60),limb(0,0,foot=-60),arm(45,45),arm(45,45))
        if name=='Pancake':
            for sd,sign in [('near',1),('far',-1)]:
                a[sd+'Leg'].update(reach3=[28*math.cos(math.pi/5),0,sign*28*math.sin(math.pi/5)],
                                  pole=[0,-1,0],end3=[0,-1,0],keepReachRadius=True)
        b=cp(a); b.update(torso=-45,caption='Inclínate desde la cadera; conserva las rodillas rectas')
        return cycle(a,b,contacts=['hip','nearAnkle','farAnkle'],yaw=55 if name=='Pancake' else 15)
    if name == 'Dorsal en la cama':
        # Closed chain: knee stays on floor and elbow stays on the bed.
        # Solve the shoulder as the intersection of torso/upper-arm circles;
        # dense authored keys keep those supports throughout the movement.
        elbow=(24,-19)
        sweep=[]
        for i in range(17):
            leg=math.radians(90-8*i/16)
            hip=(-14*math.cos(leg),-1.6-14*math.sin(leg))
            dx,dy=elbow[0]-hip[0],elbow[1]-hip[1]
            distance=math.hypot(dx,dy)
            along=(18**2-10**2+distance**2)/(2*distance)
            offset=math.sqrt(max(0,18**2-along**2))
            neck=(hip[0]+along*dx/distance+offset*dy/distance,
                  hip[1]+along*dy/distance-offset*dx/distance)
            torso=math.degrees(math.atan2(neck[1]-hip[1],neck[0]-hip[0]))
            upper=math.degrees(math.atan2(elbow[1]-neck[1],elbow[0]-neck[0]))
            f=pose('Cadera atrás; pecho entre brazos, codos apoyados',hip,torso,
                   limb(math.degrees(leg),180,foot=180),limb(math.degrees(leg),180,foot=180),
                   arm(upper,-90,hand=-90,planarAngles=True),arm(upper,-90,hand=-90,planarAngles=True))
            sweep.append(f)
        sweep[0]['caption']='Rodillas al suelo; codos en el borde de la cama'
        frames=sweep+[cp(sweep[-1])]+[cp(f) for f in reversed(sweep[:-1])]
        motions=[phase('Cadera atrás',seconds=.15) for _ in sweep[1:]]+[phase('Respira',kind='hold')]+[phase('Regresa',seconds=.15) for _ in sweep[1:]]
        return result(frames,motions,props=bench(elbow[0]+3,elbow[1]+1.4,width=15,depth=12),yaw=10,gripZ=4.5)
    if name == 'Pectoral en el marco de la puerta':
        # 052: marco al costado, brazo abducido 90° con el antebrazo vertical
        # en el marco; pie de ese lado adelante y el pecho gira al otro lado.
        from illustration_upper import doorframe
        frames, motions, props = doorframe()
        return result(frames, motions, props=props, per_side=True, yaw=-50, pitch=14)
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
    from illustration_catalog import pose, limb, arm, reach, phase, box, bench, tube, squat, running, generate as existing
    if name == 'Copenhague':
        long = variant == 'copenhagen_long'
        support_x=28 if long else 14
        length=28 if long else 14
        def supported(y):
            # Closed chain: superior knee/ankle on bed and inferior elbow on
            # floor. Solve hip-x and torso rotation with anatomical lengths.
            def constraints(x,t):
                ux,uy=math.cos(t),math.sin(t); fx,fy=-uy,ux
                hip_top=(x+fx*3.3,y+fy*3.3)
                shoulder_bottom=(x+ux*18-fx*4.5,y+uy*18-fy*4.5)
                return ((support_x-hip_top[0])**2+(-19-hip_top[1])**2-length**2,
                        (-18-shoulder_bottom[0])**2+(-1.2-shoulder_bottom[1])**2-100)
            x,t=0.,math.pi
            for _ in range(30):
                f,g=constraints(x,t)
                if max(abs(f),abs(g))<1e-10: break
                h=1e-5; fx,gx=constraints(x+h,t); ft,gt=constraints(x,t+h)
                a,b,c,d=(fx-f)/h,(ft-f)/h,(gx-g)/h,(gt-g)/h
                det=a*d-b*c
                x-=(d*f-b*g)/det; t-=(-c*f+a*g)/det
            ux,uy=math.cos(t),math.sin(t); front=(-uy,ux)
            hip_top=(x+front[0]*3.3,y+front[1]*3.3)
            shoulder=(x+ux*18-front[0]*4.5,y+uy*18-front[1]*4.5)
            f=pose('Eleva o baja la pelvis; apoyos inmóviles',(x,y),math.degrees(t),
                   limb(0,0),limb(0,0),arm(90,0),arm(90,0))
            f['bodyRoll']=-90
            knee=[support_x-hip_top[0],-19-hip_top[1],0]
            target=cp(knee)
            if not long: target[2]=14
            f['nearLeg'].update(reach3=target,pole=knee,end3=[1,0,0] if long else [0,0,1])
            f['farArm'].update(reach3=[-9-shoulder[0],-1.2-shoulder[1],0],
                               pole=[-18-shoulder[0],-1.2-shoulder[1],0],end3=[1,0,0])
            return f
        up=[supported(-13.7-2*i/16) for i in range(17)]
        up[0]['caption']='Codo al suelo; '+('tobillo' if long else 'rodilla')+' superior sobre cama'
        up[-1]['caption']='Pelvis alineada; sostén sin girarte'
        frames=up+[cp(up[-1])]+[cp(f) for f in reversed(up[:-1])]
        motions=[phase('Eleva la pelvis',seconds=.15) for _ in up[1:]]+[phase('Sostén',kind='hold',seconds=2)]+[phase('Baja con control',seconds=.15) for _ in up[1:]]
        return result(frames,motions,props=bench(support_x,-18 if long else -17.4,width=10,depth=7),per_side=True,yaw=25,pitch=25)
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
        # 052: velocidad máxima, tronco casi erguido y extensión completa.
        frames,motions=running('lanzado','Tramo lanzado · ')
        return result(frames,motions,yaw=35)
    if name == 'Intervalos 15/15':
        # 052: zancada de carrera erguida, sin agacharse; el ritmo lo marca el reloj.
        frames,motions=running('carrera','15 s rápido · ')
        return result(frames,motions,yaw=35)
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
