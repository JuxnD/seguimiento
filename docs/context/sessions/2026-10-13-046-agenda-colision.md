# 046 — Colisión de fecha, identidades conservadas

Base Claude043 c51605d4573b3f3a14781bb6628cbe0a4b48eaf9, original intacto. Rama JuxnD/046-agenda-colision. Implementación local verificada; pendiente R1 root del candidato combinado043+046 exacto e integración funcional034/037/048. No APK/publicación propia ni visual035.

## Cambio y contrato

Sólo `ReadinessRepository.testAgenda` deja de deduplicar por fecha. Devuelve las seis identidades (ronda/parte) aunque torso movido dos veces coincida el miércoles con piernas. No crea fechas, movimientos ni aplaza el otro test. Orden por fecha y movimientos descendentes conservado; `effectiveTestOn` sigue escogiendo el primero para la prioridad diaria. Agenda e informe conservan ambos; benchmark consulta la identidad piernas. `readinessOn`, escritores y esquema quedan byteidénticos a043.

## Evidencia

[Manifiesto](046-evidence/final-receipt.json). Rojo independiente root contra043: esperaba6 y obtuvo5, SHA del oráculo CD65820F2165B735A56B238F16E93B489227858311E4FCD5F93E81E3B9140AA0, receipt214241336; texto original/raw preservados. Se porta sin cambiar sus expectativas y se agrega un segundo caso SQLite real: informe ambaspartes/corte, benchmark piernas pendiente sin movimiento, prioridad torso2, v3.1 separado, tercero rechazado y `total_changes()` idéntico antes/después de lectores.

Dos nuevos PASS y siete suites49PASS/0skip/analyze0: plan043_readers, plan043_agenda_benchmarks, plan043_benchmark_cutoff, readiness_repository, readiness_partial, reminder_scheduler y report_baseline_cutoff. Wrapper owner046 serial1/90s/no-pub; no full/gen. Bootstrap generado59980 sólo tras comprobar database/tables/lock iguales a045.

**Identidad final versus ejecutada:** el formato120 autorizado cambió también envolturas fuera del resolver. Después FIN y liberación, por aprobación root, se restauró únicamente readiness_repository al contenido del commit propio da473af para preservar readinessOn exacto y reducir ruido. El archivo formateado probado se conserva en evidencia; comparación sin espacios idéntica, hashes distintos explícitos. Fixture queda formateado. No se atribuye el hash final al SDK anterior: R1 root ejecutará el candidato final exacto. No se repiten51 propias por un cambio sólo de formato.

El diff funcional final modifica sólo el retorno/comentarios del resolver. Los otros lectores de043 conservan autoría y contenido. Los siete fallos preexistentes documentados por043 siguen separados para034; estas pruebas no los ocultan ni establecen aceptación humana. La guía visual se pospone por instrucción humana; este frente contribuye al entregable funcional.
