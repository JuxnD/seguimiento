# ADR 0004 — Longitudes siempre en centímetros

Fecha: 2026-09-22 · Estado: aceptada

## Contexto

Ya hubo un caso real de mezclar pulgadas y centímetros en el registro. Una
medida sin unidad explícita convierte una serie histórica en basura.

## Decisión

La base guarda `valueCm` en centímetros, siempre. El perfil elige la unidad de
presentación (cm o pulgadas) y el formulario convierte al escribir y al leer.
Al cambiar de unidad en el formulario, los valores ya escritos se convierten en
pantalla en lugar de reinterpretarse.

## Consecuencias

- Comparar cualquier par de medidas es válido sin mirar la unidad.
- El informe imprime la unidad usada en su encabezado de medidas.
- Si algún día se soportan otras unidades, solo cambia la capa de presentación
  (`toCm` / `fromCm` en `lib/domain/nutrition.dart`).
