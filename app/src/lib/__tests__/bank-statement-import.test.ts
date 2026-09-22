import { describe, it, expect, vi, beforeEach } from 'vitest'

// AUD-G03 : les lecteurs CAMT.053 / MT940 / CFONB n'étaient branchés sur aucun écran —
// l'import de relevé n'enregistrait que le nom du fichier, en « pending ».

const inserted: Record<string, unknown[]> = {}
const existing: unknown[] = []

function chain(table: string) {
  const c: Record<string, unknown> = {}
  for (const m of ['select', 'eq', 'or', 'order']) c[m] = vi.fn(() => c)
  c.insert = vi.fn(async (rows: unknown) => {
    inserted[table] = ([] as unknown[]).concat(inserted[table] || [], rows as unknown[])
    return { data: null, error: null }
  })
  return c
}

vi.mock('@/lib/supabase', () => ({ supabase: { from: (t: string) => chain(t) } }))
vi.mock('@/lib/queries/core', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/queries/core')>()
  return {
    ...actual,
    getTenantId: vi.fn(async () => 't1'),
    fetchAllRows: vi.fn(async () => existing),
    ti: (row: Record<string, unknown>, _t: string, tid: string) => ({ ...row, tenant_id: tid }),
  }
})

const MT940 = `:20:STMT001
:25:FR123456789
:60F:C250101EUR1000,00
:61:250101250101C500,00NTRF
:86:Virement reçu
:61:250102250102D120,00NCHG
:86:Frais bancaires
:62F:C250102EUR1380,00`

describe('importBankStatement (AUD-G03)', () => {
  beforeEach(() => {
    for (const k of Object.keys(inserted)) delete inserted[k]
    existing.length = 0
  })

  it('importe les opérations du relevé comme lignes de relevé signées, rattachées au compte', async () => {
    const { importBankStatement } = await import('@/lib/queries/banking')
    const res = await importBankStatement('bank-1', 'releve.sta', MT940)
    expect(res).toMatchObject({ format: 'mt940', parsed: 2, imported: 2, duplicates: 0 })
    const rows = inserted.bank_transactions as Array<Record<string, unknown>>
    expect(rows).toHaveLength(2)
    expect(rows.map(r => [r.type, r.amount])).toEqual([['credit', 500], ['debit', 120]])
    for (const r of rows) expect(r).toMatchObject({ bank_account_id: 'bank-1', account_id: 'bank-1', source: 'import', tenant_id: 't1' })
    expect(inserted.bank_statement_imports).toEqual([expect.objectContaining({ status: 'completed', imported_count: 2, format: 'mt940' })])
  })

  it('écarte une opération déjà importée (même date, montant signé, référence)', async () => {
    const { parseMt940 } = await import('@/lib/bankParsers')
    const first = parseMt940(MT940).transactions[0]
    existing.push({ date: first.date, amount: Math.abs(first.amount), type: first.type, reference: first.reference || null })
    const { importBankStatement } = await import('@/lib/queries/banking')
    const res = await importBankStatement('bank-1', 'releve.sta', MT940)
    expect(res).toMatchObject({ imported: 1, duplicates: 1 })
    expect((inserted.bank_transactions as Array<Record<string, unknown>>).map(r => r.type)).toEqual(['debit'])
  })

  it('un fichier illisible est tracé en échec, sans opération', async () => {
    const { importBankStatement } = await import('@/lib/queries/banking')
    const res = await importBankStatement('bank-1', 'n-importe-quoi.txt', 'ceci n’est pas un relevé')
    expect(res.imported).toBe(0)
    expect(inserted.bank_transactions).toBeUndefined()
    expect(inserted.bank_statement_imports).toEqual([expect.objectContaining({ status: 'failed', imported_count: 0 })])
  })
})
