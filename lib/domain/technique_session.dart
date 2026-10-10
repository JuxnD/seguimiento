// Sesión técnica (§16.21, handoff del 7 oct): corta, para moverse sin gastar
// fuerza en descarga o víspera de intento/test. Todo a RIR 4. Se registra con
// `mode = 'tecnica'`. Para la regla de carga cuenta como intensa sólo si el
// RPE anotado lo es (≥ 7): la etiqueta no prueba que fue suave.

const techniqueMode = 'tecnica';
const techniqueRir = 4;

/// (nombre, series, reps, segundos, descanso, por lado, agarre, bloque).
const techniqueTemplate = [
  ('Pino pecho a la pared', 1, null, 300, null, false, null, 'pino'),
  ('Dominadas', 3, 4, null, 120, false, 'supina', null),
  ('Flexiones diamante', 2, 8, null, 90, false, null, null),
  ('Flexión a una mano', 2, 2, null, 120, true, null, null),
  ('Pike push-up', 2, 5, null, 90, false, null, null),
  ('Elevaciones laterales con banda', 3, 15, null, 60, false, null, null),
  ('Face pull con banda', 3, 15, null, 60, false, null, null),
  ('Colgarse de la barra', 2, null, 30, 60, false, null, null),
];

const techniqueNote = 'Sesión técnica: todo a RIR 4, sin fallo. Para moverse sin gastar fuerza.';

/// ¿Ofrecerla hoy? En la descarga, la víspera de un test o de las pruebas, o
/// cuando ya se sugiere el plan B. Nunca la impone: es una alternativa.
bool suggestTechniqueSession({required bool deload, required bool eveOfTest, required bool planB}) =>
    deload || eveOfTest || planB;
