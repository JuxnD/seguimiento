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


## Plan 011: integración local del radar y referencias por fecha

`SummaryScreen` (Tu progreso, desde Informe) muestra primero el radar real de
`PersonalRadarSection`. Usa el mismo núcleo y painter018: primera y última
prueba apta de toda la historia hasta el menor entre fin mostrado y hoy.
No son máximos ni una nota global. Una sola fecha y una base0 no producen un
porcentaje relativo; el valor por encima de100% se conserva aunque el dibujo
se recorte. El detalle de cada eje conserva intentos parciales/dudosos y fechas.

`PersonalRadarRepository` lee todos los tests y el inventario Cindy/resistencia
por lotes de128 sesiones ordenadas por ID. Lee sets+nombres de cada lote juntos,
ordenados por sesión e ID de inserción, nunca por `setIndex` (es por ejercicio).
El recorrido hace una consulta de tests, B+1 consultas de sesiones y hasta B de
sets; retiene O(observaciones+sets), además del buffer128. No es memoria total
constante ni un SLA. El fixture300 compara todos los payloads con el núcleo
sobre el recorrido completo, conservando inicio/actual. El core018 acredita
receta5/10/15 y ventana real1200s: 1201s legados, 30min, Tabata, DDFFSS, lastre,
variante, importadas, estimadas, cortadas y dudas quedan observaciones.
Fechas inválidas se traducen a desconocidas, nunca normalizadas; SQLite no cambia.

Las seis referencias opcionales son `refDominadas/refFlexiones/refHollow/
refBulgara/refSaltoLargo/refCindy`. `GoalHistory.on(corte)` conocido y finito>0
habilita coordenadas; la misma referencia identificada escala ambos contornos.
`setReference` guarda desde el reloj real de decisión, no desde el período
observado. Null/legado/ausente conserva raw sin coordenadas. Guardar, cancelar,
restaurar y editar/borrar evidencia antigua cruzan SQLite→Riverpod→UI. Los IDs
sólo se mantienen en DTOs y manifiestos; no son etiquetas del producto.

El lector compartido `goalHistoryProvider` observa `watchHistory`; el radar
observa tests/sesiones/sets/ejercicios y cambio de conexión por restauración.
El informe observa también historia. `historicalChartGoal` conecta proteína y
pasos a sus vigencias; fin abierto es null, no el fin ficticio de una consulta.
Pasos omite meta en fines de semana y no convierte ausente en0 observado.
`fillDays` aritmético del informe permanece igual.

`ReportInput.referenceOn` distingue historia cargada sin vigencia, null explícito
y compatibilidad sin historia. `kcalReferenceOn` conserva el calendario existente
de `dailyKcalTarget`: sábado/domingo usa kcalFutbol conocida, null hereda semanal;
no depende de partidos registrados. El selector0/1 interno sólo selecciona esa
regla, nunca se presenta como kcal. PeriodSummary comprime referencias por día.
Con proteína130→160, el anillo muestra días que alcanzaron mínimo, con denominador
conocido; promedio crudo se muestra aparte. Sin referencia no se dibuja ratio0.
Con kcal mixtas se muestra promedio y referencias por día, sin anillo con una
cifra falsa. Null explícito y legado se cuentan por separado, sin clasificación
clínica ni una nueva banda de tolerancia.

Registro de tests usa elección explícita T1/T2/T3 y parte; editar conserva fecha,
nuevo intento conserva el reloj existente. Calendario usa `plannedDateFor` y
rótulo Previsto, sin noviembre/diciembre fijos ni obligación sin plan. Cindy
usa wrapper público `startCindyTest`, protección de pendiente y `_runTimer` real;
no abre un cronómetro alterno. UI abre/cancela sin crear filas.

Lectores globales de presencia/bootstrap, APK, continuidad Android y aceptación
humana siguen en frentes012/022. Este slice no declara el piloto ni publicación.
[Recibo011](context/sessions/2026-10-10-011-radar-integrado.md).


Cierre de decisión: el diálogo lee `decisionClockProvider` al confirmar. Si
cruza medianoche, guarda la vigencia del día real de confirmación y la indica
al guardar; no reutiliza la fecha de apertura. El origen de GoalVersion se
muestra con rótulos humanos. El selector de período usa dropdown ancho en
texto1.6/2, conserva escala/elección/rango sin partir Semana. Ver recibo011.
