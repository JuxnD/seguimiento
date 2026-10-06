# Plan 003: preguntas con fuentes e historial local

Implementación candidata aislada en `JuxnD/120-informes`, iniciada desde
`792abd8` (cliente común aprobado). No se ha integrado, publicado ni probado
en teléfono; el dueño del producto conserva esos gates.

El esquema 18 agrega snapshots locales verificables y turnos con citas. La
fixture sintética de esquema 17 fue generada desde el código anterior al cambio
y congelada en `c3d6bbb`; migración y ZIP se prueban contra esa fixture. Preguntas
nuevas requieren consentimiento por contexto, usan las fuentes visibles y solo
se persisten tras validar semánticamente la respuesta. El flujo común aplica
modelo y contrato, límites de entrada/historial y citas exactas.

La fuente de informe es el texto exacto del renderer seleccionado; el usuario
elige si añade la comparación previa calculada localmente. No se envían fotos.
Las acciones de completar datos son
locales, tipadas y fechadas; abrir un formulario no registra información. La
guía de ejercicio toma el contenido de la misma guía que está en pantalla.

Detalles de esquema, validación y límites: [modelo-datos.md](../../modelo-datos.md)
y [ia-informes.md](../../ia-informes.md). La migración 17 → 18 usa
`test/fixtures/schema17-synthetic.sqlite`, no una reconstrucción del esquema
actual. Las pruebas de código no confirman aceptación visual ni operativa.
