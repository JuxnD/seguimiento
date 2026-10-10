# Plan 007: recuperar avisos veraces y adoptar la base de 5.000 pasos

- Estado: TODO; prioridad P1; esfuerzo M; riesgo MED (perfil persistido y criterios de consejo).
- Preparado contra `7b28ef6fc84b240a592069b6221b7da31e858e5c`, 9-oct-2026.
- Repositorio: `C:/My Projects/seguimiento-ilustraciones`, Flutter 3.22/Dart 3.4, SQLite/Drift, Riverpod.
- Owner solicita auditar y acompañar progreso; solicita bajar su base de pasos de 7.500 a 5.000. Decisión del responsable: nueva instalación 5000; perfil existente se cambia mediante CTA explícita, nunca por abrir la pantalla. No aumentar automáticamente cargas, kcal ni metas futuras.
- Esta auditoría sólo escribe `plans/`; implementación corresponde al ejecutor. No publicar ni tocar el teléfono/datos reales para las pruebas.

## Evidencia y causa

`lib/data/repositories/dashboard_repository.dart:198–205` consulta sesiones/partidos desde `date−7`; `lib/domain/recovery.dart:169` arranca en ayer cuando hoy no tiene nada intenso, aunque sí haya sesión moderada. Una racha real de 20 días se muestra como 7 antes de entrenar cada mañana: reproducido con `[7,7,7,7]` en cuatro fechas diferentes. Una sesión moderada hoy conserva indebidamente la racha 7 terminada ayer. No se ha leído la base del teléfono: ésta explica una causa posible comprobada, no prueba cuáles fueron sus RPE reales.

`lib/features/home/home_screen.dart:447–462` recalcula Plan B, pero siempre promete “vuelve en 48 h”. No existe fecha de vencimiento ni reevaluación asociada a ese texto. `LoadReading.reason` (`recovery.dart:157–162`) siempre promete recuperar para “el viernes”, incluso si hoy es viernes o sábado.

Descartado: no hay literal 7 días constante ni congelación general de fecha; `TodayNotifier` refresca medianoche/foreground (`providers.dart:221–245`, `app.dart:81–87`), y guardar chequeo invalida dashboard (`morning_check_screen.dart:84`). Las 63 pruebas de recuperación/pasos/hábitos/escaleras/progreso existentes pasan, pero no cubren los casos anteriores.

`profiles.stepsTarget` tiene default 7500 (`tables.dart:36`), se añadió en migración esquema 9 (`database.dart:147`), Ajustes guarda el valor personal (`settings_screen.dart:363`). Cambiar sólo el default deja el perfil actual en 7500.

Carga no filtra `imported`: `db.trainingSessions` sólo excluye movilidad (`database.dart:255`), y dashboard excluye `mode=test` después de consultar. El importador guarda duración 0/esfuerzo nulo (`history_import.dart:85–112`): esos registros cuentan como actividad pero no generan intensidad ni carga positiva. Su historial acaba 21 septiembre, fuera de la ventana actual: no explica por sí solo los 7 días de octubre. Sin RPE, `LoadItem.load` estima 6 y `intense` esfalse (`recovery.dart:125–126`); no usar ausencia de RPE como prueba de recuperación.

`twoWeekRule` (`habits.dart:136`) no valida `WeekAverage.count`: dos semanas con 1 pesaje cada una producen consejo de kcal. `_waistStill` (`habits.dart:187–193`) ignora `today`: medidas de enero combinadas con peso de octubre producen “cintura no se mueve en 3 semanas, −150 kcal/+2000 pasos”. Ambos reproducidos con código real y datos ficticios.

## Alcance y límites

Modificar sólo: `lib/domain/recovery.dart`, `lib/domain/steps.dart`, `lib/domain/habits.dart`, `lib/data/repositories/dashboard_repository.dart`, `lib/data/tables.dart`, `lib/data/database.dart`, defaults coherentes de `lib/domain/report/report_input.dart` y `lib/domain/reminders.dart`, `lib/features/home/home_screen.dart`, `lib/features/settings/settings_screen.dart`; pruebas correspondientes en `test/domain`, `test/data` y `test/ui`. Si se necesita generar `database.g.dart`, seguir build_runner del repositorio sin cambiar dependencias. Documentar `docs/context/INDEX.md`, `docs/plan-v 3-1.md`, `docs/modelo-datos.md`, `docs/roadmap.md`, ADR breve y recibo de sesión.

No tocar las ilustraciones concurrentes, firma, gateway IA, Health Connect, permisos, fotos, perfiles del teléfono, nutrición guardada, planes versionados ni guion congelado de sesión. Conservar metas personales distintas de 7500 y todos los otros campos del perfil. No aumentar pasos/cargas/kcal automáticamente.

## Ejecución ordenada

1. **Escribir pruebas que fallen primero con el código anterior.** Modelo: `test/domain/recovery_test.dart`, `habits_test.dart`, `test/data/migration_test.dart`, `test/ui/experience_test.dart`. Capturar cada fallo exacto sin relajar criterios. Utilizar simulaciones de varias fechas, no sólo un getter.
2. **Contar la racha real y distinguir hoy de ayer.** Consultar sólo días≤hoy y suficiente historia para llegar al primer hueco real; preferir fechas distintas de actividad intensa mediante consulta compacta, no cargar todos los detalles ni llamar al plan por día. Separar carga reciente de contador de racha. Si hay una sesión conocida moderada hoy, cortar la racha de días intensos; si faltó RPE, declarar incertidumbre sin asegurar recuperación. Mantener hoy vacío como pendiente: informa la racha hasta ayer, no inventa descanso completado.
3. **Cambiar la comunicación de recuperación.** Aportar causa, rango/fecha de evidencia y fecha de próxima reevaluación, distinguiendo “hasta ayer” de “incluye hoy”. Sustituir promesa fija “vuelve en 48 h” por reevaluación diaria explícita; una reevaluación no garantiza que puedan volver las piernas. Si se muestra una fecha calculada de referencia, usar días de calendario y aclarar que se revisan nuevos registros; los datos actuales no contienen hora exacta de último esfuerzo. Quitar “para el viernes” fijo. Cero duplicados de aviso por reconstrucción de UI; actividad nueva debe cambiar evidencia/mensaje.
4. **Adoptar 5000 con control humano.** Nueva instalación 5000; perfiles existentes no cambian automáticamente. Mostrar CTA “Usar 5.000 pasos como base” en Ajustes cuando la meta actual sea 7500, explicando el cambio; guardar sólo `stepsTarget` al aceptar. Cancelar, abrir o reabrir pantalla no escribe. Preserva metas distintas (ej.6500/10000), demás valores, sesiones, comidas y pasos. Verificar upgrade desde esquema 20 y desde esquema 9, reabrir y restaurar base sintética: conserva valor anterior hasta aceptar CTA. Defaults de informe/avisos 5000; Hoy, caminatas y recordatorios leen el perfil, no número literal. No rehacer guion ya iniciado.
5. **Rehusar consejo con señales insuficientes o viejas.** Exigir mínimo 3 pesajes en ayunas por semana usada en `twoWeekRule`; si falta cobertura, pedir registros. Filtrar medidas futuras y exigir abdomen reciente dentro de una ventana explicitada (recomendación de política inicial≤14 días, documentada), con comparación de≥21 días. Si cintura es vieja o falta comparación, explicar que falta evidencia y evitar consejo de bajar kcal/subir pasos. No modificar kcal del perfil ni valores registrados.
6. **Separar base, meta de hoy y futura propuesta.** En esta entrega implementar recuperación veraz/base 5000 y claridad de consejo, sin inventar adaptación clínica. Documentar como siguiente paso una política local versionada de metas con evidencia, cansancio percibido, sueño, RPE, molestias y cumplimiento; propuestas revisables, aceptación explícita, vigencia por fecha e historial. Una sesión de 30 min/RPE 10 hoy da carga 300 y no dispara umbral 600: es un gap de producto, no fallo aritmético. No se debe exigir caminar extra por haber completado 10 rondas exhausto.

## Matriz mínima de pruebas

| Caso ficticio | Actual comprobado | Resultado que exige el cambio |
|---|---|---|
| 20 días intensos, cuatro mañanas | 7,7,7,7 | contador real 20; siguiente día cambia con datos, rango y fecha explícitos |
| 7 intensos previos +moderado hoy | conserva 7 | racha intensa termina; nuevo estado sin consejo engañoso |
| hoy vacío tras 3 intensos | racha 3 | “hasta ayer”, revisión de hoy; no asumir recuperación |
| 2 días sin actividad intensa | racha 0 | aviso por racha termina; molestias independientes pueden mantener cuidado |
| sesión hoy RPE desconocido | no intensa, carga estimada 6 | no afirmar estar recuperado ni subir metas por falta de dato |
| Plan B, molestia ayer y cero hoy | texto 48 h fijo | causa/fechas/revisión explícitas; cero registrado≠no registrado |
| nuevo perfil | 7500 | 5000 en Hoy, Ajustes y avisos |
| upgradeperfil 7500 | permanece 7500 si sólo default | permanece 7500 hasta CTA; aceptar 5000 cambia sólo pasos |
| abrir/cancelar/reabrir Ajustes | sin nueva acción | cero escrituras al perfil; valor intacto |
| upgradeperfil 6500/10000 | personalizado | queda 6500/10000 |
| dos semanas 1 pesaje cadauna | consejo+150–200 kcal | faltan registros, cero consejo de ajuste |
| cinturaenero/pesooctubre | consejo−150 kcal/+2000 pasos | cintura vieja: pedir nueva medida, no aumentar meta |
| 3 pesajes/semana+cintura válida | reglas ya existentes | conservar decisión justificada y mostrar cobertura |

## Comandos y gates

```powershell
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test test/domain/recovery_test.dart test/domain/steps_test.dart test/domain/habits_test.dart test/domain/core_ladders_test.dart test/domain/progress_test.dart --reporter expanded
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test test/data/migration_test.dart test/ui/experience_test.dart --reporter expanded
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' analyze
& 'C:/seguimiento-sdk-3.22.0/flutter/bin/flutter.bat' test
```

Todos deben salir 0 tras probar primero el fallo. Auditar diff y confirmar que el perfil 7500 cambia sólo tras aceptar CTA en base sintética, recompilar APK firmado y probar upgrade/reapertura en emulador propio con respaldo. Eso no confirma la versión ni el comportamiento en el teléfono del owner.

La evidencia ejecutada está en `plans/2026-10-09-adaptive-probes.dart.txt`; se renombró para no entrar al analizador Dart. Para repetir como ejecutor, copiar a `build/adaptive-probes.dart` (ignorado), ejecutar `dart run build/adaptive-probes.dart`; imports relativos resuelven `../lib`. Sus salidas caracterizan el código previo, no son tests verdes del arreglo. No desactivar reglas de análisis global.

STOP si hay edición simultánea de los archivos de alcance, si se necesitan claves/red IA, si falta identidad de perfil o se pretende reescribir otra meta; reportar en lugar de improvisar. Verificación de ilustraciones queda en su propio frente.

## Riesgos y continuidad

Los informes históricos usan el perfil actual (`report_repository.dart:185`, `period_summary.dart:223`): bajar a 5000 reclasifica retrospectivamente cumplimiento antes de existir historial de metas. Documentar “comparado con meta actual” en esa lectura y no venderlo como progreso histórico. Adaptación real requiere metas con fecha/razón/aceptación, explicación y comparación sobre la meta que estaba vigente cada día.

La doble progresión acepta RIR desconocido (`progress.dart:103`) por diseño explícito y recomienda+2–5 kg. Para el futuro motor de acompañamiento, usar sólo series comparables, recientes y con esfuerzo conocido; no heredar esa suposición como prueba de estar listo. Las escaleras de core sí tienen criterio de dos sesiones y 14 días, con confirmación, y son referencia reutilizable (`core_ladders.dart:252`, `ladder_repository.dart:82`).

Esta auditoría no revisó todo el código de IA, seguridad remota, macroprecisión de comidas, protocolo clínico ni pantalla instalada del owner. No solicita publicación ni transforma recomendaciones en prescripción.

