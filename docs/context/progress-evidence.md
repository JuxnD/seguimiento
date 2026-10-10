# Evidencia de progreso: contrato compartido

Implementación del plan008 sobre d2d3070; no modifica esquema20 ni historia.
Los planes009/011 deben reutilizar este contrato antes de adaptar metas o
dibujar capacidades. La publicación y aceptación en el teléfono siguen siendo
gates del candidato integrado.

| Dato | Fuente y significado | Uso permitido |
|---|---|---|
| RoundTimingEvidence | sesión/fecha/tipo/plan/formato; segundos por ronda ya convertidos; base work o lap; firma de ejercicios/dosis/variante/carga; importado/estimado/incompleto | media descriptiva. Comparación sólo con base, plan, formato y firma conocidos iguales; no inventar descanso cero |
| StrengthSessionEvidence | sesión/fecha/tipo/plan; reps, RIR, split, splitDetail, fallo, carga y variante de cada serie | política de doble progresión con evidencia conservada. Falta de RIR mantiene política existente; no demuestra técnica buena |
| TestResult | ítem/T1–T3/lado/valor/clean y fecha SQLite real | observado sigue visible incluso con dudas o parcial |
| eligibleTestValue / latestEligibleTestRound | resultado completo, válido, limpio, fecha conocida no futura, I/D del mismo día | dosis/comparación. La última apta se elige por fecha, no por un T3 parcial |

`timedSessionComparison` es la frontera usada por el cierre de la guía. Recibe
duraciones, nunca marcas acumuladas: 60/125/195 se convierte una vez en
60/65/70 y su media es65. No vuelve a aplicar `lapDurations`.

`previousTiming` distingue trabajo sin descanso y vueltas con descanso.
`previousOfType` se conserva como adaptador antiguo; nuevos consumidores deben
usar el DTO. Firma de protocolo ausente limita la comparación, pero no elimina
sesiones ni valores observados. Dosis distintas, variantes/cargas distintas,
plan distinto o modo distinto no prueban mejora de velocidad.

`strengthProgressionHint` conserva las reglas numéricas anteriores; bloquea
fallo explícito, partición, RIR0, sesión cortada/importada, fecha futura, conjuntos
de carga/variante mezclados y plan conocido incompatible. `session_sets` no
guarda lado: no reconstruir I/D por orden ni proponer aumento bilateral con esa
evidencia. No se alteran dosis, fórmulas clínicas ni registros antiguos.
`lastStrengthEvidence` no conserva el cap arbitrario de40sesiones del adaptador
antiguo: hoy consulta el historial antes de la fecha y filtra día de semana.
009 debe consolidar/optimizar consultas con igual semántica, sin ocultar una
referencia sólo por cantidad de sesiones de otro tipo. No hay medición de
latencia ni afirmación de rendimiento en este cambio.

El resolver de tests acepta `asOf` y `maxAgeDays` para políticas de frescura
explícitas. No agrega una caducidad clínica arbitraria:009/011 deben definir la
ventana por uso y mostrar fecha/calidad. `testValue` sigue siendo observado,
por compatibilidad, y jamás debe sustituir al resolver apto en una propuesta.
La tabla muestra fecha de resultados completos; las dudas llevan* y los
parciales permanecen visibles. Un test dudoso puede estar registrado completo
sin ser apto para aumentar dosis.

`recordedDateFor` y `plannedDateFor` separan ejecución y calendario. `dateFor`
conserva su contrato antiguo de fallback previsto para consumidores existentes.
La pantalla nueva utiliza fecha de hoy confirmable/cambiable; la edición de una
parte ya guardada conserva su fecha original. Guardar continúa requiriendo una
acción del usuario y no reconstruye ni altera una guía pausada.
Si una fila legacy tiene fecha inválida, editar no la sustituye por hoy:
Guardar queda bloqueado hasta una selección explícita de fecha.
`recordedTestDate` exige roundtrip exacto YYYY-MM-DD:30febrero no se normaliza
silenciosamente a marzo ni se reescribe en la base.

Referentes conservados: dominio puro, repositoriosDrift, providersRiverpod,
tabla y dosis existentes y snapshot congelado de ADR0013. Sin SDK, dependencias,
firma, figuras, gateway ni plan del usuario modificados.

Pruebas y gates: [recibo008](sessions/2026-10-09-008-evidencia.md).
