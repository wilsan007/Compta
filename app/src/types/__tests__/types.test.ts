import { describe, it, expect } from 'vitest'

import type {
  RecurringEntry,
  RegularizationEntry,
  CurrencyRevaluation,
  AnalyticPlan,
  DistributionGrill,
  BankReconciliationRule,
  TvsDeclaration,
  FiscalBackup,
} from '@/types'

describe('Phase 1 — TypeScript Types', () => {
  describe('RecurringEntry (Phase 1.1)', () => {
    it('has required fields', () => {
      const entry = {
        id: 'test',
        tenant_id: 'test',
        name: 'Test',
        description: null,
        journal_id: 'j1',
        journal_code: 'OD',
        frequency: 'monthly',
        day_of_month: 1,
        start_date: '2024-01-01',
        end_date: null,
        next_generation_date: '2024-06-01',
        last_generation_date: null,
        lines: [],
        status: 'active',
        total_debit: 100,
        total_credit: 100,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      } as RecurringEntry
      expect(entry.id).toBe('test')
      expect(entry.frequency).toBe('monthly')
    })
  })

  describe('RegularizationEntry (Phase 1.2)', () => {
    it('has required fields', () => {
      const entry = {
        id: 'test',
        tenant_id: 'test',
        type: 'CCA',
        fiscal_year_id: null,
        account_code: '486000',
        third_party_code: null,
        description: 'Test',
        invoice_number: null,
        invoice_date: null,
        invoice_amount: 0,
        start_date: '2024-01-01',
        end_date: '2024-12-31',
        amount: 1000,
        used_amount: 0,
        remaining_amount: 1000,
        status: 'pending',
        journal_id: null,
        journal_code: null,
        created_entry_id: null,
        extourne_entry_id: null,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      } as RegularizationEntry
      expect(entry.type).toBe('CCA')
      expect(entry.status).toBe('pending')
    })
  })

  describe('CurrencyRevaluation (Phase 1.6)', () => {
    it('has required fields', () => {
      const rev = {
        id: 'test',
        tenant_id: 'test',
        fiscal_year_id: null,
        period_date: '2024-06-30',
        account_code: '411USD',
        third_party_code: null,
        currency: 'USD',
        original_rate: 1.08,
        new_rate: 0.92,
        original_amount: 15000,
        original_amount_eur: 13888,
        revalued_amount_eur: 13800,
        gain_loss: -88,
        type: 'receivable',
        status: 'pending',
        entry_id: null,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      } as CurrencyRevaluation
      expect(rev.currency).toBe('USD')
      expect(rev.type).toBe('receivable')
    })
  })

  describe('AnalyticPlan (Phase 1.9)', () => {
    it('has required fields', () => {
      const plan = {
        id: 'test',
        tenant_id: 'test',
        code: 'AN1',
        name: 'Main analytic',
        description: null,
        is_default: true,
        active: true,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      } as AnalyticPlan
      expect(plan.code).toBe('AN1')
      expect(plan.is_default).toBe(true)
    })
  })

  describe('DistributionGrill (Phase 1.10)', () => {
    it('has required fields', () => {
      const grill = {
        id: 'test',
        tenant_id: 'test',
        name: 'Frais généraux',
        description: null,
        account_code: '614000',
        journal_code: null,
        active: true,
        lines: [],
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      } as DistributionGrill
      expect(grill.name).toBe('Frais généraux')
      expect(grill.account_code).toBe('614000')
    })
  })

  describe('BankReconciliationRule (Phase 1.11)', () => {
    it('has required fields', () => {
      const rule = {
        id: 'test',
        tenant_id: 'test',
        name: 'Virements',
        afb_code: 'VIR',
        description: null,
        match_pattern: 'VIREMENT',
        counterpart_account: '411000',
        journal_code: 'BQ',
        priority: 1,
        active: true,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      } as BankReconciliationRule
      expect(rule.afb_code).toBe('VIR')
      expect(rule.priority).toBe(1)
    })
  })

  describe('TvsDeclaration (Phase 1.16)', () => {
    it('has required fields', () => {
      const tvs: TvsDeclaration = {
        id: 'test',
        tenant_id: 'test',
        fiscal_year: 2024,
        vehicle_registration: 'AB-123-CD',
        vehicle_type: 'berline',
        co2_emissions: 145,
        first_registration_date: '2022-03-15',
        amount_co2: 500,
        amount_age: 0,
        amount_total: 500,
        status: 'draft',
        filed_at: null,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }
      expect(tvs.fiscal_year).toBe(2024)
      expect(tvs.status).toBe('draft')
    })
  })

  describe('FiscalBackup (Phase 1.22)', () => {
    it('has required fields', () => {
      const backup: FiscalBackup = {
        id: 'test',
        tenant_id: 'test',
        fiscal_year_id: null,
        backup_type: 'manual',
        status: 'pending',
        file_url: null,
        file_size: null,
        created_by: null,
        created_at: new Date().toISOString(),
      }
      expect(backup.backup_type).toBe('manual')
      expect(backup.status).toBe('pending')
    })
  })
})
