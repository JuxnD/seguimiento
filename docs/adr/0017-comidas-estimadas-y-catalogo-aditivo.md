# ADR0017 · Comidas estimadas y catálogo aditivo

Fecha: 9-oct-2026. Estado: implementación local; despliegue y precisión real pendientes.
Decisión autorizada en plan010, ejecución coordinada con Claude por el owner.

El contrato antiguo `meal_text` sólo enlaza catálogo y prohíbe macros. Cambiarlo
rompería clientes instalados. Se añade `meal_estimate` a contrato2, anunciada por
`status.tasks`; las cuatro tareas anteriores y endpoints legacy se conservan.
El cliente de status es el mismo blob `3969149f3d918adfa6b15d4ad59692d89b2ef38a`
de a0521c8 y acepta la tarea adicional. Servidor antiguo permite seguir con el
flujo anterior y entrada manual. No se reintenta una consulta automáticamente.

Las variantes son `known` (ID y cantidad/unidad del catálogo; macros locales),
`estimated` (macros totales de una porción, supuestos y revisión), y `unresolved`
(pregunta y ninguna cifra asignada). Ambos runtimes validan límites, pertenencia,
unidades, finitud, coherencia de macros y cobertura de la frase original mediante
segmentos exactos. Un plato compuesto puede ocupar una fila. La cobertura de
caracteres no prueba cobertura semántica: se añade un control para nombres de
preparaciones frecuentes y confirmación humana explícita de toda la comida.
No se afirma detectar todos los alimentos omitidos por un modelo.

La pantalla nunca escribe. Devuelve un `MealTextSelection`, compatible con los
consumidores de List anteriores, con items, notas de procedencia y decisión
opcional de recordar. La comida y el aprendizaje solicitado se escriben en una
transacción al Guardar/Fusionar. Cancelar no guarda. La nota conserva frase,
porción, cifras revisadas, supuestos, dudas y exclusiones con motivo; las cifras
históricas se congelan como antes. Las notas son editables y describen la
propuesta original si luego cambia el borrador, sin fingir que se regeneraron.
La cantidad de una estimación se escala únicamente en su unidad original:
la UI la fija y el draft rechaza cambios entre g, ml y porción. Otra unidad
requiere consultar de nuevo o registrar manualmente una referencia nueva.

Recordar crea un alimento estimado nuevo; no sobrescribe un homónimo. Mantiene
base por100 para g/ml y unidad propia para otras porciones. Guardar una comida
no la aprende por sí solo. C01 de Claude permanece: una entrada libre nunca
convierte un alimento por100g en porción ni cambia combos existentes.

`catalog_patches` (esquema21) guarda sourceId, patchVersion y foodId nullable.
El parche1 usa36 identidades fuente congeladas de las referencias ya sembradas.
Completa referencias ausentes en instalaciones existentes, preserva ediciones,
combos y snapshots. Una colisión personalizada se registra con foodId null; una
borrada queda como tombstone y no reaparece. Un renombre conserva su identidad
por registro SQLite; el registro viaja dentro de respaldos. Cambiar/renombrar una
fuente del patch1 exige un patch nuevo, no modificar sus claves congeladas.

No se introducen macros universales para arroz chino, Milo o recetas caseras sin
etiqueta/receta sustentada. Sus nombres sirven para estimar/preguntar y aprender
la versión revisada del usuario. No se ha importado la TCAC ni validado permisos
de redistribución. Fuente de investigación: [ICBF TCAC](https://www.icbf.gov.co/tabla-de-composicion-de-alimentos-colombianos-tcac).

La selección local busca todo el catálogo por nombre/aliases antes de limitar
a200 candidatos, con empates en orden de favoritos/uso reciente. El límite
del gateway se conserva. No se transmiten macros locales ni registros.

Gates: tests de cliente viejo, contratos PHP antiguos/nuevos, corpus sintético,
UI→SQLite, upgrade20→21 y respaldo/relectura. Transporte del proveedor simulado;
precisión/coste del modelo real: **NO_EVALUADO**. Publicación, activación remota,
APK integrado y aceptación en teléfono corresponden al coordinador.
