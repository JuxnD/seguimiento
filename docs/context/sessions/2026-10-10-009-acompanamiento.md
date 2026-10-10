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

## Evidencia

- `flutter analyze`: sin hallazgos.
- `flutter test --concurrency 2` en `8f50b95`: **718 pasan**, 17 omitidas, exit 0.
- Rojo observado y corregido en el camino: `addColumn(feeling)` duplicada
  en bases < 17 (13 migraciones rojas → verdes con la guarda); la propuesta
  aceptada seguía visible el mismo día; `catalog_upgrade_test` de 010 armaba
  una base "20" con tablas del 22 (corregido en el merge).

## No verificado / pendiente

- Emulador y teléfono: sin probar esta rama.
- Paso 5 del plan (fixture de 1.000 días y conteo de consultas): no hecho.
  `CoachRepository.load` sigue leyendo toda la historia, como la 1.22.
- Propuestas persistentes para fuerza/escaleras: la fuerza es lectura del
  día; las escaleras siguen con su propia confirmación (§19.10).
- Umbrales nuevos de la política v1 (ADR 0016) pendientes de confirmar con el owner.
