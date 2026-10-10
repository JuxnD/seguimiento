# Plan010 · Comidas conocidas y nuevas con estimación revisable

Fecha: 9-oct-2026. Estado: implementación local verificada; publicación,
servidor remoto, APK integrado y aceptación del owner pendientes.

## Autoridad y objetivo

El owner autorizó implementar los cinco frentes de la auditoría, incluido comidas
con Luna, en conjunto con Claude. Este recibo corresponde únicamente al plan010:
evitar que una comida ausente del catálogo desaparezca o exija introducir todas
sus cifras manualmente. La propuesta sigue siendo revisable; la app conserva
porción, incertidumbre y procedencia antes de guardar.

App: `C:/My Projects/seguimiento-010-luna`, rama `JuxnD/010-comidas-luna`,
base `a0521c856dc08b1c567bb8066709e01ac9683648` (C01 de Claude incluido).
Gateway: `C:/My Projects/control360i-010-estimate`, rama
`JuxnD/010-seguimiento-estimate`, base
`c41b1a35f917cbf5c4dbed1c33dda35f956234d3`, entrega local
`3f4bff14e5d811415860f4a59180ab3af2e1c1e8`.
Fuente del alcance: `seguimiento-ilustraciones/plans/010-comidas-luna-catalogo.md`.
Sin push, deploy, teléfono, datos reales ni consultas al proveedor real.

## Comportamiento entregado

1. C01 se preserva: una ficha por100g no se convierte implícitamente en porción.
   El umbral20 es una señal sospechosa, no una regla universal de cantidades.
   Snapshots y cantidades futuras de combos tienen regresiones independientes.
2. Nueva tarea compatible `meal_estimate`: known/local, estimated/revisable y
   unresolved/pregunta. `meal_text`, tareas antiguas y cliente viejo de status
   siguen funcionando. JSON truncado, IDs extraños, unidad incompatible, macros
   incoherentes y cobertura parcial se rechazan sin guardar ni filtrar errores
   privados. Si el servidor no anuncia capacidad, permanece el flujo anterior.
3. La búsqueda local examina todo el catálogo antes de limitar200 candidatos:
   nombre, aliases del mismo alimento y orden de favoritos/uso reciente.
   Un alimento fuera de los primeros200 aparece con un catálogo de1000.
4. La pantalla permite revisar/corregir cantidades y cifras, resolver pendientes
   o excluir con motivo; exige confirmar toda la comida. `350ml de leche con
   Milo` mantiene350ml, y Milo queda separado y pendiente/estimado sin reemplazar
   leche ni duplicar la bebida. La cobertura textual y vocabulario finito no
   prueban comprensión semántica general.
5. La unidad de la propuesta estimada queda fija. Escalar250g sólo permite
   otra cantidad en g; porción/ml requieren aclarar y consultar otra vez o
   entrada manual. El guard del draft rechaza incluso la alteración del
   controlador. También se preserva250g al editar el borrador libre heredado.
6. Añadir devuelve items + notas + decisión opcional de recordar. Guardar/Fusionar
   escribe comida y aprendizaje en una transacción. Volver/cancelar no escribe.
   Homónimos crean una ficha nueva; no se sobrescriben bases/unidades existentes.
   Procedencia, dudas y exclusiones sobreviven SQLite, informe y ZIP/reapertura.
7. Esquema21 añade `catalog_patches`:36 source IDs congelados, versión y foodId
   nullable. Parche aditivo/idempotente de referencias existentes: conserva
   ediciones, renombres, combos y snapshots; una colisión personalizada no se
   identifica como semilla y una eliminación no provoca resurrección.
   Nombres de recetas frecuentes son candidatos para estimar/preguntar, sin
   rellenarlos con macros inventados. Milo no tiene etiqueta nueva validada.

Decisión: [ADR0017](../../adr/0017-comidas-estimadas-y-catalogo-aditivo.md).
Contrato: [ia-contrato-v2.md](../../ia-contrato-v2.md).

## Evidencia roja y recuperación

- Catálogo1000: viejo `describeMeal` rechaza por superar límites antes de enviar;
  rojo real exit1, después encuentra ID1000 y envía≤200. [Rojo](evidence/010/red-catalog.txt).
- Borrador250g: editar/Guardar heredado lo transformaba en1porción; assertion
  expected250/actual1 falla. Después conserva250g y500kcal, además de la base
  per100 opcional. [Rojo](evidence/010/red-free-edit.txt).
- Unidad estimada: UI permitía editar g por porción/ml; assertion readOnly falla.
  Después UI fija unidad y draft rechaza ambas alteraciones;125g escala250kcal.
  [Rojo](evidence/010/red-unit-edit.txt), [verde](evidence/010/green-unit-edit.txt).
- Mutante retirando sólo el hook de aplicación del catálogo: upgrade20→21 falla
  expected36markers/actual0. Hook restaurado; fixtures históricos congelados no
  se modificaron. [Mutante](evidence/010/mutant-catalog.txt).

La primera suite concurrente tuvo fallos por el cambio del target schema20→21
y dos fallos temporizados de UI heredada; no se atribuyen a carga como causa
demostrada. Se corrigió únicamente el constructor de fixture vieja y expectativa
del target21; las assertions de valores legacy se conservaron. La prueba de
backup UI aislada y la suite secuencial pasaron después. La nueva tabla tiene
assertions independientes de creación, sourceId→foodId/patchVersion, arroz/leche/
Klim en sus unidades originales, idempotencia, renombre y respaldo.

Una suite posterior detectó nuestra frontera250g→1porción:631pasadas,16omitidas,
1fallo. Tras corregirla pasaron632/16; la revisión del coordinador abrió la
frontera adicional de unidad libre. El cierre vigente es el recorrido posterior
a esa corrección, no los verdes anteriores.
Los archivos de evidencia sólo normalizan espacios al final de línea y encoding
a UTF-8; no cambian assertions, veredictos ni stacktraces. El mock de transporte
de catálogo se corrigió para leer multipart, pues antes lo interpretaba como
JSON directo y fallaba dentro del harness (FormatException).

## Gates ejecutados

SDK preservado: Flutter3.22.0/Dart3.4; sin cambio de dependencia, firma o Android.
Código Drift regenerado exclusivamente con build_runner; `.g.dart` conserva su
tratamiento ignorado existente.

| Gate | Resultado |
|---|---|
| Baseline C01 `free_entry_replace_test` + `meal_form_free_replace_test` | 5 pasan |
| Migración/ZIP/fixtures18–19 y valores legacy | 48 pasan |
| DTO/catálogo1000/unknown/Milo350ml/cobertura/macros | pasan en suite focalizada |
| Focalizada antes del fix unidad, incluido interop | 15 pasan |
| UI final tras fix unidad | 4 pasan |
| Suite completa final con interop habilitado, posterior al fix unidad | 633 pasan,16 opcionales existentes omitidas; exit0,7min38s |
| Análisis final | 0, No issues found |
| PHP lint + pruebas antiguas + nuevas | 0;154 +79 comprobaciones |
| Diff whitespace, paths SDK/deps/native/fixtures congelados | 0; sin cambios |

Comando de suite app: `flutter.bat test --no-pub --concurrency=1 --reporter expanded`.
Evidencia completa: [suite final](evidence/010/suite-final.txt),
[análisis](evidence/010/analyze.txt), [upgrade/ZIP](evidence/010/migration.txt).
Variables opt-in del interop: `SEGUIMIENTO_ESTIMATE_GATEWAY` apunta al worktree
gateway y `SEGUIMIENTO_ESTIMATE_PHP` a `C:/xampp/php/php.exe`.
El test atraviesa Dart real→PHP real→Dart validado; sólo se simula el transporte
del proveedor con fake-key, store=false y datos sintéticos. No demuestra HTTP
remoto, autorización real ni calidad del modelo. PHP muestra aviso preexistente
de openssl cargado dos veces; su exit sigue0 y no se cambió entorno.

## Límites y gates abiertos

Precisión, coste y latencia del modelo real: **NO_EVALUADO**. Ninguna cifra del
corpus ficticio se presenta como ground truth nutricional. No se usó Sonnet
como oráculo ni se importó TCAC sin licencia/fuente. Antes de afirmar precisión
se necesita corpus de etiquetas/recetas pesadas, errores medidos y presupuesto
autorizado. La coherencia energética sólo verifica aritmética, no exactitud.

El coordinador debe integrar esquema21 con los demás frentes, regenerar Drift,
ejecutar gates y construir APK de esa fuente. Desplegar gateway y verificar
capacidad en producción, probar actualización/preservación y aceptar la UX en
el teléfono son gates separados. Esta entrega no modifica la versión publicada
ni demuestra operatividad del servidor.
