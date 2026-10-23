const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
let cachedKeys;
let expiresAt = 0;
function decode(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('Invalid token');
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
}
export async function verifyFirebaseToken(token, projectId) {
  if (!projectId || !token || token.length > 8192) throw new Error('Invalid token');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Invalid token');
  const header = JSON.parse(new TextDecoder().decode(decode(parts[0])));
  const claims = JSON.parse(new TextDecoder().decode(decode(parts[1])));
  const now = Math.floor(Date.now() / 1000);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string' ||
      claims.aud !== projectId || claims.iss !== `https://securetoken.google.com/${projectId}` ||
      typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 128 ||
      !Number.isFinite(claims.exp) || claims.exp <= now ||
      !Number.isFinite(claims.iat) || claims.iat > now ||
      !Number.isFinite(claims.auth_time) || claims.auth_time > now) throw new Error('Invalid token');
  if (!cachedKeys || Date.now() >= expiresAt) {
    const response = await fetch(JWKS_URL, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error('Identity service unavailable');
    const data = await response.json();
    if (!Array.isArray(data.keys)) throw new Error('Invalid identity keys');
    cachedKeys = data.keys;
    const ttl = Number(response.headers.get('cache-control')?.match(/max-age=(\d+)/)?.[1] || 300);
    expiresAt = Date.now() + Math.min(ttl, 3600) * 1000;
  }
  const jwk = cachedKeys.find(key => key.kid === header.kid);
  if (!jwk) throw new Error('Invalid token');
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, decode(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  if (!valid) throw new Error('Invalid token');
  return claims;
}
