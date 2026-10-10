# Recibo015 — gráficas con rango y evidencia

Fecha:10oct2026. Estado: implementación local completa, gates finales exit0.
Autoridad: ejecución aislada del plan015 y reaperturas acotadas del
coordinador. No autoriza publicación, servicios externos, teléfono o datos reales.

## Identidad y alcance

- Worktree: `C:/My Projects/seguimiento-015-graficas`.
- Rama: `JuxnD/015-graficas-evidencia`.
- Base verificada: `bf1da688d88c89d231200e6aa3b4f1b8dcb013d7`, integración122 con008.
- SDK: Flutter3.22.0 / Dart3.4.0, ruta `C:/seguimiento-sdk-3.22.0/flutter/bin`.
- Esquema, dependencias, firma, Android, fixtures legadas y planes no modificados.
- Commit de entrega: el que incorpora este recibo; obtener su identidad con
  `git log -1 --format=%H -- docs/context/sessions/2026-10-10-015-graficas-evidencia.md`.
  El manifiesto adjunto vincula los archivos funcionales y las pruebas finales.

Objetivo: que las gráficas representen las fechas, valores, ausencia y condiciones
guardadas, con evidencia accesible antes de concluir evolución. Este slice de011
no implementa radar, nota universal, motor009, historial de metas o piloto.
Contrato: [progreso-metricas](../../progreso-metricas.md).

## Pasos y resultados

1. **Autoridad y deriva.** Ruta y rama inicialmente ausentes, worktree creado desde
   la base aprobada; contexto leído. Deusctx verificó índice/base y callers de
   ChartRepository; claims materiales comprobados en fuente. Sin cambios previos
   del owner. Se reutilizan SessionDraft.exerciseProtocol, RoundTimingEvidence,
   circuitSpanSec, weighMomentOf, isDayClosed, tema, Riverpod y fl_chart existentes.
2. **Preparación y referencia.** Pub/build_runner regeneraron dependencias y
   archivos ignorados necesarios del worktree nuevo, sin editar generado a mano
   ni cambiar esquema/lock. Una primera corrida empezó antes de terminar la
   generación: error de compilación, no rojo funcional. Tras generación pasan
   **28 pruebas de referencia**, [baseline](evidence/015/baseline-015-complete.log).
3. **Cuatro rojos funcionales contra la base.** Ausencia diaria rellenada con0;
   mismo Circuito sin distinguir modo; fechas1ene/2ene/1feb ubicadas0/1/2; peso
   fuera del rango aún presente. [Registro](evidence/015/red-015-complete.log),
   exit1 por assertions, no por imports ausentes. Tras corregir pasan los4.
4. **Consultas y evidencia.** Rango inclusivo y orden en SQLite para todas las
   métricas; sesiones máximo200 y sets/rondas consultados en lotes. Fixture240
   sesiones verifica corte y clamp. Tipo, modo, plan y dosis reales separan series.
   Calidad dudosa conserva valor y motivo, sin construir mejora comparable.
5. **Nutrición y tiempo.** DTO visual nullable mantiene ausencia distinta de0;
   el cierre coincide con ReportStats y no verifica macros. X por días reales,
   segmentos sin suavizado, punto único y tooltip con fecha/valor. Meta opcional
   exige fecha, unidad y fuente: no dibuja perfil actual como historia.
6. **UI y recuperación de gates.** Tabla diaria conserva expansión ante cierre;
   selección cambia línea, resumen y registros. La prueba de cierre produjo un
   rojo funcional antes de PageStorageKey. También hubo Timer de teardown: quedó
   separado del fallo funcional, [primer recorrido](evidence/015/ui-evidence-015.log),
   [segundo recorrido](evidence/015/ui-evidence-015-fixed.log).
   Se declaró STOP y el coordinador autorizó desmontar/pump/cerrar/pump inline,
   con fallback idempotente; se conservaron assertions y timeout.
7. **Ventana y revisiónR1.** La prueba20/30min falló antes de usar circuitSpanSec:
   [rojo](evidence/015/red-window-015.log). Calentamiento/enfriamiento diferentes
   con ventana real20min no separan protocolos. R1 reprodujo tres rojos adicionales:
   ayuno en medidas, momento antes/después de fútbol en peso y selector «grupo1»
   sin condiciones, [registro](evidence/015/red-r1-all-015.log). Se corrigieron
   con campos guardados y rótulo humano. La hora queda en evidencia, fuera de la
   firma; no se infiere ayuno desde notas. Un finder ambiguo entre encabezado y
   ListTile se acotó al registro, conservando su cardinalidad requerida.
8. **Refutaciones y renderer.** Proteína0 real en día cerrado ya tenía eje
   positivo: se conservó el cálculo y añadió regresión; todo ausente se verifica
   por separado. Edición de registros antiguos fuera de90/60días actualiza el
   rango activo: [prueba](evidence/015/old-reactivity-015.log), sin otro invalidator.
   Capturas reales360dp/900dp, texto1.6, pixelRatio2; Roboto de fixtures sólo en
   harness para rótulos legibles. Sin HTML que sustituya la app.
9. **Gate final.** Fuente congelada tras R1: **44 pruebas dirigidas/referencia,
   exit0**, [log](evidence/015/gates-r1-final-015.log); **análisis limpio, exit0**,
   [log](evidence/015/analyze-r1-final-015.log). Suite completa secuencial: **675
   pruebas pasan y16 opcionales heredadas omitidas, exit0**,3min16s,
   [log](evidence/015/suite-final-015.log). `git diff --check` exit0. Sólo se
   editaron documentos después de estos gates; fuente y tests conservaron sus hashes.

Los errores iniciales de tipos (snapshot sourceVerified, enum SQL convertido de
String) y el import ambiguo Drift/matcher fueron preparación del harness/fuente,
no rojos funcionales. Tras el segundo análisis con isNull ambiguo se declaró STOP;
el coordinador autorizó únicamente importar Drift con `show Value`.
[Primer análisis](evidence/015/analyze-015.log),
[análisis tras ajustes](evidence/015/analyze-015-fixed.log). No se flexibilizaron
assertions para pasar ni se cambiaron las políticas008 o fixtures congeladas.

## Comandos reproducibles

Ejecutar desde el worktree, PowerShell; las salidas enlazadas conservan el texto
con UTF-8 y sólo quitan whitespace final de línea para versionarlo.

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/domain/progress_test.dart test/data/progress_evidence_test.dart
$env:CHARTS_015_OUT='C:/My Projects/seguimiento-015-graficas/build/qa-015-r1'
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/data/chart_evidence_test.dart test/ui/progress_charts_test.dart test/domain/progress_test.dart test/data/progress_evidence_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze --no-pub
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded
git diff --check
git status --short
```

Antes del primer gate, `flutter pub get` y `dart run build_runner build
--delete-conflicting-outputs` prepararon el worktree fresco. No hubo actualización
del SDK ni de dependencias. Los rojos contra versiones intermedias quedaron
archivados; la suite final no modifica ni reconstruye una base histórica.

## Capturas y manifest

[Manifiesto SHA-256](evidence/015/manifest-sha256.json): fuentes, tests, núcleo
compartido y artefactos de estos gates. No modifica manifests históricos.

Los tresPNG provienen del renderer de los mismos widgets con fixtures sintéticos,
no de datos personales ni de Android instalado. El banner debug de la captura
del selector es del harness. No constituye aceptación de comprensión del owner.

| Captura | SHA-256 |
|---|---|
| [Rondas](evidence/015/rondas-360-texto16.png) | `6257be0a87901a1bfe0be2e862a42cc20dd3201a699740294981d5df71818b95` |
| [Proteína](evidence/015/proteina-360-texto16.png) | `39caa300d51e2c81ececde35961bd84a9f88be9e0e4286eb4dd7faff6f5145a7` |
| [Selector](evidence/015/selector-360-texto16.png) | `88d8657034a135ca9e7bcb54552e1674aab1c9f136a41dc69b5d3ae3743e1379` |

## Cierre y límites

Implementación completa sólo para015; gates locales indicados arriba exit0.
No evaluación de velocidad Android, IA, backend o seguridad clínica; las
diferencias son descriptivas y dependen de las condiciones que se guardaron.
No se escribe historia ni se añade persistencia. Interfaz para meta histórica
probada con fixtures; adaptador009 pendiente. Publicación, upgrade del APK,
teléfono, radar y piloto corresponden al coordinador y conservan sus gates.
