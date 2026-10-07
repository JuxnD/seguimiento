# Fixture congelada de 1.20.0 / esquema 18

Datos exclusivamente ficticios. No contiene licencias, credenciales, fotos ni
datos del teléfono. Se creó con `AppDatabase` y los repositorios de IA y avisos
de la fuente **1.20.0 genuina**, commit
`410da05d341d8ea88915fe8a197d3df6eee54283`. Los cambios desde el tag publicado
`c7972c7e505a342033a1762db73d85dd032f6555` son sólo documentación y planes;
`lib/`, `pubspec.yaml` y `pubspec.lock` son iguales.

SHA-256 SQLite:
`6bfe3abcf1295bbc109ee597c61ca39a7262f394163e8347d8cfa4b56279827a`.
`PRAGMA user_version = 18`; 29 tablas de producto. No se obtiene eliminando
columnas o tablas de la app actual.

Incluye una sesión/serie (IDs 902/903), comida/plato (904/905), peso (906),
ejercicio (901), perfil estable y once avisos. El aviso de sesión está
personalizado: desactivado, 14:15. Contiene dos conversaciones validadas:
informe con dos fuentes y dos turnos completos, guía con variante local
de Dominadas/carga/prona y un turno; seis mensajes en total.

El oráculo JSON se escribió con literales independientes en Python, sin el
serializador de Dart. Comprueba IDs, datos, citas, JSON/hash exactos de fuentes
y guía. El test además captura todas las columnas de las 29 tablas del archivo
congelado y exige su preservación exacta en la migración, reapertura en disco,
exportación ZIP, restauración y segunda reapertura. Los campos nuevos de la
app actual no forman parte de esta comparación de datos originales.

El fixture no ejecuta la siembra completa de plan/alimentos: una apertura
nativa puede añadir esas filas válidamente. En esa prueba se deben verificar
los IDs y campos del manifiesto, distinguiendo filas añadidas de pérdidas.

## Reproducción

Usar Flutter 3.22.0 / Dart 3.4.0. Crear checkout temporal separado en el commit
indicado, ejecutar `flutter pub get` y
`dart run build_runner build --delete-conflicting-outputs` allí. Copiar
`tool/schema18_121_migration_generate_test.dart` al mismo directorio `tool/`
del checkout congelado. Nunca ejecutar este generador contra la app nueva.

En PowerShell, desde esa fuente congelada:

```powershell
$env:SCHEMA18_OUTPUT='C:\ruta\nueva-fixture.sqlite'
flutter test --no-pub tool/schema18_121_migration_generate_test.dart --reporter expanded
```

El generador exige esquema18 y rechaza sobrescribir un archivo existente.
Reabrirá el archivo para comprobar conversaciones/guía. Desde la app actual:

```powershell
python tool/schema18_121_migration_manifest.py test/fixtures/schema18-synthetic.sqlite C:\ruta\fuente-120-congelada
flutter test --no-pub test/data/schema18_121_migration_test.dart --reporter expanded
```

El script Python abre SQLite sólo en lectura; genera el manifiesto y exige el
commit18 exacto. La prueba utiliza el archivo versionado, no regenera sus datos.
La huella identifica este artefacto congelado; otra reconstrucción equivalente
puede producir páginas SQLite distintas y no autoriza cambiar el pin sin revisión.

Controles negativos: cambiar fuentes, quitar citas, borrar una respuesta.
Cada mutante vive en una copia temporal y debe fallar en la tabla exacta,
además del rechazo de lectura de IA cuando el contexto/cita queda inválido.
