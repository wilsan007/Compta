import { describe, it, expect, vi, beforeEach } from 'vitest'

// ============ Mock infra ============
// getFECData passe par supabase.from(...) ; on rejoue des pages de 1 000 lignes.
const mockState: {
  pages: Record<string, unknown[][]>
  calls: Array<{ table: string; from: number; to: number }>
} = { pages: {}, calls: [] }

function makeChain(table: string) {
  const chain: any = {
    select: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    in: vi.fn(() => chain),
    order: vi.fn(() => chain),
    limit: vi.fn(() => chain),
    not: vi.fn(() => chain),
    gte: vi.fn(() => chain),
    lte: vi.fn(() => chain),
    or: vi.fn(() => chain),
    range: vi.fn((from: number, to: number) => {
      mockState.calls.push({ table, from, to })
      const pages = mockState.pages[table] ?? []
      const index = Math.floor(from / 1000)
      return Promise.resolve({ data: pages[index] ?? [], error: null })
    }),
    then: vi.fn((resolve: any) => {
      const pages = mockState.pages[table] ?? []
      return Promise.resolve({ data: pages[0] ?? [], error: null }).then(resolve)
    }),
  }
  return chain
}

vi.mock('@/lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => makeChain(table)),
    auth: { getSession: vi.fn(() => Promise.resolve({ data: { session: null } })) },
    rpc: vi.fn(() => Promise.resolve({ data: null, error: null })),
  },
  getCachedTenantId: vi.fn(() => 'tenant-1'),
  isTenantTable: vi.fn(() => true),
}))

import { fetchAllRows, PAGE_SIZE } from '@/lib/queries/core'
import { getFECData } from '@/lib/queries/accounting'

function rows(n: number, offset = 0) {
  return Array.from({ length: n }, (_, i) => ({ id: `r${offset + i}` }))
}

beforeEach(() => {
  mockState.pages = {}
  mockState.calls = []
})

describe('fetchAllRows', () => {
  it('rapatrie toutes les pages : 1000 + 1000 + 3 = 2003 lignes', async () => {
    const pages = [rows(1000, 0), rows(1000, 1000), rows(3, 2000)]
    let call = 0
    const query = {
      range: vi.fn((_from: number, _to: number) =>
        Promise.resolve({ data: pages[call++] ?? [], error: null })
      ),
    }

    const all = await fetchAllRows<{ id: string }>(query)

    expect(all).toHaveLength(2003)
    expect(all[0].id).toBe('r0')
    expect(all[2002].id).toBe('r2002')
    expect(query.range).toHaveBeenCalledTimes(3)
    expect(query.range).toHaveBeenNthCalledWith(1, 0, 999)
    expect(query.range).toHaveBeenNthCalledWith(2, 1000, 1999)
    expect(query.range).toHaveBeenNthCalledWith(3, 2000, 2999)
  })

  it("s'arrête à la première page incomplète", async () => {
    const query = { range: vi.fn(() => Promise.resolve({ data: rows(42), error: null })) }
    const all = await fetchAllRows(query)
    expect(all).toHaveLength(42)
    expect(query.range).toHaveBeenCalledTimes(1)
  })

  it('rend un tableau vide quand la table est vide (data null inclus)', async () => {
    const query = { range: vi.fn(() => Promise.resolve({ data: null, error: null })) }
    expect(await fetchAllRows(query)).toEqual([])
  })

  it('remonte une page pleine puis vide sans dupliquer', async () => {
    const pages = [rows(1000, 0), []]
    let call = 0
    const query = {
      range: vi.fn(() => Promise.resolve({ data: pages[call++] ?? [], error: null })),
    }
    const all = await fetchAllRows(query)
    expect(all).toHaveLength(1000)
    expect(query.range).toHaveBeenCalledTimes(2)
  })

  it('accepte une fabrique de builder', async () => {
    const pages = [rows(1000, 0), rows(2, 1000)]
    let call = 0
    const factory = vi.fn(() => ({
      range: vi.fn(() => Promise.resolve({ data: pages[call++] ?? [], error: null })),
    }))
    const all = await fetchAllRows(factory)
    expect(all).toHaveLength(1002)
    expect(factory).toHaveBeenCalledTimes(2)
  })

  it('propage une erreur PostgREST', async () => {
    const query = {
      range: vi.fn(() => Promise.resolve({ data: null, error: { message: 'boom' } })),
    }
    await expect(fetchAllRows(query)).rejects.toEqual({ message: 'boom' })
  })

  it('lève au-delà du plafond maxRows au lieu de boucler sans fin', async () => {
    const query = { range: vi.fn(() => Promise.resolve({ data: rows(1000), error: null })) }
    await expect(fetchAllRows(query, { maxRows: 3000 })).rejects.toThrow(/plus de 3000 lignes/)
  })

  it('respecte une taille de page personnalisée', async () => {
    const query = { range: vi.fn(() => Promise.resolve({ data: rows(10), error: null })) }
    await fetchAllRows(query, { pageSize: 50 })
    expect(query.range).toHaveBeenCalledWith(0, 49)
  })

  it('PAGE_SIZE vaut max_rows de supabase/config.toml', () => {
    expect(PAGE_SIZE).toBe(1000)
  })
})

describe('getFECData', () => {
  it("n'est plus tronqué à 1 000 écritures (export légal exhaustif)", async () => {
    mockState.pages['fiscal_periods'] = [[{ id: 'p1' }]]
    mockState.pages['journal_entries'] = [rows(1000, 0), rows(1000, 1000), rows(3, 2000)]

    const fec = await getFECData('fy-1')

    expect(fec).toHaveLength(2003)
    const entryCalls = mockState.calls.filter((c) => c.table === 'journal_entries')
    expect(entryCalls).toEqual([
      { table: 'journal_entries', from: 0, to: 999 },
      { table: 'journal_entries', from: 1000, to: 1999 },
      { table: 'journal_entries', from: 2000, to: 2999 },
    ])
  })

  it('pagine aussi les périodes fiscales', async () => {
    mockState.pages['fiscal_periods'] = [[{ id: 'p1' }, { id: 'p2' }]]
    mockState.pages['journal_entries'] = [[]]
    await getFECData('fy-1')
    expect(mockState.calls.some((c) => c.table === 'fiscal_periods' && c.from === 0)).toBe(true)
  })

  it('rend un tableau vide si aucune période', async () => {
    mockState.pages['fiscal_periods'] = [[]]
    expect(await getFECData('fy-1')).toEqual([])
  })
})
