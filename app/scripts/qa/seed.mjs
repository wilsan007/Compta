// ============================================================
// qa/seed.mjs — l'AGENT « DONNÉES DU DÉBUT »
//
// Il ne fabrique pas la société en base : il la CRÉE PAR L'ÉCRAN. Inscription
// réelle (/signup), puis assistant de création (/onboarding) — les cinq étapes,
// comme un client. C'est la première page testée du parcours, et elle doit
// aboutir pour que le reste de la tournée ait un sens.
//
// Ensuite il ouvre un compte par ouvrier (autant que de shards), chacun membre
// de la société créée : sans cela, N navigateurs partageraient le même jeton de
// rafraîchissement et GoTrue ferait tourner le jeton sous leurs pieds.
//
// Local uniquement (garde-fou ci-dessous) : ce script écrit dans la base.
// Usage : node scripts/qa/seed.mjs [--workers=4] [--company="QA Essaim"]
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { launchBrowser } from './lib/browser.mjs'
import { QA_DIR, APP_DIR } from './inventory.mjs'

const BASE = (process.env.QA_BASE_URL || 'http://localhost:5174').replace(/\/$/, '')
const API = (process.env.QA_API_URL || 'http://127.0.0.1:54321').replace(/\/$/, '')
const DB_CONTAINER = process.env.QA_DB_CONTAINER || 'supabase_db_app'
// Facteur local (Mailpit) : c'est lui qui dit si un e-mail est réellement parti.
const MAILPIT = (process.env.QA_MAILPIT_URL || 'http://127.0.0.1:54324').replace(/\/$/, '')
const PASSWORD = process.env.QA_PASSWORD || 'Qa-Essaim-2026!'
// Ce que le banc constate sur les écrans d'amorçage eux-mêmes (distinct des
// défauts de tournée mesurés par les ouvriers).
const observations = []
const STAMP = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14)
const COMPANY = argOf('company', `QA Essaim ${STAMP}`)
const WORKERS = Number(argOf('workers', '4'))

function argOf(name, def) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`))
  return hit ? hit.split('=').slice(1).join('=') : def
}

if (!/^https?:\/\/(127\.0\.0\.1|localhost)/.test(BASE) || !/^https?:\/\/(127\.0\.0\.1|localhost)/.test(API)) {
  console.error('Refus : le banc crée des comptes et une société — BASE et API doivent être locales.')
  process.exit(2)
}

function sql(statement) {
  const out = execFileSync('docker', ['exec', DB_CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-tAc', statement], { encoding: 'utf8' })
  return out.trim()
}

/** Clés de la pile locale (`supabase status -o env`), mises en cache hors dépôt. */
function localKeys() {
  const cache = path.join(QA_DIR, 'local-keys.json')
  if (fs.existsSync(cache)) return JSON.parse(fs.readFileSync(cache, 'utf8'))
  let raw = ''
  try {
    raw = execFileSync('supabase', ['status', '-o', 'env'], { cwd: APP_DIR, encoding: 'utf8' })
  } catch (e) {
    console.error('Impossible de lire `supabase status` : la pile locale est-elle démarrée ?', e.message)
    process.exit(2)
  }
  const keys = {}
  for (const line of raw.split('\n')) {
    const m = /^([A-Z_]+)="?(.*?)"?$/.exec(line.trim())
    if (m) keys[m[1]] = m[2]
  }
  const out = {
    anon: keys.ANON_KEY || keys.PUBLISHABLE_KEY,
    service: keys.SERVICE_ROLE_KEY || keys.SECRET_KEY,
    url: keys.API_URL || API,
  }
  fs.mkdirSync(QA_DIR, { recursive: true })
  fs.writeFileSync(cache, JSON.stringify(out, null, 2), { mode: 0o600 })
  return out
}

/** Inscription par l'API RÉELLE du produit (celle que l'écran appelle). */
async function signupViaApi(email, password, name) {
  const keys = localKeys()
  const res = await fetch(`${API}/auth/v1/signup`, {
    method: 'POST',
    headers: { apikey: keys.anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, data: { name } }),
  })
  const body = await res.json()
  if (!res.ok) throw new Error(`signup ${email} refusé : ${res.status} ${JSON.stringify(body).slice(0, 200)}`)
  return body.user?.id ?? body.id
}

const FR = { continue: 'Continuer', create: 'Créer mon entreprise' }

async function newContext(browser) {
  const ctx = await browser.newContext({ locale: 'fr-FR', timezoneId: 'Europe/Paris', serviceWorkers: 'block', viewport: { width: 1440, height: 900 } })
  // L'interface doit être en français : les libellés attendus ci-dessous sont
  // ceux du produit, pas des traductions devinées.
  await ctx.addInitScript(() => { try { localStorage.setItem('i18nextLng', 'fr') } catch { /* stockage refusé : on continue */ } })
  return ctx
}

async function waitFor(page, pathname, timeout = 25000) {
  await page.waitForURL((u) => u.pathname.startsWith(pathname), { timeout })
}

/** 1. L'inscription, par l'écran réel. */
async function signupViaUI(page, email) {
  await page.goto(`${BASE}/signup`, { waitUntil: 'domcontentloaded' })
  await page.locator('input[type="email"]').waitFor({ state: 'visible', timeout: 20000 })
  await page.locator('input[type="email"]').fill(email)
  const passwords = page.locator('input[type="password"]')
  await passwords.nth(0).fill(PASSWORD)
  await passwords.nth(1).fill(PASSWORD)
  await page.locator('button[type="submit"]').click()
  try {
    await waitFor(page, '/onboarding', 20000)
    return
  } catch { /* écran « Vérifiez votre email », ou formulaire qui n'a rien créé */ }

  const accountExists = sql(`SELECT count(*) FROM auth.users WHERE email = '${email}'`) !== '0'
  if (accountExists) {
    const observed = await observeBlockedSignup(page, email)
    observations.push(observed)
    console.log(`   ⚠ ${observed.detail}`)
  } else {
    // L'écran d'inscription n'a créé AUCUN compte (mesuré le 29/09/2026, à la
    // deuxième tentative) : on passe par l'API RÉELLE du produit — le même
    // service que l'écran appelle — et on le dit. La suite du parcours, elle,
    // reste celle de l'écran : l'assistant de création de société.
    const screen = (await page.locator('#root').innerText().catch(() => '')).replace(/\s+/g, ' ').trim().slice(0, 160)
    observations.push({
      at: new Date().toISOString(), kind: 'inscription_ecran_en_echec', email, screen,
      detail: `l'inscription par l'écran n'a créé aucun compte (écran : « ${screen.slice(0, 80)}… ») — repli sur l'API d'inscription du produit`,
    })
    console.log(`   ⚠ l'inscription par l'écran n'a créé aucun compte — repli sur l'API réelle du produit`)
    await signupViaApi(email, PASSWORD, email.split('@')[0])
  }
  // Le compte est confirmé pour que la tournée ait une société à visiter : sur
  // la pile locale, l'e-mail de confirmation ne part pas (clé Resend absente).
  sql(`UPDATE auth.users SET email_confirmed_at = now() WHERE email = '${email}' AND email_confirmed_at IS NULL`)
  await loginViaUI(page, email)
}

/** Mesure le blocage de l'inscription : e-mail réellement parti ? compte confirmé ? */
async function observeBlockedSignup(page, email) {
  const screen = (await page.locator('#root').innerText().catch(() => '')).replace(/\s+/g, ' ').trim().slice(0, 160)
  let mailpit = null
  try {
    const res = await fetch(`${MAILPIT}/api/v1/messages`, { signal: AbortSignal.timeout(3000) })
    const body = await res.json()
    mailpit = body.total ?? (body.messages || []).length
  } catch { /* facteur indisponible : on le dit */ }
  const confirmed = sql(`SELECT email_confirmed_at IS NOT NULL FROM auth.users WHERE email = '${email}'`)
  return {
    at: new Date().toISOString(), kind: 'inscription_bloquee', email, screen,
    mailpitMessages: mailpit, emailConfirmed: confirmed === 't',
    detail: `l'inscription n'atteint pas /onboarding : « ${screen.slice(0, 60)}… » — compte créé non confirmé (email_confirmed_at=${confirmed || 'null'}), ${mailpit ?? '?'} message(s) dans le facteur local`,
  }
}

/** Connexion par le formulaire réel. */
async function loginViaUI(page, email) {
  await page.goto(`${BASE}/login`, { waitUntil: 'domcontentloaded' })
  await page.locator('input[type="email"]').waitFor({ state: 'visible', timeout: 20000 })
  await page.locator('input[type="email"]').fill(email)
  await page.locator('input[type="password"]').fill(PASSWORD)
  await page.locator('button[type="submit"]').click()
  await page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 30000 })
  // La session doit être persistée : sinon la navigation suivante repart déconnecté.
  await page.waitForFunction(() => Object.keys(window.localStorage).some((k) => /^sb-.+-auth-token$/.test(k)), null, { timeout: 20000 }).catch(() => {})
}

/** 2. La société, par les cinq étapes de l'assistant. */
async function createCompanyViaUI(page, name, opts = {}) {
  await page.locator('input[placeholder="Mon Entreprise SARL"]').waitFor({ state: 'visible', timeout: 20000 })
  await page.locator('input[placeholder="Mon Entreprise SARL"]').fill(name)
  if (opts.legalName) await page.locator('input[placeholder="Mon Entreprise SARL (si différent)"]').fill(opts.legalName).catch(() => {})
  if (opts.siren) await page.locator('input[placeholder="123 456 789"]').fill(opts.siren).catch(() => {})
  await page.getByRole('button', { name: FR.continue, exact: true }).click()

  // Étape 2 — pack législatif : laissé au produit (aucune contrainte bloquante ici).
  await page.waitForTimeout(600)
  await page.getByRole('button', { name: FR.continue, exact: true }).click()

  // Étape 3 — adresse et contacts.
  await page.waitForTimeout(600)
  await page.locator('input[placeholder="12 rue de la Paix"]').fill('1 rue de la Recette').catch(() => {})
  await page.locator('input[placeholder="75001"]').fill('75001').catch(() => {})
  await page.locator('input[placeholder="Paris"]').fill('Paris').catch(() => {})
  await page.locator('input[placeholder="contact@entreprise.fr"]').fill('recette@essaim.test').catch(() => {})
  await page.getByRole('button', { name: FR.continue, exact: true }).click()

  // Étape 4 — modules : on les active TOUS. Mesuré le 29/09/2026 : avec les
  // cinq modules par défaut, tous les écrans de RH, stock, production,
  // tableaux de bord et reporting répondaient « Module non activé » — visités,
  // mais jamais mesurés.
  await page.waitForTimeout(600)
  for (const label of ['Stock', 'Production', 'Paie & RH', 'Tableaux de bord', 'Reporting', 'Gestion de projets']) {
    const tile = page.locator('button', { hasText: label }).first()
    if (await tile.count().catch(() => 0)) await tile.click({ timeout: 3000 }).catch(() => {})
  }
  await page.getByRole('button', { name: FR.continue, exact: true }).click()

  // Étape 5 — création. Le bouton d'envoi est le seul `submit` de l'assistant.
  await page.waitForTimeout(600)
  await page.locator('form button[type="submit"]').first().click({ timeout: 20000 }).catch(() => {})
  // Mesure du correctif (W-QA 29/09/2026) : l'application doit rendre la main
  // D'ELLE-MÊME. On le constate avant tout contournement — sinon on ne saurait
  // jamais si le défaut est réparé.
  const selfNavigated = await page
    .waitForURL((u) => !u.pathname.startsWith('/onboarding'), { timeout: 25000 })
    .then(() => true)
    .catch(() => false)
  if (selfNavigated) {
    observations.push({
      at: new Date().toISOString(), kind: 'creation_navigation', company: name, reachedHome: true,
      detail: "l'assistant a rendu la main tout seul après création (correctif W-QA vérifié en direct)",
    })
    await page.waitForTimeout(1500)
    console.log('   société créée, accueil atteint par l’application elle-même')
    return
  }
  // L'application n'a pas navigué : on constate la création là où elle est vraie
  // (en base), on recharge l'accueil, et on le déclare comme défaut persistant.
  const safe = name.replace(/'/g, "''")
  const deadline = Date.now() + 45000
  let born = false
  while (Date.now() < deadline) {
    if (sql(`SELECT count(*) FROM tenants WHERE name = '${safe}'`) !== '0') { born = true; break }
    await page.waitForTimeout(1500)
  }
  observations.push({
    at: new Date().toISOString(), kind: 'creation_sans_navigation', company: name,
    detail: born
      ? `création demandée depuis l'assistant, société présente en base, mais l'écran reste sur « Création... » et ne navigue pas vers l'accueil`
      : `l'assistant a été soumis, aucune société « ${name} » en base après 45 s`,
    reachedHome: false,
  })
  if (!born) throw new Error(`la société « ${name} » n'apparaît pas en base après la soumission`)
  await page.goto(`${BASE}/`, { waitUntil: 'domcontentloaded' })
  await page.waitForTimeout(3000)
  const landed = new URL(page.url()).pathname
  observations[observations.length - 1].reachedHome = !landed.startsWith('/onboarding')
  if (landed.startsWith('/onboarding')) throw new Error(`la société existe en base mais l'accueil renvoie encore vers l'assistant (${landed})`)
  console.log(`   société créée (${landed} atteint au rechargement)`)
}

/** 3. Un compte par ouvrier, membre de la société créée. */
async function addWorker(browser, index, tenantId) {
  const email = `qa-ouvrier-${index}-${STAMP}@qa.local`
  const name = `Ouvrier QA ${index}`
  const uid = await signupViaApi(email, PASSWORD, name)
  sql(`INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
       VALUES ('${tenantId}', '${uid}', '${email}', '${name}', 'admin', 'active')
       ON CONFLICT DO NOTHING`)
  const ctx = await newContext(browser)
  const page = await ctx.newPage()
  await loginViaUI(page, email)
  await page.goto(`${BASE}/`, { waitUntil: 'domcontentloaded' })
  await page.waitForTimeout(2000)
  const landed = new URL(page.url()).pathname
  if (landed.startsWith('/onboarding')) throw new Error(`l'ouvrier ${email} n'est rattaché à aucune société (${landed})`)
  const dir = path.join(QA_DIR, 'accounts')
  fs.mkdirSync(dir, { recursive: true })
  const file = path.join(dir, `ouvrier-${index}.json`)
  await ctx.storageState({ path: file })
  await ctx.close()
  return { email, password: PASSWORD, name, storageState: file, role: 'admin' }
}

async function main() {
  fs.mkdirSync(QA_DIR, { recursive: true })
  const email = `qa-patron-${STAMP}@qa.local`
  const browser = await launchBrowser()
  try {
    const ctx = await newContext(browser)
    const page = await ctx.newPage()
    console.log(`1/3 · inscription par l'écran : ${email}`)
    await signupViaUI(page, email)
    console.log(`2/3 · création de la société « ${COMPANY} » par l'assistant (5 étapes)`)
    await createCompanyViaUI(page, COMPANY, { legalName: `${COMPANY} SAS`, siren: '123456789' })
    const safe = COMPANY.replace(/'/g, "''")
    const tenantId = sql(`SELECT id FROM tenants WHERE name = '${safe}' ORDER BY created_at DESC LIMIT 1`)
    if (!tenantId || tenantId.includes(' ')) throw new Error(`société créée mais introuvable en base sous « ${COMPANY} »`)
    console.log(`      société ${tenantId}`)
    const dir = path.join(QA_DIR, 'accounts')
    fs.mkdirSync(dir, { recursive: true })
    const ownerState = path.join(dir, 'patron.json')
    await ctx.storageState({ path: ownerState })
    await ctx.close()

    const workers = []
    for (let i = 0; i < WORKERS; i++) {
      const w = await addWorker(browser, i, tenantId)
      workers.push(w)
      console.log(`3/3 · ouvrier ${i} : ${w.email}`)
    }

    const session = {
      createdAt: new Date().toISOString(), base: BASE, api: API, company: COMPANY, tenantId,
      owner: { email, password: PASSWORD, storageState: ownerState, role: 'admin' }, workers,
    }
    fs.writeFileSync(path.join(QA_DIR, 'session.json'), JSON.stringify(session, null, 2))
    const outDir = path.join(APP_DIR, '.qa-out')
    fs.mkdirSync(outDir, { recursive: true })
    fs.writeFileSync(path.join(outDir, 'seed-observations.json'), JSON.stringify(observations, null, 2))
    console.log(`\nsession prête : .qa/session.json — société « ${COMPANY} », ${workers.length + 1} compte(s)`)
    if (observations.length) console.log(`⚠ ${observations.length} blocage(s) constaté(s) à l'amorçage → .qa-out/seed-observations.json`)
  } finally {
    await browser.close()
  }
}

main().catch((e) => { console.error('seed : échec —', e.stack || e.message); process.exit(1) })

