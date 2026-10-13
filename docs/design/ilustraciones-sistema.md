---
name: Seguimiento — sistema de ilustraciones
description: Guías visuales consultables para reconocer posiciones, orientación y apoyos.
colors:
  accion: "#F08A34"
  fondo: "#0B0806"
  superficie: "#150F0B"
  superficie-alta: "#241A13"
  texto: "#FFF6EC"
  texto-secundario: "#C9B8A8"
  texto-sobre-accion: "#1A0C00"
  borde: "#4A3526"
  piel-frontal: "#CF9670"
  piel-posterior: "#A2826A"
  ropa: "#3F6476"
  equipo: "#34766E"
  contacto: "#3DD6C6"
typography:
  titulo-pantalla:
    fontSize: "22px"
    fontWeight: 700
    letterSpacing: "0.2px"
  boton-principal:
    fontSize: "15px"
    fontWeight: 700
  navegacion:
    fontSize: "11px"
    fontWeight: 500
rounded:
  campo: "12px"
  accion: "14px"
  tarjeta: "16px"
  chip: "10px"
spacing:
  relacion: "4px"
  grupo: "8px"
  interior: "12px"
  margen: "16px"
components:
  boton-principal:
    backgroundColor: "{colors.accion}"
    textColor: "{colors.texto-sobre-accion}"
    typography: "{typography.boton-principal}"
    rounded: "{rounded.accion}"
    height: "48px"
  boton-secundario:
    textColor: "{colors.texto}"
    rounded: "{rounded.accion}"
    height: "44px"
  campo-busqueda:
    backgroundColor: "{colors.superficie-alta}"
    textColor: "{colors.texto}"
    rounded: "{rounded.campo}"
  chip-seleccionado:
    backgroundColor: "{colors.accion}"
    textColor: "{colors.texto-sobre-accion}"
    rounded: "{rounded.chip}"
  chip:
    backgroundColor: "{colors.superficie-alta}"
    textColor: "{colors.texto}"
    rounded: "{rounded.chip}"
  figura:
    backgroundColor: "{colors.fondo}"
    rounded: "{rounded.accion}"
    height: "330px"
---

# Design System: Seguimiento — ilustraciones

## Overview

**Creative North Star: "Apoyo visual para aprender el ejercicio"**

Sistema derivado del candidato en `lib/ui/exercise_figure_3d.dart`,
`lib/ui/exercise_figure_3d_view.dart`, la biblioteca de ejercicios y el tema
nativo. Conserva la identidad oscura y naranja de Seguimiento. El cuerpo
humano mate, la ropa azul y los objetos de apoyo dan referencias para leer
la posición; las figuras tienen momentos con explicaciones y una vista ampliable.

La consulta sigue buscar → abrir guía → recorrer momentos → ampliar y girar
→ leer técnica. La biblioteca no crea una sesión. Este documento describe
implementación, no aprobación clínica ni aceptación del usuario. El catálogo
del candidato contiene 73 entradas, incluyendo alias, progresiones y movilidad;
no son 73 movimientos distintos. La release pública 1.21 tiene cobertura parcial.
`build/mockups/renovacion` contiene capturas del mismo renderer para revisión,
no composiciones aceptadas ni evidencia de publicación.

**Key Characteristics:**
- Figura humana y equipo representados con un rig determinista compartido.
- Momentos rotulados y controles explícitos de orientación.
- Variantes de lado, agarre y mochila cuando el catálogo las soporta.
- Identidad visual heredada del tema de la app y movimiento opcional.

## Colors

Paleta cálida para la interfaz y materiales sobrios para separar cuerpo, ropa y equipo.

### Primary
- **Naranja de acción:** controles y selección; en el cuerpo, regiones de trabajo.

### Secondary
- **Azul de ropa:** separa el pantalón del torso y las extremidades.
- **Verde de equipo:** mochila y objetos cargados; evita confundirlos con piel.
- **Turquesa de contacto:** marcas visuales de apoyo cuando el renderer las dibuja.

### Neutral
- **Negro cálido:** fondo de figura y pantalla ampliada.
- **Superficies marrones oscuras:** campos, tarjetas y chips sin seleccionar.
- **Marfil y beige:** texto principal y texto de apoyo.
- **Piel frontal y posterior:** materiales diferentes con luces y sombras propias.

### Named Rules
**The Material Reference Rule.** Frente, espalda, ropa y equipo conservan su material al girar; la orientación no depende únicamente del color.

## Typography

El sistema utiliza el `TextTheme` de Material 3 heredado por `buildGymTheme`.
No introduce una familia tipográfica propia. Los tamaños del frontmatter son
las modificaciones explícitas del tema; las instrucciones y los pies heredan
los roles `bodyLarge`, `labelLarge`, `titleMedium` y `bodySmall`.

### Hierarchy
- **Título de pantalla:** nombre de la superficie, peso fuerte.
- **Título de guía:** nombre del ejercicio y secciones de técnica.
- **Cuerpo:** pasos y errores frecuentes del catálogo existente.
- **Pie de figura:** número de momento y descripción, centrados; altura calculada con el ancho y la escala de texto reales.
- **Etiqueta:** botones y variantes breves, con selección visible.

### Named Rules
**The Caption Space Rule.** Los pies de momentos crecen con la escala de texto; su lectura no se resuelve recortando la explicación.

## Layout

Biblioteca vertical con búsqueda, filtro por grupo y lista desplazable. Cada
fila muestra miniatura, nombre, grupo y acceso a la guía. La búsqueda normaliza
los nombres; un resultado vacío explica que se puede probar otro nombre.

La guía conserva márgenes de 16 y grupos separados por 8. Las variantes se
distribuyen con `Wrap`, evitando exigir una sola fila. La figura de cada
momento tiene altura de 330 unidades lógicas de Flutter. El carrusel usa
fracción de viewport 0.94 para sugerir el siguiente momento; la miniatura de
la biblioteca es sólo navegación, no reemplaza esta figura grande.

La vista ampliada reparte el espacio entre un lienzo flexible y controles
desplazables. Estos últimos tienen un máximo de 350 o 40% de la altura de
pantalla, el menor. `SafeArea` protege los controles. La cámara encuadra las
poses y objetos del recorrido. No se define un breakpoint de escritorio: es
una superficie nativa que responde a las restricciones reales del dispositivo.

## Elevation & Depth

Las superficies de interfaz usan separación tonal y bordes del tema; las
tarjetas y la navegación tienen elevación cero. La profundidad de la figura
se expresa con proyección, materiales sombreados, orden por profundidad y
sombras de contacto. El suelo no lleva una cuadrícula decorativa. La oclusión
que impida leer una mano, un apoyo o una extremidad es un hallazgo por revisar,
no una característica que este sistema legitime.

## Shapes

Campos, acciones, chips y tarjetas heredan los radios del tema. El cuerpo
combina contornos de extremidades, cabeza, torso, manos y calzado; los apoyos
usan geometría reconocible según el objeto. El rig se resuelve desde las
poses del catálogo, sin una semilla aleatoria ni imágenes generadas al azar.
La forma busca reconocer cuerpo y apoyo; no pretende constituir un modelo
anatómico o biomecánico validado.

## Components

### Buttons
Botones principales llenos para acciones; secundarios delineados y acciones
de texto para vistas. Heredan colores, forma y mínimos de altura del tema.
Los controles de movimiento se deshabilitan con movimiento reducido; las
secuencias marcadas sin continuidad no ofrecen una animación interpolada.

### Chips
Lado izquierdo/derecho, prona/supina y mochila se muestran sólo donde la guía
los soporta. Los momentos se pueden seleccionar también en la vista ampliada.
El chip seleccionado utiliza fondo de acción y texto oscuro. La selección de
lado se transmite al rig, no se limita a cambiar la etiqueta.

### Cards / Containers
El contenedor de figura usa fondo negro cálido y borde redondeado. La biblioteca
usa filas con divisores y miniaturas. La hoja de técnica conserva las secciones
de músculos, instrucciones y errores existentes.

### Inputs / Fields
Búsqueda con icono y etiqueta explícita. El campo hereda relleno oscuro, borde
y foco naranja del tema; los errores de carga ofrecen un reintento.

### Navigation
La entrada de guías está en Entreno. Una fila abre su guía; ampliar abre la
figura en una ruta propia, sin iniciar entrenamiento ni alterar registros.
Movilidad y sesión guiada reutilizan `ExerciseFigureView` con el lado o variante
del paso cuando existe ese contexto.

### Figura y momentos
El recurso es `assets/tecnica/figuras3d.json`, generado por la entrada única
`python tool/figuras3d.py`, que delega al catálogo completo. No editar el JSON
para crear una pose independiente del generador. `Figure3DPainter` dibuja el
mismo rig en miniaturas, guía, movilidad, pantalla ampliada y capturas.

La animación inicia sólo por acción del usuario: pausa de 0.6 s en momentos
y transición de 2.4 s con suavizado cúbico, ida y vuelta en figuras legadas.
Las figuras con etapas035 declaran su propio recorrido hacia delante:
`interpolate` para transiciones, `hold` para sostener, `cut` para cambios
anunciados de ejercicio o reinicio. Los contactos conservan coordenadas de
mundo; vuelo no se normaliza al suelo. No activar continuidad sin una
secuencia y apoyos explícitos. El contrato generado exige `motion` ⇒
`continuous: true`, comprobado sobre todas las entradas del asset. La consulta
manual y el movimiento reducido son estados del controlador: no convierten
una figura con etapas en `continuous: false` ni aplican el ajuste de suelo legado.
El curl conserva ángulos sagitales mediante
`planarAngles`, opt-in sólo para brazos sin pin y mano al plano del hombro;
las demás figuras conservan la resolución histórica.

Pausa/reanudar conserva pose y offset; salir del viewport o desactivar la
ruta detiene la reproducción. FIFA ofrece diez partes en selector compartido
entre visores: reproducir anima únicamente la seleccionada, detiene al final
y «Siguiente parte» cambia directamente a la siguiente postura/equipo.
Cambiar la figura o
activar movimiento reducido detiene la reproducción. Recorrer momentos sigue
disponible, así como la selección manual de partes. Arrastrar gira la cámara; `Vista inicial`, `De perfil` y `Ver apoyos`
dan alternativas explícitas. El giro horizontal está limitado a ±180° y la
inclinación a 0–85°. Las etiquetas semánticas incluyen ejercicio y momento.

Si una entrada personalizada no tiene figura se informa esa ausencia. Carga
fallida permite reintentar; no se sustituye silenciosamente la variante por
otra figura. Las pruebas de cobertura, geometría, navegación y render cruzan
costuras concretas, pero no certifican enseñanza segura ni comprensión humana.

## Do's and Don'ts

### Do:
- **Do** reutilizar el rig y el generador para que mockup y app compartan poses.
- **Do** mantener pies legibles y orientación, equipo y variantes explícitos.
- **Do** conservar consulta por momentos cuando el movimiento está reducido.
- **Do** revisar apoyos y oclusiones en capturas reales antes de aceptar una pose.

### Don't:
- **Don't** editar el asset generado para ocultar una discrepancia con su fuente.
- **Don't** interpretar 73 entradas o pruebas verdes como aceptación clínica o humana.
- **Don't** convertir un cruce de extremidades o contacto ambiguo en una regla visual.
- **Don't** presentar los mockups del candidato como ilustraciones ya publicadas.


## Apoyos y orientación (feedback del owner, 9oct)

Las señales de apoyo son texto Roboto de 12dp con líder y punto naranja unidos
al joint real; siguen la cámara y aparecen sólo en visores de al menos 200dp,
para conservar miniaturas simples. Se aplican a Vela/dragon, Cuádriceps, fondos
y remo donde el contacto resultó ambiguo. No sustituyen la secuencia ni el texto.
La cabeza de Vela/dragon se orienta aparte del torso, el apoyo gira alrededor
de hombros, y el equipo permanece fijo. Barra transversal y paralela tienen
ejes distintos; asa y sujeción corporal prolongan la muñeca en vez de heredar
el puño de barra. La suela sigue el plano corporal. Cada pose conserva su
orientación explícita; no hay normalización universal de tobillos.
