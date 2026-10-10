# 0015 — Calentamiento guiado sin cambio de esquema

Fecha: 2026-10-09. Estado: aceptada para la rama `claude/handoff-sueno-tecnica-calentamiento`
(desde la candidata 1.22.0+30, esquema 20). Fuente: handoff §16.23 (9 oct).

## Contexto

La fase de calentamiento del cronómetro era un reloj con meta de minutos y
"Empezar" avisaba si no se llegaba. El handoff pide un bloque guiado de
5–8 min en toda sesión (movilidad, activación del día y aproximación al ~40 %
con 2 min de descanso), que se pueda saltar dejando registro, y en días de
intento o test, a la vista y con checklist. La auditoría Improve del mismo
día pidió no dar el calentamiento por hecho porque pasó el tiempo y dejar
oráculos de fases, aproximación, guardado y reanudación.

## Decisión

- `lib/domain/warmup.dart` arma el bloque, puro y probado:
  - movilidad 4 × 30 s;
  - activación según el primer ejercicio del día (tirón, empuje o piernas);
  - un paso por molestia ≥ 3 hoy o ayer en rodilla (cuádriceps), hombro
    (dislocaciones con banda) o codo (muñecas), sin repetir;
  - aproximación al 40 % hacia abajo, mínimo 1: en circuito, una ronda; si
    no, el primer ejercicio. Los aguantes, al 40 % del tiempo;
  - con FIFA 11+ (miércoles), sólo la aproximación.
- Cada paso lo marca la persona. El reloj de un paso por tiempo sólo lo
  marca si se arrancó ese reloj. Marcar toda la aproximación arma 2 min de
  descanso visibles; empezar antes se permite.
- "Empezar" con pasos sin marcar pregunta ("Calentamiento a medias"); "Saltar
  calentamiento" no pregunta y queda anotado.
- **Registro sin migración.** `warmupSec` sigue siendo el tiempo real de la
  fase: ponerlo en 0 al saltar inflaría el trabajo neto. Lo hecho va en la
  nota de la sesión: "Calentamiento: 7 de 9 pasos (5:40)" o "Calentamiento
  saltado". Las marcas viven en la foto de la sesión para retomar.
- Test de condición: tarjeta "Antes del intento" fija, con el calentamiento
  (torso: movilidad + tirón + empuje; piernas: FIFA 11+) y el checklist
  (pulso, escaleras 0–10, agua, reloj). Ayuda en pantalla: no se guarda.

## Por qué sin columna `warmup_done`

El plan 009 de la auditoría prepara su propia migración (metas versionadas).
Dos migraciones paralelas al esquema 21 chocarían. Si 009 o una entrega
posterior necesitan consultarlo como dato, la migración puede leer la nota
("Calentamiento: … / saltado") para poblar la columna.

## Límites

- La dosis (40 %, 30 s, 2 min) y los ejercicios por zona son la propuesta
  del handoff, no una validación clínica.
- Faltan figuras de Círculos de hombros, Balanceos de pierna, Retracciones
  escapulares, Flexiones escapulares, Puente de glúteo y Dislocaciones con
  banda: tienen ficha (pasos y errores) y el visor declara la ausencia.
  Corresponde al frente de ilustraciones.
- La Cindy de prueba y las pruebas del viernes (temporizadores) no muestran
  aún el checklist.


Actualización10oct2026: el frente014 resuelve las seis ausencias visuales
mediante recetas específicas, no fallback. [Diseño y límites](../design/calentamiento-014.md).
La lista anterior describe la base histórica; no modifica la política de dosis
ni demuestra seguridad por dolor, instalación o comprensión humana.
