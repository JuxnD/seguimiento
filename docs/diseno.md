# Diseño y motivación

La app tiene que dar ganas de abrirla sin volverse recargada. El criterio: **el
progreso se ve antes de leerse**, y cada color significa algo.

## Sistema visual

Tema oscuro único ([`lib/ui/theme.dart`](../lib/ui/theme.dart)) con la paleta
del logo: fondo `#0B0806`, superficies `#150F0B` y `#241A13`, naranja base
`#F08A34` (profundo `#E4661F`) reservado para lo accionable y el dato en foco,
texto `#FFF6EC`. Todo lo demás son neutros cálidos.

**Marca actual My Prime (036):** icono MP/M-rayo, maestro SVG y pipeline determinista en assets/icon y tool/brand_assets.py. La inicial S de la candidata013 queda como referencia histórica; la identidad técnica y la base local se conservan.

**Referencia histórica de arranque016:** reutilizaba el foreground013, cuadrado108dp y centrado en
legacy; icono nativo31+ y fondo`#0B0806` también en NormalTheme/día/noche.
El arranque actual usa la marca036 MP/M-rayo y conserva el formato adaptativo sin espera artificial. Los30PNG013 quedan como evidencia histórica; XML y
referencias se verifican en fuente. Arranque frío/transición del APK exacto y
lectura del owner pendientes: [ADR0018](adr/0018-arranque-y-respaldo-android.md).

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

La racha de constancia cuenta días con sesiones de actividad guardadas de
cualquier tipo, incluidas movilidad, Activa/Suelta, técnica y recuperación
parcial; fútbol conserva su participación y el descanso planificado no rompe
la racha. Comidas, pesos, sueño y checks no son actividad. Este cálculo relee
el historial existente: no modifica registros ni el criterio de «Hoy hecho»
o adherencia al entrenamiento. Corrección local050, 14 oct 2026.

## Pantalla Hoy

[`home_screen.dart`](../lib/features/home/home_screen.dart), alimentada por
[`DashboardRepository`](../lib/data/repositories/dashboard_repository.dart) en
una sola consulta.

1. **Tarjeta del día**: fecha, racha, semana desde el inicio, tipo en grande con
   su color e icono y meta de rondas. **Empezar** aparece antes de los ejercicios;
   **Ver rutina** despliega todo el trabajo principal y los bloques A/B. Las
   alertas de carga, pulso y molestias quedan fuera del desplegable. Un ✓ cuando
   ya entrenaste; en ese caso se conserva **Día completo**, recuperación y el
   acceso secundario a otra sesión con su confirmación. El Plan B y la versión
   ligera mantienen sus acciones y reglas.
2. **Anillos**: proteína y kcal contra la meta, y rondas contra el objetivo (o
   sesión hecha/no hecha si el día no cuenta rondas). Se animan al cambiar, así
   que registrar una comida se nota. Debajo, el récord vigente.
3. **Registrar**: conserva los registros manuales, la fecha de destino y los
   atajos. El registro de la mañana sigue junto a los anillos.
4. **Medición**: días para la próxima, o que ya toca.

## Edición del plan y claves de técnica

El editor de una nueva versión permite modificar sostén mínimo/máximo en
segundos, RIR mínimo/máximo, **Por lado** y notas del ejercicio, además de los
campos anteriores y el descanso máximo. Usa los campos existentes del modelo:
guardar crea otra versión y no reescribe el historial ni la variante/superserie
que no se editaron. Antes de escribir, rechaza sostén de cero segundos, rangos
invertidos y RIR fuera de 0–5; el extremo máximo necesita su mínimo. Son
límites de entrada, no una recomendación nueva de entrenamiento. Los campos
numéricos pasan a una columna cuando el texto del sistema está ampliado.

La hoja de técnica muestra **Cómo hacerlo** de la guía fija y, debajo,
**Claves personales** del catálogo que no repiten un paso. Quita duplicados por
mayúsculas, tildes y espacios; sin guía fija, las claves siguen siendo los pasos.
Los enlaces a una búsqueda se rotulan **Buscar demostración**; un enlace directo
conserva **Ver video de referencia**. Las opciones Más fácil/Más difícil se
apilan para permitir texto ampliado sin comprimir la lectura.

`test/ui/experience_test.dart` cruza edición → SQLite → reapertura y comprueba
el historial anterior, los rechazos, claves y enlaces, la rutina desplegable,
el registro de la mañana, Día completo y Plan B a 360 dp con texto 1,5×.
`EXPERIENCE_OUT=<carpeta> flutter test test/ui/experience_test.dart` guarda
capturas opcionales con los fixtures de fuentes versionados para revisión visual. Estas comprobaciones
no sustituyen la aceptación del usuario en el teléfono.

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
| Rondas por sesión | Datos del rango; selector de tipo y condiciones guardadas. Dosis, variante, lastre y ventana explican qué se está comparando |
| Proteína por día | Barras de días observados; sin registro, incompleto y cerrado se distinguen con texto. Una meta sólo se muestra si tiene fuente y vigencia documentadas |
| Peso | Pesajes del rango separados por momento declarado; las referencias fuera de ayunas conservan su evidencia |
| Medidas | Sitios con alguna toma en el rango; unidad visible y condiciones de ayuno separadas |

Las fechas ocupan su distancia real de calendario. No se suavizan curvas ni se
unen protocolos distintos u observaciones dudosas. Un dato aislado muestra
fecha y valor; tocar un punto o abrir los registros permite revisar la evidencia.
El cero observado se conserva, y un día sin registro carece de barra numérica.
Los controles y la tabla usan el tema existente y admiten texto ampliado.
El perfil actual no se presenta como historia de metas. Contrato y límites:
[progreso-metricas.md](progreso-metricas.md); verificación local:
[recibo015](context/sessions/2026-10-10-015-graficas-evidencia.md).

## Fotos de progreso

**Cuerpo → Fotos de progreso.** Frente, perfil y espalda por fecha, con
**comparador lado a lado**: dos fechas, el mismo ángulo, y los días entre ellas.
Mantén presionada una foto para borrarla.

Las fotos se copian al directorio de la app y la base guarda la ruta relativa
(`fotos/2026-09-23-frente.jpg`): una ruta absoluta se rompe al reinstalar.

**Las fotos no van en el respaldo**: el archivo exportado es la base de datos.
Ver [roadmap](roadmap.md).

## Figuras de técnica: publicada y candidato de renovación

La1.21 pública contiene tres3D (pino, nórdico, dominadas pronas con mochila);
las otras figuras siguen planas. El candidato local1.22 renueva73entradas
entre guías, alias, movilidad y escaleras, con biblioteca consultable desde
Entreno. No equivale a73ejercicios diferentes ni a aceptación del owner.

Fuente editable: `tool/illustration_catalog.py`; entrada única pública
`python tool/figuras3d.py` genera el catálogo completo. No editarJSON a mano
ni regenerar solamente los treslegacy. La geometría se reusa en Canvas,
mockups y app; no hay motor paralelo ni imágenes remotas.

Figura humana simplificada, piel mate, frente/espalda diferenciados, pelo,
ropa azul, dedos y suela visibles. Contactos y agarres sobre el equipo;
variantes de lado, supina/prona y mochila se pasan desde sesión o biblioteca.
Rig comparte longitudes, IK3D, plano frontal, pelvis y rotación lateral.
Nombres personalizados sin figura muestran ausencia y admiten foto propia.

Guía: momentos grandes330dp con pie adaptable al texto; ampliar y girar±180°,
vista inicial, perfil y apoyos. Las posturas cíclicas se animan lentamente;
calentamiento compuesto, saltos, carrera, burpees, cambios90/90 y variantes
hollow se consultan por pasos sin interpolación ficticia. Reducir movimiento
inhabilita animación. Los controles de pantalla completa se desplazan en
paisaje/texto ampliado en vez de desbordar.

Ver [contrato, cobertura y revisión](design/ilustraciones-renovacion.md).
Galería local regenerable: `ILLUSTRATION_OUT=build/mockups/renovacion`,
`ILLUSTRATION_ALL=1`, Fluttertest illustration_mockup_render_test.dart;
`python tool/illustration_gallery.py` construyeHTML desde esosPNG.
Tests prueban cobertura/geometría/flujo; no certifican técnica deportiva ni
comprensión por usuario. Orden por piezas puede ocultar contactos en giros
extremos: conserva vista inicial y permite volver a ella. No publicar sin
verificarAPK, firma, upgrade y pendientes explícitos de revisión.


## Rayito y widget (051)
Rayito es el rayo sin cuerpo ni extremidades: ocho fases de constancia y cuatro estados del día. La fase no representa condición física. Hoy calcula racha y actividad guardada desde la misma consulta; el ánimo respeta recuperación/descanso y evita culpa. El widget Android sólo muestra mascota, racha y agenda efectiva con fecha visible; tocar abre Hoy. Snapshot único atómico fuera de respaldos, sin fotos ni registros de salud. Datos vencidos se sustituyen por una invitación a abrir Hoy. No añade notificaciones, permisos, migraciones, IA ni dependencias. Guías035 diferidas.
