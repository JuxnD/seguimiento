# Implementación 1.19
| Plan | Estado | Evidencia |
|---|---|---|
| 119-fuentes | DONE | Fuentes versionadas; negativo SDK sin Roboto, verde 19 controles/renders |
| 119-experiencia | DONE | Editor y SQLite, guía, Hoy; negativo y cinco controles con capturas |
| 119-respaldo | DONE | ZIP/DB/fotos, negativos y reversión; Android con espacios sintéticos |

Integración en `JuxnD/release-1-19`, 1.19.0+27. Pruebas locales: 476 aprobadas,
dos capturas opcionales omitidas en la corrida general y ejecutadas aparte.
Tres controles Android aprobados, incluida consulta ficticia al gateway real.
Gate de publicación aprobado: fuente ce68981, CI37499905119 y Release37499977216
exitosos; APK publicado descargado, hash y firma verificados e instalado en QA.
[Recibo y pendientes de aceptación](../docs/context/sessions/2026-10-06-entrega-119.md).
# Nueva versión 1.20: Improve antes de ejecutar

Owner autoriza todas las funciones propuestas y publicación (6-oct-2026).
[Auditoría confirmada](120-improve-audit.md). La selección ya está dada;
no repetir aprobación para acciones dentro de este alcance.

| Orden | Plan | Estado | Dependencia |
|---|---|---|---|
| 1 | [001 Gateway y contratos](001-120-gateway.md) | DONE | Contratos, cuota, status y compatibilidad publicados/releídos |
| 2 | [002 Comidas/frase/etiqueta](002-120-comidas.md) | DONE | Borradores revisados y relectura SQLite; etiqueta real sintética |
| 3 | [003 Historial/informe/guía](003-120-informes-guia.md) | DONE | Fuentes/citas, migración17→18, ZIP, acciones y guía contextual |
| 4 | [004 Integración/release1.20](004-120-release.md) | DONE | Tag c7972c7, CI/release success, APK público firmado y upgrade QA |
| 5 | [005 Preflight de dependencias](005-120-preflight-dependencias.md) | DONE | Rojo/verde, orden y preflight repetidos por asesor |
| 6 | [006 Ingreso HTTP real](006-120-ingreso-http-real.md) | DONE | JSON multipart completo, visión >1 MB, diagnóstico retirado |

Cada ejecutor en worktree aislado, asesor revisa diff/comandos. La auditoría
solo escribe plans; implementación y despliegue suceden después bajo autorización
expresa de nueva versión. Límites de captura/privacy/incertidumbre no se eliminan.

[Recibo final de la publicación](../docs/context/sessions/2026-10-06-entrega-120.md).
La aceptación en el teléfono del owner y la precisión con comidas reales siguen
como gates humanos; no son pendientes de implementación ni de publicación.

