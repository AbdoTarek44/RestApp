import {test,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {aggregateInsights,adminEngagement,handleEngagement,deleteEngagementData,setUserPushStatus,validatePush,TOPIC} from '../src/engagement.js';
import worker from '../src/index.js';

const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const jwk={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'engagement-test',alg:'RS256'};
const pem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';
const env={FIREBASE_PROJECT_ID:'engagement-test',ADMIN_EMAILS:'owner@example.com',GOOGLE_OPERATIONS_CREDENTIALS:JSON.stringify({client_email:'fake@example.com',private_key:pem}),CHAT_RATE_LIMITER:{limit:async()=>({success:true})}};
const admin={email:'owner@example.com',sub:'admin'};
const prefix='projects/engagement-test/databases/maalish/documents/';
const store=new Map(),sends=[],subscriptions=[];let sequence=0,failSend=false,revokeDuringCommit=false;
const field=v=>typeof v==='boolean'?{booleanValue:v}:typeof v==='number'?{integerValue:String(v)}:Array.isArray(v)?{arrayValue:{values:v.map(field)}}:{stringValue:v};
function seed(path,value){const doc={name:prefix+path,fields:Object.fromEntries(Object.entries(value).map(([k,v])=>[k,field(v)])),updateTime:'revision-'+(++sequence)};store.set(path,doc);return doc;}
const value=v=>v?.stringValue??v?.booleanValue??(v?.integerValue!==undefined?Number(v.integerValue):null);
function matches(doc,filter){if(!filter)return true;if(filter.compositeFilter)return filter.compositeFilter.filters.every(f=>matches(doc,f));const f=filter.fieldFilter,a=value(doc.fields[f.field.fieldPath]),b=value(f.value);return f.op==='EQUAL'?a===b:f.op==='GREATER_THAN_OR_EQUAL'?a>=b:f.op==='LESS_THAN'?a<b:true;}
globalThis.fetch=async(url,options={})=>{
 const path=String(url);
 if(path.includes('/jwk/'))return Response.json({keys:[jwk]});
 if(path.includes('oauth2.googleapis.com'))return Response.json({access_token:'test-operations-token',expires_in:3600});
 const body=options.body?JSON.parse(options.body):{};
 if(path.includes('fcm.googleapis.com')){
  if(path.includes('/messages:send')){if(failSend)throw new DOMException('Timed out','TimeoutError');if(!body.validate_only)sends.push(body.message);return Response.json({name:'projects/engagement-test/messages/fake'});}
  subscriptions.push({method:options.method,url:path});return Response.json({topic_name:TOPIC});
 }
 if(path.includes('firestore.googleapis.com')){
  if(path.endsWith(':runQuery')){const q=body.structuredQuery;return Response.json([...store.values()].filter(d=>d.name.slice(prefix.length).split('/')[0]===q.from[0].collectionId&&d.name.slice(prefix.length).split('/').length===2&&matches(d,q.where)).slice(0,q.limit||1000).map(document=>({document})));}
  if(path.endsWith(':commit')){
   if(revokeDuringCommit){revokeDuringCommit=false;seed('users/user1/preferences/insights',{enabled:false});}
   for(const w of body.writes){const key=w.update.name.slice(prefix.length),old=store.get(key);if(w.currentDocument?.exists===false&&old||w.currentDocument?.updateTime&&w.currentDocument.updateTime!==old?.updateTime)return Response.json({error:'conflict'},{status:409});}
   for(const w of body.writes)store.set(w.update.name.slice(prefix.length),{...w.update,updateTime:'revision-'+(++sequence)});
   return Response.json({writeResults:[]});
  }
  const key=decodeURIComponent(path.split('/documents/')[1]?.split('?')[0]||'');
  if(options.method==='PATCH'){store.set(key,{name:prefix+key,fields:body.fields,updateTime:'revision-'+(++sequence)});return Response.json(store.get(key));}
  if(options.method==='DELETE'){store.delete(key);return Response.json({});}
  return store.has(key)?Response.json(store.get(key)):Response.json({error:'not found'},{status:404});
 }
 throw new Error('Unexpected network request: '+path);
};
beforeEach(()=>{store.clear();sends.length=0;subscriptions.length=0;failSend=false;revokeDuringCommit=false;});
const encode=v=>Buffer.from(JSON.stringify(v)).toString('base64url');
async function token(uid='user1',extra={}){const now=Math.floor(Date.now()/1000),text=encode({alg:'RS256',kid:jwk.kid})+'.'+encode({aud:env.FIREBASE_PROJECT_ID,iss:'https://securetoken.google.com/'+env.FIREBASE_PROJECT_ID,sub:uid,iat:now-1,auth_time:now-1,exp:now+3600,firebase:{sign_in_provider:'anonymous'},...extra});return text+'.'+Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(text))).toString('base64url');}
async function user(path,body,uid='user1'){return handleEngagement(new Request('https://example.com'+path,{method:'POST',headers:{authorization:'Bearer '+await token(uid),'content-type':'application/json'},body:JSON.stringify(body)}),env);}
function owner(path,body,origin='https://example.com'){return adminEngagement(new Request('https://example.com/api/admin/'+path,{method:body?'POST':'GET',headers:{origin,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),env,admin);}
const event={runId:'abcdefghijklmnopqrstuvwx',phase:'start',beforeMood:'angry',afterMood:'skip',categories:['work']};
const notice={title:'خبر من معلش',body:'رسالة عامة للاختبار',target:'all',uid:''};
const registration='fake-registration-secret-for-unit-test';

test('insight denominator excludes unfinished and skipped endings, and counts unique accounts',()=>{
 const now=Date.now(),rows=[{ownerId:'one',startedAt:now,beforeMood:'angry',afterMood:'better',finished:true,categories:['work','family']},{ownerId:'one',startedAt:now,beforeMood:'angry',afterMood:'same',finished:true,categories:['work']},{ownerId:'two',startedAt:now,beforeMood:'skip',afterMood:'skip',finished:true,categories:['work']},{ownerId:'three',startedAt:now,beforeMood:'sad',finished:false,categories:[]}];
 const result=aggregateInsights(rows);assert.equal(result.started,4);assert.equal(result.participants,3);assert.equal(result.rated,2);assert.equal(result.improvementRate,.5);assert.equal(result.unratedCompleted,1);assert.equal(result.noCompletion,1);assert.deepEqual(result.topics.work,{sessions:3,users:2});assert.equal(result.before.angry.users,1);assert.equal(JSON.stringify(result).includes('ownerId'),false);
});
test('survey events require authentication, explicit consent and fixed vocabulary',async()=>{
 assert.equal((await handleEngagement(new Request('https://example.com/insights/session',{method:'POST',body:'{}'}),env)).status,401);
 assert.equal((await user('/insights/session',event)).status,403);
 assert.equal((await user('/insights/session',{...event,categories:['Private personal title']})).status,400);
 assert.equal((await user('/insights/session',{...event,ownerId:'victim'})).status,400);
});
test('session events are idempotent, cannot be rewound and separate each owner',async()=>{
 assert.equal((await user('/insights/consent',{enabled:true})).status,200);
 assert.equal((await user('/insights/session',event)).status,200);
 assert.equal((await user('/insights/session',{...event,phase:'progress',categories:['family']})).status,200);
 assert.equal((await user('/insights/session',{...event,phase:'finish',afterMood:'better'})).status,200);
 assert.equal((await user('/insights/session',event)).status,200);
 const doc=store.get('sessionInsights/user1_'+event.runId);assert.equal(doc.fields.finished.booleanValue,true);assert.equal(doc.fields.afterMood.stringValue,'better');assert.equal(doc.fields.categories.arrayValue.values.length,2);
 assert.equal((await user('/insights/consent',{enabled:true},'user2')).status,200);
 assert.equal((await user('/insights/session',event,'user2')).status,200);
 assert.equal((await user('/insights/consent',{enabled:false})).status,200);
 assert.equal(store.has('sessionInsights/user1_'+event.runId),false);assert.equal(store.has('sessionInsights/user2_'+event.runId),true);
});
test('revoking consent during an in-flight event prevents recreating the event',async()=>{
 await user('/insights/consent',{enabled:true});revokeDuringCommit=true;
 assert.equal((await user('/insights/session',event)).status,409);
 assert.equal(store.has('sessionInsights/user1_'+event.runId),false);
});
test('push registration is owner-scoped, opt-in and blocks disabled users',async()=>{
 assert.equal((await user('/push/register',{registration,enabled:true})).status,200);
 assert.equal(store.size,1);assert.equal(subscriptions[0].method,'POST');
 assert.equal((await user('/push/register',{registration,enabled:false},'user2')).status,404);
 seed('operationsUsers/user1',{disabled:true});
 assert.equal((await user('/push/register',{registration,enabled:true})).status,403);
 assert.equal((await user('/push/register',{registration,enabled:false})).status,200);
 assert.equal([...store.keys()].some(k=>k.startsWith('notificationDevices/')),false);
});
test('notification preview never sends, confirmation is idempotent and secrets are redacted',async()=>{
 await user('/push/register',{registration,enabled:true});
 assert.equal((await owner('notifications/preview',notice,'https://evil.example')).status,403);
 const draft=await(await owner('notifications/preview',notice)).json();assert.equal(sends.length,0);assert.equal(draft.registeredDevices,1);
 assert.equal((await owner('notifications/send',{campaignId:draft.id,confirm:false})).status,400);
 const result=await(await owner('notifications/send',{campaignId:draft.id,confirm:true})).json();assert.equal(result.status,'accepted');assert.equal(sends.length,1);assert.equal(sends[0].topic,TOPIC);
 await owner('notifications/send',{campaignId:draft.id,confirm:true});assert.equal(sends.length,1);
 const history=await(await owner('notifications')).json();assert.equal(JSON.stringify(history).includes(registration),false);
 await validatePush(env);assert.equal(sends.length,1);
});
test('uncertain push result is recorded and never automatically retried',async()=>{
 await user('/push/register',{registration,enabled:true});
 const draft=await(await owner('notifications/preview',notice)).json();failSend=true;
 const first=await(await owner('notifications/send',{campaignId:draft.id,confirm:true})).json();assert.equal(first.status,'unknown');
 failSend=false;const retry=await(await owner('notifications/send',{campaignId:draft.id,confirm:true})).json();assert.equal(retry.alreadyProcessed,true);assert.equal(sends.length,0);
});
test('admin aggregate endpoint returns no raw session data and rejects excessive range',async()=>{
 await user('/insights/consent',{enabled:true});await user('/insights/session',event);
 const result=await(await owner('insights')).json();assert.equal(result.started,1);assert.equal(result.participants,1);assert.equal(JSON.stringify(result).includes('user1'),false);assert.equal(JSON.stringify(result).includes(event.runId),false);
 assert.equal((await owner('insights?from=2020-01-01&to=2026-10-23')).status,400);
 const outsiders=await worker.fetch(new Request('https://example.com/api/admin/insights',{headers:{authorization:'Bearer '+await token('other',{email:'outsider@example.com',email_verified:true})}}),env);assert.equal(outsiders.status,403);
});
test('disabling and deleting an account removes subscriptions and only its insight records',async()=>{
 await user('/push/register',{registration,enabled:true});await user('/insights/consent',{enabled:true});await user('/insights/session',event);
 await setUserPushStatus(env,'user1',true);assert.ok(subscriptions.some(v=>v.method==='DELETE'));
 await setUserPushStatus(env,'user1',false);assert.ok(subscriptions.filter(v=>v.method==='POST').length>=2);
 await deleteEngagementData(env,'user1');assert.equal([...store.keys()].some(k=>k.startsWith('notificationDevices/')||k.startsWith('sessionInsights/')),false);
});
