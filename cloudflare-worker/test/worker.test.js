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
