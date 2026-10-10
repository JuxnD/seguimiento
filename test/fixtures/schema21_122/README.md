# Base sintética congelada del esquema 21

`fixture.sqlite` fue creada por la `AppDatabase` real de
`e6b420a66c55f0da82ee4dc97ebf31c7155ac98a` (integración anterior a 009),
en una copia aislada de esos archivos Git, con Flutter 3.22/Dart 3.4.
Se llamó al `seedFoodsIfEmpty` real de esa fuente y se añadieron registros
ficticios de comida, sesión/serie, mañana y conversación/mensaje de IA.
Sin datos de usuario, claves, red, APK ni instalación.

La base contiene 33 tablas, `user_version=21` y `catalog_patches` con registros.
No contiene `goal_versions`, `coach_proposals` ni `morning_checks.feeling`.
El [manifiesto](manifest.json) se fijó ANTES de abrirla con código 22:
SHA256 del SQLite, PRAGMA de todas las columnas, todas las filas de las 33 tablas,
hashes de las fuentes 21 y valores de las cinco metas tomados del perfil físico.

SHA256: `00ab5cd15636ed48cf41c3aabaf06f558b1014387b15f6efe9ac04b81e3c77c2`.
La prueba copia este archivo a una carpeta temporal, verifica primero la base
con SQLite independiente en sólo lectura y después abre/reabre con el candidato.
Conserva cada fila/columna 21 y verifica únicamente las adiciones 22 esperadas.
No deriva el esquema antiguo quitando tablas del actual ni normaliza evidencia.

Generación/procedencia, comandos y diagnóstico del primer montaje están en
[el recibo de integración 009](../../../docs/context/sessions/2026-10-10-integracion-122-009.md).
La copia fuente usada para generar la fixture queda ignorada en
`build/qa-122-009/source21`; no forma parte de los assets o del producto.
Esta fixture acredita un ensayo de migración local con datos ficticios,
no una base pública ni conservación de un teléfono.
