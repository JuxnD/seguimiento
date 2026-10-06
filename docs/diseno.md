# Diseño y motivación

La app tiene que dar ganas de abrirla sin volverse recargada. El criterio: **el
progreso se ve antes de leerse**, y cada color significa algo.

## Sistema visual

Tema oscuro único ([`lib/ui/theme.dart`](../lib/ui/theme.dart)) con la paleta
del logo: fondo `#0B0806`, superficies `#150F0B` y `#241A13`, naranja base
`#F08A34` (profundo `#E4661F`) reservado para lo accionable y el dato en foco,
texto `#FFF6EC`. Todo lo demás son neutros cálidos.

**Ícono**: anillo de 10 segmentos (la meta de 10 rondas) con la figura colgada
de la barra. Los originales están en `assets/icon/`; `python tool/icons.py`
genera el ícono clásico, el adaptable (con capa monocroma para los íconos
temáticos) y el de la barra de estado.

### Color por tipo de día

Definido una sola vez en [`lib/ui/session_style.dart`](../lib/ui/session_style.dart)
y usado en Hoy, el plan y las sesiones, para que el tipo se reconozca sin leer.

| Tipo | Color | Icono | Por qué |
|---|---|---|---|
| Circuito | Naranja `#FF7A18` | Ronda | El trabajo principal: es el acento de la app |
| Circuito ligero | Naranja claro `#FFB067` | Ronda abierta | La misma familia, más suave |
| Progresión | Rojo `#FF4D4D` | Tendencia al alza | El día de intentar récord |
| Bloques | Azul `#4EA8FF` | Columnas | Fuerza por series, otro registro |
| Fútbol | Verde `#7ED957` | Balón | Cardio de fin de semana |
| Descanso | Gris `#9A9AA2` | Luna | No hay nada que hacer |

Los anillos usan su propio color fijo: proteína azul, kcal naranja claro,
rondas el color del tipo del día.

## Tarjeta principal en todas las pestañas

Cada pestaña abre con una **tarjeta principal** ([`lib/ui/hero.dart`](../lib/ui/hero.dart))
con el lenguaje de Hoy: degradado del color de la sección, rótulo en mayúsculas,
dato en grande y píldoras de estado. Debajo, filas con icono de color
(`TypedTile`) y estados vacíos con icono (`EmptyState`).

| Pestaña | Color | Qué muestra la tarjeta |
|---|---|---|
| Hoy | Color del día | Tipo de día, racha, semana, ejercicios |
| Entreno | Color del día | Qué toca hoy, racha, récord, empezar / a mano / fútbol |
| Comidas | Naranja claro | Día con navegación, anillos de proteína y kcal, armar comida |
| Cuerpo | Verde | Último peso, cambio desde el primero, cuándo medir |
| Informe | Naranja | Semana con navegación |

## Pantalla Hoy

[`home_screen.dart`](../lib/features/home/home_screen.dart), alimentada por
[`DashboardRepository`](../lib/data/repositories/dashboard_repository.dart) en
una sola consulta.

1. **Tarjeta del día**: fecha, racha, semana desde el inicio, tipo en grande con
   su color e icono, meta de rondas y ejercicios. Un ✓ cuando ya entrenaste.
2. **Anillos**: proteína y kcal contra la meta, y rondas contra el objetivo (o
   sesión hecha/no hecha si el día no cuenta rondas). Se animan al cambiar, así
   que registrar una comida se nota. Debajo, el récord vigente.
3. **Registrar**: el botón principal toma el color del día y dice qué empieza.
4. **Medición**: días para la próxima, o que ya toca.

## Racha

[`currentStreak`](../lib/domain/progress.dart): días seguidos con sesión. Un día
de **descanso o fútbol planificado no la rompe ni la suma**; un día de
entrenamiento sin sesión sí la corta. Hoy sin entrenar todavía no rompe lo de
ayer. Probado en [`test/domain/progress_test.dart`](../test/domain/progress_test.dart).

## Récord

Al guardar una sesión de circuito que **supera** el máximo anterior (igualar no
cuenta) aparece una celebración a pantalla completa con la marca nueva y la
anterior. No se dispara si las rondas fueron estimadas o la sesión quedó
incompleta: un récord tiene que ser contado.

## Gráficas (pestaña Informe)

[`charts_section.dart`](../lib/features/report/charts_section.dart), con `fl_chart`.

| Gráfica | Qué muestra |
|---|---|
| Rondas por sesión | Evolución de las sesiones de circuito: la línea que debe subir |
| Proteína por día | Barras del rango del informe con la línea del mínimo; los días por debajo se ven apagados |
| Peso | Evolución, solo con pesajes en ayunas si los hay |
| Medidas | Una línea por sitio, con selector; solo aparecen los sitios con al menos dos tomas |

Los días sin dato se dibujan en cero en vez de unirse con una pendiente
inventada. El eje de rondas solo muestra enteros y se deja margen para que la
última fecha no se corte.

## Fotos de progreso

**Cuerpo → Fotos de progreso.** Frente, perfil y espalda por fecha, con
**comparador lado a lado**: dos fechas, el mismo ángulo, y los días entre ellas.
Mantén presionada una foto para borrarla.

Las fotos se copian al directorio de la app y la base guarda la ruta relativa
(`fotos/2026-09-23-frente.jpg`): una ruta absoluta se rompe al reinstalar.

**Las fotos no van en el respaldo**: el archivo exportado es la base de datos.
Ver [roadmap](roadmap.md).

## Figuras de técnica en 3D (iteración 1)

Primera iteración de un **maniquí compartido** en 3D, validado en tres
ejercicios antes de llevarlo al catálogo: *Pino pecho a la pared*, *Nórdico
(isquios)* y *Dominadas* (la del lunes, con mochila). El resto sigue con las
figuras planas; la hoja de técnica elige sola.

**Cómo funciona.** [`tool/figuras3d.py`](../tool/figuras3d.py) reutiliza la
cinemática de perfil de `tool/figuras.py` (mismos largos de segmento, misma
IK) y exporta a `assets/tecnica/figuras3d.json` la postura de cada momento
clave: cadera, ángulo del torso, ángulos de cada extremidad, apoyos (mano en
la barra, en el suelo), orientación de pies y manos, zonas musculares, props
y la vista inicial. La app ([`lib/ui/exercise_figure_3d.dart`](../lib/ui/exercise_figure_3d.dart))
sube esa postura a 3D (lado cercano en z = +ancho, lejano en z = −ancho; los
codos con IK 3D hacia afuera), interpola entre momentos (ángulos por el camino
corto, apoyos sujetos con IK, la cadera del nórdico girando sobre las
rodillas, los pies del pino deslizándose por la pared en vez de atravesarla
y, como con el suelo, nada cruza una pared) y pinta con Canvas en orden de
profundidad. Sin dependencias nuevas.

**Qué hace reconocible al maniquí** (la crítica de la primera maqueta):

| Pedido | Cómo se resolvió |
|---|---|
| Cabeza y hacia dónde mira | Esfera con nariz, ojo y oreja visibles solo del lado de la cámara, y pelo oscuro en nuca y coronilla |
| Pecho y espalda | La espalda es un tono más oscura que el pecho; glúteos y pecho marcan el perfil; línea del esternón cuando el frente da a la cámara |
| Pelvis | Pantaloneta azul en cadera y arranque del muslo |
| Manos y pies | Mitones con pulgar (o puño cerrado sobre la barra) y zapatos en cuña con suela clara: se ve hacia dónde apuntan los dedos |
| Lado cercano y lejano | El lejano más oscuro y apagado, con contorno más fino |
| Naranja = un músculo | Una cara del segmento, no el cilindro: isquios (atrás del muslo), deltoides (casquete del hombro) y tríceps, dorsal (triángulo de la axila a la cintura) |
| Apoyos | Sombras de contacto bajo manos, rodillas y pies; el sofá se pinta en corte sobre los pies, con una marca turquesa donde empuja el talón |

**Presentación.** En la hoja de técnica, tres momentos grandes (inicio,
medio, final) que se pasan de lado, casi a todo el ancho y 260 dp de alto,
con su pie debajo. *Ver movimiento* los anima en el mismo cuadro (va y
vuelve, con una pausa en cada momento). Tocar un momento lo abre en pantalla
completa: ahí arrastrar gira la figura (±60°) y *De perfil* o un doble toque
la devuelven a la vista inicial; ampliar mientras se anima abre la pose que se
estaba viendo. El pie de cada momento crece con el texto del sistema (se mide,
no se reserva un alto fijo). La vista inicial es de perfil con una leve
inclinación; el pino arranca 15° desde atrás (para ver la pared de frente y
que la nuca da a la sala) y la dominada 14° desde adelante (de perfil exacto
la barra se ve de punta).

**Variante.** Una figura puede declarar la variante que dibuja (`variant` en
`tool/figuras3d.py`: la dominada es prona con mochila). El cronómetro pasa a la
hoja el agarre del paso y si va con carga; si no coincide (jueves supina,
circuito sin mochila) se muestra la figura plana, y el paso de la mochila de
la guía escrita se omite. Desde el catálogo, sin contexto, se ve la 3D.

**Agregar un ejercicio.** Copiar una entrada de `EXERCISES` en
`tool/figuras3d.py` con el mismo nombre del catálogo (se busca sin tildes ni
mayúsculas), tres momentos y sus pies (`Inicio: …`, `Medio: …`, `Final: …`),
`regions` con la cara del músculo, los `props` y, si algo se esconde de
perfil, `view`. Correr `python tool/figuras3d.py` (avisa si algo queda bajo
el suelo o un apoyo no se alcanza) y revisar a ojo con
`FIG3D_OUT=<carpeta> flutter test test/ui/exercise_figure_3d_render_test.dart`,
que escribe los PNG de cada momento, girados y la hoja completa.

**Límites conocidos.** Es un maniquí de cápsulas: no hay manos con dedos ni
músculos con volumen propio. El orden de pintado es por pieza, así que en
giros extremos una pieza puede tapar mal a otra. Las posturas son de perfil:
lo que pasa en el plano frontal (codos abiertos de la dominada) se aproxima
con la IK 3D de los codos. El bíceps de la dominada no se resalta porque casi
nunca da a la cámara. En la caja de 260 dp las figuras altas (pino,
dominada) quedan más chicas; la pantalla completa lo compensa.

