// ============================================================
// screen-rig/setup.mjs — X0 (audit fonctionnel exécuté du 28/09/2026)
//
// Prépare le banc « chemin de l'écran » sur une base déjà migrée :
//   1. le rôle `authenticator` que PostgREST utilise (LOGIN, NOINHERIT, membre de
//      anon / authenticated / service_role) ;
//   2. quatre comptes, créés par le CHEMIN RÉEL d'inscription
//      (`create_tenant_for_current_user`) — admin A (France), admin B (Djibouti),
//      puis un lecteur et un comptable ajoutés à la société A ;
//   3. un secret JWT aléatoire et la clé `anon` signée avec lui.
// Tout est écrit dans `.screen-rig/rig.json` (hors dépôt) : ni secret ni mot de
// passe n'est versionné. Ne JAMAIS pointer ce banc vers la production : il écrit.
//
// Usage : DATABASE_URL=postgresql://postgres:postgres@localhost:5432/test_compta \
//         node scripts/screen-rig/setup.mjs
// ============================================================
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import { signJwt } from './setup-lib.mjs'

const DIR = path.dirname(fileURLToPath(import.meta.url))
const OUT_DIR = path.resolve(DIR, '../../.screen-rig')
const url = process.env.DATABASE_URL
if (!url) { console.error('DATABASE_URL requis'); process.exit(1) }
if (!/localhost|127\.0\.0\.1/.test(url)) {
  console.error('Refus : le banc écrit en base — DATABASE_URL doit être local.'); process.exit(1)
}
const AUTH_PASSWORD = process.env.SCREEN_RIG_AUTHENTICATOR_PASSWORD || 'screen-rig'

const c = new pg.Client({ connectionString: url })
await c.connect()

// 1. authenticator
await c.query(`DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator LOGIN NOINHERIT;
  END IF;
END $$`)
await c.query(`ALTER ROLE authenticator WITH LOGIN NOINHERIT PASSWORD '${AUTH_PASSWORD.replace(/'/g, "''")}'`)
await c.query('GRANT anon, authenticated, service_role TO authenticator')

// 2. comptes
const pw = () => crypto.randomBytes(12).toString('base64url')
async function asUser(id, email, fn) {
  await c.query('BEGIN')
  try {
    await c.query(`SELECT set_config('request.jwt.claim.sub', $1, true),
                          set_config('request.jwt.claims', $2, true),
                          set_config('app.active_tenant_id', '', true)`,
      [id, JSON.stringify({ sub: id, role: 'authenticated', email, user_metadata: { name: 'Admin' } })])
    await c.query('SET LOCAL ROLE authenticated')
    const r = await fn()
    await c.query('COMMIT')
    return r
  } catch (e) { await c.query('ROLLBACK'); throw e }
}
async function signup(name, country, currency) {
  const id = crypto.randomUUID()
  const email = `${name.toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${id.slice(0, 8)}@screen.test`
  await c.query('INSERT INTO auth.users (id, email) VALUES ($1, $2)', [id, email])
  const r = await asUser(id, email, async () =>
    (await c.query('SELECT create_tenant_for_current_user($1::jsonb) AS r', [JSON.stringify({ name, country, currency })])).rows[0].r)
  if (!r?.success) throw new Error(`inscription de ${name} refusée : ${JSON.stringify(r)}`)
  return { id, email, password: pw(), name, tenant: r.tenant_id }
}
async function member(tenant, name, role) {
  const id = crypto.randomUUID()
  const email = `${role}-${id.slice(0, 8)}@screen.test`
  await c.query('INSERT INTO auth.users (id, email) VALUES ($1, $2)', [id, email])
  await c.query(`INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
                 VALUES ($1, $2, $3, $4, $5, 'active')`, [tenant, id, email, name, role])
  return { id, email, password: pw(), name, tenant }
}

const adminA = await signup('Société Écran A', 'France', 'EUR')
const adminB = await signup('Société Écran B', 'Djibouti', 'DJF')
const viewerA = await member(adminA.tenant, 'Lecteur A', 'viewer')
const accountantA = await member(adminA.tenant, 'Comptable A', 'accountant')
await c.end()

// 3. secrets
const jwtSecret = crypto.randomBytes(32).toString('hex')
const anonKey = signJwt({ role: 'anon', iss: 'screen-rig', iat: Math.floor(Date.now() / 1000) }, jwtSecret)
fs.mkdirSync(OUT_DIR, { recursive: true })
// Ordre des comptes = convention des scénarios : 0 admin A, 1 admin B, 2 lecteur A, 3 comptable A
fs.writeFileSync(path.join(OUT_DIR, 'rig.json'), JSON.stringify({
  jwtSecret, anonKey, authenticatorPassword: AUTH_PASSWORD,
  A: adminA.tenant, B: adminB.tenant,
  users: [adminA, adminB, viewerA, accountantA],
}, null, 2), { mode: 0o600 })
console.log(`banc prêt : société A ${adminA.tenant}, société B ${adminB.tenant} → .screen-rig/rig.json`)
