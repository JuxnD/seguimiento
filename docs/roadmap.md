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
| Editor del plan sin campos para sostén, RIR ni variante A/B | Se ven, pero solo se editan desde el código; al guardar no se pierden |
| Pruebas automáticas de interfaz | Retiradas: se colgaban con drift dentro de `flutter_test`, en Windows y en Linux. La UI se verifica en el teléfono |

## En curso

Mejoras pedidas tras el primer uso real, en este orden:

| Fase | Qué | Estado |
|---|---|---|
| 1 | Cronómetro guiado, fases automáticas, cierre anticipado, validaciones de plan | Listo |
| 2 | Comidas: crear alimento sin salir del registro, editar cantidades de un combo, guardar combos desde la app, hora vs franja | Listo |
| 3 | Notificaciones locales: sesión, sesión sin registrar, comidas, proteína, medición, fin de descanso | Listo |
| 4 | Diseño: anillos de progreso, racha, gráficas, celebración de récord, fotos con comparador | Listo |

## v2

- Respaldo automático a archivo, incluyendo las fotos (hoy el respaldo solo
  lleva la base de datos).
- Editar el plan desde la app con todos los campos (sostén, RIR, variante).

## Fuera de alcance

- Sincronización en la nube o cuentas.
- Base de datos externa de alimentos.
- Análisis o IA dentro de la app: eso se hace fuera, con el informe.
