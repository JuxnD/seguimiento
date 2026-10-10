# Costuras verificadas de la candidata 1.21

## Plan022 local: alta neutral → SQLite → AppEntry → shell/restaurar

Base `f34ab7c`, worktree `seguimiento-claude-022`, Flutter3.22/Dart3.4, esquema23.
Sin APK, AVD ni teléfono; nativo (permisos reales, Health Connect) NO_EVALUADO.

| Cruce | Evidencia local / límite |
|---|---|
| onCreate → SQLite → AppEntry | Rojo f34: 5 metas aceptadas al instalar; verde: new/pending, 0 vigencias, 0 planes; AppEntry no monta HomeShell (spies: 0 permisos/avisos/pasos/respaldo, también tras 3 min) |
| Alta (pantalla) → transacción → listo → shell | Confirmar escribe 6 vigencias desde la confirmación real y corre efectos una vez; cancelar/reiniciar/fallo (trigger SQLite) dejan pending sin cambios; doble confirmación no duplica |
| Listo → restaurar alta pendiente → app abierta | Vuelve al alta, `applySchedule([])`; mutante sin guarda programó 17 avisos y fue rechazado |
| ZIP23 → trialOpen/checkComplete → base/fotos | Origen/estado inválido o pending con registros rechazado antes de reemplazar: bytes de base, fotos y flags idénticos; mutante sin `validateSetup` rechazado; fallo tardío revierte alta previa y fotos |
| ZIP/SQLite 20–22 → 23 | legacyUnknown/ready sin pedir alta; 20/21/22 conservan cada tabla→columna→fila; desde 22 sólo se añade `kcalFloor`; fixture real 21 conserva sus 33 tablas |
| Correcciones → transacción | Sin consentimiento, sin respaldo, con flags «descartado», origen nuevo o legado: 0 escrituras; consentimiento retirado entre pantalla y transacción: 0 escrituras |
| Historia «sin meta» → lectores Hoy/comidas/avisos/informe/IA | **Pendiente 012**: leen la proyección del perfil (130/2400). No activar usuarios nuevos ni publicar hasta ese cierre |

[ADR 0020](../adr/0020-alta-neutral-y-arranque-protegido.md) ·
[recibo022](sessions/2026-10-10-022-alta-neutral-claude.md).

## Plan019 local: marcas de Cindy → pantalla → draft

Base `238ef85`, worktree `seguimiento-019-cindy`, Flutter3.22/Dart3.4.
No es evidencia de APK integrado ni del teléfono del owner.

| Cruce enumerado | Evidencia local / límite |
|---|---|
| Marcas fraccionarias → AmrapScreen → Terminar y guardar → SessionDraft | Rojo1201 vs1200 en BASE; composición de fases conserva la ventana20:00 y dosis/rondas |
| Cortar a2:00 → repeticiones extra → snapshotJSON → reabrir → draft | Ventana120, incompleta, marcas y dosis idénticas; no rellenar20min prescritos |
| Cap/tiempo desconocido → registro | Sin inicio no inventa1200; ventana registrada1300 se conserva como1300, sin normalizarla al cap |
| Composición Cindy → otros cronómetros/protocolo/historia | Tabata preservado, matemáticas globales y comparación008 intactas; historias antiguas no se migran |
| Draft local → persistencia/APK/uso diario | Pendiente de integración y QA del coordinador; esta tarea sólo verifica la salida real de la pantalla en flutter_test |

[Comandos, hashes, montaje corregido y resultado de suite](sessions/2026-10-10-019-cindy-window.md).

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


R1: Retracciones valida también la suela completa respecto al suelo en61muestras
(min4,75u), no sólo mano–barra. Círculos declara dirección por texto numerado
independiente de cámara. ViewerCTA→glifo real→semantics→acción prueba etiqueta
completa a360px/text1,6 y2,0; reflow conserva todos los controles. ReciboR1
sobrebasee35a; aceptación humana yAPK pendientes.

## Slice016: consumidores Android de marca y respaldo

| Cruce | Estado / límite |
|---|---|
| S013→PNG→launch legacy/atributo31→theme consumidor | Parser fuente, consumidor y hashes30PNG; mutantes recurso/fondo/default rechazados. Render Android/arranque del APK exacto PENDIENTE |
| Política→Manifest→reglas legacy/cloud/D2D | XML real con los9dominios admitidos; modo vacío/ausente, include, dominio desconocido, path ajeno y consumidores rotos rechazados. Fusión de Manifest/OEM/transportes PENDIENTE |
| Copy→Ajustes→ZIP/cancelación/SQLite/fotos | Prueba widget de texto completo configurado y límites, más confirmación/cancelación y relectura originales. Android AutoBackup nativo NO_OBSERVADO |

Decisión y autoridad:[ADR0018](../adr/0018-arranque-y-respaldo-android.md).
No transforma una política fuente en promesa de eliminación de copias previas
ni de control de terceros; no toma verdes de APK anteriores para este slice.

Checkpoint122 con014/016:[recibo integrado](sessions/2026-10-10-integracion-122-014-016.md).
Generación repetida idéntica,73objetos/hashgeometrías legacy conservados,76gates
dirigidos verdes y4mutantes del JSON rechazados por assertions reales. Después
de restaurar bytes,10controles de apoyos/paridad verdes. SDK/schema/firma no
cambian; native/OEM/owner y full candidato siguen pendientes. En el checkpoint
Claude posterior se adaptó la cobertura014 a las fuentes reales, sin reconstruir
el mapa warmupForZone retirado por la política de dolor.

## Plan015 local: gráficas con rango y evidencia (10oct)

Autoridad acotada: `seguimiento-015-graficas`, `JuxnD/015-graficas-evidencia`,
base de integración122 `bf1da688`. Sin cambios de esquema ni servicios externos.
[Contrato](../progreso-metricas.md),
[recibo y evidencias](sessions/2026-10-10-015-graficas-evidencia.md).

| Cruce enumerado | Evidencia ejecutada / límite |
|---|---|
| Rango del informe → consultas SQL → providers → gráfica/registros | Fixtures SQLite con datos dentro/fuera; sitios y unidades del mismo rango;240sesiones y límite máximo200; selección cambia datos, resumen y tabla |
| Dosis/modo/plan/ventana/calidad → protocolo → comparación | Firma compartida008;20/30min y técnica/normal separados; importada, estimada, cortada y desconocida siguen observaciones; rótulo humano muestra condiciones antes de escoger |
| Fecha real → eje/tocar → fecha/valor/evidencia textual |1ene,2ene,1feb ocupan0,1,31días; sin curva inventada, punto aislado visible; tap y registros inspeccionables |
| Snapshot de comida/cierre → nullable → barra/estado | Ausencia sin barra≠cero guardado; cierre igual aReportStats; actualización del cierre conserva tabla abierta; proteína0 real tiene eje válido |
| Meta con fuente y vigencia → resolver → referencia y tabla | DTO/fixture local cubierto; rechaza unidad/fecha/fuente/número inválidos; no usa perfil actual para historia. Adaptador009 no implementado aquí |
| Registro antiguo editado → reconsulta → rango activo | Actualiza peso/sesión fuera de90/60días; prueba refuta invalidación adicional, sin modificar watchers de otros consumidores |
| Widgets compartidos → renderer360/texto1.6 → capturas | TresPNG sintéticos del Flutterrenderer; tabla y opciones completas revisadas. No equivale a aceptación humana o medición de latencia Android |
| Fuente local → APK integrado → teléfono/piloto | Declarado pendiente del coordinador; ninguna instalación, publicación o usuario real verificado en015 |

Siete cruces locales cubiertos y uno declarado en este alcance. No cierra011,
radar, historial de metas o piloto, ni hereda validación de otro APK.

En [checkpoint122/015](sessions/2026-10-10-integracion-122-015.md),los44criterios
pasan sobre la fuente combinada con008/010/014/016. Nueve controles compartidos
cruzan unidad de comida, paridad geométrica, controles grandes y divulgación.
No se cambió comportamiento para integrar; catálogo79/73 y30PNG preservados.
Rango/protocolo comparten el mismo read-model; metas históricas y radar siguen
pendientes de sus adaptadores, no se fabrican a partir del perfil actual.

## CheckpointClaude en122: molestiasSQLite y Cindy de prueba

[Recibo separado](sessions/2026-10-10-integracion-122-warmup.md). El nuevo caso
SQLite→RecoveryRepository→GuidedSessionScreen exige aviso de Hombro5 reciente,
excluye Rodilla2/Codo antiguo, conserva siete dosis y relee snapshot sin pasos
completos.18casos pasan, junto con24controles de figuras/guía/snapshots; esquema21,
paridad79/73 y30PNG intactos. Las notas son avisos, no recetas ni completitud.

La sensibilidad negativa a provider conectado a otraDB vacía queda
NO_EVALUADO: diagnóstico de harness BLOCKED al cerrar la DB fuente, pese a
que el montaje llega al oráculo y la DB vacía cierra. Se conserva salida de
los intentos; no se declara rojo a una interrupción ni se infiere bug nativo
del cierre de una prueba. Revisión final, full candidato e instalación pendientes.

La repetición independiente deRoot en9c0de20 encontró2 snapshots históricos
viejos (16casos pasan/2fallan), por lo que no aprobó el cierre completo. Traza
aislada conserva emitted/completion/archivo de una misma instancia: foto vieja
mientras quedaban saves nuevos pendientes; último completion deja foto correcta.
No reproduce el fallo justo tras20ticks y su causa exacta sigueNO_CONFIRMADA.
Se autorizó una barrera en el harness que espera las futures reales emitidas
sin pendientes, cota5s dentro del timeout original y relectura física/assertions
intactas.18dirigidos+8Store pasan con esa barrera; producción no cambia y la
revisión independiente de esta fuente queda pendiente. Mutante2DB no se reabre.

## Integración122/019 · reloj→fases→draftCindy

[Recibo combinado](sessions/2026-10-10-integracion-122-019.md). Source019
aprobado3b91c96 se integra sobre7843732 sin conflictos;51casos cruzan draft
fraccionario/cortado/retomado y controlesClaude/warmup/Store. Composición de
fases conserva la ventana medida, sin tolerancia ni cap inventado. Checklist
Cindy y barrera deFuture reales sobreviven; writer y registros viejos intactos.
Schema21, SDK3.22, JSON79/73 y30PNG no cambian. Full681/16 del source019
es anterior al copyplural y no acredita este snapshot. APK/owner pendientes;
mutante2DBNO_EVALUADO y causa previaNO_CONFIRMADA conservados explícitamente.

## Integración122/018 · evidencia→radar y receta→draft

[Recibo combinado](sessions/2026-10-10-integracion-122-018.md): sourcebc6cc9b
integrado sobre d108fafa, conflictos documentales concatenados.74casos cruzan
núcleo008/renderer, SQLite→UI y cronómetros/snapshots anteriores. Se compara
literalmente `_draft`019 y receta extraída; checklistClaude y barrera784 intactos.
CincoPNG/JSON nuevos coinciden con fuente aprobada y raster corre siempre en
las3escalas. No se crea persistencia ni ruta deproducto;011/009/piloto pendientes.
Solo lectura conserva79/73/30PNG/schema21/SDK/Android.698/16 de018 previos al
último copy no son full de integración. Comprensiónowner y gate de APK abiertos.

## Plan018 local: núcleo y widget del radar (10oct)

Base238ef85f/018-radar-core, sin esquema/repos/providers/metas009 o rutas nuevas.
[Contrato](../design/radar-personal.md), [recibo](sessions/2026-10-10-018-radar-core.md).

| Cruce enumerado | Evidencia / límite |
|---|---|
| TestResult008 → selección por fecha → actual/inicio | Primera/última apta, I/D coherentes y menor; futuro/parcial/duda posterior no borran apta anterior; una fecha no demuestra cambio |
| Receta del timer → helper compartido → conteo Cindy | Extracción literal/re-export conserva callers; receta completa+parcial validada, ventana real1200s; overflow y denominador no demostrado quedan observaciones |
| Referencia explícita → dos perfiles → raw/porcentaje | Misma referencia identificada; sin referencia no score;>100 sólo recortado en geometría;0 real no ausencia |
| SQLite de tests → repositorio008 → núcleo → widget | Relectura sintética conserva fecha/calidad/I/D y muestra duda posterior separada; sin cambiar consultas de producto |
| DTO → pintura Flutter → comprensión inspeccionable | Nombres en ejes/texto1/1.6, números+leyenda a2; RGBA de punto y tramos de ambos contornos fuera de círculos; ausencia no cierra/rellena; tabla y tap/teclado/semántica/callbacks |
| Núcleo/widget → pantallas/metas reales/APK | Declarado pendiente011/009; callbacks sin navegación ni escritura.019 corregirá composición del timer fuera018. Capturas no equivalen a aceptación del owner |

Cinco cruces locales cubiertos y uno declarado. El inventario acota018,
no certifica condición física, publicación o utilidad con datos reales.

## Integración 122 / 009 — metas 22 junto a radar 18/timer 19

[Recibo combinado](sessions/2026-10-10-integracion-122-009.md), merge 4f11d87
sobre e6b420a con fuente 566 aprobada; ancestro 784, sin conflictos. Preserva
nueve rutas 018/019, composición medida de Cindy, plural/checklist y barrera real
Future → archivo. Esquema 22 conserva CatalogPatches 21; no escribe 23 ni cambia SDK.

| Cruce | Evidencia local y límite |
|---|---|
| SQLite 21 real → migración 22 → reapertura | Fixture sintética generada por AppDatabase de e6, hash/33 tablas/PRAGMA/filas fijados antes de abrir 22; todos datos 21 intactos, sólo tablas/columna 22 esperadas y metas legado desconocidas/conocidas; una prueba, no upgrade APK |
| Metas/historial → Hoy/informe/avisos → decisión | 310 dirigidos combinados conservan dosis, variante/modo/calidad, vigencias, medianoche y cancelación/reactividad; RIR null no certifica reserva ni RPE moderado recuperación |
| Evidencia → núcleo/widget 18 y reloj → draft 19 | Nueve archivos 18/19 idénticos a e6; radar no conecta aún 011, receta compartida/total de fases/plural preservados; sin nueva receta por dolor |
| UI → save Future real → archivo | Barrera 784 intacta; causa histórica NO_CONFIRMADA y mutante 2DB BLOCKED/NO_EVALUADO se conservan |
| Producto combinado → suite | Única full 829/17 anterior al tipado del test nuevo, con producto final exacto; mismo probe 21 tipado/analyze 0 después, sin cambios de oráculo/SQL/fixture ni otra full |
| Fuente → APK/Manifest/upgrade → teléfono/owner | Pendiente QA nativa del candidato, firma y conservación reales; no se tocó AVD/backend/rama diaria ni se publicó |

RPE de recuperación del ADR 0016 se reconcilió sólo en docs: favorable únicamente
feeling 1–2 o recoveryOk=true en 3 días; negativo prevalece, faltante desconocido.
Se mantienen RPE ≥ 9 como fatiga y política v1 experimental a revisar con el owner.
011, alta/esquema 23 y gate 012 con candidato final siguen abiertos.


## Plan011 local: SQLite → radar → referencias → registro

| Frontera | Oráculo y límite |
| --- | --- |
| SQLite tests/sesiones/sets/nombres → DTO018 | Historial completo≤corte; bilateral parcial/dudas no tapan apta; fechas futuras excluidas, inválidas no normalizadas. Sets ID conserva DDFFSS; lote300 equivale a recorrido completo. Memoria O(observaciones+sets), no constante. |
| GoalHistory → contornos/gráficas | Referencia única ambos contornos, vigencia conocida; null/ausente/legado sin coordenada. DatedChartGoal fin abierto null. Proteína por día; pasos sin meta fin de semana ni ausencia→0. |
| UI diálogo → setReference → SQLite → Riverpod | Save/cancel con relectura; fecha real de decisión sin backdate; State del diálogo conserva controller hasta desmontaje; eje seleccionado conserva recarga. |
| SQLite antigua / restore → conexión/providers | Edición/borrado fuera90d reactivos; ZIP restore relee referencia y databaseGeneration recrea streams reales. Warnings Drift conservados, no silenciados. |
| PeriodSummary → alimentación |130→160:1/2 días con referencia conocida y promedio140 separado. Kcal sábado/domingo propia/heredada/ausente; null/legado separados, sin score0 falso. |
| Eje → TestResults / Cindy real | T1/2/3+parte explícitas, calendario Previsto real. Abrir/cancelar no crea SQL; pendiente conserva selección/archivo, wrapper mantiene timer/checklist/snapshot019. |
| DTO → renderer360/escala1/1.6/2 |Captura inicial sin scroll; detalle touch; painter018 intacto; oráculo píxel100% y mitad de ambos tramos, mutante sin tramos y restauración hash. Capturas ficticias, no native ni aceptación humana. |

[Recibo y resultados finales](sessions/2026-10-10-011-radar-integrado.md).
No se reabre launch/cleanup020 rechazados por policy ni se toca otro AVD,
SDK/esquema/servicio/IA/datos reales.012 y022 consumen estos helpers después de
la revisión raíz; no duplicar fórmula de kcal ni motor de metas.
# Checkpoint de construcción 011+022 (10 de octubre)

API de radar/historia 011 y setup/origen 022 se combinan mediante merges locales
sin conflictos, fuente5352440 y esquema23. GeneraciónDrift/analyze/diff pasan;
no es evidencia de una suite final combinada. Barrera Navigator tras ZIPpending
024 sigue NO_EVALUADA; cierre de lectores023 y continuidad genuina18/20/22→23
pendientes. [Recibo](sessions/2026-10-10-integracion-122-011-022-base.md).
