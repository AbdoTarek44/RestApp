import { verifyFirebaseToken } from './auth.js';

let access, accessExpires = 0;
let settingsCache, settingsExpires = 0;
const encoder = new TextEncoder();
const base64url = bytes => btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
const encode = data => base64url(encoder.encode(JSON.stringify(data)));
function credentials(env) {
  if (!env.GOOGLE_OPERATIONS_CREDENTIALS) throw new Error('Operations unavailable');
  return JSON.parse(env.GOOGLE_OPERATIONS_CREDENTIALS);
}
export async function googleAccessToken(env) {
  if (access && Date.now() < accessExpires) return access;
  const sa = credentials(env), now = Math.floor(Date.now()/1000);
  const pem = sa.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
  const key = await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),
    {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const unsigned = `${encode({alg:'RS256',typ:'JWT'})}.${encode({iss:sa.client_email,
    scope:'https://www.googleapis.com/auth/cloud-platform',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600})}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,encoder.encode(unsigned));
  const result = await fetch('https://oauth2.googleapis.com/token',{method:'POST',
    headers:{'content-type':'application/x-www-form-urlencoded'},signal:AbortSignal.timeout(8000),
    body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${unsigned}.${base64url(new Uint8Array(signature))}`})});
  if (!result.ok) throw new Error('Operations identity unavailable');
  const data = await result.json(); access = data.access_token;
  accessExpires = Date.now() + (Number(data.expires_in)-120)*1000;
  return access;
}
export async function googleRequest(env, url, method='GET', body) {
  const token = await googleAccessToken(env);
  const response = await fetch(url,{method,headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},
    signal:AbortSignal.timeout(8000),...(body===undefined?{}:{body:JSON.stringify(body)})});
  if (response.status===404) return null;
  if (!response.ok) throw new Error(`Operations request failed (${response.status})`);
  return response.status===204 ? {} : response.json();
}
const db = env => `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/maalish/documents`;
const auth = env => `https://identitytoolkit.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/accounts`;
const f = value => typeof value==='boolean'?{booleanValue:value}:typeof value==='number'?{doubleValue:value}:{stringValue:String(value)};
export function unpack(doc) {
  return Object.fromEntries(Object.entries(doc?.fields || {}).map(([k,v])=>[k,
    v.stringValue ?? v.booleanValue ?? (v.integerValue!==undefined ? Number(v.integerValue) : v.doubleValue ?? v.timestampValue ?? null)]));
}
async function put(env,path,values) {
  return googleRequest(env,db(env)+'/'+path,'PATCH',{fields:Object.fromEntries(Object.entries(values).map(([k,v])=>[k,f(v)]))});
}
export const defaultSettings = {maintenance:false,maintenanceMessage:'بنجهّز معلش. جرّب كمان شوية.',
  announcement:'',temperature:.65,maxOutputTokens:1100,inputPrice:0,outputPrice:0};
export function validateSettings(data) {
  const keys = Object.keys(defaultSettings);
  if (!data || typeof data!=='object' || Object.keys(data).some(k=>!keys.includes(k))) throw new Error('Invalid settings');
  if (typeof data.maintenance!=='boolean' || typeof data.maintenanceMessage!=='string' || data.maintenanceMessage.length>200 ||
    typeof data.announcement!=='string' || data.announcement.length>200 ||
    !Number.isFinite(data.temperature) || data.temperature<0 || data.temperature>1 ||
    !Number.isInteger(data.maxOutputTokens) || data.maxOutputTokens<700 || data.maxOutputTokens>1600 ||
    !Number.isFinite(data.inputPrice) || data.inputPrice<0 || data.inputPrice>100 ||
    !Number.isFinite(data.outputPrice) || data.outputPrice<0 || data.outputPrice>100) throw new Error('Invalid settings');
  return Object.fromEntries(keys.map(k=>[k,data[k]]));
}
export async function appSettings(env) {
  if (!env.GOOGLE_OPERATIONS_CREDENTIALS) return defaultSettings;
  if (settingsCache && Date.now()<settingsExpires) return settingsCache;
  const result = unpack(await googleRequest(env,db(env)+'/operationsConfig/current'));
  const merged = {...defaultSettings,...result};
  settingsCache = validateSettings(merged); settingsExpires=Date.now()+5000;
  return settingsCache;
}
export async function accountAllowed(env,identity) {
  if (!env.GOOGLE_OPERATIONS_CREDENTIALS) return true;
  const doc = await googleRequest(env,db(env)+'/operationsUsers/'+encodeURIComponent(identity.sub));
  return unpack(doc).disabled!==true;
}
async function query(env,parent,collection,limit=100) {
  const data = await googleRequest(env,db(env)+(parent?'/'+parent:'')+':runQuery','POST',{
    structuredQuery:{from:[{collectionId:collection}],limit}});
  return (data||[]).filter(v=>v.document).map(v=>({id:v.document.name.split('/').pop(),...unpack(v.document)}));
}
async function increment(env,path,counts,values={}) {
  const name=`projects/${env.FIREBASE_PROJECT_ID}/databases/maalish/documents/${path}`;
  const fields=Object.fromEntries(Object.entries(values).map(([k,v])=>[k,f(v)]));
  return googleRequest(env,db(env)+':commit','POST',{writes:[{
    update:{name,fields},updateMask:{fieldPaths:Object.keys(fields)},
    updateTransforms:[...Object.entries(counts).map(([fieldPath,value])=>({fieldPath,increment:{integerValue:String(Math.round(value))}})),
      {fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}]});
}
export async function trackRequest(env,identity,status,duration,usage={}) {
  if (!env.GOOGLE_OPERATIONS_CREDENTIALS) return;
  const day=new Date().toISOString().slice(0,10);
  const counts={requests:1,successes:status===200?1:0,errors:status===200?0:1,
    durationMs:duration,inputTokens:usage.promptTokenCount||0,
    outputTokens:(usage.candidatesTokenCount||0)+(usage.thoughtsTokenCount||0)};
  // No message, summary, mood, memory, or category is collected here.
  await Promise.all([
    increment(env,'operationsDaily/'+day,counts,{day,model:env.MAALISH_MODEL||'gemini-3.5-flash-lite'}),
    increment(env,`operationsActivity/${day}/users/${identity.sub}`,{requests:1},{uid:identity.sub}),
  ]);
}
export async function requireAdmin(request,env) {
  const token=request.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
  const identity=await verifyFirebaseToken(token,env.FIREBASE_PROJECT_ID);
  const emails=String(env.ADMIN_EMAILS||'').toLowerCase().split(',').map(v=>v.trim());
  if (!identity.email_verified || !emails.includes(String(identity.email||'').toLowerCase()) ||
    identity.firebase?.sign_in_provider!=='google.com' ||
    Math.floor(Date.now()/1000)-identity.auth_time>1800) throw new Error('Admin authentication required');
  // Check live account state so revoked/disabled admin tokens cannot keep access.
  const result=await googleRequest(env,auth(env)+':lookup','POST',{localId:[identity.sub]});
  const user=result?.users?.[0];
  if (!user || user.disabled || Number(user.validSince||0)>identity.auth_time) throw new Error('Admin authentication required');
  return identity;
}
const safeUser = user => ({uid:user.localId,email:user.email||'',name:user.displayName||'',
  disabled:user.disabled===true,createdAt:Number(user.createdAt||0),lastLoginAt:Number(user.lastLoginAt||0),
  providers:(user.providerUserInfo||[]).map(p=>p.providerId)});
async function audit(env,identity,action,target) {
  await put(env,'operationsAudit/'+crypto.randomUUID(),{admin:identity.email,action,target,at:new Date().toISOString()});
}
export async function handleAdmin(request,env) {
  const headers={'content-type':'application/json; charset=utf-8','cache-control':'no-store',
    'x-content-type-options':'nosniff','content-security-policy':"default-src 'none'; frame-ancestors 'none'"};
  const respond=(body,status=200)=>new Response(JSON.stringify(body),{status,headers});
  let identity;
  try{identity=await requireAdmin(request,env);}catch{return respond({error:'الدخول للإدارة محتاج حساب Google المصرّح له وتسجيل دخول حديث.'},403);}
  const url=new URL(request.url), path=url.pathname;
  if(request.method==='POST' && request.headers.get('origin')!==url.origin) return respond({error:'Origin rejected'},403);
  try {
    if(path==='/api/admin/users' && request.method==='GET') {
      const search=(url.searchParams.get('search')||'').trim();
      let result;
      if(search) {
        if(search.length>254)return respond({error:'بحث غير صالح'},400);
        result=await googleRequest(env,auth(env)+':lookup','POST',search.includes('@')?{email:[search]}:{localId:[search]});
      } else {
        const next=url.searchParams.get('pageToken')||'';
        if(next.length>4096)return respond({error:'Invalid page'},400);
        result=await googleRequest(env,auth(env)+':batchGet?maxResults=100'+(next?'&nextPageToken='+encodeURIComponent(next):''));
      }
      return respond({users:(result?.users||[]).map(safeUser),nextPageToken:result?.nextPageToken||''});
    }
    if(path==='/api/admin/overview' && request.method==='GET') {
      const [count,daily,activity,logs,settings]=await Promise.all([
        googleRequest(env,`https://identitytoolkit.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}:queryAccounts`,'POST',{returnUserInfo:false}),
        query(env,'','operationsDaily',1000),
        query(env,'operationsActivity/'+new Date().toISOString().slice(0,10),'users',20000),
        query(env,'','operationsAudit',1000), appSettings(env)]);
      return respond({totalUsers:Number(count.recordsCount||0),activeToday:activity.length,
        activeTodayCapped:activity.length===20000,daily:daily.sort((a,b)=>a.id.localeCompare(b.id)).slice(-30),
        audit:logs.sort((a,b)=>String(b.at).localeCompare(String(a.at))).slice(0,30),settings,model:env.MAALISH_MODEL||'gemini-3.5-flash-lite'});
    }
    if(request.method==='POST') {
      if(Number(request.headers.get('content-length'))>4096)return respond({error:'طلب كبير'},413);
      const raw=await request.text(); if(encoder.encode(raw).length>4096)return respond({error:'طلب كبير'},413);
      const body=JSON.parse(raw);
      if(path==='/api/admin/user-status') {
        if(typeof body.uid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(body.uid)||typeof body.disabled!=='boolean'||body.uid===identity.sub)
          return respond({error:'لا يمكن تعديل الحساب ده'},400);
        const target=await googleRequest(env,auth(env)+':lookup','POST',{localId:[body.uid]});
        const user=target?.users?.[0]; if(!user)return respond({error:'الحساب غير موجود'},404);
        if(String(env.ADMIN_EMAILS).toLowerCase().split(',').includes(String(user.email).toLowerCase()))return respond({error:'حساب إدارة محمي'},400);
        await audit(env,identity,'user-status-requested',body.uid+':'+body.disabled);
        if(body.disabled) await put(env,'operationsUsers/'+body.uid,{disabled:true});
        await googleRequest(env,auth(env)+':update','POST',{localId:body.uid,disableUser:body.disabled});
        if(!body.disabled) await put(env,'operationsUsers/'+body.uid,{disabled:false});
        await audit(env,identity,'user-status-applied',body.uid+':'+body.disabled);
        return respond({ok:true});
      }
      if(path==='/api/admin/settings') {
        let values;try{values=validateSettings(body);}catch{return respond({error:'قيم الإعدادات غير صالحة'},400);}
        await audit(env,identity,'settings-requested','application');
        await put(env,'operationsConfig/current',values);
        settingsCache=values;settingsExpires=Date.now()+5000;
        await audit(env,identity,'settings-applied','application');
        return respond({ok:true,settings:values});
      }
    }
    return respond({error:'Not found'},404);
  }catch{return respond({error:'تعذّر تنفيذ العملية. جرّب تاني.'},503);}
}

export async function deleteOwnAccount(request,env) {
  const respond=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':'*'}});
  const token=request.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
  let identity;
  try{identity=await verifyFirebaseToken(token,env.FIREBASE_PROJECT_ID);}catch{return respond({error:'Authentication required'},401);}
  if(String(env.ADMIN_EMAILS||'').toLowerCase().split(',').includes(String(identity.email||'').toLowerCase()))
    return respond({error:'حساب إدارة المشروع محمي من الحذف داخل التطبيق.'},403);
  if(identity.firebase?.sign_in_provider!=='anonymous' && Math.floor(Date.now()/1000)-identity.auth_time>300)
    return respond({error:'سجّل الدخول بجوجل من جديد لتأكيد الحذف.'},401);
  try{
    await put(env,'operationsUsers/'+identity.sub,{disabled:true,deleting:true});
    // Deny client writes while recursively purging. Repeating the operation is safe.
    async function purge(path) {
      const result=await googleRequest(env,db(env)+'/'+path+':listCollectionIds','POST',{pageSize:100});
      if(result?.nextPageToken)throw new Error('Unexpected collection count');
      for(const collectionId of result?.collectionIds||[]) {
        while(true){
          const page=await query(env,path,collectionId,100);
          if(!page.length)break;
          for(const doc of page)await purge(path+'/'+collectionId+'/'+doc.id);
        }
      }
      await googleRequest(env,db(env)+'/'+path,'DELETE');
    }
    await purge('users/'+identity.sub);
    // Purge per-account activity identifiers as well; aggregate daily totals remain.
    while (true) {
      const matches=await googleRequest(env,db(env)+':runQuery','POST',{structuredQuery:{
        from:[{collectionId:'users',allDescendants:true}],
        where:{fieldFilter:{field:{fieldPath:'uid'},op:'EQUAL',value:{stringValue:identity.sub}}},limit:100}});
      const docs=(matches||[]).filter(v=>v.document).map(v=>v.document.name);
      if(!docs.length)break;
      for(const name of docs){
        if(!name.startsWith(`projects/${env.FIREBASE_PROJECT_ID}/databases/maalish/documents/operationsActivity/`))throw new Error('Unexpected activity path');
        await googleRequest(env,'https://firestore.googleapis.com/v1/'+name,'DELETE');
      }
    }
    const response=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${encodeURIComponent(env.FIREBASE_WEB_API_KEY)}`,{
      method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({idToken:token}),signal:AbortSignal.timeout(8000)});
    if(!response.ok)throw new Error('Account deletion incomplete');
    return respond({ok:true});
  }catch{return respond({error:'الحذف ما اكتملش. حسابك مقفول مؤقتًا لمنع أي حفظ جديد؛ جرّب الحذف تاني.'},503);}
}
