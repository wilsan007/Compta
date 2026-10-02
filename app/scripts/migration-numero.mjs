#!/usr/bin/env node
/**
 * Numéros de migration — les PRENDRE et les VÉRIFIER sans jamais de doublon.
 *
 * Pourquoi : le 02/10, `310` → `321` ont été pris deux fois le matin, `415`
 * deux fois l'après-midi, puis `416` TROIS fois en moins de deux heures
 * (`416_chain_l4_invariants_mesurables` commité sur `l4-invariants`,
 * `416_chain_l3_releve_bancaire` sur `partie-3-chainages`,
 * `416_chain_l17_capacite_absence` non suivi dans la copie principale) — et
 * pendant qu'on corrigeait, `417_chain_banc_moteur` naissait dans la plage
 * d'une autre session. Le runner refuse un doublon (SOC-06), mais seulement
 * APRÈS la fusion, quand le travail est fait des deux côtés ; et
 * `ls app/sql | uniq -d` ne voit que SA copie de travail. Ce script regarde
 * tout ce qu'une session peut voir :
 *
 *   1. les dossiers `app/sql/` de TOUS les worktrees du dépôt (fichiers non
 *      suivis compris — c'est là que naissent les collisions) ;
 *   2. les branches vivantes, locales ET distantes (`origin/…`) ;
 *   3. le REGISTRE partagé par tous les worktrees de la machine (il vit dans
 *      le dossier git commun) : les PLAGES inscrites et les numéros PRIS.
 *
 * La procédure, en quatre temps (commande `prendre`) :
 *   1. contrôle AVANT : le numéro est-il libre partout, et dans MA plage ?
 *   2. création exclusive du fichier `app/sql/NNN_<nom>.sql` ;
 *   3. contrôle APRÈS, immédiatement : si un autre a pris le même numéro
 *      entre-temps, le fichier est retiré et on passe au suivant ;
 *   4. le numéro est inscrit PRIS au registre.
 *   Le tout sous un verrou partagé par tous les worktrees.
 *
 * Commandes :
 *   plages                                   les plages inscrites
 *   plage NNN-MMM --session "<ligne>"        inscrire une plage (refusée si elle
 *                                            chevauche une plage existante)
 *   prendre <nom> --session "<ligne>"        prendre le prochain numéro libre de
 *                                            la plage de cette ligne de travail
 *   inscrire app/sql/NNN_<nom>.sql --session "<ligne>"
 *                                            rattacher un fichier créé à la main
 *   verifier [--staged] [--ci]               exit 1 si collision (--staged : les
 *                                            migrations ajoutées au commit doivent
 *                                            aussi être inscrites — crochet
 *                                            pre-commit ; --ci : branches
 *                                            distantes seulement)
 *   liste [--toutes]                         registre + collisions visibles
 */
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, rmdirSync, statSync, unlinkSync } from 'node:fs'
import { join, dirname, resolve, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

// MIGRATION_REPO : la racine du worktree à vérifier. Le crochet pre-commit la
// passe, parce qu'un worktree dont la branche n'a pas encore ce script est
// vérifié par la copie du script d'un autre worktree.
const repoRoot = resolve(process.env.MIGRATION_REPO || join(dirname(fileURLToPath(import.meta.url)), '../..'))
const sqlDir = join(repoRoot, 'app/sql')

const git = (...args) => {
  try {
    return execFileSync('git', args, { cwd: repoRoot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch {
    return ''
  }
}

const commonDir = resolve(repoRoot, git('rev-parse', '--git-common-dir') || '.git')
const ledgerPath = join(commonDir, 'onusuite-migrations-prises.json')
const lockDir = join(commonDir, 'onusuite-migrations.lock')

// Les plages inscrites au 02/10/2026 (AGENTS.md, NUMEROTATION-MIGRATIONS.md et
// les plans des parties). Elles amorcent le registre la première fois ; ensuite
// le registre fait foi, et `plage` en ajoute.
const PLAGES_INITIALES = [
  [100, 129, 'fondations produit'],
  [130, 197, 'sessions fonctionnelles'],
  [200, 209, 'socles'],
  [210, 299, 'audits fonctionnels, W7/W8, L7'],
  [300, 309, 'W7'],
  [310, 324, 'session recette (qa/recette-2026-09-29)'],
  [325, 325, 'partie 1 (correctif TVA 198, tâche 1.7)'],
  [340, 369, 'partie 2 (défauts métier)'],
  [400, 413, 'chaînages L1-L4 (socle)'],
  [414, 414, 'partie 3 (L3, L4)'],
  [415, 429, 'L16-L24'],
  [430, 449, 'partie 3 (L3, L4)'],
  [450, 459, 'partie 5 (intégrité référentielle)'],
]

// Branches VIVANTES : celles qu'une fusion peut ramener. Les sauvegardes
// (`backup/…`) et les branches `claude/…` abandonnées n'en font pas partie ;
// `liste --toutes` les inclut.
const LIVE = /^(origin\/)?(main|master|develop|commercial-hr-paie|partie-[^/]+|qa\/.+|l\d[^/]*|fusion[^/]*)$/

// Une suite peut porter un autre nom que sa migration (`450_chain_integrite_
// referentielle_tests` pour `450_chain_document_types`) : seules les migrations
// définissent le nom d'un numéro ; une suite seule le définit à défaut.
function parse(file) {
  const m = /^(\d{3})_(.+)\.sql$/.exec(basename(file))
  if (!m) return null
  const test = m[2].endsWith('_tests')
  return { num: m[1], name: test ? m[2].slice(0, -'_tests'.length) : m[2], test }
}

function namesBySource(files) {
  const byNum = new Map()
  for (const f of files) {
    const p = parse(f)
    if (!p) continue
    if (!byNum.has(p.num)) byNum.set(p.num, { migs: new Set(), tests: new Set() })
    byNum.get(p.num)[p.test ? 'tests' : 'migs'].add(p.name)
  }
  const out = new Map()
  for (const [num, { migs, tests }] of byNum) out.set(num, migs.size ? migs : tests)
  return out
}

function worktrees() {
  return git('worktree', 'list', '--porcelain')
    .split('\n')
    .filter((l) => l.startsWith('worktree '))
    .map((l) => l.slice('worktree '.length))
    .filter((w) => existsSync(join(w, 'app/sql')))
}

function branches({ all = false, remoteOnly = false } = {}) {
  return git('for-each-ref', '--format=%(refname:short)', ...(remoteOnly ? [] : ['refs/heads']), 'refs/remotes')
    .split('\n')
    .filter((b) => b && !b.endsWith('/HEAD') && b !== 'origin')
    .filter((b) => all || LIVE.test(b))
}

function readLedger() {
  let l
  try {
    l = JSON.parse(readFileSync(ledgerPath, 'utf8'))
  } catch {
    l = {}
  }
  l.prises ||= []
  l.plages ||= PLAGES_INITIALES.map(([de, a, session]) => ({ de, a, session, inscrite_le: '2026-10-02' }))
  return l
}
const writeLedger = (l) => writeFileSync(ledgerPath, JSON.stringify(l, null, 2) + '\n')

/** Tous les noms connus, numéro par numéro : Map<num, Map<nom, Set<où>>>. */
function inventory({ ci = false, all = false } = {}) {
  const inv = new Map()
  const add = (num, name, where) => {
    if (!inv.has(num)) inv.set(num, new Map())
    const m = inv.get(num)
    if (!m.has(name)) m.set(name, new Set())
    m.get(name).add(where)
  }
  if (!ci) {
    for (const w of worktrees()) {
      const label = w === repoRoot ? 'cette copie' : `worktree ${w.replace(process.env.HOME || '', '~')}`
      for (const [num, names] of namesBySource(readdirSync(join(w, 'app/sql')))) for (const n of names) add(num, n, label)
    }
    for (const p of readLedger().prises) add(p.num, p.nom, `registre (${p.session})`)
  }
  for (const b of branches({ all, remoteOnly: ci })) {
    const files = git('ls-tree', '--name-only', b, 'app/sql/').split('\n')
    for (const [num, names] of namesBySource(files)) for (const n of names) add(num, n, b)
  }
  return inv
}

const collisions = (inv) => [...inv].filter(([, names]) => names.size > 1).sort()
const fmt = ([num, names]) =>
  `  ${num} : ` + [...names].map(([n, w]) => `${num}_${n} [${[...w].join(', ')}]`).join('\n        ≠ ')

const plageDe = (ledger, n) => ledger.plages.find((p) => n >= p.de && n <= p.a)
const plagesDeSession = (ledger, session) => ledger.plages.filter((p) => p.session === session)

function exigeSession(ledger, session) {
  if (!session) throw new Error('--session "<ligne de travail>" obligatoire. Plages inscrites :\n' + listePlages(ledger))
  if (!plagesDeSession(ledger, session).length)
    throw new Error(
      `aucune plage inscrite pour « ${session} ». Inscrivez-en une LIBRE d'abord :\n` +
        `  node app/scripts/migration-numero.mjs plage NNN-MMM --session "${session}"\nPlages inscrites :\n` +
        listePlages(ledger),
    )
}
const listePlages = (ledger) =>
  ledger.plages
    .slice()
    .sort((x, y) => x.de - y.de)
    .map((p) => `  ${String(p.de).padStart(3, '0')} → ${String(p.a).padStart(3, '0')}  ${p.session}`)
    .join('\n')

// ── Verrou partagé par tous les worktrees (mkdir est atomique) ──
function lock() {
  const t0 = Date.now()
  for (;;) {
    try {
      mkdirSync(lockDir)
      return
    } catch {
      try {
        // un verrou de plus de 60 s est un verrou abandonné (session tuée)
        if (Date.now() - statSync(lockDir).mtimeMs > 60_000) rmdirSync(lockDir)
      } catch {
        /* déjà retiré par un autre */
      }
      if (Date.now() - t0 > 30_000) throw new Error(`verrou ${lockDir} tenu depuis plus de 30 s`)
      execFileSync('sleep', ['0.2'])
    }
  }
}
function unlock() {
  try {
    rmdirSync(lockDir)
  } catch {
    /* rien */
  }
}
function sousVerrou(fn) {
  lock()
  try {
    return fn()
  } finally {
    unlock()
  }
}

function plage(spec, session) {
  const m = /^(\d{3})-(\d{3})$/.exec(spec || '')
  if (!m || !session) throw new Error('usage : plage NNN-MMM --session "<ligne de travail>"')
  const [de, a] = [Number(m[1]), Number(m[2])]
  return sousVerrou(() => {
    const ledger = readLedger()
    const chevauche = ledger.plages.filter((p) => de <= p.a && a >= p.de)
    if (chevauche.length)
      throw new Error(`la plage ${spec} chevauche :\n${chevauche.map((p) => `  ${p.de} → ${p.a}  ${p.session}`).join('\n')}`)
    const pris = [...inventory().keys()].filter((n) => Number(n) >= de && Number(n) <= a)
    if (pris.length) throw new Error(`la plage ${spec} contient des numéros déjà pris : ${pris.join(', ')}`)
    ledger.plages.push({ de, a, session, inscrite_le: new Date().toISOString().slice(0, 10) })
    writeLedger(ledger)
    console.log(`✅ Plage ${spec} inscrite pour « ${session} ».`)
    console.log('   Inscrivez-la aussi dans AGENTS.md et NUMEROTATION-MIGRATIONS.md, dans le même commit que la première migration.')
  })
}

function prendre(nom, session) {
  if (!/^[a-z0-9_]+$/.test(nom || '')) throw new Error(`nom invalide « ${nom} » : minuscules, chiffres et _ seulement`)
  const branche = git('branch', '--show-current')
  return sousVerrou(() => {
    const ledger = readLedger()
    exigeSession(ledger, session)
    for (const p of plagesDeSession(ledger, session).sort((x, y) => x.de - y.de)) {
      for (let n = p.de; n <= p.a; n++) {
        const num = String(n).padStart(3, '0')
        // 1. Contrôle AVANT : le numéro existe-t-il déjà, n'importe où ?
        if (inventory().has(num)) continue
        // 2. Création exclusive du fichier (échoue s'il existe déjà).
        const file = join(sqlDir, `${num}_${nom}.sql`)
        try {
          writeFileSync(
            file,
            `-- ${num} — ${nom}\n-- Numéro pris le ${new Date().toISOString()} par migration-numero.mjs` +
              ` (ligne « ${session} », branche ${branche || '?'}).\n`,
            { flag: 'wx' },
          )
        } catch {
          continue
        }
        // 3. Contrôle APRÈS, immédiatement : un autre a-t-il pris le même numéro ?
        const names = inventory().get(num)
        if (names && [...names.keys()].some((k) => k !== nom)) {
          unlinkSync(file)
          console.error(`⚠️  ${num} pris par un autre entre les deux contrôles (${[...names.keys()].join(', ')}) — numéro suivant.`)
          continue
        }
        // 4. Le numéro est inscrit PRIS au registre partagé.
        ledger.prises.push({ num, nom, session, branche, worktree: repoRoot, le: new Date().toISOString() })
        writeLedger(ledger)
        console.log(`✅ ${num} PRIS : app/sql/${num}_${nom}.sql — inscrit au registre (${ledgerPath}).`)
        return num
      }
    }
    throw new Error(`les plages de « ${session} » sont pleines : inscrivez-en une nouvelle (commande plage)`)
  })
}

function inscrire(file, session) {
  const p = parse(file || '')
  if (!p) throw new Error('usage : inscrire app/sql/NNN_<nom>.sql --session "<ligne de travail>"')
  return sousVerrou(() => {
    const ledger = readLedger()
    exigeSession(ledger, session)
    const owner = plageDe(ledger, Number(p.num))
    if (!owner || owner.session !== session)
      throw new Error(
        `${p.num} est dans la plage de « ${owner ? owner.session : 'personne (plage non inscrite)'} », pas de « ${session} ».\n` +
          `   Renommez le fichier : node app/scripts/migration-numero.mjs prendre ${p.name} --session "${session}"`,
      )
    const names = inventory().get(p.num)
    const autres = names ? [...names.keys()].filter((k) => k !== p.name) : []
    if (autres.length) throw new Error(`${p.num} est déjà pris par : ${autres.map((k) => `${p.num}_${k}`).join(', ')}`)
    if (!ledger.prises.some((x) => x.num === p.num && x.nom === p.name)) {
      ledger.prises.push({ num: p.num, nom: p.name, session, branche: git('branch', '--show-current'), worktree: repoRoot, le: new Date().toISOString() })
      writeLedger(ledger)
    }
    console.log(`✅ ${p.num}_${p.name} inscrit au registre pour « ${session} ».`)
  })
}

function verifier({ staged = false, ci = false }) {
  const errors = []
  const ledger = ci ? null : readLedger()
  const added = staged
    ? git('diff', '--cached', '--name-only', '--diff-filter=AR', '--', 'app/sql/').split('\n').filter(Boolean)
    : readdirSync(sqlDir)
  const myNums = namesBySource(added)
  for (const c of collisions(inventory({ ci })).filter(([num]) => myNums.has(num))) errors.push(fmt(c))
  // Doublon INTERNE à cette copie (le cas du runner, vu avant lui).
  for (const [num, names] of namesBySource(readdirSync(sqlDir)))
    if (names.size > 1) errors.push(`  ${num} : doublon dans cette copie (${[...names].join(', ')})`)
  // Au commit : toute migration AJOUTÉE doit être passée par `prendre` ou
  // `inscrire` — c'est ce qui garantit le contrôle de plage et le double contrôle.
  if (staged && ledger) {
    for (const [num, names] of myNums) {
      if (Number(num) < 325) continue // séries antérieures au registre (02/10/2026)
      for (const n of names) {
        if (!ledger.prises.some((x) => x.num === num && x.nom === n)) {
          const owner = plageDe(ledger, Number(num))
          errors.push(
            `  ${num}_${n} : numéro jamais PRIS au registre (plage de « ${owner ? owner.session : 'personne'} »).\n` +
              `        → node app/scripts/migration-numero.mjs inscrire app/sql/${num}_${n}.sql --session "<votre ligne>"`,
          )
        }
      }
    }
  }
  if (!errors.length) {
    console.log(`✅ Numéros de migration : aucune collision (${myNums.size} numéro(s) vérifié(s) contre les worktrees, les branches vivantes et le registre).`)
    return 0
  }
  console.error('❌ Numéros de migration :')
  for (const e of errors) console.error(e)
  console.error(
    '\n   Règle (doc/audit/NUMEROTATION-MIGRATIONS.md) : la plage INSCRITE garde le numéro ; l’autre se déplace.' +
      '\n   Prendre un numéro : node app/scripts/migration-numero.mjs prendre <nom> --session "<votre ligne>"',
  )
  return 1
}

// ── Entrée ──
const [cmd = 'verifier', ...rest] = process.argv.slice(2)
const opt = (k) => {
  const i = rest.indexOf(k)
  return i >= 0 ? rest[i + 1] : undefined
}
try {
  if (cmd === 'prendre') prendre(rest[0], opt('--session'))
  else if (cmd === 'inscrire') inscrire(rest[0], opt('--session'))
  else if (cmd === 'plage') plage(rest[0], opt('--session'))
  else if (cmd === 'plages') console.log(listePlages(readLedger()))
  else if (cmd === 'verifier') process.exit(verifier({ staged: rest.includes('--staged'), ci: rest.includes('--ci') }))
  else if (cmd === 'liste') {
    const ledger = readLedger()
    console.log(`Plages inscrites :\n${listePlages(ledger)}\n\nNuméros pris au registre (${ledgerPath}) : ${ledger.prises.length}`)
    for (const p of ledger.prises) console.log(`  ${p.num}_${p.nom}  « ${p.session} »  ${p.branche || ''}  ${p.le}`)
    // Numéros présents quelque part mais hors de toute plage, ou dans la plage d'une autre ligne : à surveiller.
    const c = collisions(inventory({ all: rest.includes('--toutes') }))
    console.log(c.length ? `\nCollisions visibles (${c.length}) :\n${c.map(fmt).join('\n')}` : '\nAucune collision visible.')
  } else {
    console.error(`commande inconnue « ${cmd} » (plages | plage | prendre | inscrire | verifier | liste)`)
    process.exit(2)
  }
} catch (e) {
  console.error(`❌ ${e.message}`)
  process.exit(1)
}
