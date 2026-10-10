# Recibo014 · figuras del calentamiento

Fecha:9→10oct2026. Worktree `C:/My Projects/seguimiento-014-calentamiento`,
rama `JuxnD/014-figuras-calentamiento`, base929f2897c73a86760cc73ce228a89f3aaa3789a8.
Estado: implementación independiente completa; revisión visual del coordinator, integración y comprensión humana
y entrega enAPK pendientes. Este recibo pertenece a esta fuente, no a la app
instalada del owner. Se cumplieron los cinco pasos del plan014 ampliado por root.

## Resultado y alcance

Seis recetas específicas de calentamiento,79entradas (no79ejercicios distintos),
JSON generado, contratos de hombros y arco opt-in y aclaraciones de Círculos
(con brazos relajados) y pase de banda (rango cómodo, no luxación).
Reutiliza rig/painter/visor/TechniqueContent. No cambia dosis, política por dolor,
base, metas, SDK, logo, backend, cronómetro ni esquema. No instaló, publicó,
construyóAPK, llamóIA, hizo push ni operó datos personales.

73objetos del catálogo previo son idénticos aGit929 y73hashes de coordenadas
2D/3D son idénticos en61muestras al rig histórico real. Los nuevos campos
son opcionales y conservan default0/false; no migran datos.

## Rojo, STOP y nuevas decisiones explícitas

1. Cobertura producción roja: seis guías ausentes, por nombres provenientes de
   movilidad/activación/buildWarmup. No se aceptó fallback genérico.
2. Testescapular rojo: cuello fijo como raíz de brazos impedía subida del torso
   con manos en barra y codos rectos. Root autorizó `shoulderOffset` local;
   mínimo cambio entre Python/JSON/parser/copias/solver2D/lift3D/interpolación.
3. Primer gategeneral:56pasan/1falla, mano de Balanceos no llegaba a la pared;
   se corrigió el cálculo según ancho de hombro real4,5u, sin cambiar el guard.
4. Segundo gate:16pasan/1falla, dotpie0,39757 supera0,35. STOP comunicado.
   Diagnóstico de sólo lectura: máximo0,4999447 a15/60; extremos correctos,
   cuerda de reach3 hacía flexión artificial entre55° y115°.
5. Root reabrió estrategia con `keepReachRadius` sólo en pierna móvil.
   Nueva prueba roja: radio28 se volvía24,2487 a mitad; pasó tras el campo opt-in.
   Antipodales usan plano explícito; radio0/no finito y pares inconsistentes
   fallan cerrado. No se cambió umbral0,35 ni IK/contacto.
6. Primer gate de la estrategia nueva:16pasan/1falla, deriva0,115431u del apoyo.
   La punta móvil tocaba suelo cerca del centro y la guarda levantaba el cuerpo.
   Spike sobre copia delJSON: radio27,5 da deriva0,0 y máximo dot0,191529.
   Root autorizó holgura y rodilla relajada acorde con guía, sólo pierna móvil.
   La prueba genérica radio28 permanece. No es un valor clínico certificado.
7. Gate final:62pasan. Relectura final del rig6pasan, apoyos8pasan con ambos
   lados de Balanceos y61muestras. Cuatro mutantes deJSON fallan exit1:
   omitirradiopt-in, omitir hombros, quitar grip y pieinvertido. No se cuenta
   una salida esperada de harness como validación funcional del mutante.
8. Analyze falló primero16hallazgos (incluyendo diagnóstico ignorado escrito
   como.dart y lints de fixtures), luego limpio. Diagnósticos se conservan
   como texto y fixes de tipado/estilo mantienen assertions. No se relajólint.

Salidas exactas normalizadas sólo en espacios/encoding: [evidencia](evidence/014/README.md).
Hashes de fuentes en [JSON](2026-10-10-014-calentamiento.json).

## Verificación reproducible

SDK `C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat`; Dart3.4 del mismoSDK.
Si worktree fresco carece de.g.dart: `dart run build_runner build --delete-conflicting-outputs`
(sólo ignorados; deps, lock y esquema no cambiaron).

```text
python tool/figuras3d.py
flutter test test/ui/illustration_warmup_rig_test.dart test/ui/illustration_geometry_test.dart test/ui/illustration_supports_test.dart test/ui/illustration_legacy_parity_test.dart test/ui/illustration_catalog_coverage_test.dart test/ui/exercise_figure_3d_test.dart test/ui/exercise_figure_3d_audit_test.dart --reporter expanded
flutter analyze
git diff --check
```

PowerShell para capturas:
```powershell
$env:ILLUSTRATION_OUT='build/mockups/calentamiento'
$env:ILLUSTRATION_ALL='1'
$env:ILLUSTRATION_NAMES='Círculos de hombros;Balanceos de pierna;Retracciones escapulares;Flexiones escapulares;Puente de glúteo;Dislocaciones con banda'
& C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat test test/ui/illustration_mockup_render_test.dart --reporter expanded
python tool/warmup_mockup_montage.py
```

Captura2/2 pasa; recaptura de hojas1/1 tras declararRoboto en etiqueta de
propuesta del mockup.65PNG reales:28claves+12intermedios+1espejo+24hojas.
Miniaturas y montajes derivan exclusivamente de esosPNG, sin otro renderer.
Revisados los seis recorridos completos, apoyos y ambas hojas con texto1,6.

Regeneración repetida misma huellaJSON:
f9a42b6fe6c4bc300ea044e37a9c74e25b28da801677efff1c169a62aad8c0b2.
Fuentes y límites de referencia: [diseño](../../design/calentamiento-014.md).

## Gates pendientes

- Comprensión del owner y aceptación técnica humana; maniquí no sustituye
  vídeo/profesional ni certifica seguridad de un ejercicio ante molestias.
- Integración con otros frentes/Claude y suite completa sobre esa integración.
- APK exacto, asset empacado, firma, actualización con datos sintéticos,
  Android real y teléfono del owner. Nada de eso se prueba con estosPNG.
- Compatibilidad/piloto del plan012 sigue pendiente; esta entrega no lo activa.

Estado local debe quedar limpio tras el commit. Fuentecommit se comunica al
coordinator; éste registra planes/README, aceptación y eventual integración.


Control final: la última relectura de analyze detectó2warnings
`strict_raw_type` en casts del nuevo fixture, después del pase anterior.
Se detuvo antes de commit y se informó a root. No se presentan como verde final.
Corrección propuesta: tipos explícitos deMap en los dos casts, sin cambiar
assertions. Evidencia `analyze-closure.txt`; espera autorización de reapertura.


Reapertura explícita autorizada por root: se cambiaron únicamente los dos
casts a `Map<String,Object?>`; cinco casos del fixture pasan y analyze informa
«No issues found» (11,2s). `git diff --check` pasa. Ninguna geometría ni assertion
cambió. Se preserva el STOP anterior y su evidencia. Revisión visual del
coordinator todavía pendiente, al igual que aceptación humana del owner.


## Revisión visual R1 · basee35a72c

Root leyó los seis recorridos y autorizó tres ajustes acotados antes de aprobar:

- Retracciones: diagnóstico61muestras midió tobillo/suelo2u y suela/suelo0,75u.
  Figura+barra elevadas4u, sin otros ángulos: suela mínima4,75u, captura lateral
  real y control de perfil completo de zapato, no sólo agarre o centro de joint.
- Círculos: anotación existente y captions numeradas Arriba/ Atrás/ Abajo/ Frente,
  conservando anatomía; sin flechas que se inviertan al girar cámara.
- Viewer: labelheredado conellipsis dentroRow falló selección de última letra
  a1,6 y2,0. Ahora Wraprefluye sin bajar fuente ni ocultar controles; ambos
  estados conservan semantics y son accionables. Root amplió únicamente ese
  viewer y prueba de legibilidad correspondiente.

Rojo real R1:8pasan/3fallan (gap y2truncamientos). Primer intento verde:
45pasan/2fallan por cierre tardío delSemanticsHandle del fixture; visual y
semantics pasaban. Dispose se llevó a finally, sin cambiar assertions.
Gatefinal R1:47pasan. Analyze tuvo una observación de braces delnuevo test,
corregida manteniendoassertion; luego «No issues found». No se tocó el rig.
Generación determinista y73objetos/hashgeometrías originales idénticos.

2pruebas de captura pasan,65recapturas de catálogo/hojas+1lateral diagnóstico.
Recorridos R1 y CTAcompleta inspeccionados; R2 del coordinator y comprensión
humana pendientes. La cifra f9a42... previa corresponde a basee35a,
JSON actual R1 SHA256: 1ee6e443f42f91fa3096af7a3006de374f45334ca25400e924e5e5376c3d992a.

Salidas `r1-*.txt/json`, diagnóstico y capturas están vinculados en diseño.
La recreación opcional de la captura antigua desdeGit fue rechazada por
revisión automática del comando; no se ejecutó ni se atribuye una imagen nueva
al antes. Se conserva la medición anterior real y la basee35a para reproducirla.
No impide comprobar el gapactual con el artefacto real.
