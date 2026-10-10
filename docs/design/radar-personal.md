# Radar personal: contrato del núcleo018

Slice local de011 sobre238ef85f, sin persistencia, providers o rutas de producto.
Datos y referencias se reciben explícitamente; ninguna cifra del mock se siembra.

| Eje | Fuente y unidad | Protocolo y aptitud |
|---|---|---|
| Tirón | TestResult pullup, reps | Prueba máxima de dominadas pronas estrictas; resolver008, no sesiones ordinarias |
| Empuje | TestResult pushup, reps | Flexiones normales limpias, fecha registrada |
| Core | TestResult hollow_hold, s | Hollow con técnica declarada, no otra variante |
| Piernas | TestResult bulgarian_split_squat, reps | I/D limpios del mismo día; menor valor, sin reconstruir lados |
| Salto | TestResult broad_jump, cm | Salto horizontal de la prueba, sin inferir velocidad/VO2 |
| Circuito | Sesión Cindy20min, rondas+reps | Receta guardada5/10/15 completa más prefijo parcial, ventana real1200s y conteo conocido; no marca por nombre/contexto |

Por eje: primera apta y última apta por fecha, último intento observado separado
y todas las observaciones necesarias para explicar parciales, dudas y fechas
inconsistentes. Una marca antigua no se reemplaza por un intento posterior dudoso.
Los datos sin fecha no demuestran cuál fue el último intento.
La evolución porcentual sólo se calcula entre fechas distintas; una sola fecha
no demuestra un cambio. Los empates por fecha conservan el desempate del test,
sin inventar horas de ejecución.
`sourceKey` de tests identifica la agrupación ítem/T1–T3, no inventa un ID de fila
SQLite ausente enTestResult008. Cindy y referencias conservan IDs suministrados.

Cada referencia viene identificada, con unidad, vigencia y fuente. La misma
referencia elegida se aplica a inicio/actual;100×raw/ref es avance hacia esa
referencia personal, no puntuación física. El dibujo se recorta a100%, el texto
conserva el porcentaje real. Sin referencia no hay porcentaje. Desde raw0 no
se calcula delta porcentual, aunque el0 observado sigue siendo valor.

Sin política de actualidad documentada se muestra fecha y antigüedad, sin
declarar caducidad clínica. El futuro caller puede proporcionar ventana/fuente
explícitas: dato viejo se conserva como historia y deja vacío el actual.
No se deduce técnica positiva desde flags ausentes, peso corporal desde pesajes,
carga, lados o protocolo desde notas. En los tests no se registran peso/carga;
es una limitación visible, no un cociente de fuerza.

El denominador Cindy se acredita con al menos una vuelta guardada5/10/15,
orden y prefijo parcial exactos, sin variante/lastre/partición/fallo distintos.
Se verifica la cantidad de sets antes de multiplicar para evitar overflow de
enteros, sin inventar un máximo físico de rondas. Cero vueltas y sólo un prefijo
no demuestran la receta completa: counts crudos visibles, sin normalización.
La equivalencia `rondas + extraReps/30` conserva también rondas y reps originales.
Flags de técnica/rango ausentes permanecen «no declarados»; aptitud del conteo
no certifica técnica. Ventana1201s,30min, importada, estimada, cortada o con
dudas sigue siendo observación. No tolerancia ni parseo de notas/contexto.
El riesgo de truncamiento del cronómetro se corregirá separadamente en019;
018 sólo mueve literalmente la receta/helper y mantiene el export antiguo.

Hexágono: naranja última apta, turquesa discontinua primera apta; leyenda textual,
mostrar inicio, tocar eje y alternativa textual. Cerrar/rellenar sólo con los6
ejes normalizados aptos de ese contorno. Los huecos son null, no0. Los callbacks
de registrar/configurar quedan sin navegación ni escritura en018.
Canvas muestra nombres junto a los ejes a360dp/texto1 y1.6. Atexto2 o canvas
menor280dp usa números y leyenda con botones accesibles; ningún control limita
la escala de texto. IDs técnicos permanecen enDTO/evidencia durable, sin exigir
que la persona los interprete. Referencia visible: valor, unidad, fuente y vigencia.

Antes de implementación: los contrafactuales deben reproducir selección por fecha,
bilateral parcial, futuro/duda, cero real, ausencia, referencia distinta y>100,
y receta/ventana Cindy incompatible por assertion, no por error de compilación.
Render Flutter a360dp con texto1/1.6/2; capturas sintéticas no son aceptación humana.

011 integrará GoalMetric.ref* / GoalRepository aprobado de009, consultas y rutas
existentes; el adaptador de proteína015 requerirá vigencia conocida y no inventará
un fin de vigencia. No se completan011 o el piloto al entregar018.

## Entrada reutilizable y fronteras

`buildPersonalRadar(tests, cindy, references, asOf, freshness?)` no lee SQLite,
perfil, reloj global o red. Tests son los DTO008; el caller conserva consultas
y permisos. `RadarReference` recibe identidad, eje, valor, unidad, vigencia y
fuente: positiva/finita y compatible, o se rechaza sin perder el crudo.
No se elige automáticamente otra referencia ni una población estándar.

`PersonalRadarWidget` recibe el snapshot y callbacks opcionales `onRegister`,
`onConfigure`, `onAxisSelected`; botones, teclado y tap del canvas los ejercitan.
No contiene Navigator ni escribe registros. `RadarProfile` mantiene null y limita
sólo dibujo a100%; el texto conserva porcentajes superiores.

En011: adaptar seis GoalMetric.ref* a referencias explícitas, guardar sólo mediante
GoalRepository.setReference aprobado y reutilizar rutas de TestResults/TestMode y
Entreno con su lifecycle. No lanzar un timer aislado que pierda su draft.
GoalHistory.on(proteinaMin, día).known será condición para el adaptador015;
la vigencia abierta no se convertirá en una fecha de fin ficticia.
