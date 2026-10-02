/**
 * W10 — le contrat d'appel entre l'écran et la base, tenu aussi côté front
 *
 * Le contrôle `scripts/check-rpc-contract.mjs` confronte chaque appel `.rpc()`
 * LITTÉRAL du front et des Edge Functions aux signatures RÉELLES de la base :
 * nom inconnu, argument inconnu, arité, et fonctions de DÉCLENCHEUR
 * (`RETURNS trigger`) que PostgREST n'expose jamais.
 *
 * Ce fichier est son miroir RAPIDE : celui qui tourne dans le job unitaire, sans
 * base. Il tient les deux moitiés du contrat :
 *   — l'appel réel transmet bien le nom et les arguments que la base attend ;
 *   — le front ne RÉINTRODUIT pas les appels mesurés comme impossibles.
 *
 * Les défauts tenus ici, mesurés le 27/09/2026 (14 contrats rompus sur 117) :
 *   · `perform_three_way_match`, `check_customer_credit_limit`,
 *     `apply_bank_reconciliation_rules`, `auto_reconcile_by_score` sont des
 *     DÉCLENCHEURS — PostgREST ne les expose pas (404 garanti) ;
 *   · `increment_stock` / `decrement_stock` étaient appelés APRÈS l'insertion
 *     d'un mouvement de stock, que le déclencheur `update_stock_on_movement`
 *     traite déjà : mauvais arguments ET double comptage ;
 *   · `close_nf525_period` / `get_nf525_attestation` attendent `p_period`
 *     (`AAAA-MM`), pas une plage de dates ;
 *   · `calculate_sick_leave_pay` se calcule sur l'ARRÊT (`p_sick_leave_id`),
 *     pas sur un couple (salarié, jours) ;
 *   · `run_mrp` parcourt les besoins sur un HORIZON, sans produit.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

const rpc = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...a: any[]) => rpc(...a), from: vi.fn() },
  getCachedTenantId: vi.fn(() => 'test-tenant-id'),
  isTenantTable: vi.fn(() => true),
}))

describe('W10 — les appels du front portent le nom ET les arguments de la base', () => {
  beforeEach(() => rpc.mockReset())

  it('rapprochement 3 voies : `run_three_way_match` (et non le déclencheur)', async () => {
    rpc.mockResolvedValue({
      data: [{ match_status: 'matched', total_ordered: 100, quantity_variance: 0 }],
      error: null,
    })
    const { performThreeWayMatch } = await import('@/lib/queries/businessFunctions')

    const res = await performThreeWayMatch('inv-1')

    expect(rpc).toHaveBeenCalledWith('run_three_way_match', { p_invoice_id: 'inv-1' })
    expect(res?.match_status).toBe('matched')
  })

  it('MRP : `run_mrp` avec un horizon en jours, sans produit', async () => {
    rpc.mockResolvedValue({ data: [{ product_id: 'p1', net_need: 5 }], error: null })
    const { runMRP } = await import('@/lib/queries/businessFunctions')

    await runMRP(30)

    expect(rpc).toHaveBeenCalledWith('run_mrp', { p_horizon_days: 30 })
  })

  it('IJSS : `calculate_sick_leave_pay` avec l’arrêt déclaré', async () => {
    rpc.mockResolvedValue({ data: [{ ijss_amount: 120, waiting_days: 3 }], error: null })
    const { calculateSickLeavePay } = await import('@/lib/queries/businessFunctions')

    const res = await calculateSickLeavePay('sl-1')

    expect(rpc).toHaveBeenCalledWith('calculate_sick_leave_pay', { p_sick_leave_id: 'sl-1' })
    expect(res?.ijss_amount).toBe(120)
  })

  it('NF-525 : la période est une PÉRIODE (`AAAA-MM`), pour la clôture ET l’attestation', async () => {
    rpc.mockResolvedValue({ data: { period: '2026-09', event_count: 2 }, error: null })
    const { closeNf525Period, getNf525Attestation } = await import('@/lib/queries/businessFunctions')

    await closeNf525Period('2026-09')
    await getNf525Attestation('2026-09')

    expect(rpc).toHaveBeenCalledWith('close_nf525_period', { p_period: '2026-09' })
    expect(rpc).toHaveBeenCalledWith('get_nf525_attestation', { p_period: '2026-09' })
  })
})

// ─────────────────────────────────────────────────────────────────────────────
// Miroir statique : les appels mesurés comme impossibles ne reviennent pas.
// ─────────────────────────────────────────────────────────────────────────────
const INTERDITS: Array<[string, RegExp]> = [
  ['perform_three_way_match est un DÉCLENCHEUR (404 garanti)', /\.rpc\(\s*'perform_three_way_match'/],
  ['check_customer_credit_limit est un DÉCLENCHEUR (404 garanti)', /\.rpc\(\s*'check_customer_credit_limit'/],
  ['apply_bank_reconciliation_rules est un DÉCLENCHEUR (404 garanti)', /\.rpc\(\s*'apply_bank_reconciliation_rules'/],
  ['auto_reconcile_by_score est un DÉCLENCHEUR (404 garanti)', /\.rpc\(\s*'auto_reconcile_by_score'/],
  ['le stock est mis à jour par `update_stock_on_movement`, pas par le front', /\.rpc\(\s*'(increment|decrement)_stock'/],
  ['`increment_download_count` attend `p_document_id`', /\.rpc\(\s*'increment_download_count'[\s\S]{0,200}?\bdoc_id\s*:/],
  ['`close_nf525_period` attend `p_period`', /\.rpc\(\s*'close_nf525_period'[\s\S]{0,200}?p_period_end/],
  ['`get_nf525_attestation` attend `p_period`', /\.rpc\(\s*'get_nf525_attestation'[\s\S]{0,200}?p_period_start/],
  ['`calculate_sick_leave_pay` attend `p_sick_leave_id`', /\.rpc\(\s*'calculate_sick_leave_pay'[\s\S]{0,200}?p_employee_id/],
  ['`run_mrp` ne prend pas de produit', /\.rpc\(\s*'run_mrp'[\s\S]{0,200}?p_product_id/],
]

// Les commentaires CITENT les appels retirés pour dire ce qui a changé : ce ne
// sont pas des appels. On les retire avant de juger.
function sansCommentaire(ligne: string): string {
  const t = ligne.trim()
  if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*') || t.startsWith('{/*')) return ''
  return ligne.replace(/\/\/.*$/, '').replace(/\{\/\*.*$/, '')
}

function fichiersSource(dir: string): string[] {
  const out: string[] = []
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) {
      if (/__tests__|node_modules|\/types$/.test(p)) continue
      out.push(...fichiersSource(p))
    } else if (/\.(ts|tsx)$/.test(p) && !/database-generated|\.test\./.test(p)) {
      out.push(p)
    }
  }
  return out
}

describe('W10 — le front ne rappelle pas ce qui ne peut pas aboutir', () => {
  const racine = path.resolve(__dirname, '../../..') // app/
  const src = path.join(racine, 'src')

  it('aucun fichier de src/ ne porte un appel mesuré comme impossible', () => {
    const fautifs: string[] = []
    for (const f of fichiersSource(src)) {
      const code = fs
        .readFileSync(f, 'utf8')
        .split('\n')
        .map(sansCommentaire)
        .join('\n')
      for (const [nom, motif] of INTERDITS) {
        if (motif.test(code)) fautifs.push(`${path.relative(racine, f)} → ${nom}`)
      }
    }
    expect(fautifs).toEqual([])
  })

  it('le front ne remet pas le stock à jour lui-même (un seul moteur : le déclencheur)', () => {
    const code = fs
      .readFileSync(path.join(src, 'lib/queries/stock.ts'), 'utf8')
      .split('\n')
      .map(sansCommentaire)
      .join('\n')
    // 2026-10-02 (Partie 5, 454) : assertion PRÉCISÉE. Elle interdisait tout
    // `.rpc(` dans stock.ts ; son objet est que le front ne recalcule pas la
    // QUANTITÉ en stock (W10 : increment_stock / decrement_stock appelés après
    // l'insertion du mouvement). `release_stock_reservation` (454) laisse la
    // base rendre la quantité réservée : c'est le moteur unique, pas un second.
    // Verdict précédent : expect(code).not.toMatch(/\.rpc\(/)
    expect(code).not.toMatch(/\.rpc\(\s*['"](increment_stock|decrement_stock|update_stock[a-z_]*|adjust_stock[a-z_]*)['"]/)
  })
})

