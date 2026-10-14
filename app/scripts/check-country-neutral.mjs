#!/usr/bin/env node
/**
 * Garde-fou « anti-code-en-dur » — règle **E01** de l'annexe E du cahier de
 * localisation (doc/localisation/CAHIER-DES-CHARGES-LOCALISATION.md).
 *
 * POURQUOI CE GARDE-FOU. Tant qu'un compte est écrit en clair (`'641000'`,
 * `'411000'`, `'512000'`…), une société djiboutienne lit un plan français : le
 * pack ne sert à rien et la neutralité pays reste une intention. E01 interdit le
 * littéral de **3 à 6 chiffres** — `'[1-9]\d{2,5}'` — quand il sert de COMPTE :
 * affecté à un nom `*account*`, `*compte*`, `*collectif*`, ou passé à
 * `getSolde`. Le remplacement attendu est `resolve_account` / `resolveAccount`.
 *
 * DEUX GISEMENTS, DEUX COMPTEURS :
 *   * `front` — `app/src/**\/*.{ts,tsx}` hors `__tests__`, `test/`,
 *               `i18n/locales` (exclusions de l'annexe E, telles quelles) ;
 *   * `sql`   — les définitions **effectives** des fonctions (`pg_proc.prosrc`,
 *               schéma `public`), lues sur la base migrée. C'est là qu'est
 *               l'essentiel de la dette : le front ne fait que recopier des
 *               comptes que les triggers ont déjà choisis.
 *
 * DOCTRINE DU DÉPÔT (identique à `check-any-ceiling.mjs` et
 * `check-knip-ceiling.mjs`) : le plafond est **GELÉ** dans
 * `app/.country-neutral-ceiling.json`. Une **hausse** fait échouer la CI ; une
 * **baisse** abaisse le plafond **automatiquement**. Le compteur ne peut donc que
 * descendre, tranche après tranche (partie C, `LOC1-10` → `LOC1-58`) — et il
 * **nomme** ce qu'il compte : un audit qui ne dit pas où sont les occurrences
 * oblige à instrumenter le garde-fou pour savoir quoi corriger.
 *
 * LES AUTRES RÈGLES DE L'ANNEXE E (E02 → E10 : `LIKE '4%'`, littéraux de
 * journal, `'EUR'`, `toFixed(2)`, `round(x, 2)`…) s'ajouteront **ici**, chacune
 * avec sa recette et son compteur. Ce fichier est le lieu unique du garde-fou ;
 * il ne se duplique pas en un script par règle.
 *
 * USAGE
 *   node scripts/check-country-neutral.mjs                # front + SQL (si base)
 *   node scripts/check-country-neutral.mjs --front-only   # front seul (job lint)
 *   node scripts/check-country-neutral.mjs --list         # nomme chaque occurrence
 */
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join, dirname, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = join(__dirname, '..')
const srcDir = join(appRoot, 'src')
const ceilingFile = join(appRoot, '.country-neutral-ceiling.json')

const args = process.argv.slice(2)
const frontOnly = args.includes('--front-only')
const listAll = args.includes('--list')

// ── E01 : le littéral interdit, et les noms qui en font un COMPTE ───────────
// Un littéral de 3 à 6 chiffres, sans zéro de tête (un compte comptable
// commence par sa classe, 1 à 9).
const _LITERAL_RE = /['"]([1-9]\d{2,5})['"]/g
// Le nom qui prouve qu'on parle d'un compte — et pas d'un montant, d'une TVA
// ou d'un code produit.
const ACCOUNT_NAME_RE = /(account|compte|collectif)/i
// `getSolde('603')` : le littéral EST la question posée aux comptes.
const GET_SOLDE_RE = /getSolde\s*\(\s*['"][1-9]\d{2,5}['"]/

// ── Le registre des exceptions — un littéral QUI N'EST PAS un compte ─────────
// Même esprit que `sql/ci/expected_failures.sql` : une exception se DÉCLARE avec
// sa raison, sinon elle n'existe pas. Le comptage est par fichier ET par
// littéral : une autre valeur dans le même fichier reste comptée.
const NOT_AN_ACCOUNT = [
  {
    file: 'src/components/PartnerBankAccountsModal.tsx',
    literal: '12345',
    why: 'exemple de code banque (RIB) dans un `placeholder`, pas un compte',
  },
]

function isExceptional(rel, literal) {
  return NOT_AN_ACCOUNT.some((e) => e.file === rel && e.literal === literal)
}

// ── Le registre du gisement SQL ─────────────────────────────────────────────
// Même règle : une exception se DÉCLARE, avec sa raison ET la tâche qui la
// possède. Sans cette dernière, l'exception devient un oubli.
const SQL_NOT_E01 = [
  {
    fn: 'seed_standard_chart_unchecked',
    why:
      'GABARIT du plan comptable : ces numéros SONT le plan semé dans ' +
      "`chart_accounts` (colonnes `code` / `name`), pas un compte choisi à la " +
      "place du pack — on ne « résout » pas le plan par lui-même. " +
      'Propriétaire : LOC1-13 (transformer `seed_standard_chart` en données du pack FR).',
  },
  {
    fn: 'seed_standard_chart',
    why: 'Même gabarit, même propriétaire (LOC1-13) : enveloppe de `seed_standard_chart_unchecked`.',
  },
]

function isSqlExceptional(fn) {
  return SQL_NOT_E01.some((e) => e.fn === fn)
}

// Exclusions. L'annexe E cite `__tests__`, `test/` et `i18n/locales` ; on y
// ajoute les **rigs d'écran** (`__screen__/`) et les fichiers `.test.`/`.spec.`,
// pour la même raison que `check-any-ceiling.mjs` : ce ne sont pas des comptes
// choisis par du code de production, ce sont des fixtures qui pilotent un écran
// ou vérifient une valeur. Les compter ferait grossir la dette d'un tiers sans
// qu'aucune société ne lise un plan français pour autant — le garde-fou doit
// pointer ce qui se corrige, pas ce qui se supprime avec le test.
function isExcluded(file) {
  const rel = relative(appRoot, file)
  return (
    /(^|\/)__tests__\//.test(rel) ||
    /(^|\/)test\//.test(rel) ||
    /(^|\/)__screen__\//.test(rel) ||
    /(^|\/)i18n\/locales\//.test(rel) ||
    /\.(test|spec)\.(ts|tsx)$/.test(rel)
  )
}

function walk(dir, acc = []) {
  if (!existsSync(dir)) return acc
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) walk(full, acc)
    else if (/\.(ts|tsx)$/.test(entry)) acc.push(full)
  }
  return acc
}

// ── E01 côté FRONT ──────────────────────────────────────────────────────────
// Une ligne est fautive si elle porte un littéral de compte ET parle d'un
// compte, ou si elle interroge `getSolde` avec un littéral.
const LINE_LITERAL_RE = /['"][1-9]\d{2,5}['"]/

function literalsOf(line) {
  return [...line.matchAll(/['"]([1-9]\d{2,5})['"]/g)].map((m) => m[1])
}

const frontHits = []

for (const file of walk(srcDir)) {
  if (isExcluded(file)) continue
  const rel = relative(appRoot, file)
  const lines = readFileSync(file, 'utf8').split('\n')
  lines.forEach((line, index) => {
    const isSolde = GET_SOLDE_RE.test(line)
    if (!isSolde && !(LINE_LITERAL_RE.test(line) && ACCOUNT_NAME_RE.test(line))) return
    const literals = literalsOf(line)
    // Une ligne ne tombe que si AU MOINS UN de ses littéraux est un compte :
    // un exemple déclaré au registre ne fait pas tomber la ligne entière.
    if (literals.length > 0 && literals.every((literal) => isExceptional(rel, literal))) return
    frontHits.push({
      where: `${rel}:${index + 1}`,
      literals,
      snippet: line.trim().replace(/\s+/g, ' ').slice(0, 120),
    })
  })
}

// ── E01 côté SQL ────────────────────────────────────────────────────────────
// Les définitions EFFECTIVES des fonctions : `pg_proc.prosrc`, schéma `public`.
// C'est là qu'est la dette de fond — un trigger qui écrit `'641000'` contamine
// tous les écrans, et le front ne fait que recopier son choix.
//
// La base est facultative : le job `lint-typecheck` de la CI n'en a pas, et la
// recette de `LOC1-10` porte sur `app/src`. Quand la base est là (job
// `db-integration`), le second compteur est mesuré — et gelé comme le premier.
async function scanSql() {
  const databaseUrl = process.env.DATABASE_URL
  if (!databaseUrl && !process.env.PGHOST) return null

  const pg = (await import('pg')).default
  const isLocal = /localhost|127\.0\.0\.1/.test(databaseUrl || process.env.PGHOST || '')
  const client = new pg.Client(
    databaseUrl
      ? { connectionString: databaseUrl, ssl: isLocal ? false : { rejectUnauthorized: true } }
      : {
          host: process.env.PGHOST,
          port: Number(process.env.PGPORT || 5432),
          user: process.env.PGUSER,
          password: process.env.PGPASSWORD,
          database: process.env.PGDATABASE,
          ssl: false,
        }
  )

  await client.connect()
  const { rows } = await client.query(`
    SELECT p.proname, p.prosrc
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
    ORDER BY p.proname
  `)
  await client.end()

  const sqlHits = []
  for (const row of rows) {
    // Les fixtures de suites (`_…`) ne sont pas des fonctions de production :
    // même convention que les gardes de `391`/`392`/`393`.
    if (/^_/.test(row.proname)) continue
    // Le gabarit de plan comptable est déclaré au registre, avec son
    // propriétaire (LOC1-13) : c'est le plan lui-même, pas un compte en dur.
    if (isSqlExceptional(row.proname)) continue
    const lines = String(row.prosrc || '').split('\n')
    lines.forEach((line, index) => {
      if (!LINE_LITERAL_RE.test(line) || !ACCOUNT_NAME_RE.test(line)) return
      sqlHits.push({
        where: `${row.proname}:${index + 1}`,
        literals: literalsOf(line),
        snippet: line.trim().replace(/\s+/g, ' ').slice(0, 120),
      })
    })
  }
  return sqlHits
}

// ── Le plafond gelé, et le verdict ──────────────────────────────────────────
const today = new Date().toISOString().slice(0, 10)

// Le plafond vit dans `app/.country-neutral-ceiling.json`. Créé au premier
// passage, il accueille aussi un compteur **jamais mesuré** — le SQL tant que la
// base n'est pas branchée — à sa PREMIÈRE mesure : on ne peut pas échouer contre
// un plafond qui n'existe pas encore. Ensuite il est gelé : une hausse est rouge,
// une baisse abaisse le plafond.
function loadCeiling(observed) {
  const existing = existsSync(ceilingFile) ? JSON.parse(readFileSync(ceilingFile, 'utf8')) : null
  const ceiling = existing ?? {}
  let froze = existing === null
  for (const [key, value] of Object.entries(observed)) {
    if (ceiling[key] === undefined) {
      ceiling[key] = value
      froze = true
    }
  }
  if (froze) {
    const ordered = {
      front: ceiling.front,
      ...(ceiling.sql !== undefined ? { sql: ceiling.sql } : {}),
      frozenAt: today,
    }
    writeFileSync(ceilingFile, JSON.stringify(ordered, null, 2) + '\n')
    return { ceiling: ordered, froze: true }
  }
  return { ceiling, froze: false }
}

function nameThem(label, hits, ceilingValue) {
  console.error(
    `❌ ${label} : ${hits.length} > plafond ${ceilingValue} — ${hits.length - ceilingValue} nouvelle(s) occurrence(s) de compte en dur.`
  )
  console.error('   Où (top 15) :')
  for (const h of hits.slice(0, 15)) {
    console.error(`   - ${h.where}  [${h.literals.join(', ')}]  ${h.snippet}`)
  }
  if (hits.length > 15) {
    console.error(`   … et ${hits.length - 15} autre(s) — \`--list\` les nomme toutes.`)
  }
}

async function main() {
  const sqlHits = frontOnly ? null : await scanSql()
  const observed = { front: frontHits.length, ...(sqlHits ? { sql: sqlHits.length } : {}) }
  const { ceiling, froze } = loadCeiling(observed)

  console.log('=== Garde-fou anti-code-en-dur — règle E01 (annexe E) ===')
  console.log(`Front (app/src) : ${frontHits.length} occurrence(s)   (plafond : ${ceiling.front ?? '—'})`)
  if (sqlHits) {
    console.log(`SQL (pg_proc)   : ${sqlHits.length} occurrence(s)   (plafond : ${ceiling.sql ?? '—'})`)
  } else {
    console.log('SQL (pg_proc)   : non mesuré — pas de base (job lint), ou --front-only')
  }
  console.log('')

  if (listAll) {
    console.log('--- occurrences FRONT ---')
    for (const h of frontHits) console.log(`  ${h.where}  [${h.literals.join(', ')}]  ${h.snippet}`)
    if (sqlHits) {
      console.log('--- occurrences SQL ---')
      for (const h of sqlHits) console.log(`  ${h.where}  [${h.literals.join(', ')}]  ${h.snippet}`)
    }
    console.log('')
  }

  if (froze) {
    console.log(
      `🔒 Plafond gelé : front ${ceiling.front}` +
        `${ceiling.sql !== undefined ? `, SQL ${ceiling.sql}` : ''} (${relative(appRoot, ceilingFile)})`
    )
    console.log('')
  }

  let failed = false
  if (frontHits.length > (ceiling.front ?? 0)) {
    nameThem('Front (app/src)', frontHits, ceiling.front)
    failed = true
  }
  if (sqlHits && sqlHits.length > (ceiling.sql ?? 0)) {
    nameThem('SQL (pg_proc)', sqlHits, ceiling.sql)
    failed = true
  }

  if (failed) {
    console.error('')
    console.error('ÉCHEC : un compte est écrit en clair là où le pack doit répondre.')
    console.error("  Cible : `resolve_account(société, RÔLE)` (SQL) / `resolveAccount(RÔLE)` (front).")
    console.error('  Catalogue : `account_role_catalog` (383), correspondances : `pack_account_roles` (385).')
    console.error('  Ne PAS relever le plafond pour faire passer la CI. Si le fichier appartient à une')
    console.error("  autre partie (R3), inscrire la demande dans PARTIE-C.md et l'occurrence reste due.")
    process.exit(1)
  }

  const lowered = []
  if (frontHits.length < (ceiling.front ?? 0)) lowered.push(`front ${ceiling.front}→${frontHits.length}`)
  if (sqlHits && sqlHits.length < (ceiling.sql ?? 0)) lowered.push(`SQL ${ceiling.sql}→${sqlHits.length}`)

  if (lowered.length) {
    const next = { ...ceiling, front: frontHits.length, frozenAt: today }
    if (sqlHits) next.sql = sqlHits.length
    writeFileSync(ceilingFile, JSON.stringify(next, null, 2) + '\n')
    console.log(`✅ OK : plafond ABAISSÉ (${lowered.join(' ; ')}) — la dette ne peut que descendre.`)
  } else {
    console.log('✅ OK : la dette E01 tient dans son plafond.')
  }
}

main().catch((err) => {
  console.error('❌ check-country-neutral : échec inattendu —', err.message)
  process.exit(1)
})
