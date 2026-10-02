#!/usr/bin/env node
/**
 * Mesures du suivi des chantiers — `doc/audit/SUIVI-CHANTIERS.md`.
 *
 * Pourquoi ce script : un suivi écrit à la main se périme le soir même (le
 * dépôt l'a vécu deux fois : « W7 reste ouverte » le 28/09, « reste ≈ 2 j » le
 * 30/09). Les lignes du suivi qui se MESURENT sont donc recalculées ici, depuis
 * le dépôt, et réécrites entre les marqueurs `<!-- MESURES:DEBUT -->` et
 * `<!-- MESURES:FIN -->` du document. Le reste du document (décisions, actions
 * humaines, verdicts) se tient à la main, dans le commit qui change l'état.
 *
 * Usage :
 *   node scripts/suivi-chantiers.mjs            # affiche les mesures
 *   node scripts/suivi-chantiers.mjs --write    # les réécrit dans le document
 *   node scripts/suivi-chantiers.mjs --check    # échoue si le bloc est périmé
 *
 * Le script ne lit que le dépôt (fichiers et `git ls-tree`) : ni base, ni réseau.
 */
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'

const appRoot = join(dirname(fileURLToPath(import.meta.url)), '..')
const repoRoot = join(appRoot, '..')
const docPath = join(repoRoot, 'doc/audit/SUIVI-CHANTIERS.md')
const BEGIN = '<!-- MESURES:DEBUT -->'
const END = '<!-- MESURES:FIN -->'

const git = (...args) => {
  try {
    return execFileSync('git', args, { cwd: repoRoot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch {
    return ''
  }
}

function walk(dir, exts, skip = ['node_modules', 'dist', '.git']) {
  if (!existsSync(dir)) return []
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = join(dir, e.name)
    if (e.isDirectory()) return skip.includes(e.name) ? [] : walk(p, exts, skip)
    return exts.some((x) => p.endsWith(x)) ? [p] : []
  })
}
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '')
const rel = (p) => relative(repoRoot, p)

// ── 1. Migrations : un numéro = un nom, sur TOUTES les branches de travail ──
// Le runner refuse un doublon (SOC-06) ; ce relevé le voit AVANT la fusion.
// Seules les migrations comptent : une suite peut porter un autre nom que sa
// migration (`450_chain_integrite_referentielle_tests` pour `450_chain_document_types`).
function migrationCollisions() {
  const branches = git('for-each-ref', '--format=%(refname:short)', 'refs/heads')
    .split('\n')
    .filter((b) => /^(main|commercial-hr-paie|partie-|qa\/|l\d)/.test(b))
  const byNum = new Map()
  const add = (file, where) => {
    const m = /^(\d{3})_(.+)\.sql$/.exec(file)
    if (!m || file.endsWith('_tests.sql')) return
    if (!byNum.has(m[1])) byNum.set(m[1], new Map())
    const names = byNum.get(m[1])
    if (!names.has(m[2])) names.set(m[2], new Set())
    names.get(m[2]).add(where)
  }
  for (const b of branches)
    for (const f of git('ls-tree', '--name-only', b, 'app/sql/').split('\n')) add(f.replace(/^app\/sql\//, ''), b)
  for (const f of readdirSync(join(appRoot, 'sql'))) add(f, 'copie de travail')
  return [...byNum]
    .sort()
    .filter(([, names]) => names.size > 1)
    .map(([num, names]) => ({ num, names: [...names].map(([n, w]) => `\`${num}_${n}\` (${[...w].join(', ')})`) }))
}

// ── 2. Les sondes, une par chantier mesurable ──
const src = walk(join(appRoot, 'src'), ['.ts', '.tsx']).filter((f) => !f.includes('database-generated'))
const srcText = (filter = () => true) => src.filter(filter).map(read).join('\n')
const countFiles = (re, filter = () => true) => src.filter(filter).filter((f) => re.test(read(f))).length

const sqlDir = join(appRoot, 'sql')
const sqlFiles = readdirSync(sqlDir).filter((f) => f.endsWith('.sql'))
const migrations = sqlFiles.filter((f) => /^\d{3}_/.test(f) && !f.endsWith('_tests.sql'))
const suites = sqlFiles.filter((f) => f.endsWith('_tests.sql'))

function coquilles() {
  // Coquille = table créée par une migration, que ni l'écran (src/) ni une
  // fonction Edge ne nomme, et que le SQL ne nomme que dans du DDL (≤ 1 ligne
  // de logique tolérée : une liste de tables d'un générateur de politiques).
  const migSql = migrations.map((f) => read(join(sqlDir, f)))
  const tables = new Set()
  for (const t of migSql)
    for (const m of t.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?"?([a-z_0-9]+)"?\s*\(/gi))
      tables.add(m[1].toLowerCase())
  const front = srcText() + '\n' + walk(join(appRoot, 'supabase/functions'), ['.ts']).map(read).join('\n')
  const ddl = /^\s*(create\s+(table|unique\s+index|index|policy|trigger)|alter\s+table|grant|revoke|comment\s+on|drop\s+(policy|trigger|index|table)|--)/i
  const lines = migSql.flatMap((t) => t.split('\n'))
  const res = []
  for (const t of [...tables].sort()) {
    const re = new RegExp(`\\b${t}\\b`, 'i')
    if (re.test(front)) continue
    const logic = lines.filter(
      (l) => re.test(l) && !ddl.test(l) && !/^\s*on\s+/i.test(l) && !/\bon\s+(public\.)?\w+\s+(for|to|using)\b/i.test(l) && !/references\s/i.test(l),
    ).length
    if (logic <= 1) res.push(t)
  }
  return res
}

const anyCeiling = JSON.parse(read(join(appRoot, '.any-ceiling.json')) || '{}')
const unusedCeiling = JSON.parse(read(join(appRoot, '.unused-tables-ceiling.json')) || '{}')
const ci = read(join(repoRoot, '.github/workflows/ci.yml'))
const e2eOnLabel = /e2e-tests:[\s\S]{0,400}contains\(github\.event\.pull_request\.labels/.test(ci)
const chartAccounts = read(join(appRoot, 'src/pages/ChartAccountsPage.tsx'))
const fn = (name) => read(join(appRoot, `supabase/functions/${name}/index.ts`))
const expectedSql = read(join(sqlDir, 'ci/expected_failures.sql'))
const expectedScreen = read(join(appRoot, 'src/__screen__/expected_failures.json'))
const suite412 = sqlFiles.find((f) => /^412_.*_tests\.sql$/.test(f))
const coq = coquilles()
const collisions = migrationCollisions()
const authSuites = suites.filter((f) => /\b(user_totp|api_keys)\b/.test(read(join(sqlDir, f))))

const ok = (b) => (b ? '✅' : '⬜')
const rows = [
  ['Branche de la copie de travail', `\`${git('branch', '--show-current') || '?'}\` @ \`${git('rev-parse', '--short', 'HEAD')}\``, '—'],
  ['Migrations / suites SQL dans `app/sql`', `${migrations.length} / ${suites.length}`, '—'],
  [
    '**Numéros de migration en collision entre branches** (SOC-06)',
    collisions.length ? `🔴 ${collisions.length} : ${collisions.map((c) => c.names.join(' ≠ ')).join(' ; ')}` : '✅ 0',
    'alerte',
  ],
  ['Registre SQL `ci/expected_failures.sql` (lignes `INSERT`)', String((expectedSql.match(/insert\s+into/gi) || []).length), 'registre'],
  ['Registre écran `__screen__/expected_failures.json`', expectedScreen.trim() === '[]' ? '✅ vide' : '🔶 non vide', 'registre'],
  ['`confirmSync` (= `window.confirm`) — fichiers', String(countFiles(/\bconfirmSync\b/, (f) => !f.endsWith('lib/confirm.ts'))), 'AUD-I01 · 1.8 · UX-03'],
  ['`useConfirm` / `confirmDialog` — fichiers', String(countFiles(/\b(useConfirm|confirmDialog)\b/)), 'AUD-I01 · 1.8'],
  [
    'Champs factices du plan comptable (`nbLines`, `pageBreak`, `regrouping`)',
    /chartAccounts\.(nbLines|pageBreak|regrouping)/.test(chartAccounts) ? '⬜ présents' : '✅ retirés',
    'AUD-I02 · 1.10',
  ],
  ['Suite `412` (caisse) finit par `_audit_assert`', ok(suite412 && /_audit_assert\(/.test(read(join(sqlDir, suite412)))), '1.2'],
  [
    '`parse-bank-statement` / `ai-import-mapping` refusent sans consentement',
    `${ok(/OCR_CONSENT|409/.test(fn('parse-bank-statement')))} / ${ok(/OCR_CONSENT|409/.test(fn('ai-import-mapping')))}`,
    'D-5 · AUD-H04 · 1.11',
  ],
  ['`get_vat_codes` (correctif TVA 198) présent en base', ok(migrations.some((f) => /get_vat_codes/.test(read(join(sqlDir, f))))), '1.7'],
  ['e2e Playwright sur chaque PR vers `main`', e2eOnLabel ? '⬜ sur étiquette seulement' : '✅', 'AUD-J01 · 4.3'],
  [
    '`any` explicites (plafond gelé : production / tests)',
    `${anyCeiling.production ?? '?'} / ${anyCeiling.tests ?? '?'} (gelé le ${anyCeiling.frozenAt ?? '?'})`,
    'AUD-J07 · DAT-02',
  ],
  ['Tables non lues par l\'écran (plafond)', `${unusedCeiling.unusedTables ?? '?'} (gelé le ${unusedCeiling.frozenAt ?? '?'})`, 'SOC-05'],
  ['**Tables coquilles** (ni écran, ni Edge, SQL = DDL seul)', `${coq.length}`, 'ORPH-02 · SOC-05'],
  ['Suites SQL qui exercent `user_totp` / `api_keys`', String(authSuites.length), 'ORPH-01 · SEC-02'],
]

const date = new Date().toISOString().slice(0, 10)
const block = [
  BEGIN,
  `*Mesuré le **${date}** par \`node app/scripts/suivi-chantiers.mjs --write\` — ne pas éditer à la main.*`,
  '',
  '| Mesure | Valeur | Chantier |',
  '|---|---|---|',
  ...rows.map((r) => `| ${r.join(' | ')} |`),
  '',
  `<details><summary>Les ${coq.length} tables coquilles</summary>`,
  '',
  coq.map((t) => `\`${t}\``).join(' · ') || '—',
  '',
  '</details>',
  END,
].join('\n')

const args = new Set(process.argv.slice(2))
if (args.has('--write') || args.has('--check')) {
  const doc = read(docPath)
  const i = doc.indexOf(BEGIN)
  const j = doc.indexOf(END)
  if (i < 0 || j < 0) {
    console.error(`Marqueurs ${BEGIN} / ${END} absents de ${rel(docPath)}`)
    process.exit(1)
  }
  const strip = (s) => s.replace(/\*Mesuré le \*\*\d{4}-\d{2}-\d{2}\*\*/, '').replace(/`[^`]+` @ `[0-9a-f]+`/, '')
  const current = doc.slice(i, j + END.length)
  if (args.has('--check')) {
    if (strip(current) !== strip(block)) {
      console.error('❌ Le bloc de mesures du suivi est périmé : lancer `node app/scripts/suivi-chantiers.mjs --write`.')
      process.exit(1)
    }
    console.log('✅ Bloc de mesures du suivi à jour.')
  } else {
    writeFileSync(docPath, doc.slice(0, i) + block + doc.slice(j + END.length))
    console.log(`✅ ${rel(docPath)} : bloc de mesures réécrit (${date}).`)
  }
} else {
  console.log(block)
}
