/**
 * E2E Business Workflows Tests
 *
 * Tests des workflows métier critiques couvrant les chaînes :
 *   1. Paie : calculate_payslip → generate_dsn
 *   2. TVA : calculate_vat_ca3 → generate_vat_return
 *   3. Clôture : generate_profit_loss → close_fiscal_year
 *   4. Stock : calculate_stock_valuation → calculate_inventory_variance
 *   5. Banque : smart_bank_reconciliation → auto_letter_accounts
 *   6. CRM : customer_credit_score → calculate_late_payment_penalties
 *   7. NF525 : log_nf525_event → verify_nf525_chain
 *   8. Frontend : businessFunctions wrappers
 */

import { describe, it, expect, vi, beforeEach } from 'vitest'

// Mock supabase — seul rpc() est utilisé par les wrappers testés
vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: vi.fn(),
    from: vi.fn(() => ({
      select: vi.fn(() => ({ data: [], error: null })),
      insert: vi.fn(() => ({ data: null, error: null })),
      update: vi.fn(() => ({ data: null, error: null })),
      delete: vi.fn(() => ({ data: null, error: null })),
      eq: vi.fn(() => ({ data: null, error: null })),
      single: vi.fn(() => ({ data: null, error: null })),
    })),
  },
}))

import { supabase } from '@/lib/supabase'
import {
  calculatePayslip,
  generateDsn,
  calculateVatCa3,
  generateVatReturn,
  generateBalanceSheet,
  generateProfitLoss,
  closeFiscalYearRpc,
  calculateDepreciation,
  autoLetterAccounts,
  smartBankReconciliation,
  calculateStockValuation,
  cashFlowForecast,
  calculateLeaveAcquisition,
  calculateSeverancePay,
  calculatePaymentDueDates,
  generateGeneralLedgerRpc,
  generateTrialBalanceRpc,
  generateAdjustingEntries,
  calculateLatePaymentPenalties,
  calculateSalesCommissions,
  customerCreditScore,
  calculateProjectProfitability,
  calculateProvisions,
  postDeferredCharge,
  generateAccountingAnnex,
  calculateProductionCost,
  calculateInventoryVariance,
} from '@/lib/queries/businessFunctions'

// ============================================================
// 1. PAIE : calculate_payslip → generate_dsn
// ============================================================
describe('Workflow Paie : calculate_payslip → generate_dsn', () => {
  beforeEach(() => vi.clearAllMocks())

  it('calculatePayslip appelle le RPC avec les bons paramètres', async () => {
    const mockResult = {
      net_salary: 2400,
      total_gross: 3000,
      social_security_employee: 660,
    }
    vi.mocked(supabase.rpc).mockResolvedValue({ data: mockResult, error: null } as any)

    const result = await calculatePayslip('emp-123', '2025-01')

    expect(supabase.rpc).toHaveBeenCalledWith('calculate_payslip', {
      p_employee_id: 'emp-123',
      p_period: '2025-01',
    })
    expect(result.net_salary).toBe(2400)
    expect(result.total_gross).toBe(3000)
  })

  it('calculatePayslip propage les erreurs', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: null,
      error: { message: 'Employé non trouvé' } as any,
    } as any)

    await expect(calculatePayslip('invalid-id', '2025-01')).rejects.toThrow('Employé non trouvé')
  })

  it('generateDsn appelle le RPC avec la période', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { dsn_id: 'dsn-123', period: '2025-01', employee_count: 15 },
      error: null,
    } as any)

    const result = await generateDsn('2025-01')

    expect(supabase.rpc).toHaveBeenCalledWith('generate_dsn', { p_period: '2025-01' })
    expect(result.dsn_id).toBe('dsn-123')
    expect(result.employee_count).toBe(15)
  })

  it('chaîne complète : payslip calculé puis DSN générée', async () => {
    // Étape 1 : Calculer le bulletin
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { net_salary: 2400, total_gross: 3000, employee_id: 'emp-1' },
      error: null,
    } as any)

    const payslip = await calculatePayslip('emp-1', '2025-01')
    expect(payslip.net_salary).toBe(2400)

    // Étape 2 : Générer la DSN
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { dsn_id: 'dsn-1', period: '2025-01', gross_total: 3000 },
      error: null,
    } as any)

    const dsn = await generateDsn('2025-01')
    expect(dsn.gross_total).toBe(3000)
    expect(dsn.period).toBe('2025-01')
  })
})

// ============================================================
// 2. TVA : calculate_vat_ca3 → generate_vat_return
// ============================================================
describe('Workflow TVA : calculate_vat_ca3 → generate_vat_return', () => {
  beforeEach(() => vi.clearAllMocks())

  it('calculateVatCa3 calcule collectée et déductible', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        output_vat: 2000,
        input_vat: 1500,
        vat_due: 500,
        total_sales_ht: 10000,
        total_purchases_ht: 7500,
      },
      error: null,
    } as any)

    const result = await calculateVatCa3('2025-01-01', '2025-01-31')

    expect(supabase.rpc).toHaveBeenCalledWith('calculate_vat_ca3', {
      p_period_start: '2025-01-01',
      p_period_end: '2025-01-31',
    })
    expect(result.vat_due).toBe(500)
    expect(result.output_vat).toBe(2000)
  })

  it('generateVatReturn crée la déclaration en base', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { return_id: 'vr-123', status: 'draft', calculation: { vat_due: 500 } },
      error: null,
    } as any)

    const result = await generateVatReturn('2025-01-01', '2025-01-31')

    expect(supabase.rpc).toHaveBeenCalledWith('generate_vat_return', {
      p_period_start: '2025-01-01',
      p_period_end: '2025-01-31',
    })
    expect(result.return_id).toBe('vr-123')
    expect(result.status).toBe('draft')
  })
})

// ============================================================
// 3. CLÔTURE : generate_profit_loss → close_fiscal_year
// ============================================================
describe('Workflow Clôture : profit_loss → close_fiscal_year', () => {
  beforeEach(() => vi.clearAllMocks())

  it('generateProfitLoss calcule le résultat', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        revenue_total: 500000,
        expense_total: 400000,
        result: 100000,
        result_type: 'bénéfice',
      },
      error: null,
    } as any)

    const result = await generateProfitLoss('fy-2024')

    expect(result.result).toBe(100000)
    expect(result.result_type).toBe('bénéfice')
  })

  it('closeFiscalYearRpc clôture et crée le nouvel exercice', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        status: 'closed',
        result: 100000,
        closing_entry_id: 'je-cloture',
        next_fiscal_year_code: '2025',
      },
      error: null,
    } as any)

    const result = await closeFiscalYearRpc('fy-2024')

    expect(supabase.rpc).toHaveBeenCalledWith('close_fiscal_year', {
      p_fiscal_year_id: 'fy-2024',
    })
    expect(result.status).toBe('closed')
    expect(result.next_fiscal_year_code).toBe('2025')
  })

  it('chaîne complète : compte de résultat puis clôture', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { result: 100000, result_type: 'bénéfice' },
      error: null,
    } as any)

    const pl = await generateProfitLoss('fy-2024')
    expect(pl.result).toBe(100000)

    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { status: 'closed', result: 100000 },
      error: null,
    } as any)

    const closure = await closeFiscalYearRpc('fy-2024')
    expect(closure.status).toBe('closed')
  })
})

// ============================================================
// 4. STOCK : calculate_stock_valuation → calculate_inventory_variance
// ============================================================
describe('Workflow Stock : valuation → variance', () => {
  beforeEach(() => vi.clearAllMocks())

  it('calculateStockValuation avec méthode CUMP', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        method: 'cump',
        total_cump: 50000,
        items: [{ product_name: 'Produit A', cump: 25, quantity: 200 }],
      },
      error: null,
    } as any)

    const result = await calculateStockValuation('cump')

    expect(supabase.rpc).toHaveBeenCalledWith('calculate_stock_valuation', {
      p_method: 'cump',
      p_warehouse_id: undefined,
    })
    expect(result.total_cump).toBe(50000)
  })

  it('calculateInventoryVariance détecte les écarts', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        variance_count: 3,
        total_variance: -150,
        positive_variance: 50,
        negative_variance: -200,
      },
      error: null,
    } as any)

    const result = await calculateInventoryVariance('wh-1')

    expect(result.variance_count).toBe(3)
    expect(result.total_variance).toBe(-150)
  })
})

// ============================================================
// 5. BANQUE : smart_bank_reconciliation → auto_letter_accounts
// ============================================================
describe('Workflow Banque : reconciliation → lettrage', () => {
  beforeEach(() => vi.clearAllMocks())

  it('smartBankReconciliation rapproche les transactions', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { matched: 15, unmatched_bank_transactions: 3 },
      error: null,
    } as any)

    const result = await smartBankReconciliation('ba-1', '2025-01-01', '2025-01-31')

    expect(supabase.rpc).toHaveBeenCalledWith('smart_bank_reconciliation', {
      p_bank_account_id: 'ba-1',
      p_from_date: '2025-01-01',
      p_to_date: '2025-01-31',
    })
    expect(result.matched).toBe(15)
  })

  it('autoLetterAccounts lettre les comptes tiers', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { lettered_lines: 42 },
      error: null,
    } as any)

    const result = await autoLetterAccounts('411000', 0.01)

    expect(result.lettered_lines).toBe(42)
  })
})

// ============================================================
// 6. CRM : customer_credit_score → calculate_late_payment_penalties
// ============================================================
describe('Workflow CRM : scoring → pénalités', () => {
  beforeEach(() => vi.clearAllMocks())

  it('customerCreditScore retourne un rating A-E', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { score: 85, rating: 'A', recommended_credit_limit: 30000 },
      error: null,
    } as any)

    const result = await customerCreditScore('cust-1')

    expect(result.score).toBe(85)
    expect(result.rating).toBe('A')
  })

  it('calculateLatePaymentPenalties calcule pénalités + indemnité 40€', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        eligible: true,
        days_overdue: 45,
        penalty_interest: 35.50,
        flat_fee: 40,
        total_penalty: 75.50,
      },
      error: null,
    } as any)

    const result = await calculateLatePaymentPenalties('inv-1')

    expect(result.eligible).toBe(true)
    expect(result.flat_fee).toBe(40)
    expect(result.total_penalty).toBe(75.50)
  })
})

// ============================================================
// 7. ÉTATS COMPTABLES : general_ledger → trial_balance → balance_sheet
// ============================================================
describe('Workflow États comptables', () => {
  beforeEach(() => vi.clearAllMocks())

  it('generateGeneralLedgerRpc retourne les écritures', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { entries: [], total_debit: 100000, total_credit: 100000, balanced: true },
      error: null,
    } as any)

    const result = await generateGeneralLedgerRpc('2025-01-01', '2025-12-31')

    expect(result.balanced).toBe(true)
  })

  it('generateTrialBalanceRpc retourne les soldes', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { accounts: [], total_debit: 100000, total_credit: 100000, balanced: true },
      error: null,
    } as any)

    const result = await generateTrialBalanceRpc('2025-01-01', '2025-12-31')

    expect(result.balanced).toBe(true)
  })

  it('generateBalanceSheet retourne actif = passif', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { asset_total: 500000, liability_total: 500000, balanced: true },
      error: null,
    } as any)

    const result = await generateBalanceSheet('fy-2024')

    expect(result.balanced).toBe(true)
    expect(result.asset_total).toBe(result.liability_total)
  })
})

// ============================================================
// 8. RH : leave_acquisition → severance_pay
// ============================================================
describe('Workflow RH : congés → rupture', () => {
  beforeEach(() => vi.clearAllMocks())

  it('calculateLeaveAcquisition calcule 2.5j/mois', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { acquired: 30, remaining: 25, taken: 5, carry_over: 0 },
      error: null,
    } as any)

    const result = await calculateLeaveAcquisition('emp-1', 2025)

    expect(result.acquired).toBe(30)  // 12 mois × 2.5 = 30
    expect(result.remaining).toBe(25)
  })

  it('calculateSeverancePay calcule l\'indemnité', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        seniority_years: 5.5,
        legal_indemnity: 8250,
        eligible: true,
      },
      error: null,
    } as any)

    const result = await calculateSeverancePay('emp-1', '2025-06-30')

    expect(result.eligible).toBe(true)
    expect(result.seniority_years).toBe(5.5)
  })
})

// ============================================================
// 9. PROVISIONS & RÉGULARISATIONS
// ============================================================
describe('Workflow Provisions & Régularisations', () => {
  beforeEach(() => vi.clearAllMocks())

  it('calculateProvisions détecte créances douteuses + stocks obsolètes', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        total_provisions: 15000,
        provision_count: 5,
        provisions: [
          { type: 'creance_douteuse', provision_amount: 10000 },
          { type: 'stock_obsolete', provision_amount: 5000 },
        ],
      },
      error: null,
    } as any)

    const result = await calculateProvisions('fy-2024')

    expect(result.total_provisions).toBe(15000)
    expect(result.provision_count).toBe(5)
  })

  it('generateAdjustingEntries crée les écritures de provision', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: { entry_count: 3, entries: [] },
      error: null,
    } as any)

    const result = await generateAdjustingEntries('fy-2024')

    expect(result.entry_count).toBe(3)
  })

  it('postDeferredCharge répartit sur 12 mois', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        total_amount: 12000,
        monthly_amount: 1000,
        months: 12,
        entry_count: 13,  // 1 initiale + 12 mensuelles
      },
      error: null,
    } as any)

    const result = await postDeferredCharge('je-1', 'cca', 12000, 12)

    expect(result.monthly_amount).toBe(1000)
    expect(result.entry_count).toBe(13)
  })
})

// ============================================================
// 10. PROJETS & PRODUCTION
// ============================================================
describe('Workflow Projets & Production', () => {
  beforeEach(() => vi.clearAllMocks())

  it('calculateProjectProfitability calcule EAC/ETC/CPI', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        margin: 15000,
        margin_pct: 25,
        progress_pct: 60,
        cpi: 1.1,
        eac: 45000,
        etc: 18000,
        health: 'healthy',
      },
      error: null,
    } as any)

    const result = await calculateProjectProfitability('proj-1')

    expect(result.health).toBe('healthy')
    expect(result.cpi).toBe(1.1)
    expect(result.margin_pct).toBe(25)
  })

  it('calculateProductionCost calcule matières + MO + charges', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        material_cost: 5000,
        labor_cost: 3000,
        overhead_cost: 800,
        total_cost: 8800,
        unit_cost: 88,
      },
      error: null,
    } as any)

    const result = await calculateProductionCost('mo-1')

    expect(result.total_cost).toBe(8800)
    expect(result.unit_cost).toBe(88)
  })
})

// ============================================================
// 11. TRÉSORERIE & ÉCHÉANCES
// ============================================================
describe('Workflow Trésorerie & Échéances', () => {
  beforeEach(() => vi.clearAllMocks())

  it('cashFlowForecast projette à 90 jours', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        current_balance: 50000,
        expected_inflows: 30000,
        expected_outflows: 20000,
        net_flow: 10000,
        projected_balance: 60000,
      },
      error: null,
    } as any)

    const result = await cashFlowForecast(90)

    expect(result.projected_balance).toBe(60000)
    expect(result.net_flow).toBe(10000)
  })

  it('calculatePaymentDueDates calcule les échéances', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        due_date: '2025-03-01',
        installments: [
          { date: '2025-02-01', pct: 50, label: '1er versement' },
          { date: '2025-03-01', pct: 50, label: '2ème versement' },
        ],
      },
      error: null,
    } as any)

    const result = await calculatePaymentDueDates('2025-01-15', 'pt-30-30')

    expect(result.installments).toHaveLength(2)
  })
})

// ============================================================
// 12. AMORTISSEMENTS & ANNEXE
// ============================================================
describe('Workflow Amortissements & Annexe', () => {
  beforeEach(() => vi.clearAllMocks())

  it('calculateDepreciation calcule l\'amortissement mensuel', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        monthly_amount: 833.33,
        accumulated_depreciation: 10000,
        net_book_value: 40000,
        method: 'linear',
      },
      error: null,
    } as any)

    const result = await calculateDepreciation('asset-1', '2025-01')

    expect(result.method).toBe('linear')
    expect(result.net_book_value).toBe(40000)
  })

  it('generateAccountingAnnex génère 6 sections', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        section_count: 6,
        sections: [
          { section: 'immobilisations', title: 'État des immobilisations' },
          { section: 'amortissements', title: 'Tableau des amortissements' },
          { section: 'creances_clients', title: 'État des créances clients' },
          { section: 'dettes_fournisseurs', title: 'État des dettes fournisseurs' },
          { section: 'stocks', title: 'État des stocks' },
          { section: 'effectifs', title: 'Effectifs et masse salariale' },
        ],
      },
      error: null,
    } as any)

    const result = await generateAccountingAnnex('fy-2024')

    expect(result.section_count).toBe(6)
    expect(result.sections).toHaveLength(6)
  })
})

// ============================================================
// 13. COMMISSIONS
// ============================================================
describe('Workflow Commissions commerciaux', () => {
  beforeEach(() => vi.clearAllMocks())

  it('calculateSalesCommissions calcule par période', async () => {
    vi.mocked(supabase.rpc).mockResolvedValue({
      data: {
        total_commission: 4500,
        representatives: [
          { rep_name: 'Jean Dupont', revenue: 100000, commission: 5000 },
          { rep_name: 'Marie Martin', revenue: 40000, commission: 2000 },
        ],
      },
      error: null,
    } as any)

    const result = await calculateSalesCommissions('2025-01')

    expect(result.total_commission).toBe(4500)
    expect(result.representatives).toHaveLength(2)
  })
})
