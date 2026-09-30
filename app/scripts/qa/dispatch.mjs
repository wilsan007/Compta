// ============================================================
// qa/dispatch.mjs — SUPERAGENT 1 : le dispatcheur
//
// Il ne teste rien lui-même. Il établit le plan de tournée (inventory.mjs),
// le découpe en shards équilibrés, lance les ouvriers EN PARALLÈLE, et tient
// le tableau de bord. À la fin, il rend la main au validateur (validate.mjs)
// qui juge — séparer celui qui mesure de celui qui juge est le seul moyen
// qu'un ouvrier ne s'auto-absolve pas.
//
// Deux ÉTATS de société peuvent se suivre dans la même tournée :
//   `remplie` (session.json, complétée par `qa:amorce`)  → les écrans avec données
//   `vide`    (session-vide.json, semée sans amorce)     → les états vides
// Chaque vague porte son jeton et son préfixe de shard ; le validateur refuse
// un shard qui n'appartient à aucune des vagues lancées.
//
// Usage : node scripts/qa/dispatch.mjs [--workers=4] [--viewports=desktop,mobile]
//         [--states=remplie,vide] [--modules=sales,stock] [--light] [--no-validate]
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { buildInventory, writeInventory, QA_DIR } from './inventory.mjs'

const DIR = path.dirname(fileURLToPath(import.meta.url))
const APP = path.resolve(DIR, '../..')
const OUT = path.join(APP, '.qa-out')
const LOG_DIR = path.join(OUT, 'logs')

const argOf = (name, def) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`))
  return hit ? hit.split('=').slice(1).join('=') : def
}
const BASE = (process.env.QA_BASE_URL || 'http://localhost:5174').replace(/\/$/, '')
const WORKERS = Math.max(1, Math.min(Number(argOf('workers', '4')) || 4, 8))
const VIEWPORTS = argOf('viewports', 'desktop,mobile')
const MODULES = argOf('modules', '')

/**
 * Les états de société qu'une tournée peut couvrir. `remplie` est le banc
 * complété par `qa:amorce` (des écrans avec données) ; `vide` est une société
 * semée et jamais remplie (des états vides). Mesurer les deux est le seul moyen
 * de ne pas confondre « l'écran va bien » et « l'écran va bien quand la liste
 * est vide » (ou l'inverse).
 */
const WAVES = {
  remplie: { session: 'session.json', prefix: '', label: 'société remplie par qa:amorce' },
  vide: { session: 'session-vide.json', prefix: 'vide', label: 'société neuve, jamais remplie' },
}

async function preflight(states) {
  const problems = []
  try {
    const res = await fetch(BASE, { signal: AbortSignal.timeout(4000) })
    if (!res.ok && res.status !== 200) problems.push(`l'application répond ${res.status} sur ${BASE}`)
  } catch {
    problems.push(`l'application ne répond pas sur ${BASE} — lancer « npm run dev -- --port 5174 »`)
  }
  for (const key of states) {
    const file = path.join(QA_DIR, WAVES[key].session)
    if (!fs.existsSync(file)) {
      const hint = key === 'vide' ? 'node scripts/qa/seed.mjs --session=session-vide.json' : 'node scripts/qa/seed.mjs'
      problems.push(`aucune session pour la vague « ${key} » (${WAVES[key].session}) : lancer « ${hint} »`)
    }
  }
  return problems
}

function statusBoard(runs) {
  const lines = []
  for (const r of runs) {
    const progress = r.lines % 100
    const state = r.code === null ? `en cours (${progress} visite(s))` : r.code === 0 ? 'terminé' : `ÉCHEC (code ${r.code})`
    lines.push(`  ouvrier ${r.shard} : ${state}`)
  }
  return lines.join('\n')
}

/** Une vague : N ouvriers sur un état de société, sous un jeton de tournée. */
async function runWave(key, run, workers) {
  const wave = WAVES[key]
  console.log(`\n— vague « ${key} » : ${wave.label} — ${workers} ouvrier(s) × ${VIEWPORTS}`)
  const runs = []
  for (let shard = 0; shard < workers; shard++) {
    const logFile = path.join(LOG_DIR, `ouvrier-${wave.prefix ? `${wave.prefix}-` : ''}${shard}.log`)
    const out = fs.openSync(logFile, 'w')
    const args = [path.join(DIR, 'worker.mjs'), `--shard=${shard}`, `--of=${workers}`, `--viewports=${VIEWPORTS}`, `--run=${run}`]
    if (wave.prefix) args.push(`--prefix=${wave.prefix}`)
    if (MODULES) args.push(`--modules=${MODULES}`)
    const limit = argOf('limit', null)
    if (limit) args.push(`--limit=${limit}`)
    for (const flag of ['light', 'shots']) {
      if (process.argv.includes(`--${flag}`)) args.push(`--${flag}`)
      const v = argOf(flag, null)
      if (v) args.push(`--${flag}=${v}`)
    }
    const child = spawn(process.execPath, args, { cwd: APP, stdio: ['ignore', out, out], env: { ...process.env, QA_SESSION_FILE: path.join(QA_DIR, wave.session) } })
    runs.push({ shard, child, code: null, logFile, lines: 0 })
  }
  const board = setInterval(() => {
    for (const r of runs) {
      try { r.lines = fs.readFileSync(r.logFile, 'utf8').split('\n').length - 1 } catch { /* pas encore de log */ }
    }
    process.stdout.write(`\r${statusBoard(runs).replace(/\n/g, ' | ')}`)
  }, 3000)
  await Promise.all(runs.map((r) => new Promise((resolve) => {
    r.child.on('exit', (code) => { r.code = code ?? 1; resolve() })
  })))
  clearInterval(board)
  process.stdout.write('\r' + ' '.repeat(120) + '\r')
  for (const r of runs) console.log(`  ouvrier ${r.shard} : ${r.code === 0 ? 'ok' : 'échec'} → ${path.relative(APP, r.logFile)}`)
  return runs
}

/**
 * Le guide de bienvenue, mesuré pour lui-même : la tournée le pose comme déjà vu
 * (`compta-onboarded`), sinon il recouvre les 334 écrans. Son shard porte le
 * même jeton que la première vague.
 */
async function runGuide(run) {
  console.log(`\n— guide de bienvenue (scénario dédié, sans `+'`compta-onboarded`'+`) —`)
  const guide = spawn(process.execPath, [path.join(DIR, 'guide.mjs'), `--run=${run}`, `--viewports=${VIEWPORTS}`], { cwd: APP, stdio: 'inherit' })
  return new Promise((resolve) => guide.on('exit', (code) => resolve(code ?? 1)))
}

async function main() {
  const stateKeys = (argOf('states', 'remplie') || 'remplie').split(',').map((s) => s.trim()).filter((s) => WAVES[s])
  const unknown = (argOf('states', 'remplie') || '').split(',').map((s) => s.trim()).filter((s) => s && !WAVES[s])
  if (!stateKeys.length || unknown.length) {
    console.error(`état inconnu : « ${unknown.join(', ') || argOf('states', '')} » — connus : ${Object.keys(WAVES).join(', ')}`)
    process.exit(2)
  }
  const problems = await preflight(stateKeys)
  if (problems.length) {
    console.error('Préalables manquants :')
    for (const p of problems) console.error(`  ✗ ${p}`)
    process.exit(2)
  }

  // Le plan de tournée est refait maintenant : une route ajoutée à App.tsx
  // depuis la dernière fois est du voyage.
  const inv = buildInventory()
  writeInventory(inv)
  fs.mkdirSync(LOG_DIR, { recursive: true })
  // Les shards d'une tournée PRÉCÉDENTE ne doivent pas se mêler à celle-ci : le
  // validateur lit TOUS les fichiers du dossier, et une tournée arrêtée en
  // route laissait des shards orphelins (mesuré le 29/09/2026 : « ouvriers : 7 »
  // pour trois lancés). Le dossier n'est vidé qu'UNE fois : les vagues d'une même
  // tournée cohabitent (société remplie, société vide, guide).
  const SHARD_DIR = path.join(OUT, 'shards')
  fs.rmSync(SHARD_DIR, { recursive: true, force: true })
  fs.mkdirSync(SHARD_DIR, { recursive: true })
  const scoped = MODULES ? inv.routes.filter((r) => MODULES.split(',').includes(r.module)) : inv.routes
  console.log(`essaim QA → ${BASE}`)
  console.log(`plan : ${inv.totalRoutes} route(s) au total, ${scoped.length} dans le périmètre, ${WORKERS} ouvrier(s) × ${VIEWPORTS}`)
  for (const [mod, n] of Object.entries(inv.modules)) console.log(`   ${String(n).padStart(3)}  ${mod}`)

  // Les vagues : un état de société, un jeton, un préfixe de shard. Le jeton
  // permet au validateur de refuser un shard étranger (session parallèle, run
  // oublié) — mesuré le 29/09/2026 : un journal annonçait 166 visites quand le
  // shard en portait 69.
  const waves = []
  const allRuns = []
  for (const [i, key] of stateKeys.entries()) {
    const run = new Date().toISOString()
    const runs = await runWave(key, run, WORKERS)
    waves.push({ state: key, label: WAVES[key].label, session: WAVES[key].session, prefix: WAVES[key].prefix, run })
    allRuns.push(...runs)
    if (i === 0) fs.writeFileSync(path.join(OUT, 'dispatch.json'), JSON.stringify({ at: run, base: BASE, workers: WORKERS, viewports: VIEWPORTS, modules: MODULES || 'tous', waves, shards: [] }, null, 2))
  }
  const guideCode = await runGuide(waves[0].run)

  const failed = allRuns.filter((r) => r.code !== 0)
  const summary = { at: new Date().toISOString(), base: BASE, workers: WORKERS, viewports: VIEWPORTS, modules: MODULES || 'tous', waves, guide: { code: guideCode }, shards: allRuns.map((r) => ({ shard: r.shard, code: r.code, log: path.relative(APP, r.logFile) })) }
  fs.writeFileSync(path.join(OUT, 'dispatch.json'), JSON.stringify(summary, null, 2))
  if (failed.length) {
    console.error(`${failed.length} ouvrier(s) en échec — lire leur journal avant de juger quoi que ce soit.`)
    process.exit(1)
  }
  if (!process.argv.includes('--no-validate')) {
    const validate = spawn(process.execPath, [path.join(DIR, 'validate.mjs')], { cwd: APP, stdio: 'inherit' })
    await new Promise((r) => validate.on('exit', (code) => { process.exitCode = code ?? 0; r() }))
  }
}
  main().catch((e) => { console.error(e); process.exit(1) })
