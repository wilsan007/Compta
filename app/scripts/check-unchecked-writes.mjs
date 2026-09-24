#!/usr/bin/env node
/**
 * check-unchecked-writes.mjs — W0.3
 *
 * L'ANGLE MORT QUE CE CONTRÔLE FERME. `npm run audit:silent` (audit-silent-failures.mjs)
 * cherche une déstructuration INCOMPLÈTE — `const { data } = …` sans `error`. Il ne
 * voit pas l'absence TOTALE de déstructuration :
 *
 *     await supabase.from('payroll_variable_elements').insert(rows)   // personne ne lit error
 *
 * L'écriture échoue, la suite s'exécute, l'écran affiche « enregistré ». Mesuré le
 * 23/09/2026 : **29 écritures dans cet état**, dont quatre alimentations de la paie.
 * C'est la même famille de défaut que les 21 colonnes fantômes (W0.2) : les deux
 * réunis expliquent pourquoi la paie pouvait ne rien recevoir sans que rien ne
 * le dise.
 *
 * LA RÈGLE. Le résultat d'une écriture Supabase (`.insert()` / `.update()` /
 * `.upsert()` / `.delete()`) est lu : déstructuré (`.error`), assigné, retourné,
 * ou chaîné (`.then()` / `.catch()`). Sinon la ligne est signalée.
 *
 * LA BASELINE EST GELÉE, et un plafond ne peut que baisser : une écriture inscrite
 * qui disparaît du code fait échouer la CI (la ligne doit être retirée dans le
 * même commit). `--update-baseline` ne sait que retirer.
 *
 * Usage :
 *   node scripts/check-unchecked-writes.mjs
 *   node scripts/check-unchecked-writes.mjs --update-baseline
 *
 * Sortie : code 1 si une écriture nouvelle n'est pas contrôlée, ou si une ligne
 * gelée n'existe plus. Code 0 sinon.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.join(__dirname, '..')
const BASELINE = path.join(__dirname, 'verify-rules', 'unchecked-writes.baseline.json')
const UPDATE = process.argv.includes('--update-baseline')

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

const findings = []
for (const file of files) {
  const rel = path.relative(ROOT, file)
  const lines = fs.readFileSync(file, 'utf8').split('\n')
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i]
    // Début d'une expression `await supabase…` dont le résultat n'est pas affecté.
    // `const { error } = await supabase…` ne commence pas par `await`.
    if (!/^\s*await\s+supabase\b/.test(l)) continue

    // Lire l'instruction complète, jusqu'à l'équilibrage des parenthèses.
    let stmt = ''
    let depth = 0
    let j = i
    for (; j < lines.length && j < i + 40; j++) {
      stmt += lines[j] + '\n'
      for (const ch of lines[j]) {
        if (ch === '(') depth++
        else if (ch === ')') depth--
      }
      if (depth <= 0 && /[)\s;]$/.test(lines[j].trim())) break
    }
    if (!/\.(insert|update|upsert|delete)\s*\(/.test(stmt)) continue
    if (/\.(then|catch|finally)\s*\(/.test(stmt)) continue // chaînée : l'erreur est traitée
    if (/\breturn\s+await\s+supabase\b/.test(stmt)) continue // retournée à l'appelant
    if (/\bvoid\s+await\s+supabase\b/.test(stmt)) continue // écartée explicitement

    findings.push({ file: rel, line: i + 1, code: l.trim() })
    i = j
  }
}

// Une entrée de baseline par (fichier, instruction), avec le NOMBRE d'occurrences :
// le numéro de ligne bouge à chaque édition, le nombre d'occurrences, lui, ne doit
// pas augmenter sans qu'on le sache. C'est ce nombre qui porte le total du 23/09
// (29 écritures), et non le nombre d'instructions distinctes.
const key = (f) => `${f.file}|${f.code}`
const seen = new Map()
for (const f of findings) {
  const k = key(f)
  const cur = seen.get(k)
  if (cur) cur.occurrences++
  else seen.set(k, { ...f, occurrences: 1 })
}
const found = [...seen.keys()].sort()
const totalOccurrences = findings.length

// --json : imprime les constats bruts (sert à geler ou à relire la baseline)
if (process.argv.includes('--json')) {
  console.log(JSON.stringify([...seen.values()], null, 2))
  process.exit(0)
}

if (!fs.existsSync(BASELINE)) {
  console.error(`❌ Baseline absente : ${path.relative(ROOT, BASELINE)}`)
  process.exit(2)
}
const baseline = JSON.parse(fs.readFileSync(BASELINE, 'utf8'))
const frozen = new Map(baseline.findings.map((f) => [key(f), f]))

const nouveaux = found.filter((k) => !frozen.has(k))
const disparus = [...frozen.keys()].filter((k) => !seen.has(k))
const aggravés = found.filter((k) => frozen.has(k) && seen.get(k).occurrences > frozen.get(k).occurrences)

if (UPDATE) {
  if (nouveaux.length > 0 || aggravés.length > 0) {
    console.error('❌ --update-baseline refuse d’AJOUTER des écritures non contrôlées :')
    for (const k of nouveaux) console.error(`   ${k}`)
    for (const k of aggravés) {
      console.error(`   ${k}  (${frozen.get(k).occurrences} → ${seen.get(k).occurrences} occurrences)`)
    }
    console.error('   Corrigez la lecture de l’erreur, ou inscrivez la ligne à la main.')
    process.exit(1)
  }
  baseline.findings = baseline.findings
    .filter((f) => seen.has(key(f)))
    .map((f) => ({ ...f, occurrences: seen.get(key(f)).occurrences, line: seen.get(key(f)).line }))
  baseline.frozenAt = new Date().toISOString().slice(0, 10)
  baseline.total = baseline.findings.reduce((n, f) => n + f.occurrences, 0)
  fs.writeFileSync(BASELINE, JSON.stringify(baseline, null, 2) + '\n')
  console.log(`✅ Baseline mise à jour : ${baseline.total} écriture(s) gelée(s).`)
  process.exit(0)
}

console.log(
  `Écritures : ${files.length} fichiers, ${totalOccurrences} occurrence(s) sans contrôle d’erreur, ` +
    `${found.length} instruction(s) distincte(s).`
)
console.log(`Baseline  : ${baseline.total || frozen.size} occurrence(s) gelée(s) le ${baseline.frozenAt || 'inconnu'}.`)

if (nouveaux.length > 0 || aggravés.length > 0) {
  console.error('\n❌ ÉCRITURE(S) DONT L’ERREUR N’EST PAS LUE :')
  for (const k of nouveaux) {
    const f = seen.get(k)
    console.error(`   ${f.file}:${f.line}  ${f.code.slice(0, 100)}`)
  }
  for (const k of aggravés) {
    const f = seen.get(k)
    console.error(`   ${f.file}:${f.line}  ×${f.occurrences} (gelé ×${frozen.get(k).occurrences})  ${f.code.slice(0, 90)}`)
  }
  console.error('\n   Au 23/09/2026 : 29 écritures, dont quatre alimentations de la paie.')
  console.error('   Une écriture qui échoue sans le dire est pire qu’une écriture absente.')
  console.error('   Lisez `error` : `const { error } = await …; if (error) throw error`.')
  process.exit(1)
}

if (disparus.length > 0) {
  console.error('\n❌ ÉCRITURE(S) GELÉE(S) QUI N’EXISTENT PLUS — la ligne doit être retirée :')
  for (const k of disparus) console.error(`   ${k}  — ${frozen.get(k).reason || 'sans raison'}`)
  console.error('\n   `node scripts/check-unchecked-writes.mjs --update-baseline` retire les lignes')
  console.error('   devenues fausses ; il n’en ajoute jamais.')
  process.exit(1)
}

console.log('✅ Aucune écriture nouvelle sans contrôle d’erreur, et aucune ligne gelée périmée.')
