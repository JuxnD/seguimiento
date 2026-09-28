# Registro de comidas

Meta: una comida arbitraria en pocos toques, con la app sumando sola.

## Formas de registrar

| Cómo | Dónde | Para qué |
|---|---|---|
| **Combo** (un toque) | Comidas → Atajos | Lo que se repite: batido, cena base. Registra tal cual, con deshacer |
| **Combo ajustado** | Mantener presionado el combo → *Ajustar cantidades* | Hoy fueron 3 huevos en vez de 4 |
| **Repetir de ayer** | Comidas → Atajos → *Repetir de ayer* | Copia una comida del día anterior con la hora de ahora |
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
