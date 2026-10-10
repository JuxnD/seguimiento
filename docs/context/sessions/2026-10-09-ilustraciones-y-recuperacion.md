# Renovación de ilustraciones y auditoría de recuperación — 9oct2026

## Autoridad y estado

Pedido: renovar todas las ilustraciones con mockups/revisión de diseño,
forma/orientación/apoyos; auditar avisos/metas con casos sintéticos y base5000.
Feedback humano: Cuádriceps parecía torcer tobillo; Vela no era comprensible.
Fuente `C:/My Projects/seguimiento-ilustraciones`, rama
`JuxnD/ilustraciones-completas`, commitfuncional7fa8099, base7b28ef6.
Candidata1.22.0+30, esquema20. Sin push, tag, release, cambios de gateway ni
llamadas IA. No se tocó teléfono ni checkout diario. Fuente final difiere del
commitfuncional sólo en documentación y whitespace del generador/plan.

## Resultado de producto

73entradas explícitas (incluye aliases, no73ejercicios distintos), biblioteca
antes de entrenar, lados/agarre/carga y movilidad con mismo rig/JSON.
Momento grande/ampliación/giro/apoyos, movimiento iniciado por el usuario,
texto grande y ausencia declarada para ejercicios personalizados.

Se corrigieron cabeza independiente/pivote y apoyo visible de Vela/dragon,
pie/agarre Cuádriceps, tobillo Piernas en la pared, asas vsbarras transversal y
paralela, mano–equipo de fondos/remo/colgado, dedos de apoyo en flexiones,
mano libre de unilateral, manos apoyadas en inversa/pike y otros errores de
cámara, silueta, figura4 y carrera. Revisión independiente y negativa conservada.
No se llama a estos resultados certificación clínica ni aceptación del owner.

Nuevo perfil5000; existente conserva metas hasta adoptar la base en Ajustes
y Guardarperfil. Racha intensa usa historiarealhasta hoy, un moderado conocido
corta, aviso incluye fecha; sin esfuerzo conocido no se presume recuperación.
Medidas escasas/viejas no generan ajuste calórico/depases. Adaptación
longitudinal/fatiga/sueño/historialmetas sigue especificada enPlan007.

## Verificación

- Suitegeneral:612pasan,16opcionalesomitidas,134segundos; después de la última
  corrección de orientación de agarres/brazo libre,51pruebas del rig, geometría,
  apoyos y visor pasan. No atribuir la suiteanterior a una revisión sin esa
  comprobación adicional. Análisis limpio.
- Dos pruebas de render pasan: todos los keyframes73entradas, guía a escalas
  1/1.6. Galería `build/mockups/renovacion/index.html`, catálogo TSV,4montajes y
  manifiesto de hashes. Son capturas del Flutterpainterreal; no rendererHTMLalterno.
- Fixtures `pre-orientacion.json` y `pre-apoyos-finales.json`:3y2casos rojos
  respectivamente. Contactos usan equipo real y61muestras por recorrido,
  no basta comprobar largos/suelo. No se aflojaron oráculos para aceptar figuras.
- Buildrelease123,2s, Flutter3.22/Dart3.4, Java17; advertencias de la configuración
  Androidlegada siguen, no se cambió SDK/NDK/llave.
- APK `build/app/outputs/flutter-apk/app-release.apk`,72.207.746bytes,
  SHA256 `1df58a267e01753679953882c55136a81eb52c442ef32f1d7a003cade1504c62`.
  Paquete `com.juandiego.seguimiento`,1.22.0+30. Firmahistórica
  `6f839c41abf9e17634544a8ae5dff18ca64333b070ef40cd582dbdc9ac133ed7`.
  JSONdelAPK idéntico al fuente, SHA256
  `a50f9c8db7ebff2ad2a2a354341db9a95ec60fb15330673ed105af4b8513cbbc`.
- Androidsintético: sólo AVDSeguimiento_QA_119/emulator-5580, GPUhost.
  Entreno→Consultar guías→búsqueda→Vela→ampliación→momento2→apoyos/giro;
  Cuádriceps→ladoderecho; rótulos Roboto y modelo visibles. Capturas en
  `build/qa/ilustraciones/vela-native-final.png`, `vela-native-apoyos.png`,
  `quad-native-right.png` y XMLde rutas. Capturas anteriores de pino/biblioteca
  son del APKprevio; no sustituyen las nuevas.
- Actualizaciónsinuninstall conservó esquema20,32tablas/528filas, cada columna
  y valor exactos respecto de baselinepúblico1.21 y prerrebuild; flags y JSONde
  sesión en curso idénticos. ComparaciónSQLite independiente y hashes:
  `build/qa/ilustraciones/preservation-final.json`.
- Única diferencia de archivos: `profileInstalled`, caché de compilación
  AndroidX,24bytes iiqq:1/0/1791591023552/0. El timestamp concuerda con
  `dumpsys package lastUpdateTime=2026-10-10 00:10:23`; se explica y valida,
  no se oculta como dato perdido. [FuenteAndroidX](https://raw.githubusercontent.com/androidx/androidx/androidx-main/profileinstaller/profileinstaller/src/main/java/androidx/profileinstaller/ProfileVerifier.java).

Logs reproducibles en TEMP: `seguimiento-ilustraciones-suite-cierre.log`,
`seguimiento-rig-final.log`, `seguimiento-render-rig-final.log`,
`seguimiento-analyze-cierre.log`, `seguimiento-ilustraciones-build-cierre.log`,
`seguimiento-soportes-rojo-fixture.log`, `seguimiento-apoyos-finales-fixture-rojo.log`.

## Límites y gates

IntentosSwiftshader cerraron el AVD incluso en APKpúblicoantes del rig nuevo;
configuraciónhost sí permitió recorrido. No se atribuye causa global al GPU
ni se afirma compatibilidad de todos los teléfonos con este resultado.
Comprensión del owner sigue abierta. No publicado. Metas adaptativas completas
requieren la siguiente decisión de producto enPlan007; la app no se declara
ya adaptativa por haber arreglado lectura/avisos.

Repetir: `python tool/figuras3d.py`; `flutter test --concurrency 2`;
`flutter analyze`; render opcional con ILLUSTRATION_OUT e ILLUSTRATION_ALL=1;
`python tool/illustration_gallery.py`; buildapk conJava17 y mismafirma,
releer assety actualizar sólo emuladorQA, conservar/comparar baseline.
