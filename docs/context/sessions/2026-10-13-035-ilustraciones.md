# 035 · ilustraciones y movimiento · ejecución local en curso

Autoridad: plan aprobado en `seguimiento-122-integracion/plans/035-ilustraciones-movimiento.md`.
Worktree exclusivo `seguimiento-035-ilustraciones`, rama
`JuxnD/035-ilustraciones-movimiento`, base `8ef2df4`. Sin APK, push, marca,
esquema, datos personales ni cambios de dosis.

## Evidencia disponible

- `035-evidence/geometry-red.txt`: cinco defectos reproducidos contra el generador original.
- `035-evidence/phases-red.txt`: falta de etapas explícitas; separado de los defectos geométricos.
- `035-evidence/geometry-phases-green.txt`: nueve pruebas Python; caracterización del generador, no aceptación visual.
- `035-evidence/dart-first.txt`: primera ronda real bajo lease035, nueve pasan y tres fallan.
  Straddle falló realmente: palmas a −2.52 en lugar del contacto −0.75.
  Los otros dos fallos fueron del arnés: MediaQuery sin tamaño posicionó los
  controles fuera del viewport. No se cuentan como rojos del producto.
- `035-evidence/analyze-first.txt`: un lint de llaves, corregido; pendiente repetir.
- `035-evidence/dart-baseline-8ef.txt`: contra código y catálogo originales
  8ef2df4, mismas seis pruebas geométricas: cinco fallos funcionales y una
  prueba de continuidad de dominada aprobada. `baseline-manifest.json` vincula
  fuentes, fixture y salida. El primer intento `dart-baseline-harness.txt`
  falló por import relativo del arnés y no cuenta como rojo funcional.
- `035-evidence/dart-round2.txt` y `dart-round3.txt`: 19 aprobadas y un fallo
  de curl. La segunda detectó desplazamiento del codo (0.213); la tercera,
  flexión artificial inicial (0.097) introducida por clamp de IK aun con los
  ángulos rectos. No se relajó el oráculo. Corrección posterior opt-in
  `planarAngles` conserva los segmentos angulares sin IK de agarre libre.
- `035-evidence/analyze-round3.txt`: cero incidencias, exit0, antes de los
  cambios posteriores de curl planar y selector FIFA (deben repetirse).
- `035-evidence/generator-determinism.txt`: regeneración de79 figuras con
  exit0 y SHA256 idéntico antes/después, anterior al ajuste posterior de
  FIFA9. La determinación final debe repetirse con ese ajuste. El asset sólo
  procede del generador.
- `035-evidence/fifa-hop-red.txt` y su manifest: el candidato previo a
  completar FIFA9 tenía desplazamiento lateral0, aunque decía salto. Rojo
  funcional Python conservado (no se atribuye a un commit original).
  Se autoró apoyo derecho, vuelo, apoyo izquierdo, vuelo y regreso, con
  traslación lateral y alcances3D explícitos en ambas piernas/todas claves.
  Diez verificaciones Python pasan después; falta mundo3D y revisión visual.

## Selector FIFA pendiente de verificar

Un control compartido entre inline y fullscreen selecciona las diez partes,
muestra «Parte X de 10» y ofrece «Siguiente parte». Reproducir se limita a la
parte seleccionada y se detiene al final; pausa/reanuda conserva fase.
La navegación cambia directamente a la postura/equipo de la siguiente parte,
sin interpolar el corte. Movimiento reducido permite selección manual.
Las pruebas contrastan parte declarada con progreso real del painter, no sólo
el texto. El rig, JSON y vista originales8ef y probe mínimo están aislados
en `build/qa/035/` para reproducir la ausencia del selector y el estado que
no se reinicia al cambiar figura. `fifa-baseline-manifest.json` conserva
SHA de la vista, transformación única del import y fuente del probe.
Ningún error de compilación o montaje se contará como rojo de producto.

## Causas y decisiones locales

- Cargas: flexión de rodilla lejana invertida en especificación angular.
- Curl con banda: interpolación angular corta 90→−100 tomaba el recorrido
  posterior. Se mantiene el codo estable y flexión por delante; no existe una
  entrada separada «curl con barra» en el catálogo.
- Straddle: alcance 3D de pierna menor que 28 producía flexión; ahora radio28.
  Además, torso−65 y palma al suelo exigían más de19 de brazo. La postura de
  straddle inclina el torso hacia delante (−50) sin alargar miembros ni cambiar
  el suelo. Falta verificar corrección Dart y renderer real.
- Colgado activo: elevación localizada del tronco, manos fijas y offset
  escapular. Oráculo adicional conserva torso18; no alarga brazos.
- Dominadas: muestreo1200 por agarre no reproduce salto geométrico del codo.
  Esto NO refuta la superposición visible denunciada; queda revisión real
  perfil/frente/35° con baseline y candidato antes de decidir corrección.
- Etapas opt-in (`interpolate`, `hold`, `cut`) conservan poses de mundo,
  contactos y vuelo. Cortes sólo entre partes y reinicio anunciado; negativos
  no suben como repetición automática. El catálogo preserva79identidades.
- Controles conservan offset/pose al pausar, reduced motion, ciclo de vida,
  salida de pantalla por scroll y ruta desactivada mediante TickerMode.

## Gates abiertos

Verificar dirigidas corregidas, rojo Dart causal con fixture8ef, análisis,
regresiones de soporte/geometría/legado; capturas reales en dos tandas acotadas,
incluidos pares confundidos, continuidad visible de dominadas y etapas FIFA.
Secuencia animada con renderer real si viable. Revisión root máximo dos ciclos.
Fullsuite corresponde a integración final y aceptación visual corresponde al
owner. Este recibo no declara implementación completa ni aceptación.

## Ventana guardada 2026-10-13 15:15–15:17 UTC

Fuente b655213 con formato120 y hashes postformato en `035-evidence/source-guarded.json`.
Cada comando pasó por el wrapper con token035 y recibo terminal; lease liberado,
reconsulta sin runners propios. Sin full ni capturas.

- Baseline8ef: dos rojos funcionales esperados, exit1: no existe selector FIFA;
  cambiar la figura fullscreen conserva progreso anterior en lugar de .35 y no
  detiene la reproducción. `fifa-baseline-guarded.txt`; no fallo de montaje.
- Candidato:21PASS/3FAIL, exit1 en `dart-guarded.txt`. Los seis oráculos de
  geometría PASS: incluye straddle, curl y colgado con longitudes conservadas.
  Dominadas geométrico PASS continúa sin cerrar la queja visual.
- `analyze-guarded.txt`: sin issues, exit0.
- `regressions-guarded.txt`:17PASS, exit0; soporte, geometría, legibilidad y
  paridad de73 figuras históricas más catálogo actual no seleccionado035.
- Python10/10 y determinismo final:79 figuras idénticas en dos regeneraciones;
  SHA955DE4FDDF3D3E709D205A06CC49416962385CBA2038E24501A6D926465469DC.

Diagnóstico posterior (todavía sin nueva ejecución Dart):

1. Burpees/key4/nearKnee: discontinuidad .1183 al cambiar pin→FK recto. El
   solver2D limitaba alcance a a+b−.001 y conservaba una flexión artificial
   incluso al límite de interpolación. Corrección opt-in `exactExtension`
   exclusivamente en resolución authored; ruta histórica conserva su clamp.
2. FIFA lateral: expectativa de punta−.9 confundía radio de tobillo .9 con
   envolvente de punta .6 definida en `jointPad`. Valor real−.614 está junto
   al suelo. Oráculo corregido comprueba punta+envolvente≈0 y coincidencia
   con Plancha lateral de referencia. No se alteró esa figura para satisfacer
   una coordenada incorrecta. Raw negativo se conserva como error de oráculo.
3. Inline: `widgetWithText(TextButton)` no encuentra el subtipo concreto de
   `TextButton.icon`. Finder usa `is TextButton` y texto; navegación mantiene
   `ensureVisible`/`hitTestable`. Error de harness, no rojo funcional.

Falta nueva dirigida+analyze+paridad tras estas correcciones. No hay aceptación
visual ni integración/R1 de035 por estos resultados.

## Diagnóstico del límite IK y cierre del oráculo (15:52 UTC)

Ronda guardada2:23/24PASS (todos los controles9 y geometría6), analyze0 y
paridad legacy PASS. Raw negativo preservado. El residual .01673/.01296 era
un supuesto de velocidad lineal respecto al progreso geométrico, no salto
restante. Mini diagnóstico compara modelo b655213 contra9fd397 con el mismo
asset y el controlador REAL (`figureMotionProgress`), sin doble easing.

`continuity-diagnostic.json` muestra key4 geométrica para epsilon1e-4/6/8/10:
actual .16694,.016729,.001673,.0001673; el modelo anterior converge a .1183216.
Es el límite sqrt(epsilon) de IK al extender una cadena de dos segmentos.
En tiempo real, epsilon1e-4 da .0012076 actual contra .1183216 previo;
1e-6 da .00001207 contra .1183216. Key5 confirma el patrón. Epsilon temporal
1e-8/10 redondea al mismo key: esos ceros NO sirven como evidencia de continuidad.

Oráculo definitivo mantiene umbral .01: exige convergencia geométrica multiε
(1e-6,1e-8,1e-10; razón≤.2 al reducirε100x, salvo ruido≤1e-6), límite<.01 y
delta de playback REAL alrededor del key conepsilon1e-4s<.01. Un control
pre-fix debe fallar por delta finito en ambos criterios. No se cambió fuente,
no se oculta salto con cut ni se deforma anatomía. Nueva ejecución pendiente.

## Primera revisión real del renderer y defecto FIFA3 (16:03 UTC)

530eedc:24/24 dirigidas PASS, control pre-fix causal FAIL [.118321595,.118321574]
con umbral.01; analyze0 tras retirar print del probe temporal (primer lint y
fuente original del diagnóstico conservados); paridad legacy PASS. Hashes en
source-final-directed.json. Ninguna prueba se contó antes de FIN terminal.

Batch1 produjo122 muestras candidato/15hojas y24 muestras baseline/1hoja usando
Figure3DPainter real. PNG y coordenadas se conservan en real-batch1; manifiesto
registra rutas originales y hashes. Dominadas baseline/candidato son iguales:
no se implementó una corrección de renderer por inferencia. Inspección de15hojas:

- Cargas/curl/straddle muestran posturas acordes con geometría ya verificada.
- V-sit sostiene equilibrio; V-up entra/sale desde supino. Vela sostiene vertical
  con agarre detrás como exige guía local501–509; Dragon desciende en bloque.
  No cambiar Vela a otra referencia de manos bajo pelvis ajena a esa guía.
- Colgado activo/pasivo mantienen diferencia pequeña anatómica, más anotación;
  no exagerar movilidad para aumentar contraste.
- Dominadas presenta oclusión de antebrazo/cabeza en vistas intermedias; estas
  imágenes no prueban dislocación ni causa de orden de profundidad. Requiere
  secuencia real densa antes de tocar renderer.
- Las etiquetas de la hoja están cortadas porque el painter deja clip315 y
  el harness escribe a316 sin restaurar. Defecto de captura, no UI de producto.
  Harness corregido con save/restore; no edición de píxeles.
- Uniformes Burpees omiten la plancha y FIFA no muestra todos los extremos.
  Segunda tanda usa todos los keys authored y captions reales.
- FIFA3 sólo balanceaba pelvis4X con pies fijos ybodyZ0. No representaba los
  pasos laterales de la guía: defecto concreto de referencia/movimiento.
  Rojo Python independiente0travel preservado. Corrección local de esa parte:
  paso de ida/vuelta con pie que abre/pie que sigue, levantamiento del pie libre,
  transferencia con apoyo estable y pausa para cambiar dirección. Sin nuevas
  dosis ni deformación del rig. Python11/11PASS; nuevo oráculo Dart de mundo
  comprueba pelvis+ambos pies viajan y apoyo real fijo, pendiente de ejecución.

Batch2 propuesto:193candidate+72baseline=265 muestras estáticas (más que la
estimación inicial~200 por incluir44keys FIFA y24muestras por3vistasDominadas).
Inventario exacto se aprueba por supervisor antes de lease. Animación propuesta:
5clips a20fps/1416frames reales:90/90(384),Burpees(336),Barca/V-up(252),
Dragon/Vela(192),Dominadas(252). Función figureMotionProgress de producción,
sin acelerar reloj; en comparación se pausa al terminar el ciclo más corto.
Sin loop artificial entre cuadros separados; composición GIF conserva20fps.
Fuente/renderers congelados antes de cada corrida. Capturas no son aceptación.

## Frontera normalizada de selector FIFA (16:31 UTC)

Ventana c8dc tras recursos recuperados: nuevo rojoDart fixture530 por viaje0
contra>6; candidato95bd con formato:24/25PASS, 1FAIL REAL en UI Parte5.
`dart-fifa-step-green.txt` es un nombre histórico incorrecto: contiene FAILURE,
exit1 y NO cuenta como verde; `fifa-step-result.json` lo clasifica explícitamente.
Analyze0 y paridad PASS; todos comandos FIN antes de cambiar fuente.

Causa medida:43stages, primer key departe5=23; 23/43*43 produce
22.999999999999996. Tres floor separados seleccionaban cut22 en vez de hold23.
Root verificó también key31 y aprobó reparación sólo authored. Nuevo resolver
`Figure3D.frameCoordinate` recupera enteros únicamente dentro de
2*machineEpsilon*max(1,abs(raw)). stageAt/skeletonAt/propsAt/inverseTime comparten
esa coordenada. Legado retorna raw sin tocarloopProgress. PropsAt es la misma
función usada por el renderer; no una copia para tests.

Nuevo oráculo26 recorre todas43fronteras exactas i/n, antes/después1e-8,
interiorescut/hold, pose de mundo/equipo/tiempo inverso y último endpoint.
UIrealParte5 preservada como rojo causal. No se relaja un umbral visual ni
se adelanta una fase con epsilon amplio. Nueva corrida pendiente.

### Contrato de continuidad authored
El exportador tool/illustration_catalog.py impone continuous:true cuando existe motion. La prueba Python revisa todas las entradas authored del asset, además de las secuencias solicitadas: 11/11 terminal exit0 (authored-continuous-python.txt). La navegación manual/reduced-motion es estado del controlador y conserva este contrato; continuous:false con motion no es una combinación emitida por el catálogo. Producto b756 sin cambios. Intento SDK16:43 rechazado exit42 por concesión reasignada: ninguna prueba Dart ejecutada, pendiente nueva ventana.

### Fronteras authored verificadas y captura ampliada
26/26 dirigidas terminal PASS, analyze0, legacy parity PASS (logs authored-boundary; recibos shared16:49). El formato sólo insertó una línea en modelo. Catálogo authored continuous validado Python11PASS. Rojos Parte5 previos preservados.
Capturador preparado una escena por comando, 7clips20fps:384+336+252+192+252+160+500=2076frames. Aceleración8s; FIFA sóloParte3 usa figureMotionParts/progressAt producción, tiempo real25.0s excluye cut (la previsión25.8 no coincide con asset, no se altera producto para satisfacer conteo). Cada clip guarda manifest separado con fuente/tiempo/progress/cámara; ensamblador conserva PNGsinredibujar y valida inventario antes GIF. Capturas aún pendientes nueva ventana; no afirmadas realizadas.

### Tanda2 real y siete clips — evidencia, no cierre
Fuente eef6e067b4a3487247be3d5523acb15bb4af930a. Capturas193candidato+72baseline y2076frames20fps terminalPASS; máximo12s por escena. EnsamblajeGIF exit0 verifica conteo, hashes y duración. Los GIF agrupan frames idénticos conservando tiempo; no se alteró velocidad. Rutas evidence/motion-preview y real-batch2, manifest/receipts por archivo. Dominadas72poses a3cámaras idénticaspixel baseline/candidato; tira temporal cerca frente conserva oclusión, sin causaIK demostrada.
HALLAZGO MATERIAL: Burpees clave5/7 recorta manos arriba en renderer real. cameraFor sólo toma9muestras uniformes, omite máximo authored; propuesta allkeys/submuestras authored preservando legacy, comunicada root antes fuente. No cierre visual ni claim de todoscasos resueltos. APIphysicalVariantKey coordinada con034 para doce variantes explícitas, pendiente commit compatible trasQA.

### Cámara authored corregida y verificada
Rojo camera-boundary-red: Burpee mano y FIFA mano/tobillo fuera del lienzo con volumen. Fix8a8 añade cada key+8submuestras por etapa al muestreo histórico y volumen conservador; no modifica movimiento ni cámara legacy/cache32. 27/27PASS,analyze0,legacyPASS con recibos camera-fix; sin alteraciones de fuente durante ventana.
Recaptura proporcional pendiente:10hojas authored91keys,6clips1824frames. ClipDominadas252 se reutiliza sólo tras probe de cámaras79figuras, mundo252samples y pixels11pares antes/después. Ensamblador marcará fuente original y verificación actual, no fabricará un SHA homogéneo. Los7GIFe eef6 quedan evidencia histórica, no finaldelproducto8a8.

### Recaptura verificada y vista oblicua de Dominadas
Fuentee46:91keys en10hojas+1824frames de6clips PASS; probe79cámaras conserva69legacy exactas y confirmaDOM252muestras mundo+11pares pixels idénticos. Ensamblaje20fps exit0 en motion-current; clip5 conservaSHAeef6 con recibo de reutilización. Hojas real-camera-fixed; Burpee manos completas inspeccionadas.
DOM vista real previa14°, no0 (consulta inicial root equivocada, corregida antes actuar). Radios sumados de codos: separación14°=1.76–1.98,35°=4.81–5.22: refuta colisión geométrica y respalda mayor separación visual, no reparaciónIK. Root aprobó sólo cámara inicial14→35, pitch12. Generadorcatalog actualizado y asset regenerado; comparación estructural demuestra78figuras exactas y DOM cambia únicamente view.yaw, sin geometría/grips/timeline. Python11PASS. Control existente ampliado para cambiar perfil y restaurar vista sin perderpose; Dart dirigido aún pendiente nueva ventana. Baseline73/929 intacto.

## Costura física y copy, 13oct17:54 UTC
598d7d + formato: 11 controles/API y legacy1 pasan; analyze1 conserva16 avoid_dynamic_calls en fixtures (api-analyze.txt). Se tipan únicamente mapas/listas, sin cambiar assertions ni producto; capturador original/evidencia de imágenes no se reescribe. Copia tipada separada camera_comparison_typed_test.dart.txt. Nuevo analyze y2API pendientes. DOM35 ycopyFIFA7 son diferencias de metadata documentadas; los seis clips recapturados y DOM35 reutilizado conservan sus SHA de captura.


Tipado API terminal17:56UTC:2API PASS y analyze0. Junto controles9+legacy1 del bloque anterior acredita interfaz compatible, no cobertura de nuevas figuras. FIN/liberación publicado. Se conserva analyze16 anterior; ninguna aserción relajada.


## Fase2 geométrica, 13oct18:24UTC
111bases y11keys exportadas;32bases nuevas,79MVP hashes exactos. Rojo previo demuestra ausencia32/11. Rojo3D detectó deriva de rodillaNordic (resuelta con pivote existente) y renderer ignorando columna/respiración/pie. Nuevos campos opt-in, pie de detalle con talón/metatarso/dedos estables; Copenhague cadena cerrada y apoyos cama/codo, anillas con primitivas tube, rotación codo estable, sóleo antepié fijo y landingapoyo/vuelo.5guided PASS +30regresionesMVP/API/legacyPASS,analyze0 sobre064706a+formato. Parse65 y rojos funcionales preservados. Aún falta QA visual real de todas las figuras yvariantes; no implementacióncompleta ni cierre formal.

