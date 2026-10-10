# Paridad histórica portable — cierre de CI

Worktree aislado `C:/My Projects/seguimiento-024-ci-probe`, rama
`JuxnD/024-ci-probe`, base exacta `604af8257751ecab1cf477a6794d53ced2274925`.
Sólo prueba, referencia congelada y recibo; producción, recursos de la app,
SDK, dependencias, versión, esquema, firma y datos permanecen intactos.

Rojo de CI38089569310: «Carga abrazada al pecho» esperaba digest `0bbc3aee…`
y recibió `59965…`.008 descargó el log completo y esta revisión leyó ese fallo;
el original se conserva comprimido con hash. Este checkout no ejecutó Linux.
La causa de la
diferencia de digest entre hosts no se declara confirmada.

## Referencia y criterio

El test anterior sigue pasando como control en Windows (1/1). Su JSON golden
original queda byte por byte sin cambios. Se sustituye el digest producido en
otro host por comparación **numérica exacta** del código anterior y actual,
ejecutados en el mismo host: 73 nombres históricos, 61 muestras por nombre,
todos los joints2D y puntos3D. Sin redondeo ni tolerancia. Los seis ejercicios
nuevos no tienen baseline929 y mantienen sus pruebas existentes separadas.

Fuente real extraída con `git show` de
`929f2897c73a86760cc73ce228a89f3aaa3789a8`:

- `lib/ui/exercise_figure_3d.dart`: SHA256
  `0fd1b6b9dcd4d284f8d7c36ddeef4a3a08a527a5e0b92c54425289f6e56bd7fd`.
- `assets/tecnica/figuras3d.json`: SHA256
  `a50f9c8db7ebff2ad2a2a354341db9a95ec60fb15330673ed105af4b8513cbbc`.
- Única transformación: un import relativo de `domain/search.dart` pasa al
  import package correspondiente. El test revierte ese import y verifica el
  hash original; el import compartido tiene el mismo blob Git
  `03a2e19b18e50fd5b354512454bea895c6fa7efc` en929 y604.
- El manifiesto fija origen, hashes, transformación y61 muestras. Se conservan
  assertions de sourceSha y sourceAssetSha256 del golden original.
- Un atributo local al directorio de la referencia fija LF para ese archivo
  Dart; así Git no cambia sus bytes al recuperar el fixture en Windows. No
  cambia la política de finales de línea del proyecto ni código de producción.

## Ejecución y límites

Flutter3.22.0/Dart3.4, Windows, puboffline0 y generación Drift0. Comandos:

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/ui/illustration_legacy_parity_test.dart
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze --no-pub
git diff --check
```

Control anterior1/1; comparación portable1/1; análisis0; diff-check0.
Único control negativo autorizado: en la extracción de coordenadas **actuales
del test**, sumar1 a X. Sale1 con assertion específica «coordenadas3D exactas»;
no se mutó lib. Se restauró el test byte por byte, SHA256
`28c7486d6acaf0737682617070240cfe6c4cbcd7b9b8e9f117e68731e3f599bc`,
igual al código verde y analizado. No se adaptó el expected hacia la geometría
actual ni se regeneró el golden. Los logs crudos comprimidos, hashes y control
están en [manifiesto](parity-portable-evidence/manifest.json).

CI Linux final todavía debe ejecutar esta prueba. No se corrió otra suite
completa, UI, APK, emulador, teléfono ni backend. El probeSQL024 quedó
**NO EJECUTADO** por instrucción posterior de Root; su hang local sigue sin
causa confirmada. Este cambio no afirma aceptación visual humana ni publicación.
