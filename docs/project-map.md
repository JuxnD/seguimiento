# Project map: Seguimiento

## 0. Preflight
- Repositorio y rama: `main`, remoto `origin` en GitHub (`JuxnD/seguimiento`),
  releases por etiqueta `vX.Y.Z`.
- Estado: MVP y fases 1–6 del [roadmap](roadmap.md) implementados; última
  auditoría en [auditoria-2026-09-23.md](auditoria-2026-09-23.md).
- Instrucciones aplicables: contrato operativo del usuario (comunicación en
  español, evidencia antes de declarar cierre, contexto durable en `docs/`).
- Stack y entrypoints: Flutter 3.22 / Dart 3.4 · `lib/main.dart` → `SeguimientoApp`
  → `HomeShell` (5 pestañas) · SQLite local vía `drift`.
- Build/test: `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs`,
  `flutter analyze`, `flutter test`, `flutter run`.
- Seguridad/acceso: sin cuentas ni secretos en la app. La única salida a red es
  una consulta GET a la API pública de GitHub para ver si hay versión nueva,
  **automática al abrir la app** (aviso en Hoy) y a pedido en Ajustes; no
  envía datos del usuario. Todos los datos son
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
| Contrato de experiencia | Tema oscuro propio sobre Material 3 | Flutter 3.22 | Extender | `lib/ui/theme.dart` (paleta y `AppColors`), `lib/ui/session_style.dart`; ver [diseno.md](diseno.md) |
| Referente de capacidades | Planeación del usuario (módulos 1–8) | Entregada en esta sesión | Reusar, con las desviaciones de la auditoría | `docs/auditoria-planeacion.md` |
| Referente informativo | Estructura del informe de la planeación | Entregada en esta sesión | Extender (alertas de calidad del dato, detalle de comidas, vueltas) | `docs/informe.md`, `test/domain/report_test.dart` |
| Verdad de dominio y datos | Modelo de datos de la planeación | Entregada en esta sesión | Adaptar (catálogo de ejercicios, macros congelados, marcas de ronda) | `docs/modelo-datos.md` |

- Desviaciones materiales: ADR 0002, 0003, 0004, 0005.
- Huecos de cobertura: el informe no menciona las fotos (decisión: se miran
  en el teléfono); el editor del plan no edita sostén ni RIR.

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
- Migraciones: `schemaVersion` 6; procedimiento en [modelo-datos.md](modelo-datos.md).
- Estado fuera de la base: `flags.json` (permisos pedidos, fechas de copia y
  consulta) y `sesion-en-curso.json` (cronómetro a medias), ambos en el
  directorio de soporte de la app; `respaldos/` con las copias automáticas.
- Entrega: `flutter build apk` / `flutter run`; CI en GitHub Actions
  (`.github/workflows/ci.yml` y `release.yml`).
- Respaldo: exportación manual con `VACUUM INTO`, copia automática semanal
  (4 últimas) y restauración validada desde Ajustes
  ([actualizaciones.md](actualizaciones.md)).
- Entrega de versiones: etiqueta `vX.Y.Z` → GitHub Actions analiza, prueba,
  firma y publica el APK en una release pública; la app avisa.
- Observabilidad: ninguna (sin telemetría, por diseño).

## 5. Risks and gates
| Riesgo | Consecuencia | Gate | Evidencia | Estado |
|---|---|---|---|---|
| Informe con números mal calculados | Decisiones de entrenamiento equivocadas | Pruebas de dominio sobre semana, neto, estimación, promedios, alertas y semana en curso | `test/domain/*` | Cubierto |
| Mapeo base → informe incorrecto | El informe no refleja lo registrado | Prueba de extremo a extremo desde SQLite | `test/data/repositories_test.dart` (incluye informe completo y récord) | Cubierto |
| Editar el catálogo reescribe el historial | Semanas viejas cambian de valores | Macros copiados + prueba que edita y borra el alimento | ADR 0002 · prueba "macros congelados" | Cubierto |
| Mezclar cm y pulgadas | Serie de medidas inservible | Guardado único en cm + conversión en el formulario | ADR 0004 · prueba de unidades | Cubierto |
| Pérdida del dispositivo | Se pierde todo el historial | Exportar y poder restaurar | Botones en Ajustes · `test/data/restore_test.dart` (5 pruebas) | Cubierto |
| Restaurar un archivo inválido | Base corrupta, historial perdido | Validación previa, borrado de `-wal`/`-shm` y rollback | `test/data/restore_test.dart` | Cubierto |
| Cambiar la llave de firma | Android no deja actualizar; hay que desinstalar y se pierden los datos | Una sola llave: la debug del equipo, subida como secret (24 sep 2026) | ADR 0006 · `docs/actualizaciones.md` ("La llave de las releases") | CI firma y publica desde la 1.6.1 con la huella de siempre (verificado). **Pendiente**: respaldar `debug.keystore` fuera del equipo |
| Nadie se acuerda de respaldar | Una restauración llega tarde | Copia automática semanal restaurable desde Ajustes | `test/data/auto_backup_test.dart` | Cubierto para errores; **abierto** para pérdida del teléfono (solo exportar a mano lo protege) |
| App cerrada durante el circuito | Se pierde la sesión en curso | Foto del cronómetro en cada paso y "Retomar" | `test/domain/active_session_test.dart`, `test/data/active_session_store_test.dart` | Cubierto en código; **pendiente** verificar en el teléfono matando la app |
| UI sin pruebas automáticas | Una regresión de pantalla no se detecta sola | Pruebas de pantalla sobre base en memoria; CI compila el APK | `test/ui/app_smoke_test.dart` (4), `ci.yml` | Parcial: no cubren permisos, notificaciones, cámara ni el ancho de teléfono |
| Fin de descanso tarde en Android 14+ | El aviso con pantalla apagada llega minutos después | Comprobar alarma exacta, caer a inexacta y ofrecer el permiso | `notification_service.dart` | Cubierto en código; **pendiente** verificar en el teléfono |
| Receivers de notificaciones perdidos | Las alarmas disparan y no aparece nada | Comprobación del manifiesto en CI | `ci.yml` | Cubierto |
| Fotos fuera del respaldo | Perder el teléfono pierde las fotos | — | — | Abierto (roadmap v2) |
| Actualización de Flutter/Dart | Las versiones fijadas bloquean el upgrade; `fl_chart` 0.70+ y `share_plus` 11+ no compilan con 3.22 aunque `pub` los resuelva | Plan en la auditoría (sección "Salto de SDK") | ADR 0001 · comentarios en `pubspec.yaml` | Abierto, conocido |

## 6. Decisions and plan
- ADRs: [0001](adr/0001-drift-sqlite-local.md), [0002](adr/0002-snapshot-macros-en-comidas.md),
  [0003](adr/0003-versiones-de-plan-inmutables.md), [0004](adr/0004-medidas-siempre-en-cm.md),
  [0005](adr/0005-contador-de-rondas-con-marcas.md),
  [0006](adr/0006-actualizaciones-por-github-releases.md).
- Rebanadas entregadas: dominio + pruebas → esquema + repositorios → UI por
  módulo → informe → documentación.
- Exclusiones explícitas: nube, cuentas, análisis dentro de la app.

## 7. Verification and closure
- Evidencia de implementación (23 sep 2026, rama `mejoras/auditoria-2026-09`):
  `flutter analyze` → "No issues found" con lints estrictos; `flutter test` →
  176 pruebas verdes (dominio, repositorios, siembra, restauración, migraciones
  1 → 6, copias automáticas, sesión en curso y 4 de pantalla);
  `flutter build apk --debug` → APK construido. CI repite todo y compila.
- Las pruebas de pantalla no cubren permisos, notificaciones, cámara ni el
  aspecto a ancho de teléfono: eso se verifica en el dispositivo.
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
