# Registro de comidas

Meta: una comida arbitraria en pocos toques, con la app sumando sola.

## Formas de registrar

| Cómo | Dónde | Para qué |
|---|---|---|
| **Combo** (un toque) | Comidas → Atajos | Lo que se repite: batido, cena base. Registra tal cual, con deshacer |
| **Combo ajustado** | Mantener presionado el combo → *Ajustar cantidades* | Hoy fueron 3 huevos en vez de 4 |
| **Repetir de ayer** | Comidas → Atajos → *Repetir de ayer* | Copia una comida del día anterior con la hora de ahora |
| **Armar** | Botón *Comida* | Buscar alimentos, sumar varios; total en vivo |
| **Entrada libre** | Dentro del formulario, icono de lápiz | Restaurante o domicilio: kcal y proteína a ojo, marcadas como *estimado* |

Dentro del formulario:

- **Tocar un alimento** permite cambiar la cantidad (o las cifras, si es entrada
  libre). Así un combo se ajusta antes de guardar.
- **Crear un alimento sin salir**: en el buscador, *Nuevo alimento* o
  *Crear "lo que buscabas"*. Queda en el catálogo como *referencia* y se añade a
  la comida con su cantidad.
- **Guardar como combo** (icono de marcador): los alimentos del catálogo de la
  comida quedan como combo de un toque. Si el nombre ya existe, se reemplaza.
  Las entradas libres no entran, porque un combo es una receta del catálogo.

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
