# Seguimiento

App local-first (Flutter + SQLite) para registrar entrenamiento, comidas y
medidas, y generar cada semana un **informe en Markdown** que se copia y se pega
en el chat para auditar.

El informe es el producto. Todo lo demás existe para alimentarlo.

## Estado

MVP implementado: perfil, plan versionado, sesiones con contador de rondas,
fútbol, catálogo de alimentos, comidas, peso, medidas, informe Markdown y
respaldo de la base. Sin cuentas, sin backend, sin sincronización.

Detalle y pendientes: [docs/roadmap.md](docs/roadmap.md).

## Arrancar

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Requiere Flutter 3.22 / Dart 3.4 (las versiones de `drift` están fijadas a ese
rango; ver [docs/adr/0001-drift-sqlite-local.md](docs/adr/0001-drift-sqlite-local.md)).

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
  data/          Repositorios contra SQLite en memoria
  widget/        Humo de la app completa
```

Regla: si un cálculo aparece en el informe, vive en `lib/domain` y tiene prueba.

## Documentación

- [docs/context/INDEX.md](docs/context/INDEX.md) — índice de contexto
- [docs/project-map.md](docs/project-map.md) — mapa del proyecto y riesgos
- [docs/modelo-datos.md](docs/modelo-datos.md) — tablas, invariantes, migraciones
- [docs/informe.md](docs/informe.md) — qué contiene el informe y cada alerta
- [docs/auditoria-planeacion.md](docs/auditoria-planeacion.md) — cambios sobre la planeación original
- [docs/adr/](docs/adr/) — decisiones con su porqué
