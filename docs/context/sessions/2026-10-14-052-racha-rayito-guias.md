# 052 — Racha «todo registro», Rayito flotante, piernas tras torso real, guías 035 y hallazgos 047

Estado: implementación local en `JuxnD/052-racha-guias-hallazgos` (worktree
`seguimiento-052-racha-guias`), base `6a48261` (v1.25.0+34 publicada).
Candidato 1.26.0+35. Autor: Claude (sesión 009) por orden directa del owner:
«prosigue con el widget, quiero mi racha de vuelta, prosigue con las guías y
los hallazgos, sin pendientes». Sin teléfono, sin vigía; SDK por lease 052c.

## Decisiones del owner (14 oct, en el chat de Claude)

| Tema | Decisión |
|---|---|
| Racha | Todo registro: sesión de cualquier tipo, fútbol, comida, peso, medidas, fotos, sueño, check matinal, molestias, pruebas, benchmarks, logros y días de comida cerrados. Pasos sólo el día que llegan a su meta vigente. Descanso planificado no rompe; sin plan cada día pide registro. |
| Test de piernas | Reporte real: torso completo el martes 13 y piernas seguía el miércoles 14. Debe quedar el jueves. |
| Mascota | Compañero flotante en las cinco pestañas, rayo vectorial animado (flota, respira, parpadea, salta al guardar), globo de texto al abrir, al guardar y al tocar; toque largo lo esconde. |
| Nombre | Sólo «Rayito»; la fase como «Nivel N de 8», sin «Prime» (choca con My Prime). |
| 047-2 intervalos | Ejercicio real con temporizador desde la semana 5, sin fútbol entre semana, omitido en la descarga. |
| 047-4 aterrizaje | Por semana: dos piernas 1–2 y descarga, una pierna 3–5, salto lateral desde 7; tras el FIFA 11+. |
| 047-5 viernes de 10 | Sin test en el bloque 2 (la semana 9 ya lleva las pruebas). |

## Qué cambió

- **Racha** (`DashboardRepository._streak`): un `SELECT DISTINCT … UNION` de
  fechas de las 13 tablas de registro en los últimos 400 días (el mismo
  límite de `currentStreak`); pasos con `goalReferenceOn(pasos)` comparable y alcanzado; sin
  plan, `currentStreak` sin días de descanso. `streakSignalsProvider` refresca
  Hoy al guardar fotos, medidas, peso, pruebas, benchmarks, logros o días
  cerrados. Se recalcula desde el historial: la racha del owner vuelve sola.
- **Piernas tras torso real** (`ReadinessRepository._anyCompleteTorsoBefore`):
  si el torso de esta identidad no se encuentra, cualquier intento de torso
  con cabecera, completo según su propio protocolo y ronda, guardado en los 6
  días previos a piernas, la separa 2 días. Cubre el torso guardado desde el
  botón de Cuerpo sin agenda (`scheme v3.1`, sin bloque), con otro bloque o
  con el protocolo anterior. Sólo mueve la fecha; `done()` de este bloque
  sigue en falso y no se comparten marcas ni dosis. Contrato 050 actualizado:
  antes otro bloque/protocolo no transfería la fecha (3 transiciones
  «rechazadas» pasan a jueves; el torso posterior a piernas sigue sin mover).
- **Rayito**: `RayitoAlive` (bucle de 6 s: flotación, respiración, halo,
  estrellas, parpadeo doble, mirada si está atento, Z al dormir; salto con
  estirón por `hop`; quieto con «quitar animaciones» y en `flutter test`).
  `RayitoCompanion` en `HomeShell` sobre las pestañas, abajo a la derecha:
  saluda una vez al día, festeja cuando lo guardado suma (y distinto al subir
  de nivel), al tocar alterna frase, avance, qué toca hoy y un consejo; se
  asoma a medias durante el scroll; toque largo lo esconde con «Deshacer» y
  vuelve con el interruptor «Rayito en pantalla» de Ajustes
  (`FlagKeys.rayitoHidden`). `rayitoView` es la lectura común de tarjeta,
  compañero y widget. La tarjeta de Hoy queda como nivel + barra de avance.
  Widget de inicio: título «Rayito», línea «Nivel N · X días de racha».
- **Hallazgos 047** (en `withV31Blocks`, así llegan a un plan v3.2 ya activo):
  muñecas 2 min el lunes tras scap pull-ups; intervalos 15/15 sobre el
  temporizador que ya integró 045 (`TrainingRepository.intervals1515Blocked`:
  semana 5+, no en la descarga, no con fútbol registrado lunes–martes; el
  diálogo de Entreno sólo los ofrece entonces y la nota del martes dice por
  qué no van) en vez de un ejercicio duplicado dentro de la fuerza; aterrizaje por semana con las
  variantes `landing_unilateral`/`landing_lateral` que ya dibujó 035 y justo
  después del FIFA 11+; viernes de 10 fijado por prueba (`maintenanceRounds`).
  047-1 (planche en descarga) ya lo cerró 034 `aee1837`.
- **Guías 035**: rama `JuxnD/035-ilustraciones-movimiento` integrada por
  `JuxnD/052-integra-035` (merge `1809d5b`): la API de variantes de 034 y 035
  era idéntica token a token, se tomó la versión 035; evidencia binaria de
  102 MB fuera del repositorio (queda en el worktree 035). `Intervalos 15/15`
  recibe figura propia con la zancada de Aceleración; inventario 112 figuras /
  18 variantes, generador byte-idéntico.

## Traspaso del gestor §16.27 (14 oct) dentro de la 1.26.0

El owner pidió «todo junto en la 1.26.0» tras compartir
`entrega-gestor-app-seguimiento.md` (§16.26 y §16.27).

- **Semana reorganizada** (`ReadinessRepository.testWeekDay`,
  `TrainingRepository.withV31Blocks`): sólo cuando el test de piernas quedó
  fuera de su fecha nominal. Test en día que no es de piernas → FIFA 11+ →
  test + 5 benchmarks → piernas corta (búlgara, PM a una pierna y nórdico a
  2 series, gemelo, sóleo, Pallof), sin sprints ni saltos; la sesión propia se
  descarta. Víspera de piernas → movilidad; otra víspera → sin carga de
  piernas. Viernes siguiente → la sesión desplazada sin pistol ni piernas.
  Piernas nunca a menos de 48 h de un partido (jugado o del plan); escaleras
  3–4 ese día → la siguiente sesión de piernas (miércoles), dentro de la
  sesión completa; ese día isométricos + benchmarks. Día después del test de
  torso: RIR 3+ en torso. Aplica a v3.1 y v3.2. Hoy rotula «Semana N
  reorganizada (test movido)» con el porqué. Contrato 050 actualizado (la
  prueba de rodilla del viernes ahora espera el miércoles 21).
- **Etiqueta única**: Hoy e informe rotulan por esquema (`Plan v3.2`), no
  por número de fila. Si el teléfono del owner mostraba «Plan v3.1» el 14,
  la versión activa ese día era v3.1: se ve tal cual.
- **Test** (esquema 26): `limited_by` por prueba; piel/dolor/equipo marcan
  ⚠ «no es un máximo real»; «No la hice» guarda motivo y colchoneta
  pendiente sin valor; resultados lista las pendientes. Dosis por encima del
  tope del rango del plan → variante más difícil (pike con pies elevados,
  dominadas/fondos con mochila, peldaño 2 del V-up…), no más reps.
- **Material** (`EquipmentRepository`, `lib/domain/equipment.dart`): tarjeta
  «Material» en Ajustes (barra, banda, báscula, colchoneta, mini paralelas,
  anillas, mochila con kg) con tengo / en compra / no tengo; paralelas y
  anillas quedan sincronizadas con sus banderas en ambos sentidos. Cada
  ejercicio declara lo que necesita: el Pino exige colchoneta y sale de la
  sesión con «pendiente: falta colchoneta (en compra)» mientras no esté; el
  suelo de core y «con mochila» la recomiendan con nota. Con la colchoneta en
  «tengo», Hoy ofrece el test pendiente del Pino. Cambio esperado: sin
  colchoneta registrada, el Pino ya no aparece como si se pudiera hacer.
- **Creatina**: Suplementos en Ajustes, toma diaria en el registro de la
  mañana, existencias con aviso a 7 tomas, nota de agua intramuscular 28
  días en peso, gráfica e informe; la regla de dos semanas no lee el peso
  como grasa en esa ventana y decide por cintura; constancia en el informe.
- **kcal**: rango del día; fútbol (también entre semana) 2.400–2.500, día
  amarillo 2.200–2.400, normal 2.100–2.200.
- **§16.26**: carga total en el anillo de fútbol, hora de inicio del partido,
  reponer 1,25–1,5 L/kg con sal, condiciones del retest copiadas de la
  ronda anterior. El pulso del reloj (§16.26.3) no aplica: la app no importa
  series de pulso (sería un permiso nuevo de Health Connect); el pulso es
  manual y «sin dato» se respeta.

## Evidencia

Pendiente de completar al cierre (suite completa, analyze, APK, QA nativa).
