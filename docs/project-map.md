# Project map: Seguimiento

## 0. Preflight
- Repositorio y rama: repositorio local nuevo (`git init`), rama `main`, sin remoto.
- Estado del worktree: proyecto creado desde cero en esta sesión.
- Instrucciones aplicables: contrato operativo del usuario (comunicación en
  español, evidencia antes de declarar cierre, contexto durable en `docs/`).
- Stack y entrypoints: Flutter 3.22 / Dart 3.4 · `lib/main.dart` → `SeguimientoApp`
  → `HomeShell` (5 pestañas) · SQLite local vía `drift`.
- Build/test: `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`,
  `flutter analyze`, `flutter test`, `flutter run`.
- Seguridad/acceso: sin cuentas ni secretos en la app. La única salida a red es
  una consulta GET a la API pública de GitHub para ver si hay versión nueva; no
  envía nada. Todos los datos son
  personales y quedan en el dispositivo; el único egreso es lo que el usuario
  comparte a mano (informe o respaldo).

## 1. Product truth
- Usuario y trabajo: una sola persona registra entrenamiento, comida y medidas
  en menos de 30 s por evento, sin depender del chat.
- Resultado: un informe semanal estructurado, copiable, que permite auditar
  qué se planeó, qué se hizo y qué se comió.
- Objetivos: registro rápido; datos con unidades y condiciones explícitas;
  historial estable; informe reproducible.
- No objetivos: nube, cuentas, base de alimentos externa, análisis dentro de la
  app.
- Fuentes autoritativas: la planeación entregada por el usuario (transcrita en
  este repositorio como requisitos) y [auditoria-planeacion.md](auditoria-planeacion.md)
  con las desviaciones aceptadas.
- Listo cuando: se puede registrar una semana completa en la app y generar el
  informe con las secciones y alertas de [informe.md](informe.md).

### Reference contract
| Rol | Autoridad | Alcance/versión | Decisión | Evidencia/estado |
|---|---|---|---|---|
| Core compartido | No existe: proyecto nuevo, sin repositorios hermanos ni design system previo | — | Línea base nueva | Se buscó en el equipo de trabajo actual (carpeta vacía) y no hay código previo de esta app |
| Contrato de experiencia | Material 3 por defecto de Flutter | Flutter 3.22 | Reusar | Tema único en `lib/app/app.dart` |
| Referente de capacidades | Planeación del usuario (módulos 1–8) | Entregada en esta sesión | Reusar, con las desviaciones de la auditoría | `docs/auditoria-planeacion.md` |
| Referente informativo | Estructura del informe de la planeación | Entregada en esta sesión | Extender (alertas de calidad del dato, detalle de comidas, vueltas) | `docs/informe.md`, `test/domain/report_test.dart` |
| Verdad de dominio y datos | Modelo de datos de la planeación | Entregada en esta sesión | Adaptar (catálogo de ejercicios, macros congelados, marcas de ronda) | `docs/modelo-datos.md` |

- Desviaciones materiales: ADR 0002, 0003, 0004, 0005.
- Huecos de cobertura: fotos de progreso y recordatorios quedaron en v2
  (ver [roadmap.md](roadmap.md)).

## 2. Domain map
- Actor único; sin roles ni permisos.
- Glosario e invariantes: [context/INDEX.md](context/INDEX.md) y
  [modelo-datos.md](modelo-datos.md).
- Ciclo de vida del plan: borrador → versión inmutable vigente desde una fecha.
- Ciclo de vida de una sesión: contador (opcional) → borrador prellenado →
  sesión guardada con series y vueltas → insumo del informe.

## 3. Architecture map
- Contexto: app móvil sin servicios externos. Entrada: el usuario. Salida: el
  informe en Markdown y el archivo de respaldo, ambos compartidos a mano.
- Contenedores: un único proceso Flutter + archivo SQLite en el directorio de
  documentos de la app.
- Componentes críticos: `lib/domain` (cálculo del informe y alertas, puro),
  `lib/data/repositories` (consultas y mapeo), `lib/features` (UI).
- Flujo de datos: UI → repositorio → drift → SQLite; para el informe,
  `ReportRepository.load` → `ReportInput` → `buildReport` → Markdown.
- Frontera de confianza: el dispositivo. Nada sale sin acción explícita.

## 4. Operation and delivery
- Configuración: ninguna; los umbrales viven en la tabla `profiles`.
- Build/lint/test: ver README. Generación de código tras tocar tablas.
- Migraciones: `schemaVersion` 1; procedimiento en [modelo-datos.md](modelo-datos.md).
- Entrega: `flutter build apk` / `flutter run`; CI en GitHub Actions
  (`.github/workflows/ci.yml` y `release.yml`).
- Respaldo: exportación manual con `VACUUM INTO` y restauración validada desde
  Ajustes ([actualizaciones.md](actualizaciones.md)).
- Entrega de versiones: etiqueta `vX.Y.Z` → GitHub Actions analiza, prueba,
  firma y publica el APK en una release pública; la app avisa.
- Observabilidad: ninguna (sin telemetría, por diseño).

## 5. Risks and gates
| Riesgo | Consecuencia | Gate | Evidencia | Estado |
|---|---|---|---|---|
| Informe con números mal calculados | Decisiones de entrenamiento equivocadas | Pruebas de dominio sobre semana, neto, estimación, promedios y alertas | `test/domain/*` (17 pruebas) | Cubierto |
| Mapeo base → informe incorrecto | El informe no refleja lo registrado | Prueba de extremo a extremo desde SQLite | `test/data/repositories_test.dart` (7 pruebas, incluye informe completo) | Cubierto |
| Editar el catálogo reescribe el historial | Semanas viejas cambian de valores | Macros copiados + prueba que edita y borra el alimento | ADR 0002 · prueba "macros congelados" | Cubierto |
| Mezclar cm y pulgadas | Serie de medidas inservible | Guardado único en cm + conversión en el formulario | ADR 0004 · prueba de unidades | Cubierto |
| Pérdida del dispositivo | Se pierde todo el historial | Exportar y poder restaurar | Botones en Ajustes · `test/data/restore_test.dart` (5 pruebas) | Cubierto |
| Restaurar un archivo inválido | Base corrupta, historial perdido | Validación previa, borrado de `-wal`/`-shm` y rollback | `test/data/restore_test.dart` | Cubierto |
| Cambiar la llave de firma | Android no deja actualizar; hay que desinstalar y se pierden los datos | Llave única en secrets, documentada | ADR 0006 · `docs/actualizaciones.md` | Abierto, depende de operar bien |
| Nadie se acuerda de respaldar | Una restauración llega tarde | Respaldo automático periódico | — | Abierto (roadmap) |
| App cerrada durante el circuito | Se pierde la sesión en curso | Persistir el estado del contador | — | Abierto (roadmap) |
| UI sin pruebas automáticas en Windows | Una regresión de pantalla no se detecta sola | `test/widget/app_smoke_test.dart` | Saltado en Windows: `flutter_tester` se cuelga al cargar `winsqlite3.dll`. Corre en macOS/Linux o con una `sqlite3.dll` propia | Abierto |
| Actualización de Flutter/Dart | Las versiones fijadas de drift bloquean el upgrade | Revisar `pubspec.yaml` al actualizar | ADR 0001 | Abierto, conocido |

## 6. Decisions and plan
- ADRs: [0001](adr/0001-drift-sqlite-local.md), [0002](adr/0002-snapshot-macros-en-comidas.md),
  [0003](adr/0003-versiones-de-plan-inmutables.md), [0004](adr/0004-medidas-siempre-en-cm.md),
  [0005](adr/0005-contador-de-rondas-con-marcas.md),
  [0006](adr/0006-actualizaciones-por-github-releases.md).
- Rebanadas entregadas: dominio + pruebas → esquema + repositorios → UI por
  módulo → informe → documentación.
- Exclusiones explícitas: fotos, gráficas, recordatorios, nube.

## 7. Verification and closure
- Evidencia de implementación (22 sep 2026): `flutter analyze` → "No issues
  found"; `flutter test` → 24 pruebas verdes y 3 saltadas (las de UI, en
  Windows); `flutter build apk --debug` → `app-debug.apk` construido.
- Evidencia operacional: **pendiente**. Nadie ha registrado todavía una semana
  real en un teléfono; el flujo de contador, permisos y compartir solo se han
  verificado por compilación y pruebas, no en uso.
- Aceptación formal: pendiente del usuario, tras una semana de uso real.

## Unknowns
- ¿La estimación de rondas con media histórica se parece al conteo real? Se
  sabrá comparando sesiones estimadas contra contadas.
- ¿Hacen falta etiquetas de contexto en vez de texto libre? Se decide tras
  leer dos o tres informes reales.
- ¿Qué tan seguido se pierde el registro por cerrar la app en el circuito? Si
  ocurre, sube la prioridad de persistir el contador.
