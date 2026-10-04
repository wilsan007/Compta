import { describe, it, expect, vi, beforeEach } from 'vitest'

/**
 * W9 — la cohérence de l'écran avec les actions de la BASE, mesurée sur les
 * appels réels :
 *
 *   * le registre d'absence se LIT par les RPC de la base (`absence_calendar`,
 *     `absence_summary`, `absence_conflicts_current`) — l'écran ne recompose
 *     jamais la règle de priorité, sinon deux écrans divergeraient ;
 *   * les paramètres NON fournis sont OMIS — un `null` explicite écraserait le
 *     défaut de la base et `d.day BETWEEN NULL AND …` ne rendrait aucune ligne,
 *     en silence (le défaut « zéro trouvé » que W0 a appris à traquer) ;
 *   * le solde de congés n'est plus écrit par l'écran : trois fonctions le
 *     faisaient (création, approbation, rejet, annulation), en plus du
 *     déclencheur de la 263 — donc deux fois — et un import le perdait ;
 *   * la provision de congés utilise LE diviseur de la société
 *     (`payroll_divisors`, 256) et non le `/ 21` que l'écran portait encore.
 */
const h = vi.hoisted(() => ({
  rpcs: [] as Array<{ name: string; args: any }>,
  writes: [] as Array<{ table: string; op: string }>,
  payloads: [] as Array<{ table: string; op: string; payload: any }>,
  rpcResult: null as any,
  single: null as any,
  rows: [] as any[],
  table: '',
}))

vi.mock('@/lib/supabase', () => {
  const chain: any = {
    select: () => chain,
    insert: (payload: any) => {
      h.writes.push({ table: h.table, op: 'insert' })
      h.payloads.push({ table: h.table, op: 'insert', payload })
      return chain
    },
    update: (payload: any) => {
      h.writes.push({ table: h.table, op: 'update' })
      h.payloads.push({ table: h.table, op: 'update', payload })
      return chain
    },
    delete: () => { h.writes.push({ table: h.table, op: 'delete' }); return chain },
    eq: () => chain,
    order: () => chain,
    limit: () => chain,
    maybeSingle: () => Promise.resolve({ data: h.single, error: null }),
    single: () => Promise.resolve({ data: h.single, error: null }),
    then: (resolve: any) => Promise.resolve({ data: h.rows, error: null }).then(resolve),
  }
  return {
    supabase: {
      from: vi.fn((table: string) => { h.table = table; return chain }),
      rpc: vi.fn((name: string, args: any) => {
        h.rpcs.push({ name, args })
        return Promise.resolve({ data: h.rpcResult, error: null })
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
  getAbsenceCalendar, getAbsenceConflicts, getAbsenceSummary,
  createMyLeaveRequest, approveLeaveRequest, rejectLeaveRequest, cancelMyLeaveRequest,
  calculateLeaveProvisions,
} from '@/lib/queries/leavesAbsences'

beforeEach(() => {
  h.rpcs = []
  h.writes = []
  h.payloads = []
  h.rpcResult = null
  h.single = null
  h.rows = []
  h.table = ''
})

describe('le registre d’absence se lit par la base', () => {
  it('getAbsenceCalendar n’envoie que les paramètres fournis (le défaut de la base reste actif)', async () => {
    h.rpcResult = []
    await getAbsenceCalendar()
    expect(h.rpcs).toHaveLength(1)
    expect(h.rpcs[0].name).toBe('absence_calendar')
    // Aucun `p_from`/`p_to`/`p_employee` posé : la base applique SES défauts
    // (le mois courant). Les passer à `null` rendrait zéro ligne en silence.
    expect(h.rpcs[0].args).toEqual({})
  })

  it('getAbsenceCalendar transmet le salarié et la plage quand ils sont fournis', async () => {
    h.rpcResult = []
    await getAbsenceCalendar('emp-1', '2026-07-01', '2026-07-31')
    expect(h.rpcs[0].args).toEqual({ p_employee: 'emp-1', p_from: '2026-07-01', p_to: '2026-07-31' })
  })

  it('getAbsenceConflicts interroge absence_conflicts_current — sans bornes par défaut', async () => {
    h.rpcResult = []
    await getAbsenceConflicts()
    expect(h.rpcs[0]).toEqual({ name: 'absence_conflicts_current', args: {} })
  })

  it('getAbsenceSummary passe la société active et les bornes', async () => {
    h.rpcResult = { days_total: 1 }
    const res = await getAbsenceSummary('emp-1', '2026-07-01', '2026-07-31')
    expect(h.rpcs[0]).toEqual({
      name: 'absence_summary',
      args: { p_tenant: 't-1', p_employee: 'emp-1', p_from: '2026-07-01', p_to: '2026-07-31' },
    })
    expect(res).toEqual({ days_total: 1 })
  })

  it('une erreur du RPC est LEVÉE, jamais remplacée par une liste vide', async () => {
    const { supabase } = await import('@/lib/supabase')
    ;(supabase.rpc as any).mockImplementationOnce((name: string, args: any) => {
      h.rpcs.push({ name, args })
      return Promise.resolve({ data: null, error: { message: 'Plage invalide (2026-08-01 → 2026-07-01)' } })
    })
    await expect(getAbsenceConflicts('2026-08-01', '2026-07-01')).rejects.toThrow(/Plage invalide/)
  })
})

describe('le solde de congés est tenu par la BASE, pas par l’écran (TRV-15)', () => {
  it('createMyLeaveRequest n’écrit aucune ligne de leave_balances', async () => {
    h.single = { id: 'lr-1' }
    await createMyLeaveRequest({
      employee_id: 'emp-1', leave_type: 'annual', start_date: '2026-07-06', end_date: '2026-07-08', days: 3,
    })
    expect(h.writes).toEqual([{ table: 'leave_requests', op: 'insert' }])
    expect(h.writes.some((w) => w.table === 'leave_balances')).toBe(false)
  })

  it('approveLeaveRequest n’écrit que leave_requests', async () => {
    h.single = { id: 'lr-1' }
    await approveLeaveRequest('lr-1', 'mgr-1')
    expect(h.writes).toEqual([{ table: 'leave_requests', op: 'update' }])
  })

  it('rejectLeaveRequest n’écrit que leave_requests', async () => {
    h.single = { id: 'lr-1' }
    await rejectLeaveRequest('lr-1', 'mgr-1')
    expect(h.writes).toEqual([{ table: 'leave_requests', op: 'update' }])
  })

  it('cancelMyLeaveRequest n’écrit que leave_requests', async () => {
    h.single = { id: 'lr-1' }
    await cancelMyLeaveRequest('lr-1')
    expect(h.writes).toEqual([{ table: 'leave_requests', op: 'update' }])
    expect(h.writes.some((w) => w.table === 'leave_balances')).toBe(false)
  })
})

describe('la provision de congés lit LE diviseur de la société (suite de RH-05)', () => {
  it('valorise la journée avec le diviseur « jours » de la société : 2 600 / 26 = 100,00, jamais 2 600 / 21', async () => {
    h.rpcResult = { heures: 151.6667, jours: 26 }
    h.single = null               // aucune provision existante → une création
    h.rows = [{ id: 'emp-1', name: 'Aya', salary: 2600 }]
    await calculateLeaveProvisions('2026-07')

    expect(h.rpcs[0]).toEqual({ name: 'payroll_divisors', args: undefined })
    const creation = h.payloads.find((p) => p.table === 'leave_provisions')
    expect(creation).toBeTruthy()
    expect(creation!.payload.daily_rate).toBeCloseTo(100, 4)
  })

  it('refuse de valoriser quand le diviseur de la société est introuvable (jamais un taux à 0 en silence)', async () => {
    h.rpcResult = { heures: 151.6667, jours: 0 }
    h.rows = [{ id: 'emp-1', name: 'Aya', salary: 2600 }]
    await expect(calculateLeaveProvisions('2026-07')).rejects.toThrow(/diviseur/i)
  })
})

