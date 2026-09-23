# Seguimiento

App local-first (Flutter + SQLite) para registrar entrenamiento, comidas y
medidas, y generar cada semana un **informe en Markdown** que se copia y se pega
en el chat para auditar.

El informe es el producto. Todo lo demás existe para alimentarlo.

## Estado

Tema oscuro con acento naranja. MVP implementado: perfil, plan versionado
(sembrado en la primera apertura), sesiones con [cronómetro guiado por el
plan](docs/cronometro.md),
fútbol, catálogo de alimentos, comidas, peso, medidas, informe Markdown,
respaldo **y restauración** de la base, y aviso de nuevas versiones por GitHub
Releases. Sin cuentas, sin backend, sin sincronización de datos.

Detalle y pendientes: [docs/roadmap.md](docs/roadmap.md).

## Arrancar

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Requiere Flutter 3.22 / Dart 3.4. Por esa versión hay dependencias fijadas a
propósito: `drift`/`drift_dev` (`>=2.19.2 <2.23.0`) y `share_plus` (`^10.1.4`);
las versiones actuales exigen Dart ≥ 3.5 o Flutter ≥ 3.27. Ver
[docs/adr/0001-drift-sqlite-local.md](docs/adr/0001-drift-sqlite-local.md).

Android está configurado para Java 21 (Gradle 8.7, AGP 8.3.2, Kotlin 1.9.22,
`minSdk` 21 por `sqlite3`). Al actualizar Flutter, revisar esas cuatro cosas
junto con las dependencias fijadas.

Tras cambiar `lib/data/tables.dart` o `lib/data/database.dart` hay que volver a
correr `build_runner`.

## Verificar

```bash
flutter analyze
flutter test
```

Las pruebas de base de datos corren contra SQLite del sistema
(`test/support/sqlite_host.dart`), no contra la librería que se empaqueta en el
teléfono.

No hay pruebas de widget: las que abrían la app con la base real se colgaban
(drift dentro de `flutter_test`), así que la interfaz se verifica en el
dispositivo. El resto — dominio, repositorios, siembra, restauración y
migraciones — sí está cubierto.

## Publicar una versión

```bash
git tag v1.1.0 && git push origin v1.1.0
```

CI analiza, prueba, firma el APK y lo publica en la release; la app instalada lo
detecta. Requisitos (llave de firma y secrets) en
[docs/actualizaciones.md](docs/actualizaciones.md).

## Estructura

```
lib/
  domain/        Lógica pura, sin Flutter ni base de datos (fechas, macros,
                 matemática de sesión, alertas, generador del informe)
  data/          Tablas drift, base de datos y repositorios
  app/           Providers de Riverpod y shell de navegación
  features/      Una carpeta por módulo de producto (home, training, meals,
                 body, plan, report, settings)
  ui/            Widgets compartidos
docs/            Mapa del proyecto, modelo de datos, informe, ADRs
test/
  domain/        Reglas de negocio (sin base de datos)
  data/          Repositorios, siembra, restauración y migraciones
  support/       Utilidades de prueba
```

Regla: si un cálculo aparece en el informe, vive en `lib/domain` y tiene prueba.

## Documentación

- [docs/context/INDEX.md](docs/context/INDEX.md) — índice de contexto
- [docs/project-map.md](docs/project-map.md) — mapa del proyecto y riesgos
- [docs/modelo-datos.md](docs/modelo-datos.md) — tablas, invariantes, migraciones
- [docs/actualizaciones.md](docs/actualizaciones.md) — respaldo, restauración, firma y cómo publicar una versión
- [docs/informe.md](docs/informe.md) — qué contiene el informe y cada alerta
- Para ver cómo queda el informe: `dart run tool/sample_report.dart > docs/ejemplo-informe.md` (ese archivo no se versiona)
- [docs/auditoria-planeacion.md](docs/auditoria-planeacion.md) — cambios sobre la planeación original
- [docs/adr/](docs/adr/) — decisiones con su porqué
