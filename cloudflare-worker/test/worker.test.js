import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';
import { verifyFirebaseToken } from '../src/auth.js';
const project = 'maalish-test';
const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1,0,1]), hash: 'SHA-256' }, true, ['sign','verify']);
const jwk = { ...await crypto.subtle.exportKey('jwk', pair.publicKey), kid: 'test-key', alg: 'RS256' };
const encode = v => Buffer.from(JSON.stringify(v)).toString('base64url');
async function token(overrides = {}) {
  const now = Math.floor(Date.now()/1000);
  const payload = `${encode({ alg: 'RS256', kid: 'test-key' })}.${encode({ aud: project, iss: `https://securetoken.google.com/${project}`, sub: 'guest-1', iat: now-10, auth_time: now-10, exp: now+3600, ...overrides })}`;
  return `${payload}.${Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, new TextEncoder().encode(payload))).toString('base64url')}`;
}
const env = { FIREBASE_PROJECT_ID: project, GEMINI_API_KEY: 'test-secret', CHAT_RATE_LIMITER: { limit: async () => ({ success: true }) } };
const reply = { text: 'أنا سامعك', expression: 'listening', categories: [], memoryCandidates: [], intensity: 5 };
const originalFetch = globalThis.fetch;
globalThis.fetch = async url => {
  if (String(url).includes('/jwk/')) return Response.json({ keys: [jwk] });
  if (String(url).includes('generativelanguage.googleapis.com')) return Response.json({ candidates: [{ content: { parts: [{ text: JSON.stringify(reply) }] } }] });
  throw new Error('Unexpected external request');
};
function chat(body = { messages: [{ role:'user', content:'أنا تعبان' }] }, auth) {
  return new Request('https://example.com/chat', { method:'POST', headers: { 'content-type':'application/json', ...(auth ? {authorization:`Bearer ${auth}`} : {}) }, body: JSON.stringify(body) });
}
test('signed Firebase token is required, including for guests', async () => {
  assert.equal((await worker.fetch(chat(),env)).status,401);
  assert.equal((await worker.fetch(chat(undefined,'invalid'),env)).status,401);
  const valid = await token();
  assert.equal((await verifyFirebaseToken(valid,project)).sub,'guest-1');
  const response = await worker.fetch(chat(undefined,valid),env);
  assert.equal(response.status,200);
  assert.match(response.headers.get('server-timing'), /auth;dur=/);
  assert.match(response.headers.get('server-timing'), /gemini;dur=/);
  assert.match(response.headers.get('server-timing'), /total;dur=/);
  assert.ok(response.headers.get('x-request-id'));
  assert.equal(response.headers.get('server-timing').includes('test-secret'),false);
});
test('wrong audience, expired and tampered tokens fail', async () => {
  await assert.rejects(verifyFirebaseToken(await token({aud:'other'}),project));
  await assert.rejects(verifyFirebaseToken(await token({exp:1}),project));
  const valid = await token();
  const parts = valid.split('.');
  const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
  parts[1] = encode({...claims, sub:'attacker'});
  await assert.rejects(verifyFirebaseToken(parts.join('.'),project));
});
test('rate limit, size limit and malformed JSON are enforced', async () => {
  const valid = await token();
  assert.equal((await worker.fetch(chat(undefined,valid),{...env,CHAT_RATE_LIMITER:{limit:async()=>({success:false})}})).status,429);
  assert.equal((await worker.fetch(chat({messages:[],padding:'x'.repeat(66000)},valid),env)).status,413);
  const req = new Request('https://example.com/chat',{method:'POST',headers:{authorization:`Bearer ${valid}`},body:'{'});
  assert.equal((await worker.fetch(req,env)).status,400);
});
test('acute safety flag overrides model metadata', async () => {
  const response = await worker.fetch(chat({messages:[{role:'user',content:'kill myself'}]},await token()),env);
  const data = await response.json();
  assert.equal(data.safetyMode,true); assert.equal(data.need,'safety');
});
test('unconfigured worker fails closed', async () => {
  assert.equal((await worker.fetch(chat(),{})).status,503);
  assert.equal((await worker.fetch(chat(),{GEMINI_API_KEY:'x'})).status,503);
});

test('consecutive user messages after a failed reply keep one provider turn', async () => {
  const previous=globalThis.fetch;let contents;
  globalThis.fetch=async(url,options)=>{
    if(String(url).includes('generativelanguage.googleapis.com'))contents=JSON.parse(options.body).contents;
    return previous(url,options);
  };
  try{
    const response=await worker.fetch(chat({messages:[{role:'user',content:'first'},{role:'user',content:'follow-up'}]},await token()),env);
    assert.equal(response.status,200);assert.equal(contents.length,1);
    assert.equal(contents[0].parts.length,2);
    assert.equal(contents[0].parts[1].text,'follow-up');
  }finally{globalThis.fetch=previous;}
});

test('admin access requires verified Google identity, allowlist and recent live account', async () => {
  const pem = '-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';
  const adminEnv={...env,ADMIN_EMAILS:'owner@example.com',GOOGLE_OPERATIONS_CREDENTIALS:JSON.stringify({client_email:'operations@example.com',private_key:pem})};
  const previous=globalThis.fetch;
  let disabled=false;const writes=[];
  globalThis.fetch=async(url,options={})=>{
    const path=String(url);
    if(path.includes('/jwk/'))return Response.json({keys:[jwk]});
    if(path.includes('oauth2.googleapis.com'))return Response.json({access_token:'fake-operations-token',expires_in:3600});
    if(path.includes('accounts:lookup')){
      const body=JSON.parse(options.body);
      return Response.json({users:[{localId:body.localId?.[0]||'target',email:body.localId?.[0]==='guest-1'?'owner@example.com':'user@example.com',disabled,validSince:'1'}]});
    }
    if(path.includes('accounts:batchGet'))return Response.json({users:[{localId:'target',email:'user@example.com',passwordHash:'MUST NOT LEAK',salt:'PRIVATE',providerUserInfo:[{providerId:'google.com'}]}]});
    if(path.includes(':queryAccounts'))return Response.json({recordsCount:'2'});
    if(path.includes('accounts:update')){writes.push({url:path,body:JSON.parse(options.body)});return Response.json({localId:'target'});}
    if(path.includes('firestore.googleapis.com')){
      if(path.endsWith(':runAggregationQuery'))return Response.json([{result:{aggregateFields:{total:{integerValue:'6'}}}}]);
      if(path.endsWith(':runQuery'))return Response.json([]);
      writes.push({url:path,body:options.body?JSON.parse(options.body):null});return Response.json({});
    }
    throw new Error('Unexpected admin request');
  };
  const adminClaims={email:'owner@example.com',email_verified:true,firebase:{sign_in_provider:'google.com'}};
  async function request(claims=adminClaims,path='/api/admin/users',body,origin='https://example.com'){
    const signed=await token(claims);
    return worker.fetch(new Request('https://example.com'+path,{method:body?'POST':'GET',headers:{authorization:`Bearer ${signed}`,origin,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),adminEnv);
  }
  try{
    assert.equal((await request({})).status,403);
    assert.equal((await request({...adminClaims,email:'outsider@example.com'})).status,403);
    assert.equal((await request({...adminClaims,email_verified:false})).status,403);
    assert.equal((await request({...adminClaims,firebase:{sign_in_provider:'anonymous'}})).status,403);
    assert.equal((await request({...adminClaims,auth_time:Math.floor(Date.now()/1000)-1900})).status,403);
    disabled=true;assert.equal((await request()).status,403);disabled=false;
    const allowed=await request();assert.equal(allowed.status,200);
    const body=await allowed.json();assert.equal(body.users[0].email,'user@example.com');
    assert.equal(JSON.stringify(body).includes('MUST NOT LEAK'),false);
    assert.equal(JSON.stringify(body).includes('PRIVATE'),false);
    assert.equal((await request(adminClaims,'/api/admin/user-status',{uid:'target',disabled:true},'https://evil.example')).status,403);
    assert.equal((await request(adminClaims,'/api/admin/user-status',{uid:'guest-1',disabled:true})).status,400);
    assert.equal((await request(adminClaims,'/api/admin/settings',{isAdmin:true})).status,400);
    assert.equal((await request(adminClaims,'/api/admin/user-status',{uid:'target',disabled:true})).status,200);
    assert.ok(writes.some(w=>w.url.includes('accounts:update')&&w.body.disableUser===true));
    assert.ok(writes.some(w=>w.url.includes('operationsUsers/target')&&w.body.fields.disabled.booleanValue));
    assert.ok(writes.filter(w=>w.url.includes('operationsAudit/')).length>=2);
    const settings={maintenance:false,maintenanceMessage:'Soon',announcement:'Hello',temperature:.65,maxOutputTokens:1100,inputPrice:0,outputPrice:0};
    assert.equal((await request(adminClaims,'/api/admin/settings',settings)).status,200);
    assert.equal((await request(adminClaims,'/api/admin/settings',{...settings,temperature:9})).status,400);
    const overview=await request(adminClaims,'/api/admin/overview');assert.equal(overview.status,200);
    assert.equal((await overview.json()).totalMessages,6);
  }finally{globalThis.fetch=previous;}
});
