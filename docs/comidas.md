# Registro de comidas

Meta: una comida arbitraria en pocos toques, con la app sumando sola.

## Formas de registrar

| Cómo | Dónde | Para qué |
|---|---|---|
| **Combo** (un toque) | Comidas → Atajos | Lo que se repite: batido, cena base. Registra tal cual, con deshacer |
| **Combo ajustado** | Mantener presionado el combo → *Ajustar cantidades* | Hoy fueron 3 huevos en vez de 4 |
| **Repetir hoy** | Comidas → Atajos → *De ayer* → botón *Repetir hoy* | Copia una comida de ayer a hoy con la hora de ahora ("Añadido a hoy · Deshacer", 5 s). Tocar la fila **no** repite: abre esa comida para verla o corregirla. Solo aparece mirando hoy |
| **Armar** | Botón *Comida* | Buscar alimentos, sumar varios; total en vivo |
| **Entrada libre** | Dentro del formulario, icono de lápiz | Restaurante o domicilio: kcal y proteína a ojo, marcadas como *estimado*. Se guarda sola en el catálogo |

Dentro del formulario:

- **Tocar un alimento** permite cambiar la cantidad (o las cifras, si es entrada
  libre). Así un combo se ajusta antes de guardar.
- **Crear un alimento sin salir**: en el buscador, *Nuevo alimento* o
  *Crear "lo que buscabas"*. Queda en el catálogo como *referencia* y se añade a
  la comida con su cantidad.
- **Guardar como combo** (icono de marcador): los alimentos del catálogo de la
  comida quedan como combo de un toque. Si el nombre ya existe, se reemplaza.
  Las entradas libres ya guardadas en el catálogo entran; las de "solo esta
  vez", no.
- **Porción** ×0,5 · ×1 · ×1,5 · ×2 en la entrada libre y al elegir la
  cantidad de cualquier alimento: "comí muchas pastas" es ×1,5, no un alimento
  nuevo.

## Registrar en días pasados (§16.12)

En Hoy, *Registrar → Anotar en*: Hoy · Ayer · Otro día (hasta 7 atrás). Sesión,
Fútbol, Comida y Medición abren con esa fecha y lo registrado cuenta en ese
día, en la racha y en el informe. El cronómetro siempre es de hoy. Todos los
formularios conservan además su propio campo de fecha.

Al día siguiente, si ayer quedó abierto o con menos de 1.200 kcal, Hoy
pregunta **"¿Te faltó registrar algo de ayer?"** con *Comida de ayer*,
*Fútbol de ayer*, *Cerrar ayer así* y *Está bien así* (no vuelve a preguntar
por ese día).

## Navegar y corregir (§16.7)

El 29 sep el usuario quiso corregir el desayuno del lunes y, al tocar la fila
de "Repetir de ayer", lo duplicó en el martes (+1.140 kcal falsas). Desde la
1.12.0:

- Cabecera con ‹ día › y calendario al tocar la fecha; *Volver a hoy* cuando
  se mira otro día. Cada tarjeta que no es de hoy lleva la fecha ("Cena ·
  20:00 · vie 2 oct").
- Menú ⋮ de cada comida: **Editar · Cambiar tipo · Cambiar fecha/hora ·
  Duplicar en hoy · Eliminar** (eliminar se deshace desde el aviso).
- Los registros de un toque (combo, *Repetir hoy*, *Duplicar en hoy*)
  preguntan antes si la hora no cuadra con el tipo (un desayuno a las 15:51:
  "Dejar desayuno" o "Como almuerzo") y si ya hay un desayuno, almuerzo o
  cena ese día ("Ya tienes un desayuno hoy · ¿Añadir otro?"). Meriendas y
  "otro" pueden repetirse sin aviso.

## Correcciones del 29 sep (§17)

*Ajustes › Correcciones del 29 sep* (y una tarjeta en Hoy mientras queden
pendientes) lista las correcciones de datos del traspaso: RPE de las sesiones
del 23, 24 y 25, notas del 25, plancha del 28 a 40 s por lado, salchichón del
desayuno del 28 a 110 g (960 kcal), tipos de las comidas del 25 y 28, la cena
del 27 separada en almuerzo y cena, días 24–28 cerrados (los que tienen
comidas) y el desayuno duplicado del 29. Cada una se aplica **solo si el
registro sigue tal cual lo describe el traspaso**; lo que ya se corrigió a
mano o no existe no se toca. Antes de aplicar se guarda un respaldo
automático. Lógica y pruebas: [`corrections_29sep.dart`](../lib/data/corrections_29sep.dart),
[`corrections_29sep_test.dart`](../test/data/corrections_29sep_test.dart).

## Entradas libres que se quedan

Desde el 27 sep 2026 toda entrada libre se guarda en el catálogo como
alimento **personalizado** de una porción (`origin = entradaLibre`, fuente
*estimado*), para no volver a digitar el almuerzo corriente o el mondongo.

- **Autocompletar**: al escribir en "Qué comiste" (2 letras o más) salen
  hasta 6 coincidencias, sin importar tildes ni orden de las palabras:
  favoritos primero, luego lo personalizado y al final lo sembrado; dentro de
  cada grupo, lo más usado en 30 días. Elegir una rellena las cuatro cifras de
  una porción.
- **Sin duplicados**: el nombre se compara sin mayúsculas, tildes ni espacios
  de sobra. Si ya existe con las mismas cifras (±0,5), se usa ese alimento. Si
  existe con otras, pregunta: *Actualizar* (reescribe las cifras), *Guardar
  como nuevo* ("Pasta (2)") o *Solo esta vez* (no toca el catálogo).
- **En el informe sigue siendo estimado**: un alimento a ojo guardado no se
  vuelve "referencia"; cuenta en la procedencia como entrada libre.
- **Gestión** en Comidas → Catálogo: filtro *Personalizados* y *Favoritos*,
  estrella para marcar, y menú con *Editar o renombrar*, *Usar como combo* y
  *Borrar*.

## Día cerrado

Un día entra a promedios y alertas si tiene **desayuno, almuerzo y cena**, o si
se **cierra a mano** en Comidas ("Cerrar día": ese día no hubo más). Debajo de
los anillos, Comidas dice qué falta; el informe marca los demás días como
"(incompleto)". Cerrar se puede deshacer con "Reabrir".

Mientras se arma una comida, "El día con esta comida" muestra el acumulado y lo
que falta para la meta de kcal y proteína. Guardar una segunda comida en la
misma franja y día ofrece **fusionarlas** en una sola. Los combos se editan
(nombre, franja y cantidades) desde su menú en Atajos.

## Franja y hora

La franja se propone según la hora
([`lib/domain/meal_slots.dart`](../lib/domain/meal_slots.dart)):

| Franja | Ventana |
|---|---|
| Desayuno | 5:00 – 11:00 |
| Almuerzo | 11:00 – 15:30 |
| Merienda | 15:30 – 19:00 |
| Cena | 19:00 – 5:00 |

Al guardar, si la hora cae fuera de la franja elegida con más de 30 minutos de
margen (un desayuno a las 14:57), la app pregunta si cambiarla. "Otro" admite
cualquier hora.

## Procedencia

Cada ítem guarda de dónde salen sus cifras: **etiqueta** (verificado),
**referencia** (tabla promedio) o **estimado** (entrada libre a ojo). El informe
reporta el porcentaje de kcal de cada una. Ver [informe.md](informe.md).

Borrar un combo o cambiar un alimento del catálogo **no** altera lo ya
registrado: cada comida guarda una copia de sus cifras
([ADR 0002](adr/0002-snapshot-macros-en-comidas.md)).
