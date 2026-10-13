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
