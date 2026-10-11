#!/usr/bin/env node
/**
 * Amorçage « chiffres » de la station de recette (D.5).
 *
 * Les quatre parcours qui lisent un chiffre (`app/e2e/parcours-chiffres.spec.ts`)
 * ont besoin qu'une société porte des chiffres JUSTES. Or un amorçage en SQL est
 * **refusé** par le produit : le garde des écritures n'accepte un `posted` qu'à
 * la validation, un bulletin ne se calcule que par le moteur, un ticket de caisse
 * ne s'encaisse que sur une session ouverte. C'est **voulu** — et c'est une
 * chance : ce script amorce donc **par le produit**, exactement par les mêmes
 * fonctions que l'écran.
 *
 *   écriture  : `post_journal_entry` (brouillon) → `validate_journal_entries`
 *   paie      : salarié + lot → `generate_pay_run_slips` (le moteur calcule)
 *   caisse    : terminal + session → `create_pos_ticket` → clôture
 *
 * Idempotent : relancé, il ne refait rien et le dit.
 *
 * Usage :
 *   E2E_TEST_PASSWORD=… node app/scripts/qa/amorce-chiffres.mjs
 *   (SUPABASE_URL, SUPABASE_KEY, E2E_TEST_EMAIL surchargent les valeurs locales)
 */

const API = process.env.SUPABASE_URL || 'http://127.0.0.1:54321'
const ANON = process.env.SUPABASE_KEY
  || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'
const EMAIL = process.env.E2E_TEST_EMAIL || 'e2e@test.local'
const PASSWORD = process.env.E2E_TEST_PASSWORD || ''

if (!PASSWORD) {
  console.error('E2E_TEST_PASSWORD requis (mot de passe du compte de recette).')
  process.exit(2)
}

const json = async (r) => {
  const t = await r.text()
  try { return JSON.parse(t) } catch { return t }
}

// ── Session ────────────────────────────────────────────────────────────────
const tok = await json(await fetch(`${API}/auth/v1/token?grant_type=password`, {
  method: 'POST', headers: { apikey: ANON, 'content-type': 'application/json' },
  body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
}))
if (!tok.access_token) {
  console.error(`Connexion impossible pour ${EMAIL} :`, tok.error_description || tok.msg || tok)
  process.exit(1)
}
const H = { apikey: ANON, authorization: `Bearer ${tok.access_token}`, 'content-type': 'application/json' }
const tid = (await json(await fetch(
  `${API}/rest/v1/tenant_users?select=tenant_id&auth_id=eq.${tok.user.id}&status=eq.active`,
  { headers: H })))[0]?.tenant_id
if (!tid) {
  console.error(`${EMAIL} n'est rattaché à aucune société active : les parcours porteraient sur /onboarding.`)
  process.exit(1)
}
const HT = { ...H, 'x-tenant-id': tid }
/** `return=representation` rend un tableau ; l'application, elle, fait `.single()`. */
const un = (x) => (Array.isArray(x) ? x[0] : x)

const lire = (chemin) => fetch(`${API}/rest/v1/${chemin}`, { headers: HT }).then(json)
const ecrire = (chemin, corps, methode = 'POST') => fetch(`${API}/rest/v1/${chemin}`, {
  method: methode, headers: { ...HT, prefer: 'return=representation' }, body: JSON.stringify(corps),
}).then(json)
const rpc = (nom, corps) => fetch(`${API}/rest/v1/rpc/${nom}`, {
  method: 'POST', headers: HT, body: JSON.stringify(corps),
}).then(json)

console.log(`société = ${tid} (${EMAIL})`)

// ── 1. L'écriture équilibrée ───────────────────────────────────────────────
// Montants ronds et lisibles : c'est ce que C2 relit dans la balance.
const NUM_ECRITURE = 'VT-E2E-0001'
const dejaEcriture = un(await lire(`journal_entries?select=id,status&number=eq.${NUM_ECRITURE}`))
if (dejaEcriture?.id) {
  console.log(`écriture (déjà là) = ${dejaEcriture.id} — ${dejaEcriture.status}`)
} else {
  const aujourdhui = new Date().toISOString().slice(0, 10)
  const cree = await rpc('post_journal_entry', {
    p_entry: {
      number: NUM_ECRITURE, date: aujourdhui, journal_code: 'VT',
      description: 'Amorçage recette (écriture équilibrée)', status: 'draft',
    },
    p_lines: [
      { account_code: '601000', account_name: 'Achats', debit: 100, credit: 0, description: 'Achat e2e', line_order: 1 },
      { account_code: '401000', account_name: 'Fournisseurs', debit: 0, credit: 100, description: 'Fournisseur e2e', line_order: 2 },
    ],
  })
  if (!cree?.entry_id) {
    console.error('écriture : brouillon refusé —', cree?.error || JSON.stringify(cree))
    process.exit(1)
  }
  // Le brouillon n'entre pas dans la balance : on le VALIDE par la fonction du
  // produit (c'est elle qui pose `posted`, numérote et contrôle l'équilibre).
  const verdict = await rpc('validate_journal_entries', { p_ids: [cree.entry_id] })
  const apres = un(await lire(`journal_entries?select=number,status,total_debit,total_credit&id=eq.${cree.entry_id}`))
  console.log(`écriture (créée) = ${apres?.number} — ${apres?.status} — ${apres?.total_debit} / ${apres?.total_credit}`,
    verdict?.error ? `(validation : ${verdict.error})` : '')
  if (apres?.status !== 'posted') process.exit(1)
}

// ── 2. La paie : c'est le MOTEUR qui calcule le bulletin ───────────────────
// Un salarié sans salaire n'est pas « à 0 » : le moteur refuse de le calculer et
// le NOMME. Le compte technique créé à l'inscription en est un.
const NUM_SALARIE = 'E2E-0001'
let salarie = un(await lire(`employees?select=id,name&employee_number=eq.${NUM_SALARIE}`))
if (salarie?.id) {
  console.log(`salarié (déjà là) = ${salarie.name} ${salarie.id}`)
} else {
  salarie = un(await ecrire('employees', {
    name: 'Dupont Jean', first_name: 'Jean', last_name: 'Dupont',
    position: 'Comptable', department: 'Administration',
    status: 'active', payroll_category: 'non_cadre',
    salary: 2400, base_salary: 2400, contract_type: 'cdi',
    hire_date: '2024-01-15', employee_number: NUM_SALARIE, weekly_hours: 35,
  }))
  console.log('salarié (créé) =', salarie?.name, salarie?.id)
}
if (!salarie?.id) process.exit(1)

const d = new Date()
const y = d.getFullYear(), m = d.getMonth(), pad = (n) => String(n).padStart(2, '0')
const debut = `${y}-${pad(m + 1)}-01`
const fin = new Date(Date.UTC(y, m + 1, 0)).toISOString().slice(0, 10)
const NUM_LOT = `PAIE-E2E-${y}${pad(m + 1)}`
let lot = un(await lire(`pay_runs?select=id,number&number=eq.${NUM_LOT}`))
if (lot?.id) {
  console.log(`lot de paie (déjà là) = ${lot.number} ${lot.id} (${debut} → ${fin})`)
} else {
  lot = un(await ecrire('pay_runs', {
    number: NUM_LOT, period_start: debut, period_end: fin, pay_date: fin, status: 'draft',
  }))
  console.log(`lot de paie (créé) = ${lot?.number} ${lot?.id} (${debut} → ${fin})`)
}
if (!lot?.id) process.exit(1)

// UN appel : la base appelle `calculate_payslip` pour chaque salarié actif de la
// période et rend un verdict par salarié — les refus sont nommés, pas tus.
// Relancer est SANS risque : mesuré, le moteur rend le bulletin existant de la
// période au lieu d'en créer un second (1 ligne pour 1 salarié, après deux
// passages). Le verdict compte un « succès » ; le comptage réel, lui, ne bouge
// pas — c'est pourquoi ce script peut être rejoué avant chaque recette.
const paie = await rpc('generate_pay_run_slips', { p_pay_run_id: lot.id })
console.log(`paie : ${paie?.generes} bulletin(s) généré(s) sur ${paie?.total} salarié(s)`,
  '| refus :', (paie?.echecs || []).map((e) => `${e.employee} — ${e.message}`).join(' ; ') || 'aucun')
for (const b of paie?.bulletins || []) {
  console.log(`  bulletin ${b.employee} : brut ${b.total_gross} → net ${b.net_salary}`)
}

// ── 3. La caisse : encaisser, puis clôturer ────────────────────────────────
let terminal = un(await lire('pos_terminals?select=id,name&order=name&limit=1'))
if (terminal?.id) {
  console.log(`terminal (déjà là) = ${terminal.name} ${terminal.id}`)
} else {
  terminal = un(await ecrire('pos_terminals', { name: 'Caisse E2E', location: 'Accueil', active: true }))
  console.log('terminal (créé) =', terminal?.name, terminal?.id)
}
if (!terminal?.id) process.exit(1)

const sessions = await lire(`pos_sessions?select=id,status,opening_amount&terminal_id=eq.${terminal.id}&order=opened_at.desc&limit=1`)
let session = Array.isArray(sessions) ? sessions[0] : sessions
if (session?.id) {
  console.log(`session (déjà là) = ${session.id} — ${session.status}, fond ${session.opening_amount}`)
} else {
  session = un(await ecrire('pos_sessions', {
    terminal_id: terminal.id, user_email: EMAIL, opening_amount: 100, status: 'open',
  }))
  console.log(`session (ouverte) = ${session?.id} — fond 100`)
}
if (!session?.id) process.exit(1)

// L'encaissement : totaux calculés par la base (`line_amounts`), la ligne n'a
// même pas besoin d'un article du catalogue.
const tickets = await lire(`pos_tickets?select=id,number,total&session_id=eq.${session.id}`)
if (Array.isArray(tickets) && tickets.length > 0) {
  console.log('ticket (déjà encaissé) =', tickets.map((t) => `${t.number} ${t.total}`).join(', '))
} else {
  const ticket = await rpc('create_pos_ticket', {
    p_ticket: {
      number: 'TICKET-E2E-0001', session_id: session.id, terminal_id: terminal.id,
      date: new Date().toISOString(), payment_method: 'cash', amount_paid: 120,
    },
    p_lines: [{ description: 'Prestation E2E', quantity: 1, unit_price: 100, vat_rate: 20 }],
    p_payments: null,
  })
  console.log(`ticket = ${ticket?.number} | HT ${ticket?.subtotal} | TVA ${ticket?.vat_total} | TTC ${ticket?.total}`,
    ticket?.message ? `ÉCHEC ${ticket.message}` : '')
  if (!ticket?.id) process.exit(1)
}

// Le tiroir : fond 100 + espèces 120 = 220 comptés. L'attendu, l'écart et
// l'écriture de clôture sont posés par le déclencheur de clôture — l'écran ne
// fait que relire ces trois nombres.
if (session.status === 'open') {
  const ferme = un(await ecrire(`pos_sessions?id=eq.${session.id}`, {
    closing_amount: 220, status: 'closed', closed_at: new Date().toISOString(),
  }, 'PATCH'))
  console.log(`clôture = ${ferme?.status} | attendu ${ferme?.expected_amount} | compté ${ferme?.closing_amount} | écart ${ferme?.difference}`,
    ferme?.message ? `ÉCHEC ${ferme.message}` : '')
} else {
  console.log(`clôture (déjà faite) = ${session.status}`)
}

console.log('AMORCE-CHIFFRES-DONE')
