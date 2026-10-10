# CASO — Piloto de Seguimiento

Fecha: 9 de octubre de 2026. Responsable de decidir: owner de Seguimiento.
Estado: preparación; piloto de usuarios no iniciado. Plan012 en la auditoría de
referencia `seguimiento-ilustraciones/plans/012-piloto-mercado.md`.
Base local d2d3070d6934eef2f70512e9cdea0b588b9c66a3.

## Canvas DOFA operativo

| Dimensión | Evidencia / situación | Nota |
|---|---|---|
| Dolor | Owner usa la app a diario y reporta comida no reconocida, mensajes que no reaccionan al progreso y figuras confusas. Fuente: petición del owner y auditoría del 9-oct. Tiempo de fricción **NO_MEDIDO**. | MEDIO (2); no hay cifra de proceso |
| Oportunidad | Registrar un plato nuevo, corregirlo y entender progreso sin depender del chat. Owner seleccionó cinco frentes, incluido piloto. Meta cuantitativa todavía no acordada. | MEDIO (2) |
| Factibilidad | Existe app local, SQLite, respaldo portable e IA revisable. Los gates se pueden ensayar con datos ficticios. 008–011, alta nueva y compatibilidad de tienda siguen abiertos. | MEDIO (2); flujo futuro completo no probado |
| Adopción | Owner decide y ya es usuario personal. No hay participantes externos elegidos, consentimiento ni ventana confirmada. | BAJO (1) para piloto externo |

Puntaje orientativo: **7/12**. Veredicto: **spike y adoptantes antes de piloto**.
El uso personal no demuestra demanda ni voluntad de pago. No se autoriza
invitar usuarios, cobrar, enviar datos reales ni publicar por este documento.
Las correcciones y preparación local autorizadas continúan; no constituyen
el build o activación de un piloto operativo.

## S0: supuesto que puede refutar el caso

Una persona que no conoce el proyecto puede registrar y corregir un plato fuera
de catálogo, y explicar una decisión de progreso con evidencia y límites sin
pedir ayuda al chat. Si no puede, la expansión comercial no tiene sustento aún.

Spike propuesto tras 008–011: tarea ficticia con arroz chino de porción declarada,
una semana sintética de entrenamiento y un día sin registro. La persona debe
encontrar la revisión de la estimación, identificar lo que falta y explicar por
qué una recomendación cambió. El facilitador no indica dónde tocar ni responde
por la persona. Capturar tiempo, errores, correcciones y explicación literal
consentida; comparar con registro manual de la misma tarea, alternando orden.

Resultado: **NO_EJECUTADO**. Los tests del gate prueban detección de alteraciones
de artefactos; no prueban S0, precisión nutricional ni comprensión humana.

## Baseline y regla de decisión

La línea base manual es **NO_MEDIDA**. Fuente a obtener: observación de tareas
equivalentes, duración desde abrir registro hasta guardar correctamente,
incluyendo correcciones. Responsable de confirmar: owner/facilitador a acordar.
Congelar corpus, porciones, criterios y orden antes de medir. No convertir
faltantes en cero ni usar respuestas de otro modelo como verdad nutricional.

Para iniciar personas reales faltan: responsables, participantes consentidos,
inicio/fin, fuente de baseline y umbrales go/no-go confirmados. La propuesta
acotada es 3–5 voluntarios durante 14 días, sin invitaciones automáticas; aún
no es una agenda. La ventana breve evalúa uso inicial, no cambios físicos.

## Cierre del caso

Acción: preparación local de privacidad y compuerta de evidencia.
Cobertura: artefactos sintéticos y pruebas host; cero usuarios externos.
Resultado frente a baseline: **NO_MEDIDO**. Implementación parcial de 012;
validación operacional y cierre formal del piloto pendientes.

Siguiente acción: integrar 008–011 y cerrar alta nueva/QA; después el owner
confirma participantes, baseline, umbrales y ventana antes de iniciar el piloto.
Detalle de recorrido, medición y gates: [piloto.md](piloto.md).
