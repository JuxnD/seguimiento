# Marca e íconos de Seguimiento

Fuente editable única: `seguimiento_icon.svg`. Candidata013: **S en movimiento**,
una ruta continua con la inicial de Seguimiento. Negro cálido `#0B0806` y naranja
`#F08A34` de la app. Sin tipografía incrustada, foto, peso, atleta anatómico,
calificación o promesa fija de diez rondas. Nombre/paquete/firma no cambian.

```powershell
python tool/icons.py
python tool/icon_verify.py --receipt build/mockups/logo/resource-receipt.json
python tool/icon_preview.py --out build/mockups/logo
```

Pillow ya era la dependencia del pipeline; no se añadió motor SVG externo.
`tool/icon_vector.py` interpreta el subconjunto geométrico explícito del SVG
(rectángulo, círculo y trazo absoluto M/L/C/Z con extremos/uniones redondos),
con supersampling4x y curvas Bézier muestreadas. Construye trazos por unión de
cápsulas, evitando huecos de las uniones densas de ImageDraw.line. Atributos o
transformaciones no soportados fallan; ampliar el renderer antes de usar otra
geometría, nunca editar PNG a mano para separarlo de la fuente.

Grilla editable1024 equivalente al canvas adaptable108dp. Foreground432
transparente respeta el círculo seguro72dp. Legacy/store usan la misma
geometría con encuadre óptico800x800 central, ampliado a1024/512. La capa
monocroma se renderiza desde el mismo trazo en blanco, sin filtro de luminosidad.
La barra de estado recorta el círculo seguro y conserva exclusivamente alpha;
no hay cuadrado opaco ni segmentos apagados.

Generación produce cinco fuentes PNG y25PNG Android en cinco densidades:
launcher clásico48dp, foreground/background/monochrome108dp y status24dp.
El XML adaptable apunta a la capa monocroma propia. Los nombres consumidos por
Manifest y NotificationService permanecen idénticos. No cambiar nombre app ni
applicationId/firma para probar una marca.

Preview genera20tamaños (16–512px)×4máscaras circular/squircle/redondeada/mono,
comparación con el icono anterior y otra dirección (atleta/arco) y vista móvil.
El baseline anterior se lee de Git d2d3070; para una renovación futura indicar
`--baseline-ref <commit>` al generador de preview. Si ese histórico no existe
en el checkout, la comparación falla explícitamente; no afecta tool/icons.py.
Marca “propuesta, no instalada”. La alternativa es sólo comparación; no se
genera como recurso Android. `icon_verify.py` valida archivos reales, tamaños,
transparencia, blanco de status/mono, círculo seguro y referencias XML, y deja
hashes. Su veredicto prueba entradas de recursos, no la aceptación visual ni
el APK final. En la candidata integrada falta comprobar launcher, íconos
temáticos y notificación release con R8 y permisos reales.
