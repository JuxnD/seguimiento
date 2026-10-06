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
| 7 | Traspaso v2 del 25 sep ([handoff-v2-2026-09-25.md](handoff-v2-2026-09-25.md)): trabajo y descanso por ronda, técnica y carga en el cronómetro, RPE obligatorio, propuesta de progresión, días cerrados, volumen e interferencia en el informe, diagnóstico de avisos, logo | Publicado en la 1.8.x |
| 8 | Adenda del 27 sep (mismo documento, §13–16): fútbol en Hoy y la racha, récord sospechoso señalado, entradas libres que se guardan solas con autocompletar y porciones, pan Mipan y platos repetidos, pasos diarios con meta y aviso, movilidad nocturna opcional | Publicado en la 1.9.0 (con figuras de técnica, foto de referencia y pasos desde Health Connect) |

## v2

- **Fase 2 del programa (traspaso §15)**, cuando el circuito de 10 rondas
  salga con RPE ≤ 8 y sin series partidas: circuito por tiempo neto,
  récords separados por carga, niveles de habilidades (L-sit, HSPU, dominada
  con pausa) y récords múltiples. La carga por serie (`session_sets.load_kg`)
  ya existe.

- Respaldo automático fuera del teléfono. El ZIP manual con fotos entra en
  1.19; las copias semanales internas conservan solamente registros.
- El editor de 1.19 añade sostén, RIR, por lado, notas y descanso máximo.
  Se conservan los campos de agarre/variante y bloque ya editables; A/B y
  agrupación de superseries se preservan al guardar.

## Fuera de alcance

- Sincronización en la nube o cuentas.
- Base de datos externa de alimentos.
- Escritura autónoma por IA o envío de fotos. El copiloto descriptivo del informe
  entra en1.19; [estado y gates de activación](ia-pendiente.md).
