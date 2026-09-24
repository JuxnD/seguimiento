# Fases

## MVP — implementado

| Módulo | Estado |
|---|---|
| Perfil (metas, umbrales, unidad, fecha de inicio) | Listo |
| Plan semanal versionado con historial | Listo |
| Sesiones: tiempos, rondas, series, partidas, fallo, RPE, contexto | Listo |
| Contador de rondas con fases y marcas por vuelta | Listo |
| Estimación de rondas por tiempo | Listo |
| Fútbol (formato, minutos, pasos, intensidad, fatiga) | Listo |
| Catálogo de alimentos y registro de comidas (catálogo + entrada libre) | Listo |
| Copiar una comida a otro día | Listo |
| Peso y tomas de medidas con unidad explícita | Listo |
| Aviso de medición antes de tiempo | Listo |
| Informe Markdown por semana o rango, copiar y compartir | Listo |
| Notas de la semana | Listo |
| Exportar la base como respaldo | Listo |
| Restaurar un respaldo desde la app (con validación y rollback) | Listo |
| Aviso de versión nueva por GitHub Releases | Listo |
| Plan real sembrado en la primera apertura (v1 y v2) | Listo |
| Regla de progresión registrada y auditada en el informe | Listo |
| Tema oscuro naranja | Listo |
| Cronómetro guiado por el plan (circuito y bloques) con descansos automáticos | Listo |
| Sesión fuera de plan e incompleta, con aviso y marca en el informe | Listo |
| Catálogo inicial de 30 alimentos con procedencia (etiqueta / referencia) | Listo |
| Combos de un toque (batido, cena base, cena completa, almuerzo típico) | Listo |
| Procedencia de las kcal en el informe | Listo |

## Pendientes conocidos del MVP

| Pendiente | Por qué importa |
|---|---|
| Confirmar contra etiqueta Klim, Nestum y atún | Son de uso diario y hoy están como referencia; el catálogo los marca |
| Editor del plan sin campos para sostén ni RIR | Se ven, pero solo se editan desde el código; al guardar no se pierden. Agarre/variante y bloque sí se editan |

## En curso

Mejoras pedidas tras el primer uso real, en este orden:

| Fase | Qué | Estado |
|---|---|---|
| 1 | Cronómetro guiado, fases automáticas, cierre anticipado, validaciones de plan | Listo |
| 2 | Comidas: crear alimento sin salir del registro, editar cantidades de un combo, guardar combos desde la app, hora vs franja | Listo |
| 3 | Notificaciones locales: sesión, sesión sin registrar, comidas, proteína, medición, fin de descanso | Listo |
| 4 | Diseño: anillos de progreso, racha, gráficas, celebración de récord, fotos con comparador | Listo |
| 5 | Pulido tras uso real: tarjeta principal en todas las pestañas, enfriamiento como fase igual al calentamiento, medalla y frase de cierre con el dato real, insignia al cerrar ronda, selector de "qué costó más" con chips | Listo |
| 6 | Auditoría del 23 sep 2026 ([auditoria-2026-09-23.md](auditoria-2026-09-23.md)): correcciones, retomar el cronómetro, respaldo automático, umbrales del perfil, menos toques, pruebas de pantalla y CI que compila | Listo |

## v2

- Respaldo que incluya las fotos (hoy exportar y las copias automáticas solo
  llevan la base de datos) y que pueda salir del teléfono sin acción manual.
- Editar el plan desde la app con todos los campos (sostén, RIR, variante).

## Fuera de alcance

- Sincronización en la nube o cuentas.
- Base de datos externa de alimentos.
- Análisis o IA dentro de la app: eso se hace fuera, con el informe.
