"""Embed public dashboard assets in the Worker. Never reads runtime secrets."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
config=json.loads((root/'config/firebase.admin.web.json').read_text(encoding='utf-8'))
assets={'adminHtml':'index.html','adminApp':'app.js','privacyHtml':'privacy.html','deletionHtml':'delete-account.html'}
lines=[]
for name,path in assets.items():
    value=(root/'admin'/path).read_text(encoding='utf-8')
    if name=='adminHtml': value=value.replace('__DASHBOARD_CSS__',(root/'admin/dashboard.css').read_text(encoding='utf-8'))
    if name=='adminApp': value=value.replace('__FIREBASE_PUBLIC_CONFIG__',json.dumps(config))
    lines.append('export const '+name+' = '+json.dumps(value,ensure_ascii=False)+';')
(root/'cloudflare-worker/src/admin-assets.js').write_text('\n'.join(lines)+'\n',encoding='utf-8')
