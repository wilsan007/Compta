// ============================================================
// qa/validate.mjs — SUPERAGENT 2 : le validateur
//
// Il ne mesure rien : il juge ce que les ouvriers ont rapporté. Il fusionne les
// shards, dédoublonne par empreinte, classe par gravité, confronte le tout au
// registre `.qa-baseline.json` (même doctrine que sql/ci/expected_failures.sql)
// et écrit le rapport — en nommant, pour chaque défaut, l'écran source à ouvrir.
//
//   un défaut hors registre                → échec (exit 1)
//   une entrée du registre repassée verte  → échec (la ligne doit partir)
//   un identifiant inconnu du barème       → échec (une règle a été inventée)
//
// Usage : node scripts/qa/validate.mjs [--baseline]
// ============================================================
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { RULES, SEVERITY_ORDER, summarize, fingerprint } from './lib/rules.mjs'

const DIR = path.dirname(fileURLToPath(import.meta.url))
const APP = path.resolve(DIR, '../..')
const OUT = path.join(APP, '.qa-out')
const SHARDS = path.join(OUT, 'shards')
const BASELINE = path.join(APP, '.qa-baseline.json')
const REPORT = path.join(OUT, `RAPPORT-QA-${new Date().toISOString().slice(0, 10)}.md`)
const ICON = { bloquant: '🔴', majeur: '🟠', mineur: '🟡' }

const loadShards = () => (fs.existsSync(SHARDS)
  ? fs.readdirSync(SHARDS).filter((f) => f.endsWith('.json')).map((f) => JSON.parse(fs.readFileSync(path.join(SHARDS, f), 'utf8')))
  : [])

/**
 * Un verdict qui décrit l'OUTIL et non le produit n'entre pas au rapport.
 * Il est compté, jamais accusé — la même règle que pour un banc d'essai : une
 * panne du moyen de mesure n'est pas un défaut de la pièce mesurée.
 */
function isHarnessCasualty(f) {
  const d = String(f.detail ?? '')
  if (f.id === 'erreur_js' && /has been closed|Target closed/i.test(d)) return true   // navigateur mort en cours de visite
  if (f.id === 'debordement_horizontal' && /^\+0px/.test(d)) return true              // page qui ne défile pas : élément dans un conteneur défilant
  // Machine en veille pendant la tournée : les ressources échouent en masse et
  // l'application renvoie vers /login — c'est l'environnement, pas le produit
  // (constaté le 29/09/2026 : ERR_NETWORK_IO_SUSPENDED).
  if (/ERR_NETWORK_IO_SUSPENDED|ERR_INTERNET_DISCONNECTED|ERR_NAME_NOT_RESOLVED/.test(d)) return true
  return false
}

function readBaseline() {
  if (!fs.existsSync(BASELINE)) return []
  const raw = JSON.parse(fs.readFileSync(BASELINE, 'utf8'))
  return Array.isArray(raw) ? raw : []
}

function main() {
  const shards = loadShards()
  if (!shards.length) {
    console.error(`Aucun shard dans ${path.relative(APP, SHARDS)} — lancer d'abord « node scripts/qa/dispatch.mjs ».`)
    process.exit(2)
  }
  // Intégrité : des shards de deux tournées ne se jugent pas ensemble. Une
  // session parallèle (ou un run oublié) écrivait dans le même dossier et le
  // verdict mélangeait deux mesures (constaté le 29/09/2026).
  const runs = new Set(shards.map((s) => s.run).filter(Boolean))
  if (runs.size > 1) {
    console.error(`Refus : ${runs.size} tournées différentes dans .qa-out/shards (${[...runs].join(' · ')}) — relancer la tournée.`)
    process.exit(2)
  }
  const findings = []
  const seen = new Set()
  const summaries = []
  let casualties = 0
  const meta = { base: shards[0].base, accounts: [], viewports: shards[0].viewports, routes: 0, shards: shards.length, from: shards[0].startedAt, to: shards[0].finishedAt }
  for (const s of shards) {
    meta.accounts.push(s.account)
    if (s.finishedAt > meta.to) meta.to = s.finishedAt
    for (const r of s.summaries ?? []) { summaries.push(r); meta.routes += 1 }
    for (const f of s.findings ?? []) {
      const fp = f.fp || fingerprint(f)
      if (seen.has(fp)) continue
      seen.add(fp)
      if (isHarnessCasualty(f)) { casualties += 1; continue }
      if (!RULES[f.id]) { console.error(`Règle inconnue rapportée par l'ouvrier ${s.shard} : ${f.id}`); process.exitCode = 3 }
      findings.push({ ...f, fp })
    }
  }

  const baseline = readBaseline()
  const known = new Set(baseline.map((b) => b.fp))
  const fresh = findings.filter((f) => !known.has(f.fp))
  const fixed = baseline.filter((b) => !seen.has(b.fp))
  const bySeverity = summarize(findings)

  const perModule = {}
  for (const f of findings) (perModule[f.module] ??= []).push(f)
  const visited = new Set(summaries.map((s) => s.path))
  const clean = [...visited].filter((p) => !findings.some((f) => f.route === p))
  const L = []
  L.push(`# Rapport QA — essaim parallèle`)
  // Les mesures brutes, exploitables par un script (le rapport est fait pour
  // être lu par un humain, ce fichier pour être compté).
  fs.mkdirSync(OUT, { recursive: true })
  fs.writeFileSync(path.join(OUT, 'findings.json'), JSON.stringify(findings, null, 2))
  L.push(``)
  L.push(`- base : \`${meta.base}\``)
  L.push(`- tournée : ${meta.from} → ${meta.to}`)
  L.push(`- ouvriers : ${meta.shards} ; comptes : ${[...new Set(meta.accounts)].join(', ')}`)
  L.push(`- gabarits d'écran : ${(meta.viewports || []).join(', ')}`)
  L.push(``)
  L.push(`## Mesures`)
  L.push(``)
  L.push(`| Mesure | Valeur |`)
  L.push(`|---|---|`)
  L.push(`| visites d'écran | ${meta.routes} |`)
  L.push(`| routes distinctes visitées | ${visited.size} |`)
  L.push(`| routes sans aucun défaut | ${clean.length} |`)
  L.push(`| défauts (dédoublonnés) | ${findings.length} |`)
  L.push(`| dont bloquants | ${bySeverity.bloquant ?? 0} |`)
  L.push(`| dont majeurs | ${bySeverity.majeur ?? 0} |`)
  L.push(`| dont mineurs | ${bySeverity.mineur ?? 0} |`)
  L.push(`| verdicts écartés (incident de harnais, jamais imputé au produit) | ${casualties} |`)
  L.push(`| onglets ouverts par les agents | ${summaries.reduce((n, s) => n + (Number(String(s.inter?.tabs || '0/0').split('/')[0]) || 0), 0)} |`)
  L.push(`| fenêtres ouvertes par les agents | ${summaries.reduce((n, s) => n + ((s.inter?.opened || []).length), 0)} |`)
  L.push(`| boutons inventoriés | ${summaries.reduce((n, s) => n + (s.buttons || 0), 0)} |`)
  L.push(``)
  for (const sev of SEVERITY_ORDER) {
    const rows = fresh.filter((f) => f.severity === sev)
    const old = findings.filter((f) => f.severity === sev && known.has(f.fp))
    if (!rows.length && !old.length) continue
    L.push(`## ${ICON[sev]} ${sev} — ${rows.length} nouveau(x), ${old.length} déjà au registre`)
    L.push(``)
    L.push(`| route | gabarit | défaut | détail | écran à ouvrir |`)
    L.push(`|---|---|---|---|---|`)
    for (const f of [...rows, ...old].slice(0, 400)) {
      const flag = known.has(f.fp) ? '' : ' **(nouveau)**'
      L.push(`| \`${f.route}\`${flag} | ${f.viewport} | ${f.label} | ${String(f.detail).replace(/\|/g, '\\|').slice(0, 150)} | ${f.source ? '`' + f.source + '`' : '—'} |`)
    }
    L.push(``)
  }
  L.push(`## Défauts par module`)
  L.push(``)
  L.push(`| module | bloquant | majeur | mineur |`)
  L.push(`|---|---|---|---|`)
  for (const [mod, list] of Object.entries(perModule).sort((a, b) => b[1].length - a[1].length)) {
    L.push(`| ${mod} | ${list.filter((f) => f.severity === 'bloquant').length} | ${list.filter((f) => f.severity === 'majeur').length} | ${list.filter((f) => f.severity === 'mineur').length} |`)
  }
  L.push(``)
  const perRule = {}
  for (const f of findings) perRule[f.id] = (perRule[f.id] ?? 0) + 1
  L.push(`## Défauts par règle`)
  L.push(``)
  L.push(`| règle | gravité | nombre | ce qu'elle dit |`)
  L.push(`|---|---|---|---|`)
  for (const [id, n] of Object.entries(perRule).sort((a, b) => b[1] - a[1])) {
    L.push(`| \`${id}\` | ${RULES[id]?.severity ?? '?'} | ${n} | ${RULES[id]?.label ?? '—'} |`)
  }
  L.push(``)
  L.push(`## Registre (\`.qa-baseline.json\`)`)
  L.push(``)
  L.push(`- défauts nouveaux, hors registre : **${fresh.length}**`)
  L.push(`- entrées du registre devenues vertes : **${fixed.length}**`)
  for (const f of fixed.slice(0, 50)) L.push(`  - à retirer : \`${f.fp}\`${f.label ? ` (${f.label})` : ''}`)
  L.push(``)
  L.push(`## Limites de cette tournée`)
  L.push(``)
  L.push(`- un agent ne clique **jamais** un bouton destructeur (supprimer, valider, payer…) : il les inventorie sans les actionner. Les parcours d'écriture irréversible restent couverts par les suites SQL (\`sql/*_tests.sql\`) et les scénarios \`src/__screen__\`.`)
  L.push(`- la société est neuve : les listes montrent l'état vide du produit — c'est vérifié, mais cela ne remplace pas une recette avec des données métier.`)
  L.push(`- en mode \`--light\`, onglets, listes déroulantes et fenêtres ne sont pas ouverts.`)
  L.push(``)
  fs.writeFileSync(REPORT, L.join('\n'))
  console.log(`rapport : ${path.relative(APP, REPORT)}`)
  console.log(`visites ${meta.routes} · routes ${visited.size} · défauts ${findings.length} (bloquants ${bySeverity.bloquant ?? 0}, majeurs ${bySeverity.majeur ?? 0}, mineurs ${bySeverity.mineur ?? 0})`)
  console.log(`registre : ${fresh.length} nouveau(x), ${fixed.length} à retirer`)

  if (process.argv.includes('--baseline')) {
    const next = findings.map((f) => ({ fp: f.fp, id: f.id, route: f.route, viewport: f.viewport, severity: f.severity, label: f.label, detail: String(f.detail).slice(0, 200), notedAt: new Date().toISOString().slice(0, 10) }))
    fs.writeFileSync(BASELINE, JSON.stringify(next, null, 2))
    console.log(`registre mis à jour : ${path.relative(APP, BASELINE)} (${next.length} entrée(s))`)
    return
  }
  if (fresh.length) { console.error(`échec : ${fresh.length} défaut(s) hors registre — corriger, ou les inscrire (« --baseline ») en disant pourquoi.`); process.exitCode = 1 }
  if (fixed.length) { console.error(`échec : ${fixed.length} entrée(s) du registre ne se reproduisent plus — les retirer.`); process.exitCode = 1 }
  if (!fresh.length && !fixed.length) console.log('aucun écart avec le registre.')
}

main()

