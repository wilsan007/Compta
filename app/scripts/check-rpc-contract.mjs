#!/usr/bin/env node
/**
 * check-rpc-contract.mjs — W10 (le contrat d'appel entre l'écran et la base)
 *
 * L'ANGLE MORT QUE CE CONTRÔLE FERME. Trois contrôles existaient déjà, et aucun
 * ne regardait les APPELS DE FONCTION :
 *
 *   · `check-embeds.mjs` (N4)      → les LECTURES d'une requête PostgREST ;
 *   · `check-written-columns.mjs`  → les colonnes écrites (.insert/.update) ;
 *   · `check-unchecked-writes.mjs` → l'erreur d'écriture non lue.
 *
 * Un `.rpc('nom', { p_argument: … })` n'est vu par AUCUN des trois. Il n'est vu
 * ni par `tsc` (le client est typé « any »), ni par les tests unitaires (Supabase
 * y est simulé), ni par PostgREST tant que l'appel n'est pas joué. Or PostgREST
 * refuse un appel pour trois raisons bien distinctes :
 *
 *   1. le nom n'existe pas dans le schéma exposé          → 404 ;
 *   2. un nom d'argument ne correspond à AUCUNE signature → 404 ;
 *   3. il manque un argument sans valeur par défaut       → 404.
 *
 * Et une quatrième, invisible pour le front : une fonction `RETURNS trigger`
 * n'est JAMAIS exposée par PostgREST. Un écran qui appelle une fonction de
 * déclencheur ne peut donc rien faire — il ne peut qu'échouer, tout en
 * prétendant agir. Mesuré le 27/09/2026 sur le schéma réel (235 migrations) :
 * **14 contrats rompus** sur 117 appels littéraux, dont 4 fonctions de
 * déclencheur appelées depuis des écrans vivants (rapprochement 3 voies, limite
 * de crédit, règles de rapprochement bancaire, score de rapprochement) et 2
 * appels au stock qui, s'ils avaient abouti, auraient compté DEUX fois le même
 * mouvement. (Une première mesure, jetable, en annonçait 15 : elle comptait
 * `calculate_payslip`, dont l'objet d'arguments est une VARIABLE — ce contrôle
 * le classe « non vérifiable », pas « rompu », et c'est dit ci-dessous.)
 *
 * LA RÈGLE. Toute clé de premier niveau de l'objet passé à `.rpc()` doit exister
 * comme nom d'argument d'AU MOINS une signature de la fonction nommée, et le
 * nombre d'arguments fournis doit couvrir les arguments sans valeur par défaut.
 * L'appel doit viser une fonction de `public` qui RETOURNE autre chose qu'un
 * `trigger`.
 *
 * CE QUI EST VOLONTAIREMENT NON VÉRIFIÉ, ET DIT. Un appel dont l'objet
 * d'arguments est une VARIABLE (`supabase.rpc('x', params)`) n'est pas
 * vérifiable statiquement : le nom est contrôlé, les arguments sont comptés à
 * part. Le schéma qualifié (`.schema('x').rpc(…)`) n'est pas suivi : le corpus
 * est celui du schéma exposé.
 *
 * LA BASELINE EST GELÉE, et un plafond ne peut que baisser : une ligne inscrite
 * qui disparaît du code fait échouer la CI (la ligne doit être retirée dans le
 * même commit). `--update-baseline` ne sait que retirer. L'objectif de cette
 * vague est une baseline VIDE : chaque appel du front vise une fonction réelle,
 * appelable, avec ses vrais arguments.
 *
 * Usage :
 *   DATABASE_URL=... node scripts/check-rpc-contract.mjs
 *   DATABASE_URL=... node scripts/check-rpc-contract.mjs --json
 *   DATABASE_URL=... node scripts/check-rpc-contract.mjs --update-baseline
 *
 * Sortie : code 1 si un contrat d'appel est rompu, ou si une ligne gelée n'est
 * plus reproduite. Code 2 si le schéma ou la baseline manquent. Code 0 sinon.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(__dirname, '..')
const BASELINE = path.join(__dirname, 'verify-rules', 'rpc-contract.baseline.json')
const UPDATE = process.argv.includes('--update-baseline')

const DATABASE_URL = process.env.DATABASE_URL
if (!DATABASE_URL && !process.env.PGHOST) {
  console.error('❌ DATABASE_URL (ou PGHOST/PGUSER/PGPASSWORD/PGDATABASE) est requis :')
  console.error('   le contrôle confronte le code aux SIGNATURES RÉELLES, pas à une liste devinée.')
  process.exit(2)
}


// ────────────────────────────────────────────────────────────
// 1. Les signatures réelles
// ────────────────────────────────────────────────────────────
const { default: pg } = await import('pg')
const client = new pg.Client(
  DATABASE_URL
    ? { connectionString: DATABASE_URL }
    : {
        host: process.env.PGHOST,
        port: Number(process.env.PGPORT || 5432),
        user: process.env.PGUSER,
        password: process.env.PGPASSWORD,
        database: process.env.PGDATABASE,
      }
)

const overloadsByName = new Map()
let functionCount = 0
try {
  await client.connect()
  const { rows } = await client.query(
    `SELECT p.proname,
            COALESCE(p.proargnames, '{}')::text[] AS argnames,
            p.pronargs,
            p.pronargdefaults,
            pg_get_function_result(p.oid) AS returns
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'`
  )
  for (const r of rows) {
    functionCount++
    const argnames = r.argnames.map((a) => a.replace(/"/g, ''))
    const entry = {
      argnames,
      nargs: Number(r.pronargs),
      ndef: Number(r.pronargdefaults),
      trigger: /^trigger$/i.test(r.returns || ''),
    }
    if (!overloadsByName.has(r.proname)) overloadsByName.set(r.proname, [])
    overloadsByName.get(r.proname).push(entry)
  }
} catch (err) {
  console.error('❌ Lecture du catalogue impossible :', err.message)
  process.exit(2)
} finally {
  await client.end().catch(() => {})
}
if (functionCount === 0) {
  console.error('❌ Catalogue vide : le contrôle ne prouverait rien. Chargez les migrations d’abord.')
  process.exit(2)
}


// ────────────────────────────────────────────────────────────
// 2. Le corpus : le front ET les fonctions Edge
// ────────────────────────────────────────────────────────────
const files = []
function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) {
      if (/node_modules|__tests__|\.git$|dist$/.test(p)) continue
      walk(p)
    } else if (/\.(ts|tsx)$/.test(p) && !/\.test\.|database-generated/.test(p)) {
      files.push(p)
    }
  }
}
for (const r of ['src', 'supabase/functions']) {
  const abs = path.join(ROOT, r)
  if (fs.existsSync(abs)) walk(abs)
}

// Découpe équilibrée à partir de la parenthèse ouvrante.
function balanced(src, openIdx) {
  let depth = 0
  let inStr = null
  let prev = ''
  for (let i = openIdx; i < src.length; i++) {
    const ch = src[i]
    if (inStr) {
      if (ch === inStr && prev !== '\\') inStr = null
    } else if (ch === '"' || ch === "'" || ch === '`') inStr = ch
    else if (ch === '(') depth++
    else if (ch === ')') {
      depth--
      if (depth === 0) return src.slice(openIdx + 1, i)
    }
    prev = ch
  }
  return null
}

// L'objet littéral d'arguments, s'il existe (`{ … }` de premier niveau).
function objectArg(callBody) {
  let depth = 0
  let inStr = null
  let prev = ''
  for (let i = 0; i < callBody.length; i++) {
    const ch = callBody[i]
    if (inStr) {
      if (ch === inStr && prev !== '\\') inStr = null
    } else if (ch === '"' || ch === "'" || ch === '`') inStr = ch
    else if (ch === '[') depth++
    else if (ch === ']') depth--
    else if (ch === '{' && depth === 0) return balancedBrace(callBody, i)
    prev = ch
  }
  return null
}

function balancedBrace(src, start) {
  let depth = 0
  let inStr = null
  let prev = ''
  for (let i = start; i < src.length; i++) {
    const ch = src[i]
    if (inStr) {
      if (ch === inStr && prev !== '\\') inStr = null
    } else if (ch === '"' || ch === "'" || ch === '`') inStr = ch
    else if (ch === '{') depth++
    else if (ch === '}') {
      depth--
      if (depth === 0) return src.slice(start + 1, i)
    }
    prev = ch
  }
  return null
}

// Clés de premier niveau d'un corps d'objet (`a: 1, b: { c: 2 }` → a, b)
function topLevelKeys(body) {
  if (body === null) return []
  const keys = []
  let depth = 0
  let inStr = null
  let prev = ''
  let start = 0
  const parts = []
  for (let i = 0; i < body.length; i++) {
    const ch = body[i]
    if (inStr) {
      if (ch === inStr && prev !== '\\') inStr = null
    } else if (ch === '"' || ch === "'" || ch === '`') inStr = ch
    else if ('{[('.includes(ch)) depth++
    else if ('}])'.includes(ch)) depth--
    else if (ch === ',' && depth === 0) {
      parts.push(body.slice(start, i))
      start = i + 1
    }
    prev = ch
  }
  parts.push(body.slice(start))
  for (const p of parts) {
    const m = p.match(/^\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?\s*:/)
    if (m) keys.push(m[1])
  }
  return keys
}

const RPC_RE = /\.rpc\(\s*(?:'([a-zA-Z0-9_]+)'|"([a-zA-Z0-9_]+)"|`([^`$]*)`|([A-Za-z_$][\w.]*))/g

const problems = []
const unverifiable = []
let literalCalls = 0
let dynamicCalls = 0

for (const file of files) {
  const src = fs.readFileSync(file, 'utf8')
  const rel = path.relative(ROOT, file)
  let m
  RPC_RE.lastIndex = 0
  while ((m = RPC_RE.exec(src))) {
    const name = m[1] || m[2] || m[3] || null
    const line = src.slice(0, m.index).split('\n').length
    if (name === null || name === '') {
      dynamicCalls++
      unverifiable.push({ file: rel, line, name: null, reason: 'nom non littéral' })
      continue
    }
    literalCalls++
    const open = src.indexOf('(', m.index + 4)
    const call = balanced(src, open)
    const rawObject = call === null ? null : objectArg(call)
    const keys = topLevelKeys(rawObject)
    const overloads = overloadsByName.get(name)

    if (!overloads) {
      problems.push({ file: rel, line, name, reason: 'FONCTION INEXISTANTE' })
      continue
    }
    if (overloads.every((o) => o.trigger)) {
      problems.push({
        file: rel,
        line,
        name,
        reason: 'NON APPELABLE — fonction de déclencheur (PostgREST ne l’expose pas)',
      })
      continue
    }
    if (rawObject === null) {
      const callable = overloads.filter((o) => !o.trigger)
      const obligatory = callable.some((o) => o.nargs - o.ndef > 0)
      if (obligatory || callable.length === 0) {
        unverifiable.push({
          file: rel,
          line,
          name,
          reason: obligatory
            ? 'arguments non vérifiables alors qu’au moins un est obligatoire'
            : 'aucun objet d’arguments fourni, arguments obligatoires inconnus',
        })
      }
      continue
    }

    const matches = overloads.filter((o) => {
      if (o.trigger) return false
      if (keys.length > o.nargs) return false
      if (keys.length < o.nargs - o.ndef) return false
      return keys.every((k) => o.argnames.includes(k))
    })
    if (matches.length === 0) {
      const inconnus = keys.filter((k) => !overloads.some((o) => o.argnames.includes(k)))
      problems.push({
        file: rel,
        line,
        name,
        reason: inconnus.length
          ? `ARGUMENT(S) INCONNU(S) : ${inconnus.join(', ')}`
          : `ARITÉ — ${keys.length} argument(s) fourni(s)`,
        provided: keys,
        signatures: overloads
          .filter((o) => !o.trigger)
          .map((o) => `${o.argnames.join(', ') || '(aucun)'} [défaut: ${o.ndef}]`),
      })
    }
  }
}

// Une (fichier, nom, raison) n'est comptée qu'une fois : c'est elle qui est gelée.
const seen = new Map()
for (const p of problems) {
  const key = `${p.file}|${p.name}|${p.reason}`
  if (!seen.has(key)) seen.set(key, p)
}
const found = [...seen.keys()].sort()

if (process.argv.includes('--json')) {
  console.log(JSON.stringify([...seen.values()], null, 2))
  process.exit(0)
}



// ────────────────────────────────────────────────────────────
// 3. Confrontation à la baseline gelée
// ────────────────────────────────────────────────────────────
if (!fs.existsSync(BASELINE)) {
  console.error(`❌ Baseline absente : ${path.relative(ROOT, BASELINE)}`)
  console.error('   Sans elle, un appel rompu ne serait pas distingué d’un autre.')
  process.exit(2)
}
const baseline = JSON.parse(fs.readFileSync(BASELINE, 'utf8'))
const frozen = new Map(baseline.findings.map((f) => [`${f.file}|${f.name}|${f.reason}`, f]))

const nouveaux = found.filter((k) => !frozen.has(k))
const disparus = [...frozen.keys()].filter((k) => !seen.has(k))

if (UPDATE) {
  if (nouveaux.length > 0) {
    console.error('❌ --update-baseline refuse d’AJOUTER des appels rompus :')
    for (const k of nouveaux) console.error(`   ${k}  (${seen.get(k).file}:${seen.get(k).line})`)
    console.error('   La baseline est un plafond qui ne peut que baisser. Alignez l’appel sur')
    console.error('   la signature réelle, ou inscrivez la ligne à la main avec sa raison.')
    process.exit(1)
  }
  baseline.findings = baseline.findings.filter((f) => seen.has(`${f.file}|${f.name}|${f.reason}`))
  baseline.frozenAt = new Date().toISOString().slice(0, 10)
  baseline.total = baseline.findings.length
  fs.writeFileSync(BASELINE, JSON.stringify(baseline, null, 2) + '\n')
  console.log(`✅ Baseline mise à jour : ${baseline.findings.length} contrat(s) rompu(s) gelé(s).`)
  process.exit(0)
}

console.log(
  `Contrat d’appel : ${files.length} fichiers, ${functionCount} fonctions en base, ` +
    `${literalCalls} appel(s) littéral(aux), ${dynamicCalls} dynamique(s).`
)
console.log(
  `Baseline gelée  : ${frozen.size} entrée(s), gelée le ${baseline.frozenAt || 'inconnu'}.`
)
if (unverifiable.length > 0) {
  console.log(`Non vérifiable  : ${unverifiable.length} (nom non littéral ou arguments variables).`)
}

if (nouveaux.length > 0) {
  console.error('\n❌ CONTRAT(S) D’APPEL ROMPU(S) — le front n’appelle pas ce que la base expose :')
  for (const k of nouveaux) {
    const p = seen.get(k)
    console.error(`   ${p.file}:${p.line}  →  ${p.name}  (${p.reason})`)
    if (p.signatures) {
      console.error(`      fourni : ${p.provided.join(', ') || '(aucun)'}`)
      console.error(`      base   : ${p.signatures.join(' | ')}`)
    }
  }
  console.error('\n   Au 27/09/2026 ce contrôle en trouvait 14, dont quatre fonctions de')
  console.error('   déclencheur appelées depuis des écrans (jamais exposées par PostgREST).')
  console.error('   Un appel qui ne peut pas aboutir est pire qu’un appel absent : il échoue')
  console.error('   en silence quand son erreur n’est pas lue.')
  process.exit(1)
}

if (disparus.length > 0) {
  console.error('\n❌ CONTRAT(S) GELÉ(S) QUI N’EXISTENT PLUS — la ligne doit être retirée :')
  for (const k of disparus) console.error(`   ${k}  — ${frozen.get(k).reason || 'sans raison'}`)
  console.error('\n   `node scripts/check-rpc-contract.mjs --update-baseline` retire les lignes')
  console.error('   devenues fausses ; il n’en ajoute jamais.')
  process.exit(1)
}

console.log('✅ Tous les appels littéraux visent une fonction réelle, appelable, avec ses vrais arguments.')
