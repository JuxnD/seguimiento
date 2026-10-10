# Handoff 9 oct: sueño, sesión técnica y calentamiento (Claude)

Pedido del owner en el chat de Claude: "prosigue con lo que puedas implementar
sin tocar el trabajo de la otra sesión". Coordinado con Codex en
`seguimiento-ilustraciones/plans/2026-10-09-coordinacion-implementacion.md`.

Worktree `C:/My Projects/seguimiento-claude-c01`, rama
`claude/handoff-sueno-tecnica-calentamiento`, desde `d2d3070` (1.22.0+30,
esquema 20) con C01 integrado. Sin push, publicación, teléfono ni datos reales.
**Sin migración**: el esquema sigue en 20.

| Commit | Qué |
|---|---|
| `a0521c8`, `d8a9ac7` (rama `claude/c01-combos`) | C01: Actualizar no cambia la base de un alimento por g/ml/unidad; combo sospechoso pregunta *Corregir* / *Registrar igual* |
| `0e24fb3` | §16.19 sueño: 9,5 y 10 h, "Otro" (10,2 · 10:11 · 10 h 11 min), en Hoy y en el registro de la mañana |
| `4db0eeb` | §16.21 sesión técnica (RIR 4, `mode = 'tecnica'`), ofrecida en descarga, víspera de test o de pruebas, o con plan B; retomar sesiones fuera del plan (plan B también) |
| `e8a0a19` | §16.23 calentamiento guiado + tarjeta "Antes del intento" en el test ([ADR 0015](../../adr/0015-calentamiento-guiado.md)) |
| `0927814` | Merge del ajuste de C01 |

## Decisiones

- Sueño: sin Health Connect (`SleepSessionRecord` espera §16.17, permisos de Innova).
- Sesión técnica: cuenta como intensa sólo si el RPE anotado es ≥ 7. La
  etiqueta no prueba que fue suave (punto de la reconciliación de Codex).
- Víspera: se mira el v3.1 de **mañana**; el domingo 11 oct todavía no hay v3.1
  y aun así es la víspera del Test 1.
- Calentamiento: pasos marcados a mano; el reloj de un paso lo marca sólo si
  se arrancó. `warmupSec` sigue siendo el tiempo real; lo hecho o saltado va
  en la nota de la sesión. Ver ADR 0015 para el porqué sin columna.

## Evidencia (rojo → verde)

- C01: `test/data/free_entry_replace_test.dart` rojo con la semántica vieja
  (2 fallos); `test/ui/meal_form_free_replace_test.dart` rojo con el diálogo
  viejo (encuentra "Actualizar"); `test/ui/suspicious_combo_test.dart`.
- Sueño: `test/domain/sleep_entry_test.dart`, `test/ui/sleep_other_test.dart`
  (10:11 → 10,18 h guardado y mostrado "10 h 11 min").
- Técnica: `test/data/technique_session_data_test.dart` (víspera del 11 oct,
  13 oct, descarga 17 nov, 10 dic; no el 15 ni el 20 oct);
  `test/ui/technique_resume_test.dart` rojo sin el arreglo (sale "El día del
  plan de esa sesión ya no existe") y verde con él (mismo índice, `planDayId`
  −1, `mode` y guion idénticos).
- Calentamiento: `test/domain/warmup_test.dart` (7),
  `test/ui/guided_warmup_test.dart` (reloj por paso, aproximación arma 2 min,
  foto con las marcas, "a medias" con 2 de 7, nota guardada, saltar sin
  diálogo, foto vieja sin campos), `test/ui/pre_attempt_card_test.dart`.
  `test/ui/guided_session_test.dart` actualizado: el diálogo es "Calentamiento
  a medias" (cuenta pasos, no tiempo).
- `flutter analyze`: sin hallazgos. `flutter test --concurrency 2` en
  `0927814`: **639 pasan**, 16 opcionales omitidas, exit 0.
- En `d8a9ac7` (sólo C01) la suite dio 1 fallo en
  `backup_archive_test.dart` ("tamaños declarados excesivos…") con 21
  procesos Dart concurrentes; pasa aislada dos veces y en la suite integrada.
  Se registra como inestable bajo carga, no atribuido a C01.

## No verificado / pendiente

- No probado en emulador ni teléfono: falta APK de esta rama.
- Figuras de 6 ejercicios de calentamiento (ADR 0015): frente de ilustraciones.
- Checklist en la Cindy de prueba y en las pruebas del viernes (temporizadores).
