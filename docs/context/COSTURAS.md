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
