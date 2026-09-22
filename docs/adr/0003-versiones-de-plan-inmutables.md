# ADR 0003 — Las versiones del plan son inmutables

Fecha: 2026-09-22 · Estado: aceptada

## Contexto

El informe debe decir qué se esperaba y qué pasó. Si el plan cambia el jueves,
el informe de esa semana tiene que saber que lunes a miércoles regía otro plan.

## Decisión

`plan_versions` nunca se edita. "Editar el plan" carga la versión vigente como
borrador y guarda una versión nueva con su `validFrom`. La versión vigente para
un día es la de mayor `validFrom ≤ día` (empate: la creada después). El número
visible (v1, v2…) es el orden de creación.

## Alternativas

- **Editar la versión en sitio**: barato, pero reescribe el pasado y las
  sesiones que apuntan a un día del plan quedan describiendo otra cosa.
- **Guardar una copia del plan dentro de cada sesión**: duplica datos y no
  cubre los días en los que no entrenaste, que son justo los que hacen falta
  para contar sesiones esperadas.

## Consecuencias

- El encabezado del informe puede mostrar `Plan v1 (desde 26 ago) → v2 (desde
  20 sep)` y contar las sesiones esperadas día por día.
- Cambiar el plan a menudo genera muchas versiones: es el precio del historial.
- Corregir un error de digitación también crea una versión nueva.
