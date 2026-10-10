# Seis guías de calentamiento · propuesta014

Fuente de partida:929f2897c73a86760cc73ce228a89f3aaa3789a8, worktree
`seguimiento-014-calentamiento`, rama `JuxnD/014-figuras-calentamiento`.
La versión base incluye las fichas del calentamiento, pero no estas seis figuras.
Este frente no cambia tiempos, dosis, selección por molestia ni esquema de datos.
Las imágenes son capturas del painter y la hoja Flutter; no prueban instalación
ni comprensión humana. Personalizados siguen informando ausencia explícitamente.

| Guía | Lectura visual y apoyos | Control ejecutable |
|---|---|---|
| Círculos de hombros | Brazos relajados; hombros arriba, atrás, abajo y delante | Movimiento escapular distinto del cuello; articulaciones y suelo |
| Balanceos de pierna | Pierna cercana móvil; mano en pared lateral y pie lejano fijo; vuelta al centro antes del lateral |61muestras, apoyo fijo y pie transversal a tibia; arco opt-in, sin cuerda que flexione rodilla artificialmente |
| Retracciones escapulares | Colgado; hombros bajan y torso sube poco, manos en barra | Manos fijas y codos rectos en61muestras |
| Flexiones escapulares | Plancha; pecho baja/sube ligeramente, brazos sin flexionarse | Palmas y pies conservados; codos rectos, cadera estable |
| Puente de glúteo | Pies planos, hombros apoyados, pelvis sube; cabeza descansada | Hombro-cadera-rodilla alineados arriba; apoyos y cabeza horizontal |
| Dislocaciones con banda | Banda visible entre manos separadas; delante→arriba→atrás y regreso | Agarre de ambas manos, brazos rectos y banda despejada de la cabeza |

## Extensiones mínimas del rig

`shoulderOffset:[frontal,longitudinal]` por pose: unidades del maniquí
(aproximadamente3,2cm/u), relativo al cuello. Frontal apunta hacia el pecho;
longitudinal sigue cadera→cuello, aun con torso horizontal. Default `[0,0]`.
Python resuelve los brazos desde ese hombro; JSON conserva el campo sólo en
poses explícitas; Dart lo copia, resuelve en2D, levanta en3D e interpola anclajes
mundiales antes de volver a coordenadas locales. Así el torso puede moverse
respecto a las manos sin fingir flexión de codo. No representa toda la escápula.

`keepReachRadius:true` por extremidad/pose conserva el radio de `reach3` durante
la interpolación: dirección normalizada × radio lineal interpolado. `reach3`
está relativo a la raíz de la extremidad, en ejes del mundo, unidades del cuerpo.
La pierna móvil usa radio27,5u frente a28u de huesos totales: ligera flexión
y holgura para pasar cerca del suelo, acorde con la ficha «relajada». No altera
escala corporal ni pie de apoyo. Sólo la pierna móvil de Balanceos lo activa; defaultfalse conserva exactamente
la cuerda de las figuras previas. Se exigen dos extremos con flag y radio finito
no nulo. Antipodales exactos requieren un pole perpendicular que define el plano;
los casi antipodales usan el plano de los extremos y el ángulo real. Datos
ambiguos se rechazan explícitamente, sinNaN ni sustitución global.

No se debilitaron guards de suelo/contacto ni el umbral ilustrativo tibia-pie0,35.
Ese umbral discrimina pies extremos en este maniquí; no es una regla clínica.
El contrato legado se prueba contra73 hashes de coordenadas2D/3D en61muestras,
obtenidos ejecutando el rig original de929f289 (no regenerados con el candidato).

## Referencias y límites

- [ACE: Glute Bridge](https://www.acefitness.org/resources/everyone/exercise-library/49/glute-bridge/): pies planos, rodillas dobladas y evitar arco lumbar.
- [ACE: Scapular Motion](https://www.acefitness.org/certifiednewsarticle/2384/correct-cues-for-scapular-motion/): diferenciar protracción/retracción, brazos y escápulas; no se extrapolan indicaciones terapéuticas.
- [CUH NHS: Shoulder rolls](https://www.cuh.nhs.uk/patient-information/cardiac-rehabilitation-home-exercise-guidelines/): hombros en círculo con brazos relajados; no se adopta la dosis de rehabilitación cardíaca.
- [CrossFit: PVC Pass-Through](https://www.crossfit.com/at-home/pvc-pass-through): referencia del nombre del movimiento; página consultada, vídeo no inspeccionado cuadro por cuadro. La guía local limita rango cómodo, separa las manos y pide parar si duele. No se certifica un ángulo universal.

Balanceos y fases concretas usan también las fichas locales existentes; falta
aceptación de un profesional y del owner para comprensión y técnica personal.
El nombre heredado «dislocaciones» se explica como paso de banda, no una luxación.
No se prescribe hacerlo por dolor: esa política pertenece al frente de dominio.

## Reproducir las capturas

`python tool/figuras3d.py` regenera el únicoJSON autoritativo, nunca se edita a mano.
Usar Flutter3.22.0 y las fuentes versionadas. `ILLUSTRATION_NAMES` admite nombres
exactos separados por punto y coma, comprueba cobertura y prevalece sobreALL;
los modosALL/default existentes siguen disponibles. `ILLUSTRATION_OUT` señala
una carpeta local. El test `illustration_mockup_render_test.dart` captura poses,
intermedios15/60 y35/60 y hojas reales a escala1,0/1,6 con instrucciones desplazadas.
La marca «Propuesta · no instalada» forma parte de los mockups, no de la UI final.

Gates de ejecución, hashes y residuos: recibo de sesión014 en `docs/context/sessions/`.


Los montajes se reproducen con `python tool/warmup_mockup_montage.py`; el helper
sólo compone y reduce capturas Flutter, no redibuja posturas. Hay65PNG reales:
28claves,12intermedios,1espejo y24hojas (6×2escalas×2scrolls).
[Recorridos y resumen](calentamiento-014/resumen.jpg),
[hojas con texto grande](calentamiento-014/hojas-texto-1-6-top.jpg),
[instrucciones con texto grande](calentamiento-014/hojas-texto-1-6-cues.jpg).
Los hashes individuales están en `calentamiento-014/capturas-sha256.json`.
