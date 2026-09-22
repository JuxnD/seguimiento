# ADR 0002 — Los macros de una comida se congelan al registrarla

Fecha: 2026-09-22 · Estado: aceptada

## Contexto

El catálogo de alimentos se llena a mano desde las etiquetas. Es normal
corregirlo semanas después (una etiqueta mal leída, otra marca de atún). El
informe se audita comparando semanas entre sí.

## Decisión

`meal_items` guarda kcal, proteína, carbos y grasa **copiados** en el momento
de registrar, junto con la cantidad y su unidad. La referencia al alimento
(`foodId`) queda solo como procedencia y pasa a `NULL` si el alimento se borra.

## Alternativas

- **Referenciar el alimento y calcular al leer**: un informe de la semana 3
  cambiaría al corregir el catálogo en la semana 9. Imposible auditar.
- **Versionar los alimentos**: correcto, pero añade tablas y pantallas para un
  problema que la copia resuelve.

## Consecuencias

- El historial es estable: lo registrado no cambia solo.
- Corregir un alimento **no** corrige el pasado; si hace falta, se edita la
  comida afectada.
- Borrar un alimento del catálogo es seguro.
