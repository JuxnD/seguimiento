# Auditoría de la planeación

Revisión del plan original antes de implementar. Cada punto dice qué se cambió
y por qué; lo que no aparece aquí se implementó tal como estaba planeado.

## Cambios aplicados

### 1. Ejercicios con catálogo, no texto libre
`SessionSet.exercise` era un texto. Con texto libre, "Flexiones" y "flexiones"
son ejercicios distintos y la alerta "mismo ejercicio partido en varias
sesiones" falla justo cuando más sirve. Ahora hay tabla `exercises`; al
escribir un nombre se reutiliza el existente sin distinguir mayúsculas.

### 2. Macros de la comida congelados al registrar
`MealItem` referenciaba `Food` y guardaba solo kcal y proteína. Si corriges la
etiqueta de un alimento seis semanas después, todos los informes anteriores
cambian de número. Ahora el item copia los cuatro macros; borrar un alimento
no altera el historial.

### 3. Carbohidratos y grasa también en el item
El plan pedía totales diarios de kcal, proteína, carbos y grasa, pero el item
solo llevaba kcal y proteína. Sin carbos/grasa por item, el total diario no se
puede calcular.

### 4. Vueltas del contador guardadas (`session_rounds`)
El plan pedía "estimación de rondas por tiempo" con el tiempo medio por ronda,
pero ese promedio no existía en ningún lado. El contador ahora guarda la marca
de cada ronda; de ahí salen el tiempo medio real y una estimación honesta.
Además, la estimación avisa: si la media viene del contador ya incluye el
descanso, así que el parámetro de descanso va en 0 para no contarlo dos veces.

### 5. El contador mide también calentamiento y enfriamiento
El contador arranca en "calentando", pasa a circuito y termina en
"enfriando". Así total, calentamiento, enfriamiento, rondas y vueltas salen
solos, y el formulario llega prellenado. Los tiempos se calculan con marcas de
reloj, no acumulando ticks: si se apaga la pantalla no se pierde tiempo.

### 6. `roundsEstimated` en la sesión
Una ronda contada y una ronda estimada no valen lo mismo. Se marcan distinto en
el informe (`~7 (est.)`) y generan alerta.

### 7. `Session.type` propio
El plan ataba la sesión a `planDayId`. Si entrenas un día no planificado no hay
dónde poner el tipo. Ahora el tipo es columna de la sesión y el vínculo al plan
es opcional.

### 8. Umbrales de alerta en el perfil
2.000 kcal, 6 minutos de calentamiento y 21 días entre mediciones estaban
implícitos en las alertas. Son datos del perfil, editables sin tocar código.

### 9. Alerta de días sin registro
Sin esta regla, una semana con tres días sin registrar muestra un promedio
bonito y falso. Los días sin comidas se excluyen del promedio **y** se listan
como alerta.

### 10. Una toma de medidas por fecha
`Measurement` repetía `fasted` en cada fila. Ahora la clave `(fecha, sitio)` es
única y la app guarda la toma completa de una fecha como un bloque; la
condición de ayunas es de la toma.

### 11. Notas de la semana persistentes
El informe tenía sección "Notas de la semana" sin ningún sitio donde guardarlas.
Se añadió `week_notes`, con la semana anclada al inicio como clave.

### 12. Respaldo dentro del MVP
Estaba en v2. Con datos solo en el teléfono y sin cuentas, una pérdida borra
meses de registro. Exportar la base es barato (`VACUUM INTO` + compartir) y ya
está. La restauración llegó después, con validación y rollback
([actualizaciones.md](actualizaciones.md)).

### 13. Fotos fuera del esquema del MVP
Estaban listadas como módulo 6 y a la vez como v2. No se crearon tablas que
nadie escribe en el MVP; entraron en la fase 4 con su migración
(`progress_photos`, esquema 6).

### 14. `isar` descartado
Se eligió `drift`. Ver [adr/0001](adr/0001-drift-sqlite-local.md).

## Riesgos que quedaban abiertos

Los tres riesgos que este documento dejó abiertos ya se cerraron: la
restauración de respaldos, los recordatorios (fase 3) y las pruebas de UI, que
se retiraron en vez de dejarse saltadas (ver [project-map.md](project-map.md)).
El estado vigente de riesgos vive en project-map, no aquí.

## Sugerencias no implementadas (decisión tuya)

- **Pasos del fútbol**: hoy se escriben a mano. Leerlos del teléfono exige
  permisos de salud y complica el local-first.
- **Medidas con dos tomas**: promediar dos mediciones del mismo sitio reduce el
  error de cinta, pero duplica el tiempo de registro.
- **Contexto con etiquetas** (oficina, dormí poco, fútbol ayer) en vez de texto
  libre: permitiría cruzar contexto con rendimiento en el informe. Hoy el texto
  libre va completo al informe, que es donde se analiza.
