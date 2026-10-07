# Fixture genuina del candidato de esquema19

Fuente: `afaaf86e1718d49acaa86e13a08515c7ea699421`, 1.21.0+29 sin las
correcciones del plan007. Se ejecutó su `AppDatabase`,
`FitnessTestRepository.save` y los avisos en checkout temporal separado,
no construyendo19 por eliminación de columnas de20.

SHA-256 SQLite:
`45cea7fcdb225e0d24671335d6932b0def99cf80a4e11bf66752e81965830d46`.
Esquema19 genuino, 31 tablas, datos exclusivamente sintéticos:

- Sesión902 de core, serie903, tiempos de trabajo/calentar/enfriar/descansar.
- Tres resultados Test1: pullup8; pino35s con técnica dudosa; flexión a una
  mano izquierda3, sin inventar lado derecho. Su sesión903 en modo test
  guarda3600s, como hacía el repositorio original.
- Dos estados de escalera con peldaño/fecha/lumbar conservados.
- Sesión906 y partido907 importados; el partido tiene0min por confirmar.
- Perfil estable y avisos completos.

`schema19-synthetic-manifest.json` contiene un oráculo literal independiente
(Python/SQLite sólo lectura), huellas de fuente/lock e inventario.
El test compara todas las columnas originales de las31tablas después de
migrar, reabrir, exportar ZIP, restaurar y volver a abrir. Se permite una
única diferencia del dato19: `sessions.id=903.total_sec`,3600→0. No se permite
perder contextos, fechas, flags importados, resultados, lados o tiempos de
la sesión regular. Las columnas nuevas20 se comprueban en sus pruebas propias.

El test quedó rojo contra el código19 original porque aún no normalizaba el
wallclock del test; debe pasar contra la fuente20 corregida. Sus mutantes
detectan borrar un resultado, borrar el tiempo regular y cambiar la fecha de
la escalera, en su tabla exacta. No es evidencia de ejecución sobre un teléfono.

## Reproducción

Crear checkout temporal separado enafaaf86. Usar Flutter3.22/Dart3.4,
`flutter pub get` y `dart run build_runner build --delete-conflicting-outputs`.
Copiar `tool/schema19_121_migration_generate_test.dart` a `tool/` de esa fuente.
Ejecutar allí, en PowerShell:

```powershell
$env:SCHEMA19_OUTPUT='C:\ruta\fixture19-nueva.sqlite'
flutter test --no-pub tool/schema19_121_migration_generate_test.dart --reporter expanded
```

El generador exige esquema19, rehúsa sobrescribir y reabre los datos. Desde
la app actual se revisa el artefacto congelado y se prueba la migración:

```powershell
python tool/schema19_121_migration_manifest.py test/fixtures/schema19-synthetic.sqlite C:\ruta\fuente-121-congelada
flutter test --no-pub test/data/schema19_121_migration_test.dart --reporter expanded
```

No hay IA remota ni licencia en este fixture. La preservación de las
conversaciones de1.20 se verifica con la fixture18 complementaria.
