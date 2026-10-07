import json,sqlite3,hashlib,sys,xml.etree.ElementTree as ET
from pathlib import Path
before,after,snap_before,snap_after,manifest,xml_before,xml_after,xml_reopen,receipt=map(Path,sys.argv[1:])
qa_manifest=json.loads(manifest.read_text(encoding='utf-8-sig'))
assert qa_manifest['schema']==18 and qa_manifest['sourceCommit']=='410da05d341d8ea88915fe8a197d3df6eee54283'
qa_a=sqlite3.connect(before.resolve().as_uri()+'?mode=ro',uri=True)
qa_b=sqlite3.connect(after.resolve().as_uri()+'?mode=ro',uri=True)
assert qa_a.execute('pragma user_version').fetchone()[0]==18
assert qa_b.execute('pragma user_version').fetchone()[0]==20
qa_tables=[r[0] for r in qa_a.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%' order by name")]
qa_rows=0
for table in qa_tables:
 cols=[r[1] for r in qa_a.execute(f'pragma table_info("{table}")')]
 select=f'SELECT '+','.join('"'+c+'"' for c in cols)+f' FROM "{table}" ORDER BY rowid'
 rows_a=qa_a.execute(select).fetchall(); rows_b=qa_b.execute(select).fetchall()
 assert rows_a==rows_b,f'Original columns changed: {table}'
 qa_rows+=len(rows_a)
qa_ai={t:qa_b.execute(f'SELECT count(*) FROM {t}').fetchone()[0] for t in ['ai_conversations','ai_messages']}
assert qa_ai=={'ai_conversations':2,'ai_messages':6}
qa_old=json.loads(snap_before.read_text());qa_new=json.loads(snap_after.read_text())
assert 'effectiveDay' not in qa_old
assert qa_new['effectiveDay'] is not None
for key in qa_old:assert qa_old[key]==qa_new[key],f'Legacy snapshot changed:{key}'
assert qa_new['index']==qa_manifest['index']
qa_ui=[]
for xml in [xml_before,xml_after,xml_reopen]:
 labels=[n.get('text') or n.get('content-desc','') for n in ET.parse(xml).iter('node')]
 text='\n'.join(labels)
 assert qa_manifest['expectedStep']['exercise'] in text, f'Wrong step:{xml}'
 assert 'SERIE 2/2' in text and 'de 6 reps' in text and '1 de 22 series hechas' in text, f'Wrong dose/count:{xml}'
 qa_ui.append({'file':str(xml),'sha256':hashlib.sha256(xml.read_bytes()).hexdigest()})
qa_receipt={'syntheticOnly':True,'beforeSchema':18,'afterSchema':20,'originalTables':len(qa_tables),'originalRows':qa_rows,'originalColumnsAndRowsPreserved':True,'aiRows':qa_ai,'snapshotOriginalFieldsPreserved':True,'effectiveDayCreated':True,'index':qa_new['index'],'uiBeforeUpgradeAfterUpgradeAfterRestart':qa_ui,'hashes':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [before,after,snap_before,snap_after,manifest]}}
receipt.write_text(json.dumps(qa_receipt,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({k:v for k,v in qa_receipt.items() if k not in ['hashes','uiBeforeUpgradeAfterUpgradeAfterRestart']},ensure_ascii=False))
