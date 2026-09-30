// ============================================================
// qa/dispatch.mjs — SUPERAGENT 1 : le dispatcheur
//
// Il ne teste rien lui-même. Il établit le plan de tournée (inventory.mjs),
// le découpe en shards équilibrés, lance les ouvriers EN PARALLÈLE, et tient
// le tableau de bord. À la fin, il rend la main au validateur (validate.mjs)
// qui juge — séparer celui qui mesure de celui qui juge est le seul moyen
// qu'un ouvrier ne s'auto-absolve pas.
//
// Usage : node scripts/qa/dispatch.mjs [--workers=4] [--viewports=desktop,mobile]
//         [--modules=sales,stock] [--light] [--no-validate]
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

async function preflight() {
  const problems = []
  try {
    const res = await fetch(BASE, { signal: AbortSignal.timeout(4000) })
    if (!res.ok && res.status !== 200) problems.push(`l'application répond ${res.status} sur ${BASE}`)
  } catch {
    problems.push(`l'application ne répond pas sur ${BASE} — lancer « npm run dev -- --port 5174 »`)
  }
  const session = path.join(QA_DIR, 'session.json')
  if (!fs.existsSync(session)) problems.push(`aucune session : lancer « node scripts/qa/seed.mjs » (la société n'a pas encore été créée)`)
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

async function main() {
  const problems = await preflight()
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
  // pour trois lancés, et des défauts d'un run mort comptés dans le verdict).
  const SHARD_DIR = path.join(OUT, 'shards')
  fs.rmSync(SHARD_DIR, { recursive: true, force: true })
  fs.mkdirSync(SHARD_DIR, { recursive: true })
  // Jeton de tournée : chaque shard le porte, le validateur refuse d'en juger
  // deux d'un coup. Sans lui, deux tournées qui se chevauchent (une session
  // parallèle, un run oublié) se mélangeaient en silence — mesuré le
  // 29/09/2026 : un journal annonçait 166 visites quand le shard en portait 69.
  const RUN = new Date().toISOString()
  const scoped = MODULES ? inv.routes.filter((r) => MODULES.split(',').includes(r.module)) : inv.routes
  console.log(`essaim QA → ${BASE}`)
  console.log(`plan : ${inv.totalRoutes} route(s) au total, ${scoped.length} dans le périmètre, ${WORKERS} ouvrier(s) × ${VIEWPORTS}`)
  for (const [mod, n] of Object.entries(inv.modules)) console.log(`   ${String(n).padStart(3)}  ${mod}`)

  const runs = []
  for (let shard = 0; shard < WORKERS; shard++) {
    const logFile = path.join(LOG_DIR, `ouvrier-${shard}.log`)
    const out = fs.openSync(logFile, 'w')
    const args = [path.join(DIR, 'worker.mjs'), `--shard=${shard}`, `--of=${WORKERS}`, `--viewports=${VIEWPORTS}`, `--run=${RUN}`]
    if (MODULES) args.push(`--modules=${MODULES}`)
    const limit = argOf('limit', null)
    if (limit) args.push(`--limit=${limit}`)
    for (const flag of ['light', 'shots']) {
      if (process.argv.includes(`--${flag}`)) args.push(`--${flag}`)
      const v = argOf(flag, null)
      if (v) args.push(`--${flag}=${v}`)
    }
    const child = spawn(process.execPath, args, { cwd: APP, stdio: ['ignore', out, out], env: process.env })
    runs.push({ shard, child, code: null, logFile, lines: 0 })
  }

  // Tableau de bord : on avance par comptage de lignes, sans bloquer les enfants.
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

  const failed = runs.filter((r) => r.code !== 0)
  const summary = { at: new Date().toISOString(), base: BASE, workers: WORKERS, viewports: VIEWPORTS, modules: MODULES || 'tous', shards: runs.map((r) => ({ shard: r.shard, code: r.code, log: path.relative(APP, r.logFile) })) }
  fs.writeFileSync(path.join(OUT, 'dispatch.json'), JSON.stringify(summary, null, 2))
  for (const r of runs) console.log(`  ouvrier ${r.shard} : ${r.code === 0 ? 'ok' : 'échec'} → ${path.relative(APP, r.logFile)}`)
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
