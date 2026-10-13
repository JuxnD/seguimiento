# 044: ciclo de vida del test UI de equipo

Alcance: tests y documentación, desde el checkpoint parcial034
`8eb5eed91c1248fe5afac02d0bab5cbf67a02ea8`. No modifica aplicación, SQLite,
esquema, dosis, assets ni datos reales. El árbol `lib` se conserva exactamente:
`398d3f506e5e1ea654c06860626656de89711ec4`.

## Diagnóstico causal

1. El tap original se ejecutaba dentro de FakeAsync. La escritura real de
   `LocalFlags` continuaba en vuelo y la lectura devolvía null. No es evidencia
   de que el switch de producción no persista.
2. `addTearDown` llegaba después de las invariantes de Flutter. Al cancelar las
   suscripciones, Drift2.21 crea un Timer.run y espera sus completers al cerrar.
   Mover solamente `dispose` y `await db.close` a runAsync tampoco basta:
   callbacks nacidos en FakeAsync necesitan que ese reloj avance.
3. El probe c2b125 inició el mismo cierre real sin esperarlo dentro de runAsync,
   alternó pump y turnos de IO real hasta completar (máximo2s). SQLite cerró y
   el test terminó FAIL1 por el null original. Quedó visible también el error
   secundario de borrar el directorio mientras seguía abierta aquella escritura.
4. Cambiar únicamente el disparo a un tap real dentro de runAsync, esperando
   el valor físico con deadline2s, produjo PASS1 terminal. No se llama al
   callback directamente ni se sustituyen LocalFlags/Drift/Riverpod.

El fixture portable conserva defaultsNULL/switchfalse, interacción accesible,
persistencia true/false, valor visual, nivel3, una PlanVersion y ausencia de
excepciones. La limpieza ocurre en finally, antes de las invariantes del test.
El helper espera el cierre real y falla si no completa; no cancela ni ignora
los temporizadores del framework. El editor manual comparte ese mismo ciclo
de vida; sus aserciones de cancelación, SQLite y ausencia de eventos permanecen.

## Evidencia

En [044-evidence](044-evidence):
- `034-native-original-failure.txt` y `034-native-original-source.json`:
  evidencia histórica de034, procedencia conservada, no ejecución044.
- `lifecycle-only-red.txt`: error de compilación del logger, no rojo funcional.
- `lifecycle-fixed-tap-original.txt` y `lifecycle-own-cancel.json`: cierre
  bloqueado; cancelación acotada de los dos procesos propios identificados.
- `dual-zone-original-tap.txt`: FAIL1 terminal con cierre completado y null
  original; recibo210918950.
- `native-trigger-green.txt`: PASS1/0skip/exit0, recibo211517531; fixture
  SHA256134D1B5C3A367E9AB59FC280B3B0E0E1AF94015AA04278725C4B5D09B33ED7C7.
- `portable-three-ui.txt`: PASS2/FAIL1 terminal; el editor encontraba el texto
  pero no podía tocarlo después del scroll. Se conserva hitTestable estricto.
- `manual-editor-centered.txt`: centrar el mismo botón con ensureVisible y
  completar el scroll produce PASS1/0skip/exit0, recibo212443845. Persisten
  las comprobaciones de borrador modificado, SQLite intacto y cero eventos.
- `portable-analyze.txt`: info inicial de Future intencionalmente no esperado;
  `manual-editor-analyze.txt`: análisis del fixture final, cero incidencias,
  recibo212500460. `unawaited` no sustituye el criterio de cierre completado.

Reproducción: Flutter3.22, `flutter test --no-pub --concurrency=1 --timeout=90s`
sobre `test/ui/plan034_equipment_and_criteria_test.dart`, mediante el wrapper
de lease coordinado. Generated59980 copiado solo tras igualdad de
database.dart/tables.dart/pubspec.lock con034; package_config relativo al WT.

- `final-three-ui.txt`: ejecución conjunta final3PASS/0FAIL/0skip, exit0,
  recibo212613469. Mismo fixture que el análisis0:
  SHA2568F9CFE97B27D35006D459166A1CF611ABCB5E48311D73AD8B646C4BF9C1DB252.

Estado: implementación test-only y validación dirigida completas; 3 UI finales
sin excepciones ni temporizadores pendientes. Ningún análisis global de la
aplicación se atribuye a este frente test-only.
Revisión root e incorporación a034/037 pendientes. Sin APK, publicación ni
aceptación operativa/humana implícita. La limpieza de cuatro temporales
compilados autorizada por root fue rechazada por revisión automática antes de
ejecutarse; ningún temporal fue borrado por044.
