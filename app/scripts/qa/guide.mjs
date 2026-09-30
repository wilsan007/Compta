// ============================================================
// qa/guide.mjs — LE GUIDE DE BIENVENUE, mesuré pour lui-même
//
// La tournée pose le guide comme déjà vu (`compta-onboarded`) : sans lui il
// recouvre les 334 écrans et l'émulation tactile ne sait pas atteindre son
// bouton « Passer ». Il ne serait donc JAMAIS mesuré. Ce scénario le prend à
// part : les quatre gabarits, les cinq étapes, Échap, les cibles tactiles — et
// il écrit ses verdicts dans un shard, que le validateur fusionne avec la
// tournée (même jeton).
//
// Usage : node scripts/qa/guide.mjs [--run=<jeton>] [--viewports=all]
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import { launchBrowser } from './lib/browser.mjs'
import { loadInventory, QA_DIR } from './inventory.mjs'
import { collectDom, dialogInfo } from './lib/probe.mjs'
import { finding, fingerprint } from './lib/rules.mjs'

const VIEWPORTS = {
  desktop: { width: 1280, height: 800, dpr: 1 },
  mobile: { width: 375, height: 812, dpr: 3, isMobile: true, hasTouch: true },
  tablet: { width: 768, height: 1024, dpr: 2, isMobile: true, hasTouch: true },
  wide: { width: 1920, height: 1080, dpr: 1 },
}

const arg = (name, def = null) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`))
  return hit ? hit.split('=').slice(1).join('=') : def
}
const BASE = (process.env.QA_BASE_URL || 'http://localhost:5174').replace(/\/$/, '')
const RUN = arg('run', '')
const VP_ARG = arg('viewports', 'desktop,mobile')
const NAMES = (VP_ARG === 'all' ? Object.keys(VIEWPORTS) : VP_ARG.split(',')).map((s) => s.trim()).filter((s) => VIEWPORTS[s])
const OUT = path.join(QA_DIR, '..', '.qa-out')

/** Le guide apparaît sur n'importe quel écran connecté : on le prend sur l'accueil. */
const HOME = (() => {
  const inv = loadInventory()
  return inv.routes.find((r) => r.path === '/dashboard') ?? { path: '/dashboard', module: 'dashboard', source: null }
})()

const GUIDES = /bienvenue|welcome|مرحبا/i


async function main() {
  const session = JSON.parse(fs.readFileSync(process.env.QA_SESSION_FILE || path.join(QA_DIR, 'session.json'), 'utf8'))
  const account = session.workers?.[0] ?? session.owner
  const browser = await launchBrowser()
  const findings = []
  const summaries = []
  const push = (f) => { const fp = fingerprint(f); if (!findings.some((x) => x.fp === fp)) findings.push({ ...f, fp }) }

  for (const vpName of NAMES) {
    const spec = VIEWPORTS[vpName]
    const ctx = await browser.newContext({
      viewport: { width: spec.width, height: spec.height },
      deviceScaleFactor: spec.dpr, isMobile: !!spec.isMobile, hasTouch: !!spec.hasTouch,
      locale: 'fr-FR', timezoneId: 'Europe/Paris', storageState: account.storageState, serviceWorkers: 'block',
    })
    const page = await ctx.newPage()
    // Volontairement SANS `compta-onboarded` : c'est le guide qu'on vient voir.
    await page.addInitScript(() => localStorage.setItem('i18nextLng', 'fr'))
    const started = Date.now()
    const before = findings.length
    const titles = []
    try {
      await page.goto(BASE + HOME.path, { waitUntil: 'domcontentloaded', timeout: 30000 })
      await page.waitForTimeout(3500)
      let dlg = await page.evaluate(dialogInfo)
      if (!dlg.open || !GUIDES.test(`${dlg.title ?? ''} ${dlg.textSample ?? ''}`)) {
        push(finding(HOME, 'page_blanche', `le guide ne s'ouvre pas (${dlg.open ? 'une autre fenêtre est ouverte' : 'aucune fenêtre'})`, vpName))
      } else {
        for (let step = 0; step < 5; step++) {
          dlg = await page.evaluate(dialogInfo)
          if (!dlg.title) push(finding(HOME, 'modal_sans_titre', `étape ${step + 1} : ${dlg.textSample.slice(0, 60)}`, vpName))
          if (dlg.widerThanViewport || dlg.tallerThanViewport) push(finding(HOME, 'modal_deborde', `étape ${step + 1} ${dlg.width}×${dlg.height}`, vpName))
          const dom = await page.evaluate(collectDom)
          if (dom.tinyTargets.length) push(finding(HOME, 'cible_etroite', `étape ${step + 1} : ${dom.tinyTargets.slice(0, 4).join(' ; ')}`, vpName))
          titles.push(dlg.title ?? '')
          // Le bouton d'avance est le même à chaque étape ; à la dernière il
          // ferme. On le clique en JavaScript : en émulation tactile, le viewport
          // de mise en page est gonflé (527 px pour un téléphone de 375) et le
          // bouton de droite tombe hors de la fenêtre visuelle — Playwright le
          // refuse. Le geste reste celui du produit (React reçoit le clic).
          const clicked = await page.evaluate(() => {
            const btn = [...document.querySelectorAll('.card.shadow-2xl button.btn-primary')].pop()
            if (!btn) return false
            btn.click()
            return true
          }).catch(() => false)
          if (!clicked) { push(finding(HOME, 'guide_etape_inchange', `étape ${step + 1} : aucun bouton d'avance`, vpName)); break }
          await page.waitForTimeout(500)
        }
        const distinct = new Set(titles.filter(Boolean))
        if (distinct.size < 5) push(finding(HOME, 'guide_etape_inchange', `${distinct.size}/5 titre(s) distinct(s) : ${titles.join(' | ').slice(0, 120)}`, vpName))
        if ((await page.evaluate(dialogInfo)).open) {
          await page.keyboard.press('Escape')
          await page.waitForTimeout(600)
          if ((await page.evaluate(dialogInfo)).open) push(finding(HOME, 'modal_sans_fermeture', 'le guide reste ouvert après Échap', vpName))
        }
      }
      summaries.push({ path: HOME.path, module: HOME.module, viewport: vpName, ms: Date.now() - started, textLength: 0, headings: 0, buttons: 0, inter: {}, findings: findings.length - before, sessionLost: false })
      console.log(`[guide] ${vpName.padEnd(7)} ${HOME.path} → ${findings.length - before} défaut(s), ${Date.now() - started} ms — étapes : ${JSON.stringify(titles)}`)
    } catch (e) {
      console.log(`[guide] ${vpName} : visite interrompue — ${String(e?.message || e).slice(0, 120)}`)
    }
    await ctx.close().catch(() => {})
  }

  fs.mkdirSync(path.join(OUT, 'shards'), { recursive: true })
  const file = path.join(OUT, 'shards', 'shard-guide.json')
  fs.writeFileSync(file, JSON.stringify({
    shard: 'guide', of: 1, prefix: 'guide', run: RUN, base: BASE, account: account.email, company: session.company, viewports: NAMES,
    startedAt: new Date(Date.now() - 1).toISOString(), finishedAt: new Date().toISOString(), routesVisited: summaries.length, findings, summaries,
  }, null, 2))
  await Promise.race([browser.close().catch(() => {}), new Promise((r) => setTimeout(r, 10000))])
  console.log(`[guide] ${summaries.length} gabarit(s), ${findings.length} défaut(s) → ${path.relative(process.cwd(), file)}`)
  process.exit(0)
}

main().catch((e) => { console.error(e); process.exit(1) })
