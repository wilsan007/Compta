// Passerelle d'audit : /rest/v1 -> PostgREST, /auth/v1 -> GoTrue minimal (JWT HS256).
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';

const DIR = new URL('.', import.meta.url).pathname;
const SECRET = fs.readFileSync(DIR + 'jwt_secret', 'utf8').trim();
const USERS = JSON.parse(fs.readFileSync(DIR + 'rig_users.json', 'utf8'));
const PGRST = 'http://localhost:3399';
const PORT = 54399;
const LOG = fs.createWriteStream(DIR + 'gateway.log', { flags: 'a' });

const b64u = (b) => Buffer.from(b).toString('base64url');
export function sign(payload) {
  const h = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64u(JSON.stringify(payload));
  const s = crypto.createHmac('sha256', SECRET).update(`${h}.${p}`).digest('base64url');
  return `${h}.${p}.${s}`;
}
function verify(tok) {
  try {
    const [h, p, s] = tok.split('.');
    const exp = crypto.createHmac('sha256', SECRET).update(`${h}.${p}`).digest('base64url');
    if (exp !== s) return null;
    return JSON.parse(Buffer.from(p, 'base64url').toString());
  } catch { return null; }
}
function userObj(u) {
  return { id: u.id, aud: 'authenticated', role: 'authenticated', email: u.email,
    email_confirmed_at: '2026-01-01T00:00:00Z', app_metadata: { provider: 'email' },
    user_metadata: { name: u.name }, created_at: '2026-01-01T00:00:00Z' };
}
function session(u) {
  const now = Math.floor(Date.now() / 1000);
  const access_token = sign({ sub: u.id, role: 'authenticated', email: u.email, aud: 'authenticated',
    iat: now, exp: now + 3600 * 8, user_metadata: { name: u.name } });
  return { access_token, token_type: 'bearer', expires_in: 3600 * 8, expires_at: now + 3600 * 8,
    refresh_token: 'rt-' + u.id, user: userObj(u) };
}
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PATCH,PUT,DELETE,OPTIONS,HEAD',
  'Access-Control-Expose-Headers': 'Content-Range, Content-Location, Preference-Applied',
};
function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json', ...cors });
  res.end(JSON.stringify(obj));
}
const readBody = (req) => new Promise((r) => { const c = []; req.on('data', (d) => c.push(d)); req.on('end', () => r(Buffer.concat(c))); });

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
  const body = await readBody(req);
  if (url.pathname === '/__sweep2.js' || url.pathname === '/__routes2.json') { res.writeHead(200, { 'Content-Type': 'application/javascript', ...cors }); return res.end(fs.readFileSync(DIR + url.pathname.slice(3))); }
  if (url.pathname === '/__sweep.js') { res.writeHead(200, { 'Content-Type': 'text/javascript', ...cors }); return res.end(fs.readFileSync(DIR + 'sweep.js')); }
  if (url.pathname.startsWith('/rest/v1')) {
    const target = PGRST + url.pathname.slice('/rest/v1'.length) + url.search;
    const headers = {};
    for (const [k, v] of Object.entries(req.headers)) {
      if (['host', 'connection', 'content-length', 'apikey', 'x-client-info', 'origin', 'referer'].includes(k)) continue;
      headers[k] = v;
    }
    const auth = headers['authorization'] || '';
    // apikey anonyme -> pas de JWT utilisateur : on retire l'en-tête (rôle anon)
    if (!verify(auth.replace(/^Bearer /, ''))?.sub) delete headers['authorization'];
    const r = await fetch(target, { method: req.method, headers, body: ['GET', 'HEAD'].includes(req.method) ? undefined : body });
    const buf = Buffer.from(await r.arrayBuffer());
    const out = { ...cors };
    for (const k of ['content-type', 'content-range', 'preference-applied', 'content-location']) if (r.headers.get(k)) out[k] = r.headers.get(k);
    if (r.status >= 400) LOG.write(`${new Date().toISOString()} ${r.status} ${req.method} ${url.pathname}${url.search} :: ${buf.toString().slice(0, 400)}\n`);
    res.writeHead(r.status, out); return res.end(buf);
  }
  if (url.pathname === '/auth/v1/token') {
    const b = body.length ? JSON.parse(body.toString()) : {};
    const gt = url.searchParams.get('grant_type');
    let u;
    if (gt === 'password') u = USERS.find((x) => x.email === b.email && x.password === b.password);
    if (gt === 'refresh_token') u = USERS.find((x) => 'rt-' + x.id === b.refresh_token);
    if (!u) return json(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials' });
    return json(res, 200, session(u));
  }
  if (url.pathname === '/auth/v1/user') {
    const p = verify((req.headers.authorization || '').replace(/^Bearer /, ''));
    const u = p && USERS.find((x) => x.id === p.sub);
    return u ? json(res, 200, userObj(u)) : json(res, 401, { msg: 'invalid JWT' });
  }
  if (url.pathname.startsWith('/auth/v1/logout')) { res.writeHead(204, cors); return res.end(); }
  if (url.pathname.startsWith('/auth/v1/')) return json(res, 200, {});
  LOG.write(`${new Date().toISOString()} 503 ${req.method} ${url.pathname} (hors banc)\n`);
  return json(res, 503, { error: 'unavailable_in_audit_rig', path: url.pathname });
}).listen(PORT, () => console.log('gateway on ' + PORT));
