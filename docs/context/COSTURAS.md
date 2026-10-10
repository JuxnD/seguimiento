# Costuras verificadas de la candidata 1.21

## Parámetros de verificación

Autoridad: «procede y dejala lista para publicar». Entorno sintético aislado,
worktree `C:/My Projects/seguimiento-121-ready`, rama `JuxnD/121-ready`, fuente
funcional33a9fa9 (árbol `lib` de48040d2), Flutter3.22/Dart3.4 y Java17.
APK `release/seguimiento-v1.21.0.apk`, versión1.21.0+29, esquema20, SHA-256
`54a4804648f4edf802d0dbce1a7673f44d017cddbf9d6126a00e68e7fd5befd5`.
Firma histórica `6f839c41abf9e17634544a8ae5dff18ca64333b070ef40cd582dbdc9ac133ed7`.
Único Android utilizado: AVD Seguimiento_QA_119, emulator-5580. Teléfono del
owner no inspeccionado; confirmó1.20 instalada. Ninguna consulta IA real ni cambio
del gateway forma parte de esta verificación.

Oráculos: fixtures18/19 congeladas de fuentes genuinas anteriores; columnas
originales comparadas con SQLite independiente; guion esperado emitido por
fuente1.20; valores de producto A1-A6 reproducidos rojos enafaaf86.
Comandos y evidencia: [recibo de preparación](sessions/2026-10-07-lista-121.md),
[fixtures y migración](sessions/2026-10-07-migracion-121.md),
[ADR0013](../adr/0013-test-parcial-y-guion-congelado.md).

## Inventario

Inventario acotado a las fronteras revisadas para esta entrega. No demuestra
que se hayan descubierto todas las costuras del producto ni equivale a una
medida porcentual de corrección general.

| Cruce conocido | Estado y evidencia | Control negativo / límite |
|---|---|---|
| Campos test → validación → SQLite | Cubierta: entrada inválida atómica,0 y coma en UI, host y Android6flujos | A3 rojo antes; finite/negativo/repsdecimal/item/lado/round/duplicado/vacío rechazados |
| Filas test → cumplimiento de Hoy | Cubierta: torso completo lunes, parcial y piernas, viernesCindy; repositorio y reentrada Cuerpo | A1/A2 rojos antes; parcial no cumple, piernas deja sesión pendiente |
| I/D → mínimo/mejora/dosis | Cubierta: lado parcial visible y calidad por lado preservada al editar | A4 rojo; nunca calcular bilateral con un solo lado |
| Guion efectivo → JSON → reinicio → cronómetro | Cubierta: callerUI/Android, snapshot real en disco y APKrelease20→21/force-stop | Mutante caller ignora snapshot:4pasan/2fallan exactos; selección nueva siguiente sesión cambia |
| Guion1.20 → APK1.21 → snapshot actualizado | Cubierta: APKpúblico20 muestra Rollout2/2, actualizaciónsinuninstall, mismo índice39/dosis y40pasos; repetición trascierre | Mutante legado agrega escalera:5pasan/1falla exacto |
| Evento lumbar → SQLite → snapshot/contexto/época | Cubierta: idempotencia, crash entreBD/JSON, sesiones de época vieja guardadas después excluidas | Evento repetido no vuelve a bajar; día efectivo no cambia al retomar |
| Crear/editar/borrar series → Drift → consejo visible | Cubierta: consumer vivo true/false/true/false; Android y widget | A6 rojo; mutante readsFrom desconectado:5pasan/1falla exacto |
| SQLite18/19 → SQLite20 → ZIP → receptor → reapertura | Cubierta: todascolumnas29/31tablas; fuentes/guía/hash/citas IA; negativos de pérdida | Única normalización19: tiempo de mode=test sin medición; tiempos normales preservados |
| Fuente → APK distribuible → firma/instalación/BD | Cubierta pública: APK72.147.050bytes/SHA7410dca1; CI/Release del tag e314151, firma histórica, install-r público20→público21,231filas exactas tras reinicio | Aceptación en teléfono pendiente; ver recibo handoff-publicacion-121 |
| Handoff → metas propuestas → confirmación → perfil/anillo | Cubierta: rojo de metas antiguas; QA APK público conserva160/170 al instalar y cambia130/160 sólo al Aplicar; Hoy de130 | No se reemplaza perfil silenciosamente; objetivo140–160 visible en propuesta |
| Tabla de resultados → contexto del informe/IA | Declarada: save escribe nombres/lados/calidad y «duración sin medir» en contexto existente | No se hizo consulta remota nueva; gateway no cambia |
| APK → técnica3D de ejercicios | Declarada: catálogo heredado, suite base de figuras; capturas opcionales omitidas | No se cambiaronfiguras ni se afirmó aceptación visual nueva |
| Datos reales → utilidad del asistente/foto | Declarada: capacidades de1.20 preservadas; pruebas existentes | Precisión con comidas reales y adopción owner siguen pendientes |

10 de 13 costuras enumeradas con ejecución vigente; 3 declaradas y 0 sin cobertura en
este alcance. Variaciones de artefacto/configuración/recorrido invalidan atribuir
estos resultados a otro paquete: ejecutar los mismos gates de nuevo.


## Candidata local 1.22: ilustraciones y recuperación (9oct)

Este alcance no hereda automáticamente el veredicto del APK1.21 de arriba.
Autoridad: renovar todas las ilustraciones y auditar acompañamiento/metas con
casos ficticios; el feedback del owner rechazó Cuádriceps y Vela. Fuente local
`seguimiento-ilustraciones`, rama `JuxnD/ilustraciones-completas`, commit7fa8099.
Comprensión humana/publicación pendientes. Recibo: [sesión](sessions/2026-10-09-ilustraciones-y-recuperacion.md).

| Cruce | Evidencia ejecutada / gate restante |
|---|---|
| Guías/detalles/escaleras/movilidad → recetas → JSON | Generación73entradas explícitas; testcoverage exige cada nombre incorporado y falla si no hay receta |
| Poses → rig3D → apoyos/equipo | Longitudes, suelo/pared, variantes, continuidad; controles reales de muñeca/pie/cabeza y mano–equipo en61muestras. Fixturesanteriores fallan3y2casos, sin convertir criterios en una regla clínica universal |
| JSON/renderer → miniatura/guía/ampliación/movilidad | Visor compartido; biblioteca con búsqueda, lados, agarre y carga; texto1/1.3/1.6, teléfono y tableta; nombre personalizado informa ausencia |
| Fuente → mockups → comprensión | PNG del mismo Flutterpainter, galería73entradas y4montajes; feedback humano abrió correcciones nuevas. Comprensión sigue pendiente del owner |
| Fuente → APK → asset/firma → Android | Requiere recibo de build posterior a la última corrección; no atribuir capturas/APKprevios al rigactual |
| SQLite/historial → carga/racha → aviso | Racha20/21 real, moderado conocido corta; sesión desconocida no prueba recuperación, excluye futuro/importados; avisos confecha y sin promesa fija |
| Perfilguardado → mínimo5000 → relectura | Nuevo perfil5000; existente conserva7500 hasta llenar campo/Guardarperfil. Widgetdemuestra apertura/CTA0escrituras y guardado cambia sólo pasos |
| Medidas → consejo | Una toma/semana y cintura vieja no autorizan ajuste; negativos antes, positivos con datos frescos después |
| APKprevio → actualizaciónsinuninstall → datos | Baseline propio QA5580: esquema20,32tablas,528filas y3archivos; comparación exacta tras actualización se registra en el recibo |

Las pruebas y recapturas prueban las fronteras enumeradas. No afirman que todo
el entrenamiento sea seguro, que el owner lo comprenda o que las metas ya se
adapten longitudinalmente; esto último queda enPlan007.

## Plan008 local: evidencia de progreso (9oct)

Entorno autorizado: SQLite en memoria y flutter_test, fuente aislada en
`seguimiento-008-evidencia`. [Contrato](progress-evidence.md),
[recibo](sessions/2026-10-09-008-evidencia.md).

| Cruce enumerado | Estado y evidencia |
|---|---|
| Marcas acumuladas → SQLite → DTO → consumidor del cierre | Cubierto local:60/125/195→60/65/70→media65; work/lap separados y protocolo distinto/unknown no compara |
| Serie manual con split/fallo → SQLite → DTO → guía siguiente | Cubierto local:12+3/fallo no muestra+kg; mutante de pérdida de flags en la proyección produce rojo en esa UI |
| Tests parciales/dudosos → SQLite → tabla/dosis | Cubierto local:T3 parcial visible conservaT2 limpio; dudoso observado no aumenta dosis; unknown/futuro/inválido no aptos |
| Fecha prevista vs real → pantalla → SQLite → reentrada | Cubierto local:nuevo usa9oct pese previsto11dic; edición homogénea conserva9oct. [Revisión2](sessions/2026-10-09-008-fecha-parte.md): todas las filas de la parte; fechas mixtas/inválidas/futuras bloqueanGuardar hasta confirmar, sin escrituras al abrir/picker/cancelar |
| Fuente integrada con Claude → APK → uso del owner | Declarado: repetir gates sobre candidato integrado y APK; no observado por este worktree |

Cuatro cruces locales cubiertos y uno declarado en este alcance. El denominador
es este inventario, no todo el producto. No hereda QA de APK anteriores.

En [integración122](sessions/2026-10-09-integracion-122-base-evidencia.md),
la costura serie→SQLite→DTO→guía conserva también mode real. Técnica no permite
subida ni se mezcla con normal; normal/normal mantiene consejo y observación.
Rojo del automerge y verde del ajuste cruzan la pantalla y la base reales.

## Preparación012: privacidad y gate futuro

Esta fila no hereda QA nativa de otro APK. Fuente base d2d3070 en worktree012;
detalle/evidencia: [recibo de sesión](sessions/2026-10-09-012-preparacion-piloto.md).

| Cruce | Cobertura / límite |
|---|---|
| Exportar → revisión de inventario → crear/compartir | Widget en ruta Ajustes exige confirmación; cancelar no llama host/plugins. Incluye IA/archivo sin cifrar; formatoZIP y guards existentes conservados. Compartir en Android nuevo PENDIENTE |
| Copia automática → preparar → confirmación de restore | Archivo SQLite ficticio real llega a confirmación que declara reemplazoIA y conservación de sesión/permisos/licencia. Rechazos/restore del formato probados en suite backup existente; APK nuevo PENDIENTE |
| Borrar conversación → DB actual → copias previas | UI explica alcance, cancelar conserva y confirmar borra al releerDB. No se implementó purga ni se prometió borrar servicio/externos |
| Manifest → SQLite/fotos/JSON/UI/logs → receipt → APKmetadata | 17tests Python con artefactos ficticios y mutantes; CLI release rechazafixtures. Lectura aapt/apksigner real y collector/candidato integrado PENDIENTES |

No hay nuevo porcentaje global: el inventario histórico permanece ligado a sus
artefactos. El recibo de herramientas no atestigua que un dispositivo ejecutó
comandos; procedencia del collector debe ser revisada antes de aceptar captura
nativa. SDK/tienda, alta aislada y ensayo humano siguen abiertos.

## Plan010: comidas estimadas y catálogo (9oct)

Fuente aislada `seguimiento-010-luna` sobre a0521c8 (C01 incluido). Gateway local
`control360i-010-estimate` commit3f4bff14. [Recibo](sessions/2026-10-09-plan010-comidas-local.md).
Esta evidencia no se atribuye al APK publicado ni a un servidor desplegado.

| Cruce | Evidencia / gate restante |
|---|---|
| Catálogo completo → candidatos≤200 → transporte | Nombre fuera de primeros200 en1000; rojo con parser anterior y verde por selección local |
| DTO Dart → schema PHP → respuesta → parser Dart | Interop de ambos runtimes reales con proveedor ficticio; cliente antiguo status intacto y154checks legacy; remoto pendiente |
| Unidad porción → escala → borrador | Unidad IA fija, guard rechaza g→ml/porción;125g escala250kcal;250g se conserva al editar/Guardar; rojos archivados |
| known+unknown → revisión → Guardar → SQLite/informe | Pendiente impide aceptar; exclusión con motivo o resolución humana; notas/dudas se releen; cancelar/red fallida0escrituras |
| Aprendizaje opcional → catálogo/combos/snapshots | Sólo al Guardar, ficha nueva ante homónimo, conserva base/unidad y cantidades originales |
| SQLite20 →21 → parche → renombre/borrado → ZIP/reapertura | Tabla/mappings/36source IDs/version comprobados aparte; sin sobrescribir ediciones; idempotencia y tombstones; registry y notas exactos en ZIP |
| Propuesta sintética → precisión/coste Luna real | NO_EVALUADO; coherencia aritmética y cobertura textual no equivalen a precisión semántica |
| Fuente nueva → APK integrado → actualización/teléfono | Pendiente del coordinador; no se tocó teléfono/producción ni se publicaron cambios |

En [integración122/010](sessions/2026-10-10-integracion-122-010.md),83controles
dirigidos cruzan los consumidores reales del checkout combinado: Dart→PHP
ficticio→Dart, revisión→SQLite,18/19/20→21, registry→ZIP→reapertura y C01.
008/mode/warmup/snapshot no cambian en este tramo. El primer timeout de carga
se conserva junto al gate consolidado posterior; no se infiere su causa.
Suite completa del candidato, APK/backend remoto y aceptación del owner siguen
pendientes: estos83casos no son una nueva certificación global del producto.


## Frente014 · figuras del calentamiento (10oct2026)

| Cruce | Evidencia / límite |
|---|---|
| warmupMobility/warmupForZone/buildWarmup → recetas | Test producción primero rojo6ausentes, ahora exige cobertura real;79entradas, sin fallback para esas seis |
| Python→JSON→KeyPose→solve2D→lift3D→interpolación | Campos opcionales de hombros y arco de pierna;61muestras, defectos rojos y mutantes reales;73objetos/geometrías previas idénticos |
| Pose→suelo/barra/pared/banda→extremos | Palmas/pies/codos/contactos y grip con relectura del JSON; no afloja umbral0,35 ni guards |
| Painter/TechniqueContent→PNG→montaje |65capturas reales, seis guías e intermedios, lado derecho, texto1/1,6 y scroll; Roboto versionado |
| Fuente→comprensión→APK→persona | Comprensión humana y QA integración/APK pendientes; no hubo build, instalación ni publicación |

[Recibo014](sessions/2026-10-10-014-calentamiento.md). La política por dolor
no pertenece a este frente y no se valida por la figura disponible.
