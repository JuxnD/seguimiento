"""Galería local de los PNG generados por Flutter; no dibuja poses alternativas."""
from pathlib import Path
import json
import hashlib
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'build/mockups/renovacion')
entries = [dict(zip(('id', 'name', 'group', 'count'), line.split('|')))
           for line in (root / 'catalog.tsv').read_text(encoding='utf-8').splitlines()]
for entry in entries:
    entry['count'] = int(entry['count'])
html = '''<!doctype html><html lang="es"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Seguimiento · renovación de ilustraciones</title>
<style>
:root{color-scheme:dark;font:16px system-ui;background:#100c09;color:#f8eee5}
*{box-sizing:border-box}body{margin:0}header,main{max-width:1400px;margin:auto;padding:24px}
header{border-bottom:1px solid #493225}h1{font-size:clamp(24px,4vw,38px);margin:4px 0 16px}
p{line-height:1.5;color:#ddc9b7}input,select,button{font:inherit;padding:12px;border:1px solid #71553e;border-radius:8px;background:#21170f;color:inherit}
input{width:min(100%,450px)}button{cursor:pointer}button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #ff942f}
.tools{display:flex;gap:12px;flex-wrap:wrap}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:28px}
article{border-bottom:1px solid #493225;padding-bottom:24px}h2{font-size:20px;min-height:48px;margin:0}small{color:#ffaf64}
img{display:block;width:100%;height:auto;background:#0b0806}footer{display:flex;justify-content:space-between;align-items:center;gap:8px}
#status{margin:20px 0}.screens{display:flex;gap:16px;overflow-x:auto}.screens a{flex:0 0 210px}.screens img{width:210px}
</style><header><small>CANDIDATO LOCAL · todavía no publicado</small>
<h1>Una guía para entender cada ejercicio</h1>
<p>Mockups obtenidos del mismo visor que usa la app. Revisa dónde apoyan manos y pies, hacia dónde mira el cuerpo y qué cambia entre los momentos. La biblioteca también se podrá abrir antes de entrenar.</p>
<div class="tools"><input id="q" placeholder="Busca un ejercicio" aria-label="Busca un ejercicio"><select id="group" aria-label="Grupo"><option value="">Todos los grupos</option></select></div>
<div id="status" role="status"></div></header><main>
<div class="grid" id="grid"></div><h2 style="margin-top:40px">Así se consulta en la app</h2>
<p>Capturas del flujo real en Flutter: biblioteca, guía, vista de apoyos y texto ampliado.</p>
<div class="screens">SCREENS</div></main><script>
const catalog=CATALOG, revision="REVISION";
const grid=document.querySelector('#grid'),q=document.querySelector('#q'),group=document.querySelector('#group');
for(const g of [...new Set(catalog.map(e=>e.group))].sort()){const o=document.createElement('option');o.value=g;o.textContent=g;group.append(o)}
const normalize=s=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
function render(){grid.replaceChildren();const rows=catalog.filter(e=>normalize(e.name).includes(normalize(q.value))&&(!group.value||e.group===group.value));document.querySelector('#status').textContent=`${rows.length} de ${catalog.length} entradas · inicio y momentos`;
for(const e of rows){const a=document.createElement('article'),h=document.createElement('h2'),tag=document.createElement('small'),im=document.createElement('img'),f=document.createElement('footer'),back=document.createElement('button'),next=document.createElement('button'),label=document.createElement('span');h.textContent=e.name;tag.textContent=e.group;im.loading='lazy';let index=0;function show(){im.src=`${e.id}-${index}.png?v=${revision}`;im.alt=`${e.name}, momento ${index+1}`;label.textContent=`${index+1} / ${e.count}`;back.disabled=index===0;next.disabled=index===e.count-1}back.textContent='← Anterior';next.textContent='Siguiente →';back.onclick=()=>{index--;show()};next.onclick=()=>{index++;show()};f.append(back,label,next);a.append(h,tag,im,f);grid.append(a);show()}}
q.oninput=render;group.onchange=render;render();
</script></html>'''
screens = ''.join(f'<a href="{name}.png"><img src="{name}.png" alt="{label}" loading="lazy">{label}</a>'
                  for name, label in [('biblioteca-movil', 'Biblioteca'), ('guia-movil', 'Guía por lado'),
                                      ('apoyos-movil', 'Ver apoyos'), ('texto-grande', 'Texto ampliado'),
                                      ('biblioteca-tableta', 'Biblioteca en tableta')])
(root / 'index.html').write_text(html.replace('CATALOG', json.dumps(entries, ensure_ascii=False)).replace('REVISION', hashlib.sha256(Path('assets/tecnica/figuras3d.json').read_bytes()).hexdigest()[:12]).replace('SCREENS', screens), encoding='utf-8')
print(f'{len(entries)} entradas → {root / "index.html"}')
