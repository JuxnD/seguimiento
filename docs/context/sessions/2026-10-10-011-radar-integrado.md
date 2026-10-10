# Recibo011 — radar real y referencias históricas

Estado: STOPPED_PACKAGING_SCOPE. Implementación local completa y gates de comportamiento exit0; portabilidad del recibo pendiente de coordinación.

## Identidad, autoridad y límites

- Worktree `C:/My Projects/seguimiento-011-radar`, rama `JuxnD/011-graficas-radar`.
- Base aprobada `f34ab7c9fd4107ffc728e2b9bfdd2153e00315a4`; esquema22.
- Dependencias008/009/015/018/019 aprobadas. Flutter3.22/Dart3.4/Java17,
  schema, pubspec/lock, core018/008, timer019 y snapshot784 conservados.
- Sólo SQLite/filesystem ficticios y renderer Flutter de tests. Sin API/modelos,
  datos reales, servidor, APK, AVD/telefono, push/merge/deploy. Launch/cleanup020
  rechazados por policy no se intentaron de nuevo.
- Skills reutilizadas: mantener contexto, navegar fuente con deusctx,
  dueño del producto, Impeccable clarify/craft-floor, anti-falso-verde y E2E.
  No se repitió loader/producto ni se creó otra identidad visual.
- Graph preflight de esta WT: provenance/index f34,5697nodes/24447edges, sin
  deriva inicial. Relaciones anteriores stale156 se contrastaron en Git; no se
  usaron para sustituir la fuente verificada ni depurar otro servicio.

## Pasos y gates

1. Base/rama/rutas/contexto completo; pub get offline y build_runner de artefactos
   ignorados, exit0. Baseline de siete archivos existentes:67 pasan/0skips.
2. Rojo funcional de Summary real con SQLite/ProviderScope: esperaba1
   PersonalRadarWidget, recibió0. Compiló y montó; no se contó error de import.
   `red-integration.log` conserva Expected/Actual y base f34. El hash inicial del
   archivo de test no se archivó en ese momento; el test después se amplió, y
   no se atribuye su hash final al rojo inicial.
3. Lectura SQLite→DTO018→núcleo: todos los tests, Cindy en lotes128, sets+nombres
   juntos y orden de inserción. Fixture300 equivale a recorrido completo y
   mantiene inicio/actual; memoria O(observaciones+sets), no constante ni SLA.
4. Referencias/watchHistory, restore de ZIP→SQLite→databaseGeneration, editar/
   borrar fila antigua, save/cancel y rutas reales. Cindy usa protección pendiente
   y timer/checklist; TestResults fecha registrada al editar, elección explícita
   y calendario previsto de fuente. No SQL nuevo al abrir/cancelar.
5. Gráficas de proteína y pasos usan metas por vigencia, con fin abierto null.
   Ausente no es0; sin referencia no es fallo. Kcal usa calendario existente
   sábado/domingo, propia/heredada/unknown.130→160 muestra1/2 días y promedio140
   separado; kcal mixta conserva promedio sin anillo con denominador falso.
6.93 dirigidos exit0 antes del último borde;10 UI después del selector grande
   exit0. Raster0188 pasan; mutante sin tramos fail exactamente
   «Tramo naranja entre vértices.» con punto100% preservado. SHA original y
   restaurado `2787648f8a748f067f37d3b9d69a9ca703aea2b9a750c3e8a4e72b11416af2fe`.
   Painter original intacto; no mutante warmup2DB ni fcdb montaje.
7. Full previo:848 pasan/17 optativos, exit0. Se preserva snapshot/source hash;
   NO acredita la modificación de reloj posterior.
8. Relectura halló fecha capturada al abrir diálogo: prueba de medianoche ROJA
   Expected11oct/Actual10oct para effectiveFrom y acceptedAt. Ahora el reloj se
   lee al confirmar, repositorio/reloj antes del await; guarda sólo setReference.
   Origen de GoalVersion traducido a fuente humana, ID/vigencia preservados.
  20 dirigidos nuevos pasan;11 UI finales/capturas exit0. Full final:849 pasan/17 optativos, exit0 sobre fuente congelada final.
   Análisis último source exit0; diffcheck0. Source digest final
   `ec96584df2c18b737847de1177c69c158eb832ca2e3c62d4ce6625db6074138c`.

Comandos (desde WT, SDK absoluto fijo):

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' pub get --offline
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/dart.bat' run build_runner build --delete-conflicting-outputs
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/domain/progress_metrics_test.dart test/ui/personal_radar_test.dart test/ui/v3_timers_test.dart test/data/goal_history_test.dart test/data/chart_evidence_test.dart test/ui/release121_flows_test.dart test/domain/period_summary_test.dart test/ui/progress_charts_test.dart test/data/personal_radar_repository_test.dart test/ui/personal_radar_integration_test.dart test/domain/progress_nutrition_reference_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze --no-pub
 git diff --check
```

## Matriz y evidencia

| Caso | Oráculo |
| --- | --- |
| Sin registros/dos/seis |SQL real y UI real; no registros/raw sin ref; huecos abiertos, no área falsa. Capturas iniciales sin scroll y detalle. |
| Fechas/bilateral/calidad |primera/última aptas por fecha, futuro excluido, inválido no normalizado, partial/doubt no sustituye apta, fecha antigua visible; una fecha no delta y base0 no% relativo. |
| Referencias |null/legado/inválida sin coords; cambiada ambos contornos usan común;>100raw preservado y dibujo limitado; save/cancel/restore y confirmación real tras medianoche. |
| Cindy |completa apta; cortada120/1201legado/30min/Tabata/receta parcial/variante/lastre/dudas/importada/estimada/DDFFSS no marca20; raw/flags conservados. |
| Reactividad |editar/borrar evidencia enero fuera90d, referencia y restore por DBgeneration sin invalidar manualmente provider en test. |
| Proteína/kcal/pasos |130→160, unknown, null explícito; kcalweekday/weekend propia/heredada/ausente; observado0 distinto de sin registro, sin meta fin de semana. |
| Rutas |Test3 abre/cancela sin resultados/sesión; Cindy abre Amrap real/checklist y cancela sin SQL; pendiente cancelada preservada. |
| Renderer |360dp1/1.6/2 sin overflow; selector ancho en texto grande, inicial sin scroll; source018 raster puntos y tramos + mutante. |

El manifiesto final en `011-evidence/manifest.json` vincula archivos, fuente,
logs y capturas ficticias. Cada PNG tiene JSON de valores/fechas/raw/calidad y
referencias. Fixtures viven en `test/support/radar_sql_fixture.dart`,
`radar_fixture.dart` y tests de integración. ZIP sintético de referencias se
conserva ignorado en `build/qa/011/refs-roundtrip.zip`; verifica continuidad
local, no un backup del teléfono ni la baseline pública020.

## Diagnósticos y residuos

- Errores de preparación no fueron rojo funcional: import Drift faltaba
  BooleanExpressionOperators; ternario nullable requería paréntesis; import de
  formatLong se corrigió a dates.dart. Un helper de limpieza de formato falló
  leyendo path Windows con backslashes en Git (no escribió); relectura con
  as_posix corrigió únicamente formato incidental.
- UI descubrió controller disposed durante transición y grid fijo desbordando
  texto1.6/2: State del diálogo y altura natural corregidos, sin aflojar oráculos.
  Recarga reemplazaba selección del eje: skipLoadingOnReload la conserva.
- Un fixture omitía la vigencia automática del seed10oct; se delimitaron sus
  versiones para afirmar fin abierto, sin modificar goalUntil. Otra expectativa
  confundía2.400 formateado y un cierre automático≥1800kcal: fixture/oráculo
  alineados con fuentes existentes, no otra fórmula para hacer verde.
- Ahem de AppBar/segmentos era del harness: Roboto sólo QA, no tema producto.
  Inspección PNG mostró palabra Semana partida a texto2: selector nativo ancho
  autorizado. Contornos sí estaban pintados; no causa de pintura inventada.
- Drift advierte múltiples conexiones al restore: warning conservado, no
  silenciado; DB real restaurada y valores releídos. No latencia Android medida.
- goalOn/lectores globales de presencia conservan compatibilidad:012/022 revisan
  ese alcance sobre esta entrega. No se declara toda la app libre de defaults.
- Aceptación humana (entender evolución/evidencia/faltante), integración raíz,
  alta022, gate012 y APK/Android/publicación siguen pendientes.011 local no es
  cierre del piloto ni validación clínica.


## Cierre de fuente

El commit que incorpora este recibo entrega los mismos bytes Dart del manifiesto
`source-frozen.json`; el hash de código/tests no cambió durante la full final.
Los17 skips son capturas optativas de otros frentes y la interop PHP sin variables
de entorno; ninguno corresponde a los criterios011. Análisis final sin avisos,
diffcheck0. Evidencia copiada a `011-evidence`;13 PNG ficticios con JSON (8 de
integración,5 standalone018). Full849/17 supera el snapshot848/17 por el nuevo
caso de medianoche, no se añadió una tolerancia ni un nuevo cálculo.

Fuente final recuperable por el commit de este recibo y hashes declarados.
El revisor repetirá criterios sobre ese SHA antes de integrar. La aceptación de
comprensión del owner y validación nativa/API/APK no se deducen de estos gates.


## Costura pendiente al verificar el commit

Git ignora23 logs del manifiesto; están presentes en esta WT y sus hashes
coinciden, pero el commit inicial sólo rastrea30 archivos del directorio de53.
Además `git check-attr text eol` es unspecified y Git avisó LF→CRLF para cinco
JSON de018 y el nuevo diálogo. La full y los hashes corresponden a estos bytes
físicos; un checkout/cherry-pick fresco puede convertirlos. No se declara el
manifiesto portable ni ese paso cerrado aún. El cambio lógico/Dart está congelado.

Se solicitó al coordinador ampliación mínima `.gitattributes` (-text sólo para
`docs/context/sessions/011-evidence/**` y el diálogo nuevo) y agregar explícitos
logs ficticios. Alternativa: cápsula ZIP binaria y hashes canónicos LF. No se
editó `.gitattributes` ni otra fuente fuera del alcance mientras falta decisión.
Este STOP es de empaque/autoridad de archivo, no un fallo de849/17 ni native.
