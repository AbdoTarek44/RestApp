import {verifyFirebaseToken} from './auth.js';
import {googleRequest, unpack, accountAllowed} from './operations.js';

export const TOPIC='maalish_updates_v11';
export const TOPICS=['marriage','family','relatives','parenting','relationship','friends','work','money','study','grief','loneliness','self_confidence','future','decision','health_concern','daily_life','other'];
export const BEFORE=['angry','stressed','sad','anxious','lonely','neutral','other','skip'];
export const AFTER=['same','lighter','better','good','skip'];
const base=env=>`https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/maalish/documents`;
const name=(env,path)=>`projects/${env.FIREBASE_PROJECT_ID}/databases/maalish/documents/${path}`;
const f=v=>typeof v==='boolean'?{booleanValue:v}:typeof v==='number'?{integerValue:String(Math.round(v))}:Array.isArray(v)?{arrayValue:{values:v.map(f)}}:{stringValue:String(v)};
const fields=data=>Object.fromEntries(Object.entries(data).map(([k,v])=>[k,f(v)]));
function decode(doc){const result=unpack(doc);for(const[k,v]of Object.entries(doc?.fields||{}))if(v.arrayValue)result[k]=(v.arrayValue.values||[]).map(x=>x.stringValue);return result;}
async function get(env,path){return googleRequest(env,base(env)+'/'+path);}
async function put(env,path,value){return googleRequest(env,base(env)+'/'+path,'PATCH',{fields:fields(value)});}
async function remove(env,path){return googleRequest(env,base(env)+'/'+path,'DELETE');}
async function query(env,collection,where,limit=1000){const rows=await googleRequest(env,base(env)+':runQuery','POST',{
  structuredQuery:{from:[{collectionId:collection}],...(where?{where}:{}),limit}});
  return (rows||[]).filter(v=>v.document).map(v=>({id:v.document.name.split('/').pop(),raw:v.document,...decode(v.document)}));}
const eq=(field,value)=>({fieldFilter:{field:{fieldPath:field},op:'EQUAL',value:f(value)}});
async function body(request){if(Number(request.headers.get('content-length'))>8192)throw new Error('Request too large');const text=await request.text();if(new TextEncoder().encode(text).length>8192)throw new Error('Request too large');return JSON.parse(text);}
const response=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','access-control-allow-origin':'*','x-content-type-options':'nosniff'}});
function validKeys(data,keys){return data&&typeof data==='object'&&!Array.isArray(data)&&Object.keys(data).every(k=>keys.includes(k));}

async function subscribe(env,registration,enabled){
 const url=`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/registrations/${encodeURIComponent(registration)}/topicSubscriptions`;
 try{return await googleRequest(env,url+(enabled?'?topic_name='+TOPIC:'/'+TOPIC+'?allowMissing=true'),enabled?'POST':'DELETE',enabled?{}:undefined);}
 catch(error){if(enabled&&error.message.includes('(409)'))return {};throw error;}
}
async function registrationId(token){const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token));return [...new Uint8Array(bytes)].map(v=>v.toString(16).padStart(2,'0')).join('');}
async function devices(env,uid){return query(env,'notificationDevices',uid?eq('ownerId',uid):eq('enabled',true),10000);}
export async function setUserPushStatus(env,uid,disabled){
 const rows=await devices(env,uid);
 for(const device of rows){if(device.enabled){await subscribe(env,device.registration,!disabled);await put(env,'notificationDevices/'+device.id,{ownerId:uid,registration:device.registration,enabled:true,suspended:disabled,updatedAt:Date.now()});}}
}
export async function deleteEngagementData(env,uid){
 const rows=await devices(env,uid);
 for(const d of rows){await subscribe(env,d.registration,false);await remove(env,'notificationDevices/'+d.id);}
 await purgeInsights(env,uid);
}
async function purgeInsights(env,uid){
 while(true){const rows=await query(env,'sessionInsights',eq('ownerId',uid),100);if(!rows.length)break;
  for(const row of rows)await remove(env,'sessionInsights/'+row.id);}
}
export async function handleEngagement(request,env){
 if(request.method!=='POST')return response({error:'Not found'},404);
 let identity;
 try{identity=await verifyFirebaseToken(request.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1],env.FIREBASE_PROJECT_ID);}catch{return response({error:'Authentication required'},401);}
 let data;try{data=await body(request);}catch{return response({error:'Invalid request'},400);}
 const path=new URL(request.url).pathname,uid=identity.sub;
 try{
  const allowed=await accountAllowed(env,identity);
  if(!allowed&&!(path==='/push/register'&&data.enabled===false))return response({error:'Account disabled'},403);
  const limited=await env.CHAT_RATE_LIMITER.limit({key:uid+':engagement'});if(!limited.success)return response({error:'Too many requests'},429);
  if(path==='/push/register'){
   if(!validKeys(data,['registration','enabled'])||typeof data.registration!=='string'||data.registration.length<20||data.registration.length>4096||typeof data.enabled!=='boolean')return response({error:'Invalid registration'},400);
   const id=await registrationId(data.registration);
   const existing=await get(env,'notificationDevices/'+id);
   if(!data.enabled){
    if(existing&&decode(existing).ownerId!==uid)return response({error:'Not found'},404);
    await subscribe(env,data.registration,false);await remove(env,'notificationDevices/'+id);
    return response({ok:true,enabled:false});
   }
   const own=await devices(env,uid);if(!own.some(v=>v.id===id)&&own.length>=10)return response({error:'Device limit reached'},409);
   await subscribe(env,data.registration,true);
   await put(env,'notificationDevices/'+id,{ownerId:uid,registration:data.registration,enabled:true,suspended:false,updatedAt:Date.now()});
   return response({ok:true,enabled:true});
  }
  if(path==='/insights/consent'){
   if(!validKeys(data,['enabled'])||typeof data.enabled!=='boolean')return response({error:'Invalid consent'},400);
   await put(env,`users/${uid}/preferences/insights`,{enabled:data.enabled});
   if(!data.enabled)await purgeInsights(env,uid);
   return response({ok:true});
  }
  if(path==='/insights/session'){
   if(!validKeys(data,['runId','phase','beforeMood','afterMood','categories'])||typeof data.runId!=='string'||!/^[A-Za-z0-9]{20,40}$/.test(data.runId)||!['start','progress','finish'].includes(data.phase)||!BEFORE.includes(data.beforeMood)||!AFTER.includes(data.afterMood)||!Array.isArray(data.categories)||data.categories.length>6||data.categories.some(v=>!TOPICS.includes(v)))return response({error:'Invalid session event'},400);
   const consentDoc=await get(env,`users/${uid}/preferences/insights`),consent=decode(consentDoc);if(consent.enabled!==true)return response({error:'Consent required'},403);
   const eventPath='sessionInsights/'+uid+'_'+data.runId;
   const old=await get(env,eventPath),previous=decode(old);
   if(previous.finished===true)return response({ok:true,alreadyFinished:true});
   const finished=data.phase==='finish';
   const value={ownerId:uid,runId:data.runId,version:11,startedAt:previous.startedAt||Date.now(),
    updatedAt:Date.now(),finished,beforeMood:previous.beforeMood||data.beforeMood,
    afterMood:finished?data.afterMood:'skip',categories:[...new Set([...(previous.categories||[]),...data.categories])].slice(0,6)};
   try{await googleRequest(env,base(env)+':commit','POST',{writes:[
    {update:{name:name(env,`users/${uid}/preferences/insights`),fields:fields({enabled:true})},currentDocument:{updateTime:consentDoc.updateTime}},
    {update:{name:name(env,eventPath),fields:fields(value)},
     currentDocument:old?{updateTime:old.updateTime}:{exists:false}}]});}
   catch(error){if(error.message.includes('(409)')||error.message.includes('(412)'))return response({error:'Retry session event'},409);throw error;}
   return response({ok:true});
  }
  return response({error:'Not found'},404);
 }catch{return response({error:'الخدمة مش متاحة مؤقتًا. جرّب تاني.'},503);}
}

export function aggregateInsights(rows){
 const users=new Set(),byTopic=Object.fromEntries(TOPICS.map(v=>[v,{sessions:0,users:new Set()}])),byMood=Object.fromEntries(BEFORE.map(v=>[v,{sessions:0,users:new Set()}]));
 const after=Object.fromEntries(AFTER.map(v=>[v,0])),matrix={},daily={};let completed=0,rated=0,improved=0;
 for(const row of rows){
  users.add(row.ownerId);const day=new Date(row.startedAt).toISOString().slice(0,10);
  daily[day]??={day,started:0,completed:0,rated:0,improved:0};daily[day].started++;
  if(byMood[row.beforeMood]){byMood[row.beforeMood].sessions++;byMood[row.beforeMood].users.add(row.ownerId);}
  for(const topic of new Set(row.categories||[])){if(byTopic[topic]){byTopic[topic].sessions++;byTopic[topic].users.add(row.ownerId);}}
  if(row.finished){completed++;daily[day].completed++;const outcome=AFTER.includes(row.afterMood)?row.afterMood:'skip';after[outcome]++;
   if(outcome!=='skip'){rated++;daily[day].rated++;if(outcome!=='same'){improved++;daily[day].improved++;}
    const key=row.beforeMood+'_'+outcome;matrix[key]=(matrix[key]||0)+1;}
  }
 }
 const simplify=b=>Object.fromEntries(Object.entries(b).map(([k,v])=>[k,{sessions:v.sessions,users:v.users.size}]));
 return {started:rows.length,participants:users.size,completed,rated,improved,unratedCompleted:completed-rated,
  noCompletion:rows.length-completed,improvementRate:rated?improved/rated:null,
  topics:simplify(byTopic),before:simplify(byMood),after,matrix,daily:Object.values(daily).sort((a,b)=>a.day.localeCompare(b.day))};
}
function range(url){
 const start=url.searchParams.get('from')||new Date(Date.now()-29*86400000).toISOString().slice(0,10),end=url.searchParams.get('to')||new Date().toISOString().slice(0,10);
 if(!/^\d{4}-\d{2}-\d{2}$/.test(start)||!/^\d{4}-\d{2}-\d{2}$/.test(end))throw new Error('Invalid range');
 const from=Date.parse(start+'T00:00:00Z'),until=Date.parse(end+'T00:00:00Z')+86400000;
 if(!Number.isFinite(from)||!Number.isFinite(until)||until<=from||until-from>91*86400000)throw new Error('Invalid range');return {from,until,start,end};
}
async function audit(env,identity,action,target){await put(env,'operationsAudit/'+crypto.randomUUID(),{admin:identity.email,action,target,at:new Date().toISOString()});}
function validateCampaign(data){
 if(!validKeys(data,['title','body','target','uid'])||typeof data.title!=='string'||!data.title.trim()||data.title.length>70||typeof data.body!=='string'||!data.body.trim()||data.body.length>180||!['all','user'].includes(data.target)||typeof data.uid!=='string'||(data.target==='user'&&!/^[A-Za-z0-9_-]{1,128}$/.test(data.uid)))throw new Error('Invalid notification');
 return {title:data.title.trim(),body:data.body.trim(),target:data.target,uid:data.target==='all'?'':data.uid};
}
function fcmMessage(value,registration){return {
 ...(registration?{token:registration}:{topic:TOPIC}),notification:{title:value.title,body:value.body},
 data:{campaignId:value.id,screen:'home'},android:{priority:'HIGH',ttl:'86400s',notification:{channelId:'maalish_updates',icon:'ic_stat_maalish',visibility:'PRIVATE',tag:value.id}}};}
async function sendFcm(env,value){const result=await googleRequest(env,`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`,'POST',value);if(!result)throw new Error('FCM request failed (404)');return result;}
export async function validatePush(env){return sendFcm(env,{
 validate_only:true,message:fcmMessage({id:'validation-only',title:'Maalish validation',body:'Synthetic validation; no delivery.'})});}
export async function adminEngagement(request,env,identity){
 const url=new URL(request.url),path=url.pathname;
 if(request.method==='POST'&&request.headers.get('origin')!==url.origin)return response({error:'Origin rejected'},403);
 try{
  if(path==='/api/admin/insights'&&request.method==='GET'){
   let selected;try{selected=range(url);}catch{return response({error:'اختار مدة لا تزيد عن ٩٠ يومًا.'},400);}
   const rows=await query(env,'sessionInsights',{compositeFilter:{op:'AND',filters:[
     {fieldFilter:{field:{fieldPath:'startedAt'},op:'GREATER_THAN_OR_EQUAL',value:f(selected.from)}},
     {fieldFilter:{field:{fieldPath:'startedAt'},op:'LESS_THAN',value:f(selected.until)}}]}},10000);
   return response({...aggregateInsights(rows),from:selected.start,to:selected.end,capped:rows.length===10000,limit:10000});
  }
  if(path==='/api/admin/notifications'&&request.method==='GET'){
   const [campaigns,registered]=await Promise.all([query(env,'operationsCampaigns',null,1000),devices(env)]);
   return response({devices:registered.filter(v=>v.enabled&&!v.suspended).length,
    campaigns:campaigns.sort((a,b)=>b.createdAt-a.createdAt).slice(0,30).map(c=>({id:c.id,title:c.title,body:c.body,target:c.target,uid:c.uid,status:c.status,createdAt:c.createdAt,accepted:c.accepted||0,failed:c.failed||0,unknown:c.unknown||0,registeredDevices:c.registeredDevices||0}))});
  }
  if(request.method==='POST'){
   let data;try{data=await body(request);}catch{return response({error:'Invalid request'},400);}
   if(path==='/api/admin/notifications/preview'){
    let value;try{value=validateCampaign(data);}catch{return response({error:'راجع عنوان الإشعار والرسالة والحساب المستهدف.'},400);}
    const targets=(await devices(env,value.target==='user'?value.uid:undefined)).filter(d=>d.enabled&&!d.suspended);
    const id=crypto.randomUUID(),draft={...value,id,creator:identity.email,createdAt:Date.now(),status:'draft',expiresAt:Date.now()+600000,registeredDevices:targets.length};
    await put(env,'operationsCampaigns/'+id,draft);await audit(env,identity,'notification-preview',id);
    return response({id,...value,registeredDevices:targets.length,expiresAt:draft.expiresAt});
   }
   if(path==='/api/admin/notifications/send'){
    if(!validKeys(data,['campaignId','confirm'])||typeof data.campaignId!=='string'||!/^[a-f0-9-]{36}$/.test(data.campaignId)||data.confirm!==true)return response({error:'معاينة وتأكيد مطلوبين'},400);
    const path='operationsCampaigns/'+data.campaignId,doc=await get(env,path),draft=decode(doc);
    if(!doc||draft.creator!==identity.email)return response({error:'المعاينة غير موجودة'},404);
    if(draft.status!=='draft')return response({ok:true,status:draft.status,alreadyProcessed:true});
    if(draft.expiresAt<Date.now())return response({error:'المعاينة انتهت؛ اعمل معاينة جديدة.'},409);
    const targets=(await devices(env,draft.target==='user'?draft.uid:undefined)).filter(d=>d.enabled&&!d.suspended);
    if(!targets.length)return response({error:'مفيش أجهزة مفعّلة للإشعارات في المجموعة دي.'},409);
    try{await googleRequest(env,base(env)+':commit','POST',{writes:[{update:{name:name(env,path),fields:fields({...draft,status:'sending'})},currentDocument:{updateTime:doc.updateTime}}]});}
    catch{return response({error:'الإرسال اتبدأ بالفعل؛ حدّث السجل.'},409);}
    await audit(env,identity,'notification-send-started',draft.id);
    let accepted=0,failed=0,unknown=0;
    const batches=draft.target==='all'?[null]:targets.map(v=>v.registration);
    for(const registration of batches){
     try{await sendFcm(env,{message:fcmMessage(draft,registration)});accepted++;}
     catch(error){if(/\((400|401|403|404|429)\)/.test(error.message))failed++;else unknown++;}
    }
    const status=unknown?'unknown':accepted?(failed?'partial':'accepted'):'failed';
    await put(env,path,{...draft,status,accepted,failed,unknown,registeredDevices:targets.length});
    await audit(env,identity,'notification-send-'+status,draft.id);
    return response({ok:true,status,accepted,failed,unknown,registeredDevices:targets.length});
   }
  }
  return response({error:'Not found'},404);
 }catch{return response({error:'تعذّر تحميل أو حفظ البيانات. جرّب تاني.'},503);}
}
