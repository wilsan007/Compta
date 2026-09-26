import { describe, it, expect, vi, beforeEach } from 'vitest'

/**
 * W4 — les importeurs du front (RH-06, RH-07, RH-09, RH-10), mesurés sur les
 * APPELS réels, pas sur une intention :
 *   * RH-06 : les bornes passent au dernier jour réel (« 2026-04-30 », jamais
 *     « 2026-04-31 » — PostgreSQL refusait la requête, 22008) ;
 *   * RH-07 : le montant vient de `total_amount` ;
 *   * RH-09 : les congés sont filtrés par INTERSECTION ;
 *   * RH-10 : l'insertion est un upsert dont l'arbitre est la clé d'unicité
 *     `uniq_payroll_element_source` (256), donc rejouer ne double pas ;
 *   * et le type d'élément est celui que `calculate_payslip` lit réellement
 *     (`unpaid_leave_deduction`, `expense_reimbursement`, `meal_vouchers`) :
 *     en `absence`, la ligne était ignorée, et en `other` la note de frais
 *     était retranchée du net au lieu d'y être ajoutée.
 */
const h = vi.hoisted(() => ({
  filters: [] as Array<[string, string, string]>,
  ors: [] as string[],
  upserts: [] as Array<{ table: string; payload: any; options: any }>,
  rpcs: [] as string[],
  single: null as any,
  rows: [] as any[],
  table: '',
}))

vi.mock('@/lib/supabase', () => {
  const chain: any = {
    select: () => chain,
    insert: () => chain,
    update: () => chain,
    delete: () => chain,
    eq: () => chain,
    neq: () => chain,
    order: () => chain,
    limit: () => chain,
    in: () => chain,
    not: () => chain,
    is: () => chain,
    range: () => chain,
    gte: (col: string, val: string) => { h.filters.push(['gte', col, val]); return chain },
    lte: (col: string, val: string) => { h.filters.push(['lte', col, val]); return chain },
    lt: (col: string, val: string) => { h.filters.push(['lt', col, val]); return chain },
    or: (filter: string) => { h.ors.push(filter); return chain },
    upsert: (payload: any, options: any) => { h.upserts.push({ table: h.table, payload, options }); return chain },
    maybeSingle: () => Promise.resolve({ data: h.single, error: null }),
    single: () => Promise.resolve({ data: h.single, error: null }),
    then: (resolve: any) => Promise.resolve({ data: h.rows, error: null }).then(resolve),
  }
  return {
    supabase: {
      from: vi.fn((table: string) => { h.table = table; return chain }),
      rpc: vi.fn((name: string) => {
        h.rpcs.push(name)
        return Promise.resolve({ data: { heures: 151.6667, jours: 21.6667 }, error: null })
      }),
    },
    getCachedTenantId: vi.fn(() => 't-1'),
    isTenantTable: vi.fn(() => true),
  }
})

vi.mock('@/lib/queries/core', () => ({
  getTenantId: vi.fn(async () => 't-1'),
  ti: (payload: any) => payload,
  tud: (q: any) => q,
  nextDocumentNumber: vi.fn(async () => 'X-1'),
  fetchAllRows: vi.fn(async () => h.rows),
}))

import {
  importExpenseElements, importLeaveElements, importTimesheetElements, generateMealVoucherElements,
} from '@/lib/queries/leavesAbsences'

beforeEach(() => {
  h.filters = []
  h.ors = []
  h.upserts = []
  h.rpcs = []
  h.single = null
  h.rows = []
  h.table = ''
})

describe('importExpenseElements — RH-06 et RH-07', () => {
  it('interroge avril avec le 30 (jamais le 31) et lit total_amount', async () => {
    h.rows = [{
      id: 'exp-1', employee_id: 'emp-1', number: 'NDF-2026-004',
      period: '2026-04', total_amount: 120, amount: undefined,
    }]
    await importExpenseElements('run-1', 4, 2026)

    // Aucune borne ne porte un « -31 » : avril n'a pas de 31.
    expect(h.ors.some((f) => f.includes('2026-04-30'))).toBe(true)
    expect(JSON.stringify(h.filters)).not.toContain('-31')

    const [write] = h.upserts
    expect(write.table).toBe('payroll_variable_elements')
    expect(write.payload.amount).toBe(120)
    expect(write.payload.element_type).toBe('expense_reimbursement')
    expect(write.payload.period).toBe('2026-04')
    expect(write.payload.source).toBe('expense_report')
    expect(write.payload.source_id).toBe('exp-1')
    expect(write.options).toEqual({
      onConflict: 'tenant_id,employee_id,period,element_type,source,source_id',
      ignoreDuplicates: true,
    })
  })

  it('un montant absent ne devient pas NaN : il vaut 0', async () => {
    h.rows = [{ id: 'exp-2', employee_id: 'emp-1', number: 'NDF-2', period: '2026-04' }]
    await importExpenseElements('run-1', 4, 2026)
    expect(h.upserts[0].payload.amount).toBe(0)
  })
})

describe('importLeaveElements — RH-09 et le diviseur (RH-05)', () => {
  it('filtre par intersection (le congé à cheval entre), et retient le type que le moteur lit', async () => {
    h.rows = [{ id: 'lr-1', employee_id: 'emp-1', leave_type: 'unpaid', days: 3 }]
    h.single = { salary: 2166.67 }   // diviseur jours 21,6667 → 100,00 par jour
    await importLeaveElements('run-1', 4, 2026)

    expect(h.ors[0]).toBe('start_date.lte.2026-04-30,end_date.gte.2026-04-01')
    expect(h.rpcs).toContain('payroll_divisors')

    const [write] = h.upserts
    expect(write.payload.element_type).toBe('unpaid_leave_deduction')
    expect(write.payload.unit_price).toBeCloseTo(100, 2)
    expect(write.payload.amount).toBeCloseTo(300, 2)
    expect(write.options.ignoreDuplicates).toBe(true)
  })

  it('un congé payé ne produit aucun élément', async () => {
    h.rows = [{ id: 'lr-2', employee_id: 'emp-1', leave_type: 'paid', days: 5 }]
    await importLeaveElements('run-1', 4, 2026)
    expect(h.upserts).toHaveLength(0)
  })
})

describe('importTimesheetElements — RH-06 et RH-05', () => {
  it('février est borné au 28, et le taux horaire vient du diviseur de la société', async () => {
    h.rows = [{ id: 'ts-1', employee_id: 'emp-1', hours: 9 }]
    h.single = { salary: 1516.67 }   // / 151,6667 → 10,00 l'heure
    await importTimesheetElements('run-1', 2, 2026)

    expect(h.filters).toContainEqual(['lte', 'date', '2026-02-28'])
    expect(JSON.stringify(h.filters)).not.toContain('2026-02-31')
    expect(h.rpcs).toContain('payroll_divisors')

    const [write] = h.upserts
    expect(write.payload.element_type).toBe('overtime')
    expect(write.payload.unit_price).toBeCloseTo(12.5, 2)   // 10,00 × 1,25
    expect(write.payload.amount).toBeCloseTo(12.5, 2)       // 1 h supplémentaire
  })

  it('un pointage de 8 h ne produit aucune heure supplémentaire', async () => {
    h.rows = [{ id: 'ts-2', employee_id: 'emp-1', hours: 8 }]
    await importTimesheetElements('run-1', 2, 2026)
    expect(h.upserts).toHaveLength(0)
  })
})

describe('generateMealVoucherElements — RH-10', () => {
  it('la source est le lot de paie : relancer l\'import ne double pas', async () => {
    h.single = {
      id: 'cfg-1', voucher_value: 10, employer_share: 60, employee_share: 40,
      eligible_days: ['1', '2', '3', '4', '5'], max_per_month: 20, active: true,
    }
    h.rows = [{ id: 'emp-1', name: 'Amina', department: 'IT' }]
    await generateMealVoucherElements('run-1', 4, 2026)

    const [write] = h.upserts
    expect(write.payload.element_type).toBe('meal_vouchers')
    expect(write.payload.source).toBe('meal_voucher')
    expect(write.payload.source_id).toBe('run-1')
    expect(write.options.ignoreDuplicates).toBe(true)
  })
})

