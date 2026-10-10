# Gráficas del informe: rango y evidencia

El [núcleo/widget018 de radar](design/radar-personal.md) extiende las métricas con
seis pruebas específicas e historial de observaciones, sin conectar aún pantallas
o metas persistidas. Los valores del mock no son referencias por defecto.

Slice015 sobre bf1da688, independiente del motor009. Reutiliza el contrato008
de evidencia y el tema existente. No completa011, no introduce radar ni una
nota universal de condición física.

| Métrica | Fuente / unidad / selección | Calidad y límite |
|---|---|---|
| Rondas por sesión | sessions + sets/exercises + session_rounds; rondas; rango inclusivo y últimas200 filas SQL, orden fecha/id | Tipo, modo real, plan, firma SessionDraft.exerciseProtocol, base work/lap y ventana real de resistencia. Importadas, estimadas, cortadas, técnica o protocolo desconocido se conservan como observaciones, sin línea comparable |
| Proteína diaria | snapshots meal_items; g; comidas y cierres del mismo rango | ChartDay nullable: sin registro≠0 observado. Estado incompleto/cerrado reutiliza isDayClosed como ReportStats. sourceVerified null identifica estimación; cierre no verifica macros |
| Peso | body_weights; kg; mismo rango | Se reutiliza weighMomentOf: ayunas, antes/después de fútbol y otros momentos se separan. Null con indicador de ayuno usa el fallback compartido declarado; null sin ayuno e identificador inválido siguen desconocidos. Referencias fuera de ayunas no producen evolución comparable |
| Medidas | measurements; cm persistidos, unidad del perfil sólo convierte presentación | Sitio real, unidad y ayuno guardado separados; rango inclusivo. Una toma ya es visible. Fuera de ayunas es referencia. Técnica no registrada: diferencia descriptiva, sin consejo ni interpretación clínica |

Rango, tipo y rutina/condiciones actualizan conjuntamente título, puntos, resumen
y registros. La rutina muestra la firma de los ejercicios realmente guardados,
no equivalencias deducidas de nombres parecidos. Desconocer el protocolo impide
concluir evolución comparable, sin ocultar el valor observado.

El selector explica dosis, variante, lastre y ventana con un rótulo humano
(`protocolLabel`), sin desarmar una firma técnica ni limitarse a «grupo1».
La duración de resistencia usa `circuitSpanSec` compartido: total menos
calentamiento/enfriamiento. Cindy20min y30min se separan; diferente tiempo total
con la misma ventana real se conserva en el mismo protocolo. Los campos de hora
de peso/medidas se leen literalmente en evidencia;07:00 y07:05 no dividen una
rutina. No se infiere ayuno o momento desde notas arbitrarias.

Las fechas tienen distancia de calendario real (`daysBetween`, UTC por día):
1ene→2ene ocupa1día;2ene→1feb ocupa30. La línea es recta y no suaviza extremos.
Una observación sola muestra fecha/valor. Cambios de protocolo o calidad rompen
la línea. Tocar una observación o un registro permite leer fecha, valor, fuente
y condiciones; la tabla ofrece la misma información como texto accesible.

Los días sin comida no tienen barra numérica. El0 registrado sigue visible;
incompletos y cerrados tienen rótulo textual además de estilo. `fillDays` del
core aritmético conserva su contrato: la proyección visual es otro DTO explícito.
La expansión de la tabla diaria mantiene su estado al actualizar el cierre,
con una clave propia del rango; cambiar de rango no reutiliza su evidencia.

## Meta por fecha: frontera opcional para009

`ChartsSection.goalResolver` recibe `(date, metric)` y devuelve `DatedChartGoal?`.
Por ahora se consume `metric=proteinMin`, unidad `g`: valor, fechas inclusivas
de vigencia y fuente obligatoria. `documentedChartGoal` rechaza unidades distintas,
fechas no cubiertas, fuente vacía y números inválidos. No se usa la meta actual
del perfil para dibujar una historia desconocida.

Con evidencia válida se dibuja una barra fina de mínimo por día y se explica
fuente/vigencia en la tabla. Sin resolver o sin vigencia, se omite la referencia.
Esta interfaz no persiste metas ni reemplaza GoalVersion;009 proporcionará su
adaptador cuando exista la historia autorizada. No inventa objetivos anteriores.

## Verificación y límites

Fixtures sintéticos SQLite→providers→widgets Flutter, captura del renderer real
a360dp con texto1.6, SQL con240 sesiones, comparación de cierre contra ReportStats
y rojos de ausencia/rango/modo/temporalidad/ventana/condiciones. El cero de proteína
se prueba con una comida real guardada sin proteína: su eje conserva margen
positivo, sin inventar valor. Un caso distinto, todo ausente, muestra estado vacío.
Editar un peso o sesión antiguo fuera de las ventanas90/60 actualiza el rango
activo; ese caso refutó la necesidad de otro invalidator. El esquema se conserva.
Ver [recibo015](context/sessions/2026-10-10-015-graficas-evidencia.md).
Captura no equivale a comprensión/aceptación del owner ni prueba latencia nativa.
APK integrado, teléfono y publicación siguen siendo gates del coordinador.
