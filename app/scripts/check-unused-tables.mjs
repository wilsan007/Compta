#!/usr/bin/env node
/**
 * LOT6-04 : Détection des tables métier jamais lues par le frontend
 *
 * Croise les tables du schéma SQL avec les références dans src/lib/queries/
 * pour identifier les tables qui ne sont jamais lues par l'application.
 *
 * Le plafond est gelé dans .unused-tables-ceiling.json.
 * Toute augmentation fait échouer la CI.
 */

import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = join(__dirname, '..')
const sqlDir = join(appRoot, 'sql')
const queriesDir = join(appRoot, 'src', 'lib', 'queries')
const ceilingFile = join(appRoot, '.unused-tables-ceiling.json')

// 1. Extraire les noms de tables depuis le schéma SQL
function extractTableNames() {
  const tables = new Set()
  const files = readdirSync(sqlDir).filter(f => f.endsWith('.sql'))
  for (const file of files) {
    // Les commentaires SQL sont retirés avant la lecture : une phrase comme
    // « APRÈS le CREATE TABLE puis… » ou « `CREATE TABLE IF NOT EXISTS` ne… »
    // inscrivait une table « puis » ou « IF » (mesuré le 03/10/2026).
    const content = readFileSync(join(sqlDir, file), 'utf8').replace(/^\s*--.*$/gm, '')
    // CREATE TABLE IF NOT EXISTS [public.]table_name (
    const matches = content.matchAll(/CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+(?:public\.)?"?(\w+)/gi)
    for (const m of matches) {
      tables.add(m[1])
    }
  }
  return Array.from(tables).sort()
}

// 2. Extraire les références de tables dans src/lib/queries/
function extractTableReferences() {
  const refs = new Set()
  function scanDir(dir) {
    for (const entry of readdirSync(dir)) {
      const fullPath = join(dir, entry)
      const stat = statSync(fullPath)
      if (stat.isDirectory()) {
        scanDir(fullPath)
      } else if (entry.endsWith('.ts') || entry.endsWith('.tsx')) {
        const content = readFileSync(fullPath, 'utf8')
        // .from('table_name') ou .from("table_name")
        const fromMatches = content.matchAll(/\.from\(['"`](\w+)['"`]/g)
        for (const m of fromMatches) refs.add(m[1])
        // .rpc('function_name' — pas une table mais on l'ignore
      }
    }
  }
  scanDir(queriesDir)
  // Aussi scanner src/pages pour les requêtes directes
  const pagesDir = join(appRoot, 'src', 'pages')
  if (existsSync(pagesDir)) {
    function scanPages(dir) {
      for (const entry of readdirSync(dir)) {
        const fullPath = join(dir, entry)
        const stat = statSync(fullPath)
        if (stat.isDirectory()) {
          scanPages(fullPath)
        } else if (entry.endsWith('.tsx')) {
          const content = readFileSync(fullPath, 'utf8')
          const fromMatches = content.matchAll(/\.from\(['"`](\w+)['"`]/g)
          for (const m of fromMatches) refs.add(m[1])
        }
      }
    }
    scanPages(pagesDir)
  }
  return refs
}

// 3. Tables métier (exclure les tables système, vues, et tables d'audit)
const SYSTEM_TABLE_PREFIXES = [
  'pg_', 'schema_', 'sql_', 'cron_', 'supabase_', 'audit_',
]
const SYSTEM_TABLES = [
  'migrations', 'sql_migrations_tracker', 'rls_audit',
  'supabase_migrations', 'schema_migrations',
]

// Tables lues et écrites uniquement par des fonctions SQL (triggers, RPC) :
// aucun écran n'a à les lire. Chaque entrée dit pourquoi ; ne pas s'en servir
// pour masquer une table métier qui attend son écran.
const SERVER_ONLY_TABLES = {
  journal_posting_sequences: '187 — compteur de numérotation des écritures validées (post_journal_entry)',
  chart_required_accounts: '201 — comptes exigés avant publication d\'un plan (contrôle serveur)',
  chart_provisional_fallbacks: '201 — correspondances du plan provisoire DJ, lues par la bascule',
  chart_pack_switch_log: '201 — journal technique des bascules de plan',
  payroll_account_mapping: '191 — comptes de la paie par rubrique, lus par payroll_post_run ; remplacés par les rôles de comptes (LOC1-34), pas d\'écran prévu',
  platform_admins: '201 — administrateurs plateforme, vérifiés par les RPC d\'import de plan',
  // ── W9 (263) : le registre d'absence ───────────────────────
  // Il n'est JAMAIS lu en direct par un écran, et c'est délibéré : la règle de
  // priorité entre les quatre sources (accident > maladie > maternité > arrêt >
  // sans solde > congé payé > mission) et les drapeaux calculés (blocks_work,
  // allows_expenses, paid, pay_rule_code) vivent dans la BASE. Un écran qui
  // lirait la table et recomposerait la règle divergerait au premier changement.
  // Les écrans le lisent par `absence_calendar()` et `absence_summary()`.
  employee_absence_days: '263 (W9) — registre d\'absence : lu par absence_calendar() / absence_summary(), jamais en direct (la priorité et les drapeaux sont calculés par la base)',

  // ── Socle des chaînages (252, lot L0) ──────────────────────
  // Ces six tables sont écrites par les fonctions du socle (link_documents,
  // emit_domain_event, chain_trace) et lues par la vue chaîne et les tableaux
  // de bord, qui viennent aux lots L5 → L7 et L23. Les deux partitions par
  // défaut sont du stockage : elles ne se lisent jamais en direct (leurs droits
  // sont retirés et leur RLS activée, mesuré par sql/252_chain_socle_tests.sql).
  document_links: '252 (L0) — registre de chaîne : écrit par link_documents(), lu par la vue chaîne du lot L6',
  document_effects: '252 (L0) — contrat d\'effet, donnée de référence lue par chain_autorise() ; l\'écran d\'administration arrive au lot L7',
  domain_events: '252 (L0) — journal d\'événements : alimenté par emit_domain_event() ; automatisations et webhooks au lot L23',
  chain_traces: '252 (L0) — traces d\'exécution des maillons, lues par les tableaux de bord internes du lot L5',
  chain_regeneration_log: '252 (L0) — historique des régénérations (M-04), append-only, relu par l\'audit',
  chain_settings: '252 (L0) — drapeau d\'application par société, lu par chain_enforcement_mode() ; l\'écran arrive au lot L5',
  domain_events_defaut: '252 (L0) — partition par défaut du journal d\'événements : stockage, jamais lue en direct',
  chain_traces_defaut: '252 (L0) — partition par défaut des traces : stockage, jamais lue en direct',
  chain_banc_maillons: '433 (L3) — registre des maillons du banc d\'épreuves : lu par chain_banc_lancer() (service_role) ; la page « Robustesse » (tâche 4.1) l\'affichera',
  chain_banc_resultats: '433 (L3) — verdicts du banc D1→D8, par exécution : écrits par chain_banc_lancer(), lus par la vue de rapport ; la page « Robustesse » (tâche 4.1) les affichera',
  chain_invariant_alertes: '414 (L4) — alertes de dégradation de l\'indice : écrites par le relevé, lues par chain_degradation_detectee(), jamais en direct ; la page « Cohérence » (tâche 4.2) les affichera',
  metric_definitions: '461 (I-08) — dictionnaire des indicateurs : lu par chain_metric_definition(), jamais en direct (la définition en vigueur à une date est résolue par la base)',
  chain_document_types: '450 (Partie 5) — registre des types de document des chaînages : lu par link_documents(), la garde de suppression (453) et INV-19 (455) ; l\'écran traduit les types par i18n (errors:chain.types)',
}

function isBusinessTable(name) {
  if (SYSTEM_TABLES.includes(name)) return false
  if (Object.hasOwn(SERVER_ONLY_TABLES, name)) return false
  for (const prefix of SYSTEM_TABLE_PREFIXES) {
    if (name.startsWith(prefix)) return false
  }
  // Exclure les vues (commencent souvent par v_)
  if (name.startsWith('v_')) return false
  return true
}

// 4. Calculer les tables non lues
const allTables = extractTableNames()
const referencedTables = extractTableReferences()
const businessTables = allTables.filter(isBusinessTable)
const unusedTables = businessTables.filter(t => !referencedTables.has(t))

console.log('=== LOT6-04 : Tables métier jamais lues par le frontend ===')
console.log(`Tables totales:     ${allTables.length}`)
console.log(`Tables métier:      ${businessTables.length}`)
console.log(`Tables référencées: ${referencedTables.size}`)
console.log(`Tables non lues:    ${unusedTables.length}`)
console.log('')

if (unusedTables.length > 0 && unusedTables.length <= 50) {
  console.log('Tables non lues:')
  for (const t of unusedTables) {
    console.log(`  - ${t}`)
  }
  console.log('')
}

// 5. Vérifier le plafond
let ceiling
if (existsSync(ceilingFile)) {
  ceiling = JSON.parse(readFileSync(ceilingFile, 'utf8'))
} else {
  ceiling = { unusedTables: unusedTables.length, frozenAt: '2026-09-14' }
  writeFileSync(ceilingFile, JSON.stringify(ceiling, null, 2) + '\n')
}

if (unusedTables.length > ceiling.unusedTables) {
  console.error(`❌ ÉCHEC : ${unusedTables.length} tables non lues > plafond ${ceiling.unusedTables}`)
  console.error('   Nouvelles tables non lues:')
  for (const t of unusedTables) {
    console.error(`   - ${t}`)
  }
  process.exit(1)
} else if (unusedTables.length < ceiling.unusedTables) {
  const newCeiling = { unusedTables: unusedTables.length, frozenAt: new Date().toISOString().slice(0, 10) }
  writeFileSync(ceilingFile, JSON.stringify(newCeiling, null, 2) + '\n')
  console.log(`✅ OK : ${unusedTables.length} tables non lues (plafond mis à jour de ${ceiling.unusedTables} à ${unusedTables.length})`)
} else {
  console.log(`✅ OK : ${unusedTables.length} tables non lues (conforme au plafond)`)
}
