// ============================================================
// qa/worker.mjs — l'AGENT OUVRIER de l'essaim QA
//
// Un processus = un navigateur = un shard de routes. Il visite chaque route
// qui lui est confiée, à chaque gabarit d'écran demandé, et rend un verdict
// par sonde : rendu, onglets, listes déroulantes, fenêtres, boutons,
// accessibilité, débordements, proportions. Rien n'est jugé « à l'œil » :
// tout verdict vient d'une mesure dans la page.
//
// Il n'écrit JAMAIS les données : les boutons destructeurs (supprimer,
// valider, payer…) sont inventoriés mais jamais cliqués (cf. lib/probe.mjs).
//
// Usage :
//   node scripts/qa/worker.mjs --shard=0 --of=6 [--viewports=desktop,mobile]
//          [--modules=sales,stock] [--limit=20] [--light] [--shots=all]
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import { launchBrowser } from './lib/browser.mjs'
import { loadInventory, QA_DIR } from './inventory.mjs'
import { collectDom, dialogInfo, menuInfo, isDestructive, isOpener } from './lib/probe.mjs'
import { finding, fingerprint } from './lib/rules.mjs'

const VIEWPORTS = {
  desktop: { width: 1280, height: 800, dpr: 1 },
  mobile: { width: 375, height: 812, dpr: 3, isMobile: true, hasTouch: true },
  tablet: { width: 768, height: 1024, dpr: 2, isMobile: true, hasTouch: true },
  wide: { width: 1920, height: 1080, dpr: 1 },
}

function arg(name, def = null) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`))
  return hit ? hit.split('=').slice(1).join('=') : def
}

const BASE = (process.env.QA_BASE_URL || 'http://localhost:5174').replace(/\/$/, '')
// Garde-fou : cet essaim écrit des sessions et remplit la base. Jamais ailleurs
// qu'en local, sauf demande explicite et consciente.
if (!/^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])/.test(BASE) && process.env.QA_ALLOW_REMOTE !== '1') {
  console.error(`Refus : QA_BASE_URL=${BASE} n'est pas local. Poser QA_ALLOW_REMOTE=1 pour forcer (déconseillé).`)
  process.exit(2)
}

const SHARD = Number(arg('shard', '0'))
const OF = Number(arg('of', '1'))
const VIEWPORT_ARG = arg('viewports', 'desktop,mobile')
// `all` = les quatre gabarits. Sans cette expansion, le filtre ci-dessous vidait
// la liste et les ouvriers sortaient « ok » après ZÉRO visite — un faux vert
// parfait, mesuré le 29/09/2026 (cinq ouvriers, 0 visite, code 0).
const VIEWPORT_NAMES = (VIEWPORT_ARG === 'all' ? Object.keys(VIEWPORTS) : VIEWPORT_ARG.split(','))
  .map((s) => s.trim())
  .filter((s) => VIEWPORTS[s])
if (!VIEWPORT_NAMES.length) {
  console.error(`Gabarit inconnu : « ${VIEWPORT_ARG} ». Connus : ${Object.keys(VIEWPORTS).join(', ')}, ou « all ».`)
  process.exit(2)
}
const MODULES = (arg('modules', '') || '').split(',').map((s) => s.trim()).filter(Boolean)
// Rejouer une ligne du registre : `--routes=/a,/b`. Le découpage en shards est
// alors ignoré — c'est un outil de diagnostic, pas une tournée.
const ONLY = (arg('routes', '') || '').split(',').map((s) => s.trim()).filter(Boolean)
const LIMIT = Number(arg('limit', '0')) || 0
const RUN = arg('run', '')
// Deux vagues peuvent cohabiter dans le même dossier de shards : la société
// REMPLIE et la société VIDE. Le préfixe les sépare (`shard-vide-0-de-4.json`),
// le jeton de tournée les authentifie.
const PREFIX = arg('prefix', '')
const LIGHT = process.argv.includes('--light')
const SHOTS = arg('shots', 'defects')

const OUT = path.join(QA_DIR, '..', '.qa-out')
const SHOTS_DIR = path.join(OUT, 'shots')
const SHARD_DIR = path.join(OUT, 'shards')

function routesForShard() {
  const inv = loadInventory()
  let routes = inv.routes
  if (MODULES.length) routes = routes.filter((r) => MODULES.includes(r.module))
  if (ONLY.length) return routes.filter((r) => ONLY.includes(r.path))
  // Découpage entrelacé : deux shards voisins ne traitent pas deux écrans du
  // même module, donc un module n'est pas jugé par un seul ouvrier.
  routes = routes.filter((_, i) => i % OF === SHARD)
  if (LIMIT) routes = routes.slice(0, LIMIT)
  return routes
}

function readSession() {
  const file = process.env.QA_SESSION_FILE || path.join(QA_DIR, 'session.json')
  if (!fs.existsSync(file)) {
    console.error(`Session absente (${file}). Lancer d'abord : node scripts/qa/seed.mjs`)
    process.exit(3)
  }
  return JSON.parse(fs.readFileSync(file, 'utf8'))
}

/** Le compte de cet ouvrier (un compte par ouvrier : aucune rotation de jeton partagée). */
function accountFor(session, shard) {
  const accounts = session.workers?.length ? session.workers : [session.owner]
  return accounts[shard % accounts.length]
}

const slug = (p) => (p === '/' ? 'home' : p.replace(/^\//, '').replace(/[^a-z0-9]+/gi, '-').toLowerCase())


// Bruits connus, sans rapport avec l'écran testé : ils ne doivent pas noyer
// le rapport (le contrôle de contraste et le SSRF, eux, restent dans la CI).
const CONSOLE_NOISE = [
  /Download the React DevTools/,
  /Multiple GoTrueClient instances/,
  /React Router Future Flag/,
  /ResizeObserver loop/,
]

// Un tourniquet de chargement est court et contient son mot : il ne doit pas
// être pris pour un écran stable (constaté le 29/09/2026 : 10 « écrans vides »
// sur 12 alors que la page se contentait de charger).
const LOADING_HINT = /chargement|loading|veuillez patienter|جار التحميل|جارٍ/i

/** Attend que l'écran ait fini de se peindre : contenu non vide, stable, et qui ne dit pas « chargement ». */
async function settle(page, timeout = 15000) {
  const read = () => page.evaluate(() => (document.querySelector('#root')?.textContent || '').replace(/\s+/g, ' ').trim()).catch(() => '')
  let prev = ''
  let stable = 0
  const deadline = Date.now() + timeout
  while (Date.now() < deadline) {
    const text = await read()
    const looksLoading = text.length < 80 && LOADING_HINT.test(text)
    if (text === prev && text.length > 0 && !looksLoading) stable++
    else stable = 0
    prev = text
    if (stable >= 2) return text
    await page.waitForTimeout(350)
  }
  return prev
}

/** Écoute la page : erreurs console, exceptions, appels refusés par l'API. */
function watch(page) {
  const state = { consoleErrors: [], jsErrors: [], api: [] }
  state.onConsole = (msg) => {
    if (msg.type() !== 'error') return
    const text = msg.text()
    if (CONSOLE_NOISE.some((re) => re.test(text))) return
    if (state.consoleErrors.length < 6) state.consoleErrors.push(text.slice(0, 260))
  }
  state.onError = (err) => { if (state.jsErrors.length < 5) state.jsErrors.push(String(err?.message || err).slice(0, 260)) }
  state.onResponse = (res) => {
    if (res.status() < 400) return
    const url = res.url()
    if (!url.startsWith(BASE)) return
    const p = new URL(url)
    const line = `${res.status()} ${res.request().method()} ${p.pathname}`
    if (state.api.length < 8 && !state.api.includes(line)) state.api.push(line)
  }
  page.on('console', state.onConsole)
  page.on('pageerror', state.onError)
  page.on('response', state.onResponse)
  state.stop = () => {
    page.off('console', state.onConsole)
    page.off('pageerror', state.onError)
    page.off('response', state.onResponse)
  }
  return state
}

/** Verdicts tirés de l'état statique de la page (aucun clic). */
// La pile locale peut tomber en cours de tournée (PostgREST qui redémarre, un
// 502 en rafale) : ce n'est pas un défaut de l'écran. Mesuré le 29/09/2026 :
// sans cet arrêt, la tournée accusait trois cents écrans « vides » alors que
// l'API ne répondait plus.
let envBroken = false

function verdictsFromDom(route, dom, state, vp, push) {
  const cap = (arr, n = 4) => arr.slice(0, n).join(' ; ')
  if ([...state.api, ...state.consoleErrors].some((l) => /50[23]/.test(l))) envBroken = true
  if (state.jsErrors.length) push(finding(route, 'erreur_js', cap(state.jsErrors), vp))
  if (dom.errorBoundary) push(finding(route, 'erreur_page', dom.textSample, vp))
  if (dom.isBlank) push(finding(route, 'page_blanche', `${dom.textLength} caractère(s) rendu(s)`, vp))
  if (!dom.isBlank && !dom.errorBoundary && dom.h1Count === 0 && dom.headings.length === 0) {
    push(finding(route, 'sans_titre', dom.textSample.slice(0, 80), vp))
  }
  if (state.api.length) push(finding(route, 'api_refusee', cap(state.api, 8), vp))
  if (state.consoleErrors.length) push(finding(route, 'erreur_console', cap(state.consoleErrors), vp))
  if (dom.unnamed.length) push(finding(route, 'bouton_sans_nom', `${dom.unnamed.length} : ${cap(dom.unnamed)}`, vp))
  if (dom.zeroSized.length) push(finding(route, 'bouton_taille_nulle', `${dom.zeroSized.length} : ${cap(dom.zeroSized)}`, vp))
  if (dom.tinyTargets.length) push(finding(route, 'cible_etroite', `${dom.tinyTargets.length} : ${cap(dom.tinyTargets)}`, vp))
  // Un débordement de PAGE est un défaut ; un élément plus large que la fenêtre
  // mais DANS un conteneur défilant ne l'est pas (bandeau d'indicateurs, tableau
  // à défilement horizontal). Mesuré le 29/09/2026 : 11 verdicts à « +0px »,
  // c'est-à-dire des pages qui ne défilent pas — l'outil s'accusait à tort.
  if (dom.docScrollOverflow > 2) {
    push(finding(route, 'debordement_horizontal', `+${dom.docScrollOverflow}px ; ${cap(dom.overflowing, 5)}`, vp))
  }
  if (dom.oversized.length) push(finding(route, 'element_trop_large', cap(dom.oversized), vp))
  if (dom.clippedText.length) push(finding(route, 'texte_coupe', cap(dom.clippedText), vp))
}


/** Onglets : chacun doit changer ce qui est affiché. */
async function probeTabs(page, route, vp, push, budget) {
  const tabs = page.getByRole('tab')
  const n = Math.min(await tabs.count().catch(() => 0), 6)
  const readText = () => page.evaluate(() => (document.querySelector('#root')?.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 4000))
  let tried = 0
  for (let i = 0; i < n; i++) {
    if (Date.now() > budget) break
    const tab = tabs.nth(i)
    const label = ((await tab.textContent().catch(() => '')) || '').trim().slice(0, 40)
    if (!label || isDestructive(label)) continue
    const before = await readText()
    const ok = await tab.click({ timeout: 3000 }).then(() => true).catch(() => false)
    if (!ok) continue
    await page.waitForTimeout(450)
    const after = await readText()
    tried++
    // Un onglet qui annonce « (0) » et laisse le panneau vide a raison : il n'y a
    // rien à montrer. Sans cette réserve, une société neuve faisait accuser les
    // cinq onglets de statut d'un projet vide (mesuré le 29/09/2026).
    if (after === before && !/[（(]\s*0\s*[)）]/.test(label)) push(finding(route, 'onglet_inchange', `« ${label} » : panneau identique (${after.length} car.)`, vp))
  }
  return { tabs: n, tried }
}

/** Listes déroulantes : une liste sans option ne peut rien sélectionner. */
async function probeSelects(page, route, vp, push, budget) {
  const selects = page.locator('select:visible')
  const n = Math.min(await selects.count().catch(() => 0), 8)
  let empty = 0
  for (let i = 0; i < n; i++) {
    if (Date.now() > budget) break
    const opts = await selects.nth(i).locator('option').count().catch(() => 0)
    if (opts === 0) { empty++; continue }
    // Un seul choix n'est un défaut que dans un FORMULAIRE (un champ réduit à son
    // placeholder). Un FILTRE qui n'offre que « Tous » est légitime — la première
    // version de cette règle le comptait à tort (mesuré le 29/09/2026).
    if (opts === 1) {
      const inForm = await selects.nth(i).evaluate((el) => !!el.closest('form')).catch(() => false)
      if (inForm) empty++
    }
  }
  if (empty) push(finding(route, 'select_vide', `${empty} liste(s) sans option sur ${n} vues`, vp))
  return { selects: n, empty }
}

/**
 * Boutons d'ouverture : on ouvre, on mesure la fenêtre, on ferme.
 * Le bouton est toujours inventorié ; il n'est cliqué que si son libellé
 * annonce une ouverture ET ne contient aucun verbe destructeur.
 */
async function probeDialogs(page, route, vp, push, budget) {
  const buttons = page.locator('button:visible, [role="button"]:visible')
  const total = Math.min(await buttons.count().catch(() => 0), 400)
  const opened = []
  let unclosed = 0
  let attempts = 0
  for (let i = 0; i < total && opened.length < 3; i++) {
    // Deux bornes, parce qu'un écran peut offrir des centaines de boutons :
    // le temps (budget partagé avec les onglets et les listes) et le nombre de
    // clics tentés. Sans elles, un bouton que recouvre une fenêtre restée
    // ouverte coûtait 2,5 s de délai × 400 = seize minutes PAR ÉCRAN, et la
    // tournée entière s'arrêtait là (mesuré le 29/09/2026 : quatre ouvriers
    // figés 15 min sur des écrans `/settings/*`).
    if (Date.now() > budget || attempts >= 30) break
    const b = buttons.nth(i)
    const label = (((await b.getAttribute('aria-label').catch(() => null)) || (await b.textContent().catch(() => '')) || '')).trim().replace(/\s+/g, ' ').slice(0, 40)
    if (!label || !isOpener(label)) continue
    attempts++
    const ok = await b.click({ timeout: 2500 }).then(() => true).catch(() => false)
    if (!ok) continue
    await page.waitForTimeout(450)
    // Un clic peut NAVIGUER : un lien de hub se présente comme un bouton. La
    // fenêtre trouvée alors appartient à un AUTRE écran. Mesuré le 29/09/2026 :
    // « Nouvel avoir » attribué à `/commercial`, un hub qui n'a aucune fenêtre —
    // c'était la fenêtre des avoirs, ouverte après avoir suivi une carte du hub.
    if (new URL(page.url()).pathname !== route.path) {
      await page.goto(BASE + route.path, { waitUntil: 'domcontentloaded' }).catch(() => {})
      await settle(page, 6000)
      break
    }
    const dlg = await page.evaluate(dialogInfo)
    if (dlg.open) {
      opened.push(label)
      if (dlg.textLength < 20) push(finding(route, 'modal_vide', `« ${label} » (${dlg.textLength} car.)`, vp))
      if (!dlg.title) push(finding(route, 'modal_sans_titre', `« ${label} » → ${dlg.textSample.slice(0, 60)}`, vp))
      if (dlg.fields > 0 && dlg.namedFields < dlg.fields) {
        // Le détail commence par les comptes (empreinte stable) puis NOMME les
        // champs fautifs : « 11/13 » ne disait pas lequel corriger (ajouté le
        // 29/09/2026). L'empreinte ne lit que les 120 premiers caractères, donc
        // l'ajout ne déplace pas une entrée de registre.
        const which = (dlg.unnamedFields ?? []).slice(0, 2).join(' | ')
        push(finding(route, 'modal_champ_sans_nom', `« ${label} » ${dlg.namedFields}/${dlg.fields} champ(s) nommé(s) — ${which}`, vp))
      }
      if (dlg.widerThanViewport || dlg.tallerThanViewport) push(finding(route, 'modal_deborde', `« ${label} » ${dlg.width}×${dlg.height}`, vp))
      await page.keyboard.press('Escape')
      await page.waitForTimeout(350)
      if ((await page.evaluate(dialogInfo)).open) {
        unclosed++
        push(finding(route, 'modal_sans_fermeture', `« ${label} » : reste ouverte après Échap`, vp))
        // On sort sans rien valider, par le bouton de fermeture s'il existe.
        const close = page.locator('[aria-label*="ermer"], [aria-label*="lose"], [aria-label*="إغلاق"]').first()
        if (await close.count().catch(() => 0)) await close.click({ timeout: 2000 }).catch(() => {})
        else { await page.goto(BASE + route.path, { waitUntil: 'domcontentloaded' }).catch(() => {}); await settle(page, 6000) }
        await page.waitForTimeout(250)
      }
    } else {
      // Un déclencheur qui annonce un menu et n'affiche rien est un bouton mort.
      const popup = await b.getAttribute('aria-haspopup').catch(() => null)
      if (popup && (await page.evaluate(menuInfo)).count === 0) push(finding(route, 'menu_vide', `« ${label} » (aria-haspopup=${popup})`, vp))
    }
    await page.keyboard.press('Escape')
    await page.waitForTimeout(150)
  }
  return { buttonsSeen: total, opened, unclosed }
}

// La fenêtre de bienvenue recouvre l'écran et intercepte les clics : sans la
// lever, AUCUN bouton de l'application n'est cliquable. Mesuré le 29/09/2026 :
// sur 639 visites, zéro onglet et zéro fenêtre ouverts, parce que tous les clics
// étaient refusés par cet overlay — l'agent mesure ce qu'un utilisateur vit.
const DISMISS_LABELS = /^(passer|fermer|skip|close|تخطي|إغلاق)$/i
let overlayAlreadyDismissed = false
// Le navigateur peut mourir (mémoire, fermeture) : c'est un incident de harnais.
// Un agent qui tombe ne doit pas accuser l'écran qu'il regardait.
let browserGone = false

async function dismissWelcome(page, route, vp, push) {
  for (let i = 0; i < 6; i++) {
    const dlg = await page.evaluate(dialogInfo)
    if (!dlg.open) return false
    const text = `${dlg.title ?? ''} ${dlg.textSample ?? ''}`
    if (!/bienvenue|welcome|مرحبا/i.test(text)) return false
    // Elle a déjà été passée dans ce contexte et revient : c'est le défaut.
    if (overlayAlreadyDismissed) push(finding(route, 'overlay_bloquant', `${dlg.title ?? ''} (${dlg.width}×${dlg.height})`, vp))
    let btn = page.getByRole('button', { name: DISMISS_LABELS }).first()
    if (!(await btn.count().catch(() => 0))) btn = page.getByRole('button', { name: /^(suivant|continue|متابعة)$/i }).first()
    if (!(await btn.count().catch(() => 0))) return false
    await btn.click({ timeout: 3000 }).catch(() => {})
    await page.waitForTimeout(400)
    overlayAlreadyDismissed = true
  }
  return true
}

/** Visite une route à un gabarit donné et rend son verdict. */
async function visit(page, route, vpName, findings) {
  const started = Date.now()
  const state = watch(page)
  const before = findings.length
  const push = (f) => { const fp = fingerprint(f); if (!findings.some((x) => x.fp === fp)) findings.push({ ...f, fp }) }
  let sessionLost = false
  let dom = null
  let inter = { tabs: 0, selects: 0, dialogs: 0, opened: [] }
  try {
    await page.goto(BASE + route.path, { waitUntil: 'domcontentloaded', timeout: 30000 })
    await settle(page)
    const finalPath = new URL(page.url()).pathname
    if (finalPath !== route.path) {
      push(finding(route, 'route_redirigee', `${route.path} → ${finalPath}`, vpName))
      if (finalPath.startsWith('/login') || finalPath.startsWith('/onboarding') || finalPath.startsWith('/select-tenant')) sessionLost = true
    }
    // La fenêtre de bienvenue recouvre l'écran : on la lève AVANT toute mesure
    // et tout clic — sinon chaque clic est refusé et le rapport ment.
    await dismissWelcome(page, route, vpName, push)
    dom = await page.evaluate(collectDom)
    // Un écran « vide » peut n'être qu'un paquet JavaScript en retard (mesuré le
    // 29/09/2026 : 15 verdicts à 13 caractères, infirmés par une visite manuelle
    // de 12 s). On ne l'accuse qu'après une seconde chance.
    if (dom.isBlank && !dom.errorBoundary) {
      await page.waitForTimeout(3000)
      await settle(page, 12000)
      dom = await page.evaluate(collectDom)
    }
    // Un squelette encore à l'écran : l'écran n'a pas fini. Le mesurer là
    // donnerait un faux « sans titre » ou une fausse « liste sans option »
    // (mesuré le 30/09/2026 sur trois écrans). On lui laisse le temps de peindre.
    if (dom.skeleton && !dom.errorBoundary) {
      await page.waitForTimeout(2500)
      await settle(page, 10000)
      dom = await page.evaluate(collectDom)
    }
    // « Failed to fetch » peut être un hoquet de la pile locale, pas un défaut de
    // l'écran : on recharge une fois, et le verdict ne tient que s'il se reproduit.
    const fetchFailed = () => [...state.consoleErrors, ...state.jsErrors].some((l) => /Failed to fetch|NetworkError|Load failed/i.test(l))
    if (fetchFailed()) {
      state.consoleErrors.length = 0
      state.jsErrors.length = 0
      await page.goto(BASE + route.path, { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {})
      await settle(page)
      dom = await page.evaluate(collectDom)
    }
    // Une visite qui a vu la pile tomber (réseau, 502/503/504) ou la session
    // s'évaporer ne juge RIEN : ses verdicts décriraient l'incident, pas l'écran
    // (mesuré le 30/09/2026 : une vague entière accusée de « route redirigée
    // vers /login », de 400 et de timeouts pendant que PostgREST tombait).
    const stackDown = [...state.api, ...state.consoleErrors].some((l) => /50[234]|ERR_NETWORK|ERR_INTERNET|ERR_NAME_NOT_RESOLVED/i.test(l))
    if (stackDown || sessionLost) {
      findings.splice(before, findings.length - before)
      console.log(`[ouvrier ${SHARD}] ${vpName} ${route.path} — incident de pile/session : visite écartée (aucun verdict imputé à l'écran).`)
      return {
        path: route.path, module: route.module, viewport: vpName, ms: Date.now() - started,
        textLength: dom?.textLength ?? 0, headings: 0, buttons: 0, inter: {}, findings: 0, sessionLost, incident: stackDown ? 'pile' : 'session',
      }
    }
    verdictsFromDom(route, dom, state, vpName, push)
    if (!LIGHT && !dom.errorBoundary && !dom.isBlank) {
      // Budget d'interaction : 90 s par écran et par gabarit, partagé entre les
      // onglets, les listes et les fenêtres. Au-delà, on garde ce qui a été
      // mesuré : mieux vaut une tournée complète qu'un écran mesuré à fond et
      // trois cents jamais visités.
      const budget = Date.now() + 90_000
      const t = await probeTabs(page, route, vpName, push, budget)
      const s = await probeSelects(page, route, vpName, push, budget)
      const d = await probeDialogs(page, route, vpName, push, budget)
      inter = { tabs: `${t.tried}/${t.tabs}`, selects: s.selects, emptySelects: s.empty, buttonsSeen: d.buttonsSeen, opened: d.opened }
    }
    const fresh = findings.slice(before)
    if (SHOTS === 'all' || fresh.some((f) => f.severity !== 'mineur')) {
      const dir = path.join(SHOTS_DIR, route.module)
      fs.mkdirSync(dir, { recursive: true })
      await page.screenshot({ path: path.join(dir, `${slug(route.path)}-${vpName}.jpg`), type: 'jpeg', quality: 45 }).catch(() => {})
    }
  } catch (e) {
    const msg = String(e?.message || e)
    if (/has been closed|Target closed|browser has been closed/i.test(msg)) browserGone = true
    // Une page qui ne répond pas (timeout) ou un réseau qui lâche : incident de
    // pile, jamais un défaut de l'écran.
    else if (/Timeout \d+ms exceeded|net::ERR_|NS_ERROR_|Navigation failed/i.test(msg)) {
      findings.splice(before, findings.length - before)
      console.log(`[ouvrier ${SHARD}] ${vpName} ${route.path} — pile muette (${msg.slice(0, 60)}) : visite écartée.`)
      return { path: route.path, module: route.module, viewport: vpName, ms: Date.now() - started, textLength: 0, headings: 0, buttons: 0, inter: {}, findings: 0, sessionLost: false, incident: 'pile' }
    }
    else push(finding(route, 'erreur_js', `visite interrompue : ${msg.slice(0, 180)}`, vpName))
  } finally {
    state.stop()
  }
  return {
    path: route.path, module: route.module, viewport: vpName, ms: Date.now() - started,
    textLength: dom?.textLength ?? 0, headings: dom?.headings?.length ?? 0, buttons: dom?.interactiveCount ?? 0,
    inter, findings: findings.length - before, sessionLost,
  }
}

/** Se reconnecter : une tournée dure plus longtemps que la validité d'un jeton. */
async function relogin(page, account) {
  try {
    await page.goto(BASE + '/login', { waitUntil: 'domcontentloaded', timeout: 30000 })
    await page.locator('input[type="email"]').waitFor({ state: 'visible', timeout: 20000 })
    await page.locator('input[type="email"]').fill(account.email)
    await page.locator('input[type="password"]').fill(account.password ?? '')
    await page.locator('button[type="submit"]').click()
    await page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 30000 })
    await page.waitForFunction(() => Object.keys(window.localStorage).some((k) => /^sb-.+-auth-token$/.test(k)), null, { timeout: 20000 }).catch(() => {})
    await page.waitForTimeout(1000)
    return true
  } catch (e) {
    console.log(`[ouvrier ${SHARD}] reconnexion impossible : ${String(e?.message || e).slice(0, 80)}`)
    return false
  }
}

async function main() {
  const startedAt = new Date().toISOString()
  const session = readSession()
  const account = accountFor(session, SHARD)
  const routes = routesForShard()
  fs.mkdirSync(SHARD_DIR, { recursive: true })
  fs.mkdirSync(SHOTS_DIR, { recursive: true })
  console.log(`[ouvrier ${SHARD}/${OF}] ${routes.length} route(s) × ${VIEWPORT_NAMES.join('+')}, compte ${account.email}`)
  const findings = []
  const summaries = []
  const shardFile = path.join(SHARD_DIR, `shard${PREFIX ? `-${PREFIX}` : ''}-${SHARD}-de-${OF}.json`)
  // Les mesures sont écrites au fur et à mesure : une fermeture de navigateur
  // qui traîne ne doit jamais emporter une tournée déjà faite (constaté le
  // 29/09/2026 : trois ouvriers bloqués sur `browser.close()`, 168 visites
  // chacun, aucun shard écrit).
  const flush = (finishedAt = null) => {
    fs.writeFileSync(shardFile, JSON.stringify({
      shard: SHARD, of: OF, prefix: PREFIX, run: RUN, base: BASE, account: account.email, company: session.company, viewports: VIEWPORT_NAMES,
      startedAt, finishedAt: finishedAt ?? new Date().toISOString(), routesVisited: summaries.length, findings, summaries,
    }, null, 2))
  }
  const browser = await launchBrowser()
  for (const vpName of VIEWPORT_NAMES) {
    const spec = VIEWPORTS[vpName]
    const context = await browser.newContext({
      viewport: { width: spec.width, height: spec.height },
      deviceScaleFactor: spec.dpr,
      isMobile: !!spec.isMobile,
      hasTouch: !!spec.hasTouch,
      locale: 'fr-FR',
      timezoneId: 'Europe/Paris',
      storageState: account.storageState,
      serviceWorkers: 'block',
    })
    const page = await context.newPage()
    // Le guide de bienvenue se garde une fois pour toutes (`compta-onboarded`) et
    // n'a rien à faire sur les 334 écrans : sans ce drapeau il recouvre chaque
    // page, et l'émulation tactile ne sait pas atteindre son bouton « Passer »
    // (mesuré le 29/09/2026 : quarante verdicts faux en gabarit téléphone, tous
    // à propos du guide). Sa géométrie est vérifiée à part, à la main.
    await page.addInitScript(() => { try { localStorage.setItem('compta-onboarded', 'true') } catch { /* stockage indisponible */ } })
    // Chaque contexte a son propre stockage : la fenêtre de bienvenue peut
    // légitimement réapparaître ici. Au sein d'un même contexte, non.
    overlayAlreadyDismissed = false
    let lost = false
    for (const route of routes) {
      const r = await visit(page, route, vpName, findings)
      summaries.push(r)
      const mark = r.sessionLost ? ' (SESSION PERDUE)' : ''
      console.log(`[ouvrier ${SHARD}] ${r.viewport.padEnd(7)} ${r.path} → ${r.findings} défaut(s), ${r.ms} ms${mark}`)
      flush()
      // L'API ne répond plus : continuer ne mesurerait que des écrans vides.
      if (envBroken) {
        console.log(`[ouvrier ${SHARD}] pile locale tombée (502) à la ${summaries.length}ᵉ visite — tournée arrêtée sans rien imputer aux écrans.`)
        process.exit(3)
      }
      if (r.sessionLost) {
        // Une tournée dure plus longtemps qu'un jeton (1 h) et la pile locale peut
        // être lente au point que le renouvellement échoue : l'ouvrier se
        // reconnecte avec le compte du banc (ses mots de passe y sont) au lieu
        // d'abandonner soixante écrans plus loin (mesuré le 30/09/2026).
        const back = await relogin(page, account)
        console.log(`[ouvrier ${SHARD}] session expirée à la ${summaries.length}ᵉ visite — reconnexion ${back ? 'réussie' : 'impossible'}.`)
        if (!back) { lost = true; break }
        continue
      }
      if (browserGone) { console.log(`[ouvrier ${SHARD}] navigateur perdu à la ${summaries.length}ᵉ visite — tournée arrêtée sans rien imputer au produit.`); lost = true; break }
    }
    await context.close().catch(() => {})
    if (lost) { console.log(`[ouvrier ${SHARD}] tournée interrompue : la session n'est plus valide.`); break }
  }
  // On écrit AVANT de fermer, et la fermeture ne peut pas retenir le verdict.
  flush()
  if (browserGone) {
    console.log(`[ouvrier ${SHARD}] ${summaries.length} visite(s) mesurée(s), puis navigateur perdu → code 3`)
    process.exit(3)
  }
  await Promise.race([browser.close().catch(() => {}), new Promise((r) => setTimeout(r, 15000))])
  console.log(`[ouvrier ${SHARD}] ${summaries.length} visite(s), ${findings.length} défaut(s) → ${shardFile}`)
  process.exit(0)
}

main().catch((e) => { console.error(e); process.exit(1) })

