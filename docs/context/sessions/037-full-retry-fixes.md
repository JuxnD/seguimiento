# Correcciones de la validación completa037

Fuente productiva final incorpora el caller existente `TestDoses` en Cuerpo: dosis del último intento completo/limpio con condiciones conocidas, identidad, fecha y protocolo. La historia conserva intentos parciales y desconocidos sin fabricar dosis. La frontera async del historial se observa durante un plazo máximo de2s; no se infiere por un retraso fijo.

Primer FULL:1244PASS/13FAIL/16SKIP, raw037-full-final.txt, source504sin cambios. Los13fallos procedían de fixtures antiguas: destinos declarados17/21→25; cuenta Android16; viejos22/23 fabricados desde25; historia legacy sobrescrita por el oráculo; condiciones/calidad omitidas. Reparaciones:8suites,80PASS/1UIFAIL primero, posteriormente lastUI1+controles2PASS y analyzeALL0. El análisis inicial de la reparación tuvo6errores de constructor de fixture, preservados en raw; no se atribuyen a fallos funcionales.

Esquemas de prueba derivados: DDL auténtico público20 más adiciones históricas integradas22(bf40054c89835c6dd54db9a6b99775b645987247)/23(8872ae2b235d46dbc9b81f43f39af8f0c2827372), datos sintéticos mínimos. NO son exportaciones publicadas22/23 ni reproducción completa de transformaciones históricas de datos. `steps_target DEFAULT7500` heredado20 se conserva; la declaración fresh22 cambió5000 sin ALTER. Manifest pinned y DBhash; ALL columnas/FK/índices/CHECK/DDL/integridad verificadas antes abrirAppDatabase. Revisión independiente producto confirmó todas estructuras. Homónimo customLeche nuevoID1/usuario65kcal/3proteína/favorito, sin convertir la semillaID6 en usuario.

16SKIP del primer FULL son capturas opcionales existentes, fuera del alcance funcional048: ai_actions_render,ai_history_render,exercise_figure_3d_render,illustration_mockup_render,meal_assistant_render. No se modificaron gates ni skips. Nuevas ilustraciones035 DEFERRED por decisión humana; assets anteriores se mantienen.

Pendiente: FULLretry de candidato congelado, buildAPK LOCAL1.24.0+32, verificar paquete/firma histórica/SHA; no publicación ni instalación teléfono autorizada por esta evidencia. No declarar aceptación operativa del dispositivo.
