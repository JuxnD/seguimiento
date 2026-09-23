# Diseño y motivación

La app tiene que dar ganas de abrirla sin volverse recargada. El criterio: **el
progreso se ve antes de leerse**, y cada color significa algo.

## Sistema visual

Tema oscuro único ([`lib/ui/theme.dart`](../lib/ui/theme.dart)): negro de fondo,
superficies en gris muy oscuro y el naranja reservado para lo accionable y el
dato en foco. Todo lo demás es gris.

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
