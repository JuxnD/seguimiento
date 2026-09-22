# ADR 0001 — Drift (SQLite) como base local, con versiones fijadas

Fecha: 2026-09-22 · Estado: aceptada

## Contexto

La app es local-first: sin backend ni cuentas. El informe necesita consultas
por rango de fechas, agregados por día y uniones (sesiones con series, comidas
con items). El entorno de desarrollo corre Flutter 3.22 / Dart 3.4.

## Decisión

`drift` sobre SQLite (`sqlite3_flutter_libs`), con `drift`/`drift_dev` fijados
al rango `>=2.19.2 <2.23.0`.

## Alternativas

- **isar**: mantenimiento incierto (la versión 3 lleva tiempo sin publicar
  estables y la 4 nunca salió); además obliga a resolver a mano lo que aquí es
  una consulta SQL.
- **Ficheros JSON**: simple al principio, caro en cuanto el informe cruza
  varias colecciones por rango de fechas.
- **drift sin fijar versión**: las versiones actuales exigen Dart ≥ 3.5, y
  además chocan con `share_plus` por el paquete `web`.

## Consecuencias

- Consultas y migraciones tipadas; el informe se arma con SQL, no en memoria.
- Hay paso de generación de código (`build_runner`) tras tocar las tablas.
- **Al actualizar Flutter/Dart, soltar las versiones fijadas** en `pubspec.yaml`
  y regenerar. Lo mismo aplica a `share_plus`, fijado en `^10.1.4` porque la 12
  requiere un Flutter más nuevo y rompe el build de Android.
- Las pruebas de host necesitan una SQLite del sistema
  (`test/support/sqlite_host.dart`).
