import { describe, it, expect, vi, beforeEach } from 'vitest'
import fs from 'fs'
import path from 'path'

// R-10 : les relevés réels anonymisés servent aussi au chemin d'import complet
const readFixture = (name: string) => fs.readFileSync(path.resolve(process.cwd(), 'src/lib/__tests__/fixtures', name), 'utf8')

// AUD-G03 : les lecteurs CAMT.053 / MT940 / CFONB n'étaient branchés sur aucun écran —
// l'import de relevé n'enregistrait que le nom du fichier, en « pending ».

const inserted: Record<string, unknown[]> = {}
const updated: Record<string, unknown[]> = {}
const existing: unknown[] = []
const account = { id: 'bank-1', currency: 'EUR', calculated_balance: 0 }

function chain(table: string) {
  const c: Record<string, unknown> = {}
  for (const m of ['select', 'eq', 'or', 'order']) c[m] = vi.fn(() => c)
  // R-10 : l'import relit le compte visé (devise, solde comptable) et lui reprend le
  // solde de clôture du relevé.
  c.maybeSingle = vi.fn(async () => ({ data: table === 'bank_accounts' ? account : null, error: null }))
  c.update = vi.fn((payload: unknown) => {
    updated[table] = ([] as unknown[]).concat(updated[table] || [], payload as unknown[])
    return c
  })
  c.insert = vi.fn(async (rows: unknown) => {
    inserted[table] = ([] as unknown[]).concat(inserted[table] || [], rows as unknown[])
    return { data: null, error: null }
  })
  // Un builder PostgREST s'attend : `await tud(...).eq('id', id)` doit se résoudre.
  c.then = (resolve: (v: unknown) => unknown) => resolve({ data: null, error: null })
  return c
}

vi.mock('@/lib/supabase', () => ({
  supabase: { from: (t: string) => chain(t) },
  // `tud`/`ti` (core.ts) filtrent par société sur les tables multi-tenant
  isTenantTable: () => true,
}))
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
    for (const k of Object.keys(updated)) delete updated[k]
    existing.length = 0
    account.currency = 'EUR'
    account.calculated_balance = 0
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

  // ============================================================
  // R-10 — devise du relevé et solde de clôture
  // ============================================================

  it('refuse un relevé libellé dans une autre devise que le compte', async () => {
    const { importBankStatement, BankStatementCurrencyError } = await import('@/lib/queries/banking')
    const erreur = await importBankStatement('bank-1', 'releve-usd.xml', readFixture('releve-camt053-usd.xml')).catch(e => e)
    expect(erreur).toBeInstanceOf(BankStatementCurrencyError)
    expect(erreur).toMatchObject({ code: 'bank_statement_currency_mismatch', statementCurrency: 'USD', accountCurrency: 'EUR' })
    // Le refus est total : ni ligne de relevé, ni trace d'import, ni solde repris.
    expect(inserted.bank_transactions).toBeUndefined()
    expect(inserted.bank_statement_imports).toBeUndefined()
    expect(updated.bank_accounts).toBeUndefined()
  })

  it('ne refuse pas un relevé muet sur sa devise, même sur un compte en DJF', async () => {
    account.currency = 'DJF'
    const { importBankStatement } = await import('@/lib/queries/banking')
    const sansDevise = ':20:X\n:25:FR76\n:60F:C2501011000,00\n:61:250101C10,00NTRFREF1\n:86:RECU\n:62F:C2501011010,00'
    const res = await importBankStatement('bank-1', 'releve-muet.sta', sansDevise)
    expect(res.imported).toBe(1)
  })

  it('reprend le solde de clôture du relevé sur le compte, avec son écart', async () => {
    account.calculated_balance = 900
    const { importBankStatement } = await import('@/lib/queries/banking')
    const res = await importBankStatement('bank-1', 'releve.sta', MT940)
    expect(res).toMatchObject({ closingBalance: 1380, closingBalanceDate: '2025-01-02' })
    expect(updated.bank_accounts).toEqual([
      { statement_balance: 1380, statement_balance_date: '2025-01-02', reconciliation_diff: 480 },
    ])
  })

  it('un relevé OFX suit le même chemin que les autres formats', async () => {
    const { importBankStatement } = await import('@/lib/queries/banking')
    const res = await importBankStatement('bank-1', 'releve.ofx', readFixture('releve-ofx1-sgml.ofx'))
    expect(res).toMatchObject({
      format: 'ofx',
      parsed: 3,
      imported: 3,
      duplicates: 0,
      closingBalance: 1107,
      closingBalanceDate: '2025-01-03',
    })
    const lignes = inserted.bank_transactions as Array<Record<string, unknown>>
    expect(lignes.map(r => [r.type, r.amount])).toEqual([['credit', 500], ['debit', 120], ['debit', 273]])
  })

  it('un relevé sans solde de clôture ne touche pas au solde du compte', async () => {
    const { importBankStatement } = await import('@/lib/queries/banking')
    const sansSolde = ':20:X\n:25:FR76\n:61:250101C10,00NTRFREF1\n:86:RECU'
    const res = await importBankStatement('bank-1', 'partiel.sta', sansSolde)
    expect(res.imported).toBe(1)
    expect(res.closingBalance).toBeNull()
    expect(updated.bank_accounts).toBeUndefined()
  })
})
