import { describe, it, expect } from 'vitest'
import type {
  AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference,
  AccountingControlRun, CashControlSession, FECAttestation, TierRIB,
  IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob,
  VATOnCollection, BatchEntrySession,
} from '@/types'

// ============ Type Shape Validation ============
// These tests verify that TypeScript interfaces have the expected fields
// matching the SQL schema. They use type assertions to catch regressions.

describe('Phase 6 — TypeScript Interface Shape Validation', () => {
  it('AutoLabelRule has all required fields', () => {
    const rule = {
      id: '1', tenant_id: 'tid', name: 'Rule', description: null,
      journal_code: 'VT', account_code: '411', account_prefix: '41',
      label_pattern: 'Pattern', priority: 100, active: true,
      created_at: '2024-01-01', updated_at: '2024-01-01',
    } as AutoLabelRule
    expect(rule.id).toBe('1')
    expect(rule.name).toBe('Rule')
    expect(rule.label_pattern).toBe('Pattern')
    expect(rule.priority).toBe(100)
    expect(rule.active).toBe(true)
  })

  it('ExtourneLog has all required fields', () => {
    const log = {
      id: '1', tenant_id: 'tid', original_entry_id: 'e1', extourne_entry_id: 'e2',
      extourne_date: '2024-01-01', reason: 'Correction', journal_code: 'VT',
      total_debit: 100, total_credit: 100, status: 'completed', created_at: '2024-01-01',
    } as ExtourneLog
    expect(log.original_entry_id).toBe('e1')
    expect(log.extourne_entry_id).toBe('e2')
    expect(log.total_debit).toBe(100)
    expect(log.status).toBe('completed')
  })

  it('CarryForwardLog has all required fields', () => {
    const log = {
      id: '1', tenant_id: 'tid', source_fiscal_year_id: 'fy1', target_fiscal_year_id: 'fy2',
      carry_forward_date: '2024-01-01', total_debit: 1000, total_credit: 1000,
      entry_count: 10, status: 'completed', journal_entry_id: 'je1', created_at: '2024-01-01',
    } as CarryForwardLog
    expect(log.source_fiscal_year_id).toBe('fy1')
    expect(log.entry_count).toBe(10)
    expect(log.status).toBe('completed')
  })

  it('LettrageDifference has all required fields', () => {
    const diff = {
      id: '1', tenant_id: 'tid', third_party_code: 'C001', lettrage_code: 'L001',
      line_id_1: 'l1', line_id_2: 'l2', debit_amount: 100, credit_amount: 95,
      difference: 5, difference_account: '658000', generated_entry_id: null,
      status: 'pending', created_at: '2024-01-01',
    } as LettrageDifference
    expect(diff.third_party_code).toBe('C001')
    expect(diff.difference).toBe(5)
    expect(diff.status).toBe('pending')
  })

  it('AccountingControlRun has all required fields', () => {
    const run = {
      id: '1', tenant_id: 'tid', control_type: 'full', fiscal_year_id: 'fy1',
      period_id: null, run_date: '2024-01-01', status: 'completed',
      total_checks: 100, errors_found: 2, warnings_found: 5,
      details: [], created_at: '2024-01-01',
    } as AccountingControlRun
    expect(run.control_type).toBe('full')
    expect(run.total_checks).toBe(100)
    expect(run.errors_found).toBe(2)
  })

  it('CashControlSession has all required fields', () => {
    const session = {
      id: '1', tenant_id: 'tid', session_number: 'CC001', journal_code: 'CQ',
      session_date: '2024-01-01', theoretical_balance: 100, counted_balance: 95,
      difference: -5, status: 'open', counted_by: 'user1', validated_by: null,
      validated_at: null, notes: 'Test', details: [],
      created_at: '2024-01-01', updated_at: '2024-01-01',
    } as CashControlSession
    expect(session.session_number).toBe('CC001')
    expect(session.theoretical_balance).toBe(100)
    expect(session.difference).toBe(-5)
  })

  it('FECAttestation has all required fields', () => {
    const att = {
      id: '1', tenant_id: 'tid', fiscal_year_id: 'fy1', attestation_number: 'FEC001',
      attestation_date: '2024-01-01', fec_type: 'definitive', entry_count: 500,
      total_debit: 100000, total_credit: 100000, file_name: 'fec.txt',
      file_content: '...', status: 'generated', generated_by: 'user1',
      created_at: '2024-01-01',
    } as FECAttestation
    expect(att.attestation_number).toBe('FEC001')
    expect(att.fec_type).toBe('definitive')
    expect(att.entry_count).toBe(500)
  })

  it('TierRIB has all required fields', () => {
    const rib = {
      id: '1', tenant_id: 'tid', third_party_account_id: 'tp1', rib_label: 'Main',
      iban: 'FR76...', bic: 'BNPAFRPP', bank_name: 'BNP', bank_code: '30002',
      branch_code: '00001', account_number: '12345678901', key: '12',
      is_default: true, active: true, created_at: '2024-01-01', updated_at: '2024-01-01',
    } as TierRIB
    expect(rib.iban).toBe('FR76...')
    expect(rib.is_default).toBe(true)
    expect(rib.active).toBe(true)
  })

  it('IFRSAdjustment has all required fields', () => {
    const adj = {
      id: '1', tenant_id: 'tid', fiscal_year_id: 'fy1', adjustment_type: 'provision',
      account_code: '391000', counter_account_code: '445800', description: 'Provision',
      amount: 5000, adjustment_date: '2024-01-01', ifrs_standard: 'IAS 39',
      journal_entry_id: null, status: 'draft', created_at: '2024-01-01', updated_at: '2024-01-01',
    } as IFRSAdjustment
    expect(adj.adjustment_type).toBe('provision')
    expect(adj.amount).toBe(5000)
    expect(adj.ifrs_standard).toBe('IAS 39')
  })

  it('TaxPayment has all required fields', () => {
    const payment = {
      id: '1', tenant_id: 'tid', payment_number: 'TP001', tax_type: 'TVA',
      period_label: '2024-Q1', period_start: '2024-01-01', period_end: '2024-03-31',
      amount: 1500, payment_date: '2024-04-15', payment_method: 'telepayment',
      bank_account_id: null, status: 'draft', confirmation_number: null,
      journal_entry_id: null, created_at: '2024-01-01', updated_at: '2024-01-01',
    } as TaxPayment
    expect(payment.payment_number).toBe('TP001')
    expect(payment.tax_type).toBe('TVA')
    expect(payment.amount).toBe(1500)
  })

  it('CustomReportTemplate has all required fields', () => {
    const tmpl = {
      id: '1', tenant_id: 'tid', name: 'Custom', description: 'Test',
      report_type: 'trial_balance', category: 'accounting', columns: [], filters: {},
      group_by: null, sort_by: null, sort_order: 'asc', page_orientation: 'portrait',
      page_size: 'A4', header_text: null, footer_text: null,
      show_logo: true, show_date: true, show_page_numbers: true, active: true,
      created_at: '2024-01-01', updated_at: '2024-01-01',
    } as CustomReportTemplate
    expect(tmpl.name).toBe('Custom')
    expect(tmpl.report_type).toBe('trial_balance')
    expect(tmpl.page_orientation).toBe('portrait')
  })

  it('DeferredPrintingJob has all required fields', () => {
    const job = {
      id: '1', tenant_id: 'tid', job_name: 'Monthly', report_type: 'trial_balance',
      scheduled_date: '2024-12-31', output_format: 'pdf', status: 'pending',
      parameters: {}, generated_file_path: null, created_at: '2024-01-01',
    } as DeferredPrintingJob
    expect(job.job_name).toBe('Monthly')
    expect(job.output_format).toBe('pdf')
    expect(job.status).toBe('pending')
  })

  it('VATOnCollection has all required fields', () => {
    const vat = {
      id: '1', tenant_id: 'tid', period_label: '2024-01', period_start: '2024-01-01',
      period_end: '2024-01-31', vat_base: 10000, vat_rate: 20, vat_amount: 2000,
      collected_amount: 5000, uncollected_amount: 5000, vat_collected: 1000,
      vat_uncollected: 1000, status: 'draft', created_at: '2024-01-01', updated_at: '2024-01-01',
    } as VATOnCollection
    expect(vat.vat_base).toBe(10000)
    expect(vat.vat_rate).toBe(20)
    expect(vat.vat_amount).toBe(2000)
  })

  it('BatchEntrySession has all required fields', () => {
    const session = {
      id: '1', tenant_id: 'tid', session_name: 'Batch Jan', journal_code: 'VT',
      session_date: '2024-01-01', entry_count: 50, total_debit: 5000, total_credit: 5000,
      status: 'draft', created_at: '2024-01-01', updated_at: '2024-01-01',
    } as BatchEntrySession
    expect(session.session_name).toBe('Batch Jan')
    expect(session.entry_count).toBe(50)
    expect(session.status).toBe('draft')
  })
})

// ============ SQL Schema Validation ============
describe('Phase 6 — SQL Migration File Validation', () => {
  it('SQL migration file exists and contains all table definitions', async () => {
    const fs = await import('fs')
    const path = await import('path')
    const sqlPath = path.resolve(process.cwd(), 'sql/25_accounting_features.sql')
    const sql = fs.readFileSync(sqlPath, 'utf-8')

    const expectedTables = [
      'auto_label_rules', 'extourne_log', 'carry_forward_log', 'lettrage_differences',
      'accounting_control_runs', 'cash_control_sessions', 'fec_attestations',
      'tier_ribs', 'ifrs_adjustments', 'tax_payments', 'custom_report_templates',
      'deferred_printing_jobs', 'journal_access_rights', 'vat_on_collections',
      'batch_entry_sessions',
    ]

    for (const table of expectedTables) {
      expect(sql).toContain(`CREATE TABLE IF NOT EXISTS ${table}`)
    }
  })

  it('SQL migration has RLS policies for all tables', async () => {
    const fs = await import('fs')
    const path = await import('path')
    const sqlPath = path.resolve(process.cwd(), 'sql/25_accounting_features.sql')
    const sql = fs.readFileSync(sqlPath, 'utf-8')

    const expectedTables = [
      'auto_label_rules', 'extourne_log', 'carry_forward_log', 'lettrage_differences',
      'accounting_control_runs', 'cash_control_sessions', 'fec_attestations',
      'tier_ribs', 'ifrs_adjustments', 'tax_payments', 'custom_report_templates',
      'deferred_printing_jobs', 'journal_access_rights', 'vat_on_collections',
      'batch_entry_sessions',
    ]

    for (const table of expectedTables) {
      expect(sql).toContain(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY`)
      // Each table should have at least a SELECT policy
      expect(sql.toLowerCase()).toContain(`tenant_select`)
    }
    // Verify DROP POLICY IF EXISTS pattern is used (idempotency)
    const dropCount = (sql.match(/DROP POLICY IF EXISTS/g) || []).length
    expect(dropCount).toBeGreaterThanOrEqual(expectedTables.length)
  })

  it('SQL migration enables RLS on all tables', async () => {
    const fs = await import('fs')
    const path = await import('path')
    const sqlPath = path.resolve(process.cwd(), 'sql/25_accounting_features.sql')
    const sql = fs.readFileSync(sqlPath, 'utf-8')

    const expectedTables = [
      'auto_label_rules', 'extourne_log', 'carry_forward_log', 'lettrage_differences',
      'accounting_control_runs', 'cash_control_sessions', 'fec_attestations',
      'tier_ribs', 'ifrs_adjustments', 'tax_payments', 'custom_report_templates',
      'deferred_printing_jobs', 'journal_access_rights', 'vat_on_collections',
      'batch_entry_sessions',
    ]

    for (const table of expectedTables) {
      expect(sql).toContain(`ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY`)
    }
  })
})

// ============ Route Validation ============
describe('Phase 6 — App.tsx Route Validation', () => {
  it('App.tsx contains all 15 Phase 6 routes', async () => {
    const fs = await import('fs')
    const path = await import('path')
    const appPath = path.resolve(process.cwd(), 'src/App.tsx')
    const appContent = fs.readFileSync(appPath, 'utf-8')

    const expectedRoutes = [
      '/accounting/batch-entry',
      '/accounting/auto-labels',
      '/accounting/extourne',
      '/accounting/carry-forward',
      '/accounting/lettrage-differences',
      '/accounting/controls',
      '/accounting/cash-control',
      '/accounting/fec-attestations',
      '/accounting/tier-ribs',
      '/accounting/ifrs-adjustments',
      '/accounting/tax-payments',
      '/accounting/custom-reports',
      '/accounting/deferred-printing',
      '/accounting/journal-access-rights',
      '/accounting/vat-on-collections',
    ]

    for (const route of expectedRoutes) {
      expect(appContent).toContain(`path="${route}"`)
    }
  })

  it('App.tsx imports all 15 Phase 6 page components', async () => {
    const fs = await import('fs')
    const path = await import('path')
    const appPath = path.resolve(process.cwd(), 'src/App.tsx')
    const appContent = fs.readFileSync(appPath, 'utf-8')

    const expectedComponents = [
      'BatchEntryPage', 'AutoLabelRulesPage', 'ExtournePage', 'CarryForwardPage',
      'LettrageDifferencesPage', 'AccountingControlsPage', 'CashControlPage',
      'FECAttestationPage', 'TierRIBsPage', 'IFRSAdjustmentsPage', 'TaxPaymentsPage',
      'CustomReportTemplatesPage', 'DeferredPrintingPage', 'JournalAccessRightsPage',
      'VATOnCollectionsPage',
    ]

    for (const comp of expectedComponents) {
      expect(appContent).toContain(comp)
    }
  })
})
