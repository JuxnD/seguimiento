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
| Persistir el contador en curso | Si la app muere a mitad del circuito, se pierde la sesión |
| Respaldo automático periódico | Hoy hay que acordarse de exportar |
| Confirmar contra etiqueta Klim, Nestum y atún | Son de uso diario y hoy están como referencia; el catálogo los marca |
| Crear y editar combos desde la app | Hoy se siembran desde el código |
| Editor del plan sin campos para sostén, RIR ni variante A/B | Se ven, pero solo se editan desde el código; al guardar no se pierden |
| Pruebas automáticas de interfaz | Retiradas: se colgaban con drift dentro de `flutter_test`, en Windows y en Linux. La UI se verifica en el teléfono |

## En curso

Mejoras pedidas tras el primer uso real, en este orden:

| Fase | Qué | Estado |
|---|---|---|
| 1 | Cronómetro guiado, fases automáticas, cierre anticipado, validaciones de plan | Listo |
| 2 | Comidas: crear alimento sin salir del registro, editar cantidades de un combo, guardar combos desde la app, hora vs franja | Pendiente |
| 3 | Notificaciones locales: sesión, sesión sin registrar, comidas, proteína, medición, fin de descanso | Pendiente |
| 4 | Diseño: anillos de progreso, racha, gráficas, celebración de récord, fotos con comparador | Pendiente |

## v2

- Fotos de progreso (frente, perfil, espalda) con comparador lado a lado.
  Requiere `image_picker`, guardar rutas **relativas** al directorio de la app
  (las absolutas se rompen al reinstalar) y su migración de esquema.
- Gráficas de rondas, proteína y medidas en el tiempo (`fl_chart`).
- Recordatorios con `flutter_local_notifications`: 15 min antes de la sesión
  según el plan y aviso de medición cada 3–4 semanas.
- Respaldo automático a archivo (la restauración ya está).

## Fuera de alcance

- Sincronización en la nube o cuentas.
- Base de datos externa de alimentos.
- Análisis o IA dentro de la app: eso se hace fuera, con el informe.
