# 023 — Cierre012 de presencia de metas

Implementación local completa del código autorizado. Worktree
`C:/My Projects/seguimiento-012-presencia`, rama `JuxnD/012-presencia`, BASE
`53524400994788d13ac94906fa5093d560c6f97a` (011+022 integradas).
Schema23/Flutter3.22/Dart3.4/Java17 conservados; pubspec1.22+30 intacto.
Versión1.23+31, empaquetado y publicación los prepara el coordinador por separado.
No edición de AppEntry/restore_access/database_host/corrections (frente024),
schema, lock, SDK, firma, rama diaria, dispositivo o backend.

## Contrato y API

- `goalReferenceOn(history,metric,day,fallback)` y `kcalGoalReferenceOn` son
  resolvers puros en goal_history. Historia cargada sin vigencia: desconocido;
  known-null: sin meta. Sólo history=null permite compatibilidad legacy
  explícita. Providers loading/error no pasan a ese fallback.
- API011 `ReportInput.referenceOn/kcalReferenceOn` delega sin cambiar firma;
  `goalOn` comparte presencia. `GoalSpan.fromReferences` sirve a GoalSpan.over
  y al span011 del resumen. Calendario sábado/domingo existente; fútbolnull
  conocido hereda semanal, sin inventarla cuando también esnull/desconocida.
- Dashboard obtiene referencias por fecha y progreso nullable; anillos
  neutrales conservan el dato crudo, sin cumplimiento0% inventado. Meals y
  Totals leen fecha seleccionada/draft; acceso Definir metas mantiene el draft.
- `GoalRepository.setPersonalGoals(selections,{profileChanges,now})` registra
  decisiones expresas, incluida ausencia nutricional/piso, en una transacción.
  No elimina pasos obligatorios ni toca refs del radar. Misma cifra que el
  placeholder se acepta si antes era known-null. ProjectDue conserva las
  proyecciones internas compatibles y las versiones pasadas.
- Ajustes espera la historia antes de montar campos, reacciona a stream/
  generación de base/día y distingue número/ausencia/desconocido. Vaciar una
  meta positiva no la quita silenciosamente: exige acción y confirmación.
  Guardar altura no acepta metas; decisión lee el reloj al guardar/confirmar.
- Avisos reciben metas nullable según fecha; no presionan proteína/calorías/
  pasos sin referencia. Avisos custom/actividad y guardsetup022 conservados.
  Coach conserva política009 y recuperación, pero no ofrece comparación/meta
  de pasos si la referencia cargada falta.
- ReportStats/alerts/Builder leen piso por fecha; ningún piso2000 inventado.
  El texto real del informe llega a reportQuestionSources para el NUEVO envío.
  No se editaron repositorio/body/hash/snapshots de conversaciones históricas.
- Nuevo perfil con plan propio no recibe tarjeta v3.1 automática: Explorar
  plantillas abre descripción y activador existente, que confirma cifras y
  calendario antes de crear plan/metas. Rutina y oferta legacy permanecen.

## Evidencia y precisión de oráculos

INDEX/contexto/plan/skills leídos; deusctx coincide con BASE y WT completo.
El primer preflight después de crear WT siguió por error en integración:
creó su carpeta build/qa/023 y pub-get ignorados; status/lock de integración
se comprobaron intactos. No se eliminó esa evidencia ni cambió producto.
Las operaciones posteriores usan el WT012 explícito.

Baseline inicial: montaje fallido porque build_runner no había completado
database.g.dart; log conservado, no rojo de producto. Tras completion
exit0/41salidas/67acciones, baseline reparado **35pasan/exit0**.

Rojo funcional **2controles pasan/3assertions fallan** contra BASE:
confirmSetup real «Más adelante» aún entrega130/2400 en Dashboard; report/payload
real marca2días bajo2.000 y alerta ficticia; loadedhistoria vacía produce
segmento130 en lugar de1día desconocido. Green-core:5pasan.

Pase dirigido siguiente:95pasan/1fallo. Fixture ReminderScheduler consultaba
28sept pero sólo conocía metas desde siembra/fecha real. Se declara usuario
sintético con vigencia1sept mediante helper existente; expected130g/43g
consumidos/87gpendientes permanece. No se restauró fallback indebido en código.

Pase acotado de setters/histórico:18pasan/1fallo de rótulo en caso NUEVO. El
fixture borraba mínimo pero mantenía máximo known-null: el resultado correcto
era «mínimo histórica no registrada, máximo sin meta», distinto del genérico
esperado. Se precisó ese expected a ambos estados; cantidades2desconocidos,
0sinmeta, macros31 y cero pasos observado/no registro siguen iguales. No se
atribuye ese fallo de fixture a un defecto del producto.

**Mínimo final:90pasan/exit0**, incluidos 6SQLite de alta/historia/guardado/quitar/
piso/rollback/dato0,3dominio de presencia/calendario, fixtures de avisos,
goal_history, coach_reminder_sync, report_goal_history y report. El test cruza
Nutrition/ReportRepository/Stats/Builder/fuente realIA, no un helper con texto
ficticio. El falloSQLite se induce en INSERT real y revierte altura/decisiones.

Análisis inicial de desarrollo incluyó formato incidental; se restauró
whitespace de bloques con tokens idénticos al BASE, verificando secuencia de
tokens sin cambios. Análisis final1 encontró2llaves y1prefer_single_quotes;
se corrigieron sólo estilo y delimitadorSQL (mismo textoSQL).
**Análisis final2 exit0/sinissues** sobre fuente final. Sin ignores/exclusions.
Diff-check0;17archivos fuente reales,1fixture modificado y2tests nuevos.

## Pruebas aplazadas por instrucción explícita del owner

El owner pidió publicar y probar él en teléfono, dejando verificación ampliada
para después si era el único pendiente. Root cambió el gate de entrega a
código completo + mínimos/análisis/diff; no añadir full/capturas/mutantes.
No se ejecutó full nueva ni se inició. Tampoco capturas360/1.6/2, pruebasUI
ampliadas de cancelar/quitar/medianoche/restore/plantilla, ni mutantes extra.
Las pantallas se compilan en análisis; sus flujos nuevos no se presentan como
operacionalmente/humanamente aceptados. Los testsUI existentes del pase95
incluyen alta022, pero no sustituyen aquellos escenarios023 aplazados.

## Reproducción y hashes

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/data/goal_presence_readers_test.dart test/domain/goal_presence_test.dart test/data/reminder_scheduler_test.dart test/domain/reminders_test.dart test/data/goal_history_test.dart test/data/coach_reminder_sync_test.dart test/domain/report_goal_history_test.dart test/domain/report_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze --no-pub
git diff --check
git status --short
```

[Manifiesto17fuentes/GitOID y13rawlogs](evidence/023/manifest.json).
Los logs originales están en build/qa/023; gzip versionado conserva exactamente
sus bytes (descompresión comparada), sin normalización de finales de línea.

| Log original | SHA-256 raw |
|---|---|
| red-presence.log | 4046e9c2f13f1efdc6ea0c923ba8ced436bc1c170c70a240849e616a8e26f970 |
| minimum-final.log | 88a6a8b410ceb8de63b2d33220f6bacf53a80ceca50b7722f3151d3ee14b15df |
| analyze-final2.log | 7fbe2276e76eb82c47187524d0870efa674a6df1f2cf1dc79e35b0583021bf0b |

## Estados de cierre

- Implementación del código023 completa, aislada y reviewable.
- Validación local mínima observada SQLite/dominio/payload/sink; UIampliada
  aplazada. No redIA, datos reales, teléfono, APK o ejecución Android.
- Cierre formal/operativo de publicación corresponde al coordinador: integrar
  023+024, CI/artefacto exacto/firma/versionCode31 y pruebas autorizadas restantes.
  Este recibo no acredita piloto comercial/clínico, backend ni aceptación humana.
