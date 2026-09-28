// ============================================================
// screen-rig/gateway.mjs — passerelle du banc « chemin de l'écran » (X0)
//
// Le vrai client Supabase du front parle à cette passerelle comme à Supabase :
//   /rest/v1/*  → PostgREST réel (RLS réelle, rôles anon / authenticated)
//   /auth/v1/*  → GoTrue minimal : mot de passe → JWT HS256 signé du secret du banc
// Un jeton non signé par le banc est retiré : la requête part en `anon`, comme
// un visiteur non connecté.
//
// Variables : SCREEN_RIG_FILE (défaut .screen-rig/rig.json), PGRST_URL
// (défaut http://localhost:3399), SCREEN_GATEWAY_PORT (défaut 54399).
// Issu du harnais de l'audit (doc/audit/harnais-audit-2026-09-28/gateway.mjs).
// ============================================================
import http from 'node:http'
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { signJwt } from './setup-lib.mjs'

const DIR = path.dirname(fileURLToPath(import.meta.url))
const RIG_FILE = process.env.SCREEN_RIG_FILE || path.resolve(DIR, '../../.screen-rig/rig.json')
const RIG = JSON.parse(fs.readFileSync(RIG_FILE, 'utf8'))
const SECRET = RIG.jwtSecret
const USERS = RIG.users
const PGRST = process.env.PGRST_URL || 'http://localhost:3399'
const PORT = Number(process.env.SCREEN_GATEWAY_PORT || 54399)
const LOG = fs.createWriteStream(path.join(path.dirname(RIG_FILE), 'gateway.log'), { flags: 'a' })

function verify(tok) {
  try {
    const [h, p, s] = tok.split('.')
    const exp = crypto.createHmac('sha256', SECRET).update(`${h}.${p}`).digest('base64url')
    if (exp !== s) return null
    return JSON.parse(Buffer.from(p, 'base64url').toString())
  } catch { return null }
}
function userObj(u) {
  return { id: u.id, aud: 'authenticated', role: 'authenticated', email: u.email,
    email_confirmed_at: '2026-01-01T00:00:00Z', app_metadata: { provider: 'email' },
    user_metadata: { name: u.name }, created_at: '2026-01-01T00:00:00Z' }
}
function session(u) {
  const now = Math.floor(Date.now() / 1000)
  const access_token = signJwt({ sub: u.id, role: 'authenticated', email: u.email, aud: 'authenticated',
    iat: now, exp: now + 3600 * 8, user_metadata: { name: u.name } }, SECRET)
  return { access_token, token_type: 'bearer', expires_in: 3600 * 8, expires_at: now + 3600 * 8,
    refresh_token: 'rt-' + u.id, user: userObj(u) }
}
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PATCH,PUT,DELETE,OPTIONS,HEAD',
  'Access-Control-Expose-Headers': 'Content-Range, Content-Location, Preference-Applied',
}
function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json', ...cors })
  res.end(JSON.stringify(obj))
}
const readBody = (req) => new Promise((r) => { const c = []; req.on('data', (d) => c.push(d)); req.on('end', () => r(Buffer.concat(c))) })

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x')
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end() }
  const body = await readBody(req)
  if (url.pathname.startsWith('/rest/v1')) {
    const target = PGRST + url.pathname.slice('/rest/v1'.length) + url.search
    const headers = {}
    for (const [k, v] of Object.entries(req.headers)) {
      if (['host', 'connection', 'content-length', 'apikey', 'x-client-info', 'origin', 'referer'].includes(k)) continue
      headers[k] = v
    }
    if (!verify((headers['authorization'] || '').replace(/^Bearer /, ''))?.sub) delete headers['authorization']
    const r = await fetch(target, { method: req.method, headers, body: ['GET', 'HEAD'].includes(req.method) ? undefined : body })
    const buf = Buffer.from(await r.arrayBuffer())
    const out = { ...cors }
    for (const k of ['content-type', 'content-range', 'preference-applied', 'content-location']) if (r.headers.get(k)) out[k] = r.headers.get(k)
    if (r.status >= 400) LOG.write(`${new Date().toISOString()} ${r.status} ${req.method} ${url.pathname}${url.search} :: ${buf.toString().slice(0, 400)}\n`)
    res.writeHead(r.status, out); return res.end(buf)
  }
  if (url.pathname === '/auth/v1/token') {
    const b = body.length ? JSON.parse(body.toString()) : {}
    const gt = url.searchParams.get('grant_type')
    let u
    if (gt === 'password') u = USERS.find((x) => x.email === b.email && x.password === b.password)
    if (gt === 'refresh_token') u = USERS.find((x) => 'rt-' + x.id === b.refresh_token)
    if (!u) return json(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials' })
    return json(res, 200, session(u))
  }
  if (url.pathname === '/auth/v1/user') {
    const p = verify((req.headers.authorization || '').replace(/^Bearer /, ''))
    const u = p && USERS.find((x) => x.id === p.sub)
    return u ? json(res, 200, userObj(u)) : json(res, 401, { msg: 'invalid JWT' })
  }
  if (url.pathname.startsWith('/auth/v1/logout')) { res.writeHead(204, cors); return res.end() }
  if (url.pathname.startsWith('/auth/v1/')) return json(res, 200, {})
  LOG.write(`${new Date().toISOString()} 503 ${req.method} ${url.pathname} (hors banc)\n`)
  return json(res, 503, { error: 'unavailable_in_screen_rig', path: url.pathname })
}).listen(PORT, () => console.log(`passerelle du banc sur ${PORT} → ${PGRST}`))
