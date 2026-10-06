# Fixture de migración 17 independiente

`schema17-synthetic.sqlite` se generó antes de editar el esquema, abriendo
`AppDatabase` en el worktree limpio `JuxnD/120-informes@792abd8e740f5fe697092e831fe9ad9ac6e4a207`
(schema 17). Contiene solo datos ficticios: perfil, un pesaje de 70 kg y una
comida con el rótulo `Dato sintético`. `PRAGMA user_version` fue 17 al cerrarla.

El binario se congela en Git para que la migración pruebe una base externa a la
definición Drift que compila el candidato. No regenerar desde el esquema nuevo.
