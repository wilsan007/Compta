import { it } from 'vitest'
import { login, A, check, attempt, save, findings } from './rig'
it('écritures des écrans rejouées telles quelles', async () => {
  await login(0, A)
  const acc = await import('@/lib/queries/accounting')
  const misc = await import('@/lib/queries/misc')
  const pay = await import('@/lib/queries/payroll')
  const n = Date.now() % 100000
  const cases: [string, string, () => Promise<any>][] = [
    ['W01', 'ThirdPartyAccountsPage : créer un compte de tiers', () => acc.createThirdPartyAccount({ code: 'T' + n, name: 'Tiers', type: 'customer', account_general_code: '411000', customer_id: null, supplier_id: null, employee_id: null, balance: 0, lettrage_code: null, currency: 'EUR', active: true,
      payment_term_id: null, credit_limit: 5000 } as any)],
    ['W02', 'JournalsPage : créer un journal', () => misc.createJournal({ code: 'J' + (n % 1000), name: 'Journal test', type: 'general', account_counterpart: null, bank_account_id: null, default_entry_template_id: null, status: 'active', locked: false, racines_autorisees: null, account_attente: null, currency_code: 'EUR', sequence: 0 } as any)],
    ['W03', 'AnalyticSectionsPage : créer une section analytique', () => acc.createAnalyticSection({ code: 'S' + n, name: 'Section', axis: 'default', active: true, level: 1, parent_id: undefined, plan_id: undefined, section_type: 'section' } as any)],
    ['W04', 'FixedAssetsPage : créer une immobilisation', () => acc.createFixedAsset({ name: 'Ordinateur', code: 'IM' + n, category: 'IT', purchase_date: '2026-09-01', purchase_value: 1200, current_value: 1200, depreciation_method: 'linear', useful_life_years: 3, residual_value: 0, derogatory_depreciation: false, subvention_amount: null, subvention_account: null, account_asset_code: null, account_depreciation_code: null, account_expense_depreciation_code: null, journal_id: null, currency_code: null, status: 'active' } as any)],
    ['W05', 'JournalSaisiePage : créer un compte à la volée', () => acc.createChartAccount({ code: '6' + n, name: '6' + n, type: acc.chartAccountTypeFromCode('6' + n), classe: '6' } as any)],
    ['W06', 'PayRunsPage : créer un lot de paie', () => pay.createPayRun({ number: 'PAY-' + n, period_start: '2026-09-01', period_end: '2026-09-30', pay_date: '2026-09-30', status: 'draft', gross_total: 0, tax_total: 0, net_total: 0, employer_contributions_total: 0, employee_count: 0 } as any)],
  ]
  for (const [id, label, fn] of cases) {
    const r = await attempt(fn)
    check(id, label + ' — aboutit', r.ok, r.err ?? 'OK')
  }
  save('s6.json', findings)
})
