# 045 — Intervalos de carrera 15/15 y snapshot congelado

Implementación local verificada; pendiente revisión independiente root y consumo por 034/037. Base b2d4bf7777f1df2d24b69f2134907a1128b930fc, fuente a52b5e240e3f5acdc51a3945fd46a992f151aa52. Sólo tres archivos de producto, dos pruebas propias y este contexto; TrainingScreen pertenece a 034.

## Contrato público

`TabataScreen.running1515(required date, required bool footballFreeConfirmed, resume, onSnapshot)` reutiliza el temporizador. Perfil tipado `TimerProfile.running1515`; `TimerPrescription` congela trabajo15, pausa15, ciclos16 por bloque, dos bloques, between0 y `includeFinalRest:true`: 32 trabajos +32 pausas =960s. Calentamiento/enfriamiento van aparte. No solicita peor ronda de repeticiones ni genera series de fuerza. Un inicio nuevo requiere confirmación true; al restaurar prevalecen fecha, ejercicios, parámetros y confirmación congelados, incluso si el caller actual pasó false. La selección de semana5/martes, disponibilidad, rodilla y fútbol corresponde al caller034.

`TimerSnapshot.prescription` opcional y getters profile/workSec/restSec/intervals/betweenBlocksSec/includeFinalRest/footballFreeConfirmed; JSON aditivo plano. Los JSON antiguos sin nuevos campos siguen siendo legados; desconocidos, parciales o inválidos se rechazan mediante el contrato existente `ActiveSession.fromJson → null`, sin reconstruir silenciosamente Tabata. El caller debe conservar su tratamiento explícito de snapshot inválido.

## Evidencia y límites

[Manifiesto y hashes](045-evidence/final-receipt.json), raw y recibos adjuntos en la misma carpeta. Los dos rojos funcionales de base muestran 930 en lugar de960 y pérdida del perfil JSON. La prueba verde de duración agrega deliberadamente el opt-in `includeFinalRest:true`; no se cambió el default para fingir compatibilidad. El fixture rojo original queda como texto.

12 nuevas pruebas pasan: cuatro de contrato/domain y ocho UI con navegación real y ActiveSessionStore físico temporal. Fronteras14/15/479/480/959/960 y restauración tardía980; pausa final, resultado parcial/completo, fecha y prescripción, snapshot emitido y nueva lectura del archivo. Predeterminados Tabata1100s (640trabajo/460pausa) y parámetros custom preservados. Después de quitar tres assertions `!` redundantes de test, analyze completo exit0; no se repitieron esas12 por decisión proporcional del coordinador.

Cinco suites existentes pasan49/49, sin skips: v3_timers_test, plan_v31_test, active_session_test, restored_session_resume_test y active_session_restore_queue_test. Analyze inicial conserva sus tres warnings en raw; analyze final0. Wrapper por comando, concurrency1/timeout90/no-pub, sin full ni generación. No cambios de esquema, publicación, APK o datos reales.

La implementación no demuestra todavía integración caller034, full037 ni aceptación operativa/humana. Root revisará este commit antes de incorporar.
