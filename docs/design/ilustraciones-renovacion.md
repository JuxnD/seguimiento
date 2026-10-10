# Renovación integral de ilustraciones — en curso

## Pedido y autoridad

El 9 oct el owner pidió renovar todas las ilustraciones, preparar mockups y
revisar diseño, forma y orientación para entender un ejercicio desconocido.
La 1.21 está publicada; esta renovación se trabaja aislada en
C:/My Projects/seguimiento-ilustraciones, rama JuxnD/ilustraciones-completas,
base7b28ef6. No se ha autorizado ni hecho otra publicación por este pedido.

## Hallazgo actual

APK público1.21 SHA7410dca1 contiene15figuras planas y3figuras3D (unión17).
3D: pino pecho a la pared, nórdico, dominadas pronas con mochila. El circuito
sin carga y la supina caen a2D. Source56a4fb7 está en tags1.19/20/21.
ExerciseFigureView sólo entra por TechniqueContent; no hay biblioteca navegable
para abrir figuras antes de entrenar. «Desde el catálogo» en docs/diseno.md
no corresponde a una ruta de catálogo real del APK.

51guías de catálogo,45detalles extensos,figuras y movilidad forman al menos
73nombres (66unión inicial+7recuperación de piernas). Se deben resolver aliases
sin borrar variantes distintas. Inventario final se verificará con siembra real
más nombres del plan, escaleras y las dos rutinas de movilidad.

25pruebas del visor existente pasaron. Inspección APK confirma el asset; la
primera exploración nativa no llegó a captura3D: AVD5580 se cerró/adb offline.
No se atribuye causa a la app o al emulador sin reproducir. El snapshot propio
QA original está conservado en ready/release/qa-figuras-2026-10-09.
No se operó teléfono ni datos del owner. No se afirmó aceptación visual.

## Contrato del rediseño

- Superficie Read/Operate dentro de la app Android existente: tema oscuro,
  acento naranja, texto Material legible. No cambiar identidad general.
- Figura humana simplificada, articulaciones continuas, manos/pies y ropa
  identificables. El color no sustituye la postura ni señala miembros enteros.
- Inicio/recorrido/final o secuencia específica; una vista principal grande y
  controles de pasos. Frontal/lateral/3-4 según movimiento, ampliar y animar.
- Apoyos, banda, anclaje, silla/mesa/barra y carga correctos. Agarre y variante
  concordantes con la sesión. Nunca sustituir silenciosamente por otra técnica.
- Biblioteca accesible desde Entreno, búsqueda por nombre y consulta previa.
- Cobertura de todos los ejercicios conocidos, movilidad y peldaños; la ausencia
  de ilustración para nombres personalizados se declara, no se dibuja una genérica.
- Mockups provenientes del mismo catálogo/renderer que la app; escenas
  representativas de inversión, unilateral, banda, suelo y movilidad.

Hipótesis perceptiva (PFD): apoyos visibles, frente/espalda reconocibles y
secuencia explícita ayudarán a identificar colocación y recorrido. Se valida
pidiendo al owner señalar manos/pies, orientación y movimiento de un ejercicio
que no conozca; no se da por aceptado por tener capturas o tests verdes.

## Trabajo y gates

1. Inventario+fuentes+matriz de variantes, prioridad por ambigüedad.
2. Mockups representativos y nuevo lenguaje de ilustración completo.
3. Generador/catálogo sin huecos; geometría propia por ejercicio, no copiar una
   pose genérica a todas las entradas.
4. Visor/consulta en app y actualización de referencias de movilidad.
5. Pruebas de cobertura, apoyos, variantes, texto/grandes tamaños/reducir
   movimiento, apertura desde rutas reales y APK candidato firmado.
6. Revisión visual acotada de teléfono/desktop y aceptación del owner separada.

Reusar guías, nombres, registro, figuras procedurales y controles existentes.
Extender el rig para planos frontal/oblicuo donde el rig de perfil actual no
representa el movimiento. Fuente por dato/página en la matriz; geometría y
orientación se contrastan, no se certifican médicamente con un render.

## Implementación candidata y revisión (9oct)

73entradas generadas, consulta independiente en Entreno, lados/agarre/carga,
movilidad usa visor compartido. Primera inspección encontró pies desaparecidos,
plancha lateral frontal y pike apoyando codos; corregidos con geometría real.
Reviewer independiente detectó contactos, finales y discontinuidad anatómica.
Tanda1 resolvió equipo/Toes/Vela/flexión; dejó parciales3/4/5/8 y abierto7.
Tanda2 aplica unión real de siluetas (no winding que produce agujeros), cámara
con límites proyectados simétricos, carrera con brazo flexionado y fixtures
Roboto para rótulos. El verdict final permanece pendiente hasta relectura.
No se identifica regeneración como aceptación humana.

Nueva petición9oct: acompañamiento dinámico, aviso7días/PlanB y base5000.
Auditoría [Plan007](../../plans/007-progreso-recuperacion-metas.md) con datos
ficticios refuta congelación general deproviders y prueba truncado de racha.
Se corrige consulta/corte por moderado, promesas fijas y consejo con datos
insuficientes/viejos. Nuevo perfil5000; existente conserva su meta hasta aceptar
el cambio explícito y guardar. Adaptación longitudinal con vigencia/historial,
fatiga/sueño y decisiones revisables permanece especificada, no implementada.

## Revisión independiente final y control semántico

Verdict2:1equipo,2finales,4cámara90/90,6flexión,7silueta y8rótulos resueltos.
3figura4 y5carrera quedaron parciales en la revisión visual acotada. No se
reescribe ese verdict como aprobado. Se corrigieron después dos errores
semánticos concretos: tobillo a rodilla opuesta y mano de carrera bajo cabeza.
Test nuevo falla contraJSONdelAPK previo (distancia real de contacto), pasa
contraJSONcorregido; comprensión del owner sigue abierta. No se abre otro
ciclo de búsqueda estética. Fuentes primarias contrastadas:
[figura4](https://na.physitrack.com/home-exercise-video/supine-figure-4-stretch),
[carrera](https://ace-pt.org/ace-physical-therapy-and-sports-medicine-institute-what-is-correct-running-form/),
[wallwalk](https://www.crossfit.com/essentials/the-wall-walk),
[nórdicoFIFA](https://tiim.no/ovelse/nordic-hamstring-niva-1-fifa-11).
Los montajes no sustituyen demostración técnica completa ni aceptación humana.


## Nueva ronda por feedback del owner (9oct)

El owner rechazó visualmente Cuádriceps (tobillo) y Vela (apoyo/orientación
incomprensible). Esto invalida cualquier lectura de la revisión anterior como
aceptación del catálogo. Inventario independiente: 73 nombres y 410 combinaciones
de lado/momento, diagnóstico en `build/reviewer-orientation-inventory.json`.
Encontró cabeza que seguía al torso, asas con eje de barra, pies invertidos y
manos separadas del equipo en fondos/elevación colgado/remo.

Corrección candidata: cabeza horizontal independiente y pivote de hombros en
Vela/dragon; sujeción detrás visible y rótulos anclados a articulaciones; pie
neutral y sujeción corporal en Cuádriceps, pie de Piernas en la pared corregido;
agarres de barra transversal/paralela/asa/sujeción separados; fondos con paralelas,
remo con borde real, colgado con barra fija y contacto de manos; flexiones y
variantes comparten apoyo de dedos con talón elevado. Base de suela sigue el
plano del cuerpo al girarlo. No se usa un umbral angular universal como certificado.

Prueba `illustration_supports_test.dart`: cabeza/cara/apoyo y pie–tibia en los
casos del feedback, mano–equipo en todo el recorrido de 12 entradas con barra,
paralelas, mesa y sujeción detrás. Los tres casos fallan contra el JSON anterior
`build/qa/ilustraciones/pre-orientacion.json`, incluidos los 3,89 de separación
de fondos; el catálogo corregido pasa. No se cambió la prueba para aceptar una
mano sin apoyo. Fuente de Cuádriceps:
[Mayo Clinic](https://www.mayoclinic.org/healthy-lifestyle/fitness/in-depth/stretching/art-20546848),
[Physitrack](https://na.physitrack.com/home-exercise-video/quadriceps-stretching-in-standing).

La galería se regenera con el visor nativo. El APK previo no contiene estas
correcciones; sólo un build posterior puede atribuirse a ellas. Revisión final,
lectura en Android y comprensión del owner son gates separados; publicación
sigue abierta. No se operó teléfono ni se cambiaron datos personales.


Revisión final de esta ronda: detectó mano libre a suelo en flexión unilateral y
palmas flotantes en plancha inversa. Corrección recoge brazo libre y calcula
postura con brazos rectos/alcance posible; fixture anterior falla ambos controles.
Pike conserva palmas al corregir altura de zapatos. Vela/dragon muestran
colchoneta y apoyo firme bajo espalda alta, para separar cabeza descansada del
apoyo de hombros. Rótulos Roboto inspeccionados legibles en la recaptura final;
el bloque Ahem pertenecía a capturas anteriores y no se toma como estado vigente.
La nueva validación exige apoyo explícito, no sólo centro de joint por encima del suelo.
