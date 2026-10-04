import { describe, it, expect, vi, beforeEach } from 'vitest'

// AUD-E05 / AUD-F02 : la conversion devis → facture et l'écriture de paie sont
// faites par le serveur (RPC). Avant V3, le front les fabriquait lui-même :
// facture sans vat_amount (1 200 ≠ 1 000) et écriture de paie sans cotisations
// salariales (4 260 ≠ 3 600), envoyée en « posted » et donc toujours refusée.

const rpc = vi.fn()
const from = vi.fn()

vi.mock('@/lib/supabase', () => ({
  supabase: { rpc: (...a: unknown[]) => rpc(...a), from: (...a: unknown[]) => from(...a) },
}))
vi.mock('@/lib/queries/core', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/queries/core')>()
  return { ...actual, getTenantId: vi.fn(async () => 't1') }
})

function chain(result: { data: unknown; error: unknown }) {
  const c: Record<string, unknown> = {}
  for (const m of ['select', 'insert', 'update', 'eq', 'order']) c[m] = vi.fn(() => c)
  c.single = vi.fn(async () => result)
  c.maybeSingle = vi.fn(async () => result)
  return c
}

describe('pièces produites par le serveur', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    from.mockImplementation(() => chain({ data: { id: 'inv-1' }, error: null }))
  })

  it('convertQuoteToInvoice appelle convert_quote_to_invoice et n’insère rien lui-même', async () => {
    rpc.mockResolvedValue({ data: { success: true, invoice_id: 'inv-1' }, error: null })
    const { convertQuoteToInvoice } = await import('@/lib/queries/sales')
    const inv = await convertQuoteToInvoice('q-1')
    expect(rpc).toHaveBeenCalledWith('convert_quote_to_invoice', { p_quote_id: 'q-1' })
    const inserted = from.mock.results.some(r => (r.value as { insert: ReturnType<typeof vi.fn> }).insert.mock.calls.length > 0)
    expect(inserted).toBe(false)
    expect(inv).toEqual({ id: 'inv-1' })
  })

  it('generatePayrollJournal appelle post_payroll_journal et ne construit pas l’écriture', async () => {
    rpc.mockResolvedValue({ data: { success: true, entry_id: 'je-1', already_posted: false }, error: null })
    const { generatePayrollJournal } = await import('@/lib/queries/misc')
    const res = await generatePayrollJournal('pr-1')
    expect(rpc).toHaveBeenCalledWith('post_payroll_journal', { p_pay_run_id: 'pr-1' })
    expect(rpc).not.toHaveBeenCalledWith('post_journal_entry', expect.anything())
    expect(res).toMatchObject({ entry_id: 'je-1' })
  })

  it('une erreur du serveur remonte telle quelle', async () => {
    rpc.mockResolvedValue({ data: null, error: new Error('Lot de paie PR6 en brouillon : approuvez-le avant de le comptabiliser') })
    const { generatePayrollJournal } = await import('@/lib/queries/misc')
    await expect(generatePayrollJournal('pr-6')).rejects.toThrow(/brouillon/)
  })
})
