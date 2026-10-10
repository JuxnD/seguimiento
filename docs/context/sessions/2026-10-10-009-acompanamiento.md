# Plan 009: acompañamiento con metas trazables (Claude)

Reparto acordado con Codex en
`seguimiento-ilustraciones/plans/2026-10-09-coordinacion-implementacion.md`.
Worktree `C:/My Projects/seguimiento-claude-009`, rama
`claude/009-acompanamiento`, desde `929f289`, con la integración 122
(`1567c9f`: 008 + `mode` + 010) mergeada. **Esquema 22.** Sin push,
publicación, teléfono ni datos reales.

| Commit | Qué |
|---|---|
| `3e5116c` | Dominio: `goal_history.dart`, `adaptive_coach.dart` (lectura de pasos) |
| `3bfc4f0` | Esquema 22: `goal_versions`, `coach_proposals`, `morning_checks.feeling`; `GoalRepository` única puerta de metas |
| `73368d0` | Hoy (tarjeta), avisos de pasos, informe/Tu progreso con la meta de cada día, "¿Cómo amaneciste?", ADR 0016 |
| `a5b2bf1` | Revisión de Codex: legado conocido desde la migración, rechazo por ventana, recuperación conocida, referencias del radar, perfil sin cambios hasta que la vigencia llega |
| `bf40054` | Merge de `1567c9f`; 21 (010) → 22 (009) |
| `8f50b95` | Fuerza del día sobre la evidencia de 008, con la causa de no subir |
| `d3fc531` | R1: recuperación sólo declarada (al despertar / `recoveryOk`), `kcalFutbol` proyectada, `updateProfile` sin futuro, referencias finitas > 0 |
| `9b1dfdc` | Paso 5: `loadReading` sin recorrido cuadrático (1.000 días) |
| `0db4308` | R1: seguimiento de propuestas de rondas, fuerza y escaleras; política v1 experimental |

## Escenarios del plan y su prueba

| Escenario | Prueba |
|---|---|
| Nuevo perfil: base 5.000, sin éxitos inventados | `goal_history_test` (inicio), `adaptive_coach_test` (faltan datos) |
| Existente con 7.500: conserva; aceptar crea vigencia futura | `migration_test` 20→22, `goal_history_test` |
| Día anterior al cambio no se reclasifica | `adaptive_coach_test`, `adaptive_coach_data_test` (informe) |
| Diez rondas + agotamiento declarado: recuperación, sin presión de caminatas | `adaptive_coach_test`, `adaptive_coach_data_test` (RPE 9, "cansado", aviso) |
| Diez rondas sin chequeo: no presume | `adaptive_coach_test` (`declaredFatigue`, recuperación desconocida) |
| Sesión limpia: propuesta concreta; fallida/partida/dudosa: no sube y dice por qué | `strength_advice_test`, `adaptive_coach_data_test` (fallo guardado) |
| Carga alta hoy / dos sesiones: la propuesta espera | `adaptive_coach_test` |
| Medidas o pasos escasos: datos insuficientes | `adaptive_coach_test`, `adaptive_coach_data_test` |
| Borrar el dato que la sostenía: se retira con razón | `adaptive_coach_data_test` |
| Pospuesta/rechazada no insiste; ventana nueva reconsidera | `adaptive_coach_test` |
| Aceptar: rige mañana, hoy igual en Hoy/avisos/informe | `goal_history_test` (antes/después de medianoche), `adaptive_coach_test` UI |
| Recuperación: `recoveryOk=false` bloquea, todo null no permite, `true` permite | `adaptive_coach_data_test` (contrafactuales SQLite) |
| Rondas/fuerza/escaleras: aceptar, hoy no, mantener, revisión | `proposal_tracking_test` |
| 1.000 días: misma lectura, 2 consultas | `coach_load_1000_days_test` |

## Evidencia

- `flutter analyze`: sin hallazgos.
- `flutter test --concurrency 2` en `0db4308` (antes del retiro de un helper
  sin uso): **733 pasan**, 17 omitidas, exit 0; analyze limpio.
- Paso 5 (Windows, 16 núcleos, flutter_tester): `loadReading` con 1.143
  registros 4,7–6,1 s → 38–63 ms; `CoachRepository.load` con 1.000 sesiones
  5.077 → 80–83 ms, 2 consultas; resultado idéntico a la 1.22.
- Rojo observado y corregido en el camino: `addColumn(feeling)` duplicada
  en bases < 17 (13 migraciones rojas → verdes con la guarda); la propuesta
  aceptada seguía visible el mismo día; `catalog_upgrade_test` de 010 armaba
  una base "20" con tablas del 22 (corregido en el merge).

## No verificado / pendiente

- Emulador y teléfono: sin probar esta rama.
- `CoachRepository.load` sigue leyendo toda la historia (2 consultas); con
  1.000 días son ~80 ms. Una ventana acotada queda para cuando haga falta.
- Umbrales de la política v1: **experimentales**, pendientes del owner (ADR 0016).
- `release121_flows_test` "legado 1.20 …" dio timeout aislado con el equipo
  cargado (sin y con cambios de 009); pasa en la suite completa. Es de Codex.
