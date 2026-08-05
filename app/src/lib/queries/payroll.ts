import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud, clearTenantCache } from './core'
import { calculatePayroll } from '@/lib/payroll'
import type { Customer, Supplier, Product, Invoice, Quote, QuoteLine, CreditNote, CreditNoteLine, PurchaseCreditNote, PurchaseCreditNoteLine, PurchaseInvoice, BankAccount, BankTransaction, BankRule, BankConnection, PartnerBankAccount, PartnerContact, PartnerCategory, JournalEntry, JournalLine, ChartAccount, CompanySettings, Project, VatReturn, InvoiceLine, DashboardStats, FixedAsset, Employee, PayRun, Timesheet, StockMovement, Currency, Journal, FiscalYear, FiscalPeriod, EntryTemplate, ThirdPartyAccount, AnalyticSection, Budget, BudgetCommitment, BudgetControlResult, StandardLabel, PaymentOrder, AssetDepreciation, CollectionReminder, SalesOrder, SalesOrderLine, DeliveryNote, DeliveryNoteLine, CustomerPayment, PurchaseOrder, GoodsReceipt, SupplierPayment, Warehouse, StockQuantity, PriceList, PriceListLine, BOM, BOMLine, ManufacturingOrder, PaySlip, PayrollAccountingEntry, LeaveRequest, Contract, LegalDeclaration, AuditLog, Routing, RoutingOperation, WorkCenter, Machine, Tooling, OFLabel, OFLot, OFConsumption, STOrder, STShipment, STShipmentLine, STReceipt, STReceiptLine, MRPRun, MRPProposal, ProductionForecast, PlanningSlot, ProductEquivalence, Workflow, OFDocumentAccess, LegislationPack, TaxRate, RecurringEntry, RegularizationEntry, CurrencyRevaluation, AnalyticPlan, DistributionGrill, DistributionGrillLine, BankReconciliationRule, BankStatementImport, TvsDeclaration, FiscalBackup, ProductVariant, ProductSerialNumber, ProductBatch, WarehouseLocation, QualityCheck, PickList, SalesRepresentative, Prospect, ProductSubstitute, DeliverySchedule, RecurringInvoiceTemplate, DocumentTemplate, FutureAccountingMovement, TreasuryTransfer, CreditLine, Investment, ValueDateTracking, TreasuryRecurring, ConsolidatedTreasury, PayrollComponent, PayrollTemplate, SalaryAdvance, PayRecall, DsnDeclaration, DpaeRecord, WorkHardship, CareerHistory, CpfAccount, PayrollArchive, LegalWatch, EmployeeDocument, ExpenseReport, Interview, AssetDepreciationPlan, AssetFamily, AssetRevaluation, AssetDocument, AssetFreeField, AssetBatchDisposal, AssetSplit, AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference, AccountingControlRun, CashControlSession, FECAttestation, TierRIB, IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob, JournalAccessRight, VATOnCollection, BatchEntrySession, PaymentTerm, MarkingType, ReminderLevel, PaymentPromise, Dispute, JustificatifSolde, EtatRapprochement, RevisionCycle, ReportingPlan, StatField, DashboardWidget, FusionLog, CompactionLog, RGPDRequest, GridTemplate, PaymentTemplateCompta, AnalyticJournalCode, ReimputationLog, BankStatementTemplate, Bank, PayrollTaxGrid, PayrollTaxGridLine, CorporateTaxGrid, CorporateTaxGridLine, TaxGroup, TaxRepartitionLine, TaxCashBasisEntry, FiscalPosition, FiscalPositionMapping, AccountTag, AccountTagMapping, ExchangeRate, ExchangeGainLossEntry, CheckBook, Check, DocumentCharge, DocumentTransformation } from '@/types'

// ============ Employees ============
export async function getEmployees() {
  const tid = await getTenantId()
  let q = supabase.from('employees').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Employee[]
}

export async function createEmployee(emp: Omit<Employee, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('employees').insert(ti(emp, 'employees', tid)).select().single()
  if (error) throw error
  return data as Employee
}

export async function updateEmployee(id: string, updates: Partial<Employee>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('employees').update(updates), 'employees', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Employee
}

export async function deleteEmployee(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('employees').delete(), 'employees', tid).eq('id', id)
  if (error) throw error
}


// ============ Pay Runs ============
export async function getPayRuns() {
  const tid = await getTenantId()
  let q = supabase.from('pay_runs').select('*').order('pay_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PayRun[]
}

export async function createPayRun(pr: Omit<PayRun, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pay_runs').insert(ti(pr, 'pay_runs', tid)).select().single()
  if (error) throw error
  return data as PayRun
}

export async function updatePayRun(id: string, updates: Partial<PayRun>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pay_runs').update(updates), 'pay_runs', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PayRun
}

export async function deletePayRun(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('pay_runs').delete(), 'pay_runs', tid).eq('id', id)
  if (error) throw error
}


// ============ Timesheets ============
export async function getTimesheets() {
  const tid = await getTenantId()
  let q = supabase.from('timesheets').select('*, employees(name)').order('date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createTimesheet(ts: Omit<Timesheet, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('timesheets').insert(ti(ts, 'timesheets', tid)).select().single()
  if (error) throw error
  return data as Timesheet
}

export async function updateTimesheet(id: string, updates: Partial<Timesheet>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('timesheets').update(updates), 'timesheets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Timesheet
}

export async function deleteTimesheet(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('timesheets').delete(), 'timesheets', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 7: Pay Slips ============
export async function getPaySlips(payRunId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('pay_slips').select('*, employees(name, position, department)').order('period_start', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (payRunId) q = q.eq('pay_run_id', payRunId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createPaySlip(ps: Omit<PaySlip, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pay_slips').insert(ti(ps, 'pay_slips', tid)).select().single()
  if (error) throw error
  return data as PaySlip
}

export async function updatePaySlip(id: string, updates: Partial<PaySlip>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pay_slips').update(updates), 'pay_slips', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PaySlip
}

export async function deletePaySlip(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('pay_slips').delete(), 'pay_slips', tid).eq('id', id)
  if (error) throw error
}

export async function generatePaySlipsForRun(payRunId: string, employees: Employee[], payRun: PayRun) {
  const tid = await getTenantId()
  const results: PaySlip[] = []
  for (const emp of employees) {
    if (emp.status === 'inactive') continue
    const grossSalary = Number(emp.salary)
    const calc = calculatePayroll({
      grossSalary,
      contractType: (String(emp.contract_type).toLowerCase() === 'cdd' ? 'cdd' : 'cdi') as 'cdi' | 'cdd',
      hoursPerWeek: 35,
      overtimeHours: 0,
      mealVouchers: 0,
      transportAllowance: 0,
      age: emp.birth_date ? Math.floor((Date.now() - new Date(emp.birth_date).getTime()) / (365.25 * 24 * 60 * 60 * 1000)) : 30,
      department: emp.department || '',
      taxRate: 10,
    })
    const overtimePay = calc.overtimePay
    const bonus = 0
    const totalGross = calc.totalGross + bonus
    const socialSecurity = calc.socialSecurityEmployee + calc.retirementEmployee + calc.healthEmployee + calc.unemploymentEmployee
    const incomeTax = calc.incomeTax
    const otherDeductions = calc.csgCrds
    const totalDeductions = socialSecurity + incomeTax + otherDeductions
    const netSalary = calc.netPay
    const employerContributions = calc.totalEmployerContributions

    const number = `BS-${payRun.number}-${emp.name.substring(0, 3).toUpperCase()}`
    const { data, error } = await supabase.from('pay_slips').insert(ti({
      number, pay_run_id: payRunId, employee_id: emp.id,
      period_start: payRun.period_start, period_end: payRun.period_end,
      gross_salary: grossSalary, overtime_pay: overtimePay, bonus,
      total_gross: totalGross, social_security_employee: socialSecurity,
      income_tax: incomeTax, other_deductions: otherDeductions,
      total_deductions: totalDeductions, net_salary: netSalary,
      employer_contributions: employerContributions, status: 'draft',
    }, 'pay_slips', tid)).select().single()
    if (error) throw error
    results.push(data as PaySlip)
  }
  return results
}


// ============ Sprint 7: Payroll Accounting Entries ============
export async function getPayrollAccountingEntries() {
  const tid = await getTenantId()
  let q = supabase.from('payroll_accounting_entries').select('*, pay_runs(number)').order('period_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createPayrollAccountingEntry(pae: Omit<PayrollAccountingEntry, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payroll_accounting_entries').insert(ti(pae, 'payroll_accounting_entries', tid)).select().single()
  if (error) throw error
  return data as PayrollAccountingEntry
}

export async function updatePayrollAccountingEntry(id: string, updates: Partial<PayrollAccountingEntry>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('payroll_accounting_entries').update(updates), 'payroll_accounting_entries', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PayrollAccountingEntry
}

export async function deletePayrollAccountingEntry(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payroll_accounting_entries').delete(), 'payroll_accounting_entries', tid).eq('id', id)
  if (error) throw error
}

export async function transferPayrollToAccounting(entryId: string, entry: PayrollAccountingEntry) {
  const tid = await getTenantId()
  const entryNumber = entry.number.startsWith('OD-PAIE-') ? entry.number : `OD-PAIE-${entry.number}`
  const { data: je, error: jeErr } = await supabase.from('journal_entries').insert(ti({
    number: entryNumber, date: entry.period_date, journal_code: 'OD',
    status: 'draft', description: `OD de paie ${entry.number}`,
  }, 'journal_entries', tid)).select().single()
  if (jeErr) throw jeErr

  const lines = [
    ti({ journal_id: je.id, account_code: '641000', account_general: '641000', debit: entry.gross_total, credit: 0, description: 'Rémunérations brutes' }, 'journal_lines', tid),
    ti({ journal_id: je.id, account_code: '645000', account_general: '645000', debit: entry.employer_contributions_total, credit: 0, description: 'Charges patronales' }, 'journal_lines', tid),
    ti({ journal_id: je.id, account_code: '431000', account_general: '431000', debit: 0, credit: entry.employee_deductions_total, description: 'Charges salariales' }, 'journal_lines', tid),
    ti({ journal_id: je.id, account_code: '437000', account_general: '437000', debit: 0, credit: entry.employer_contributions_total, description: 'Charges patronales (contrepartie)' }, 'journal_lines', tid),
    ti({ journal_id: je.id, account_code: '421000', account_general: '421000', debit: 0, credit: entry.net_total, description: 'Net à payer' }, 'journal_lines', tid),
  ]
  const { error: lineErr } = await supabase.from('journal_lines').insert(lines)
  if (lineErr) throw lineErr

  await updatePayrollAccountingEntry(entryId, { status: 'transferred', journal_entry_id: je.id })
  return je
}


// ============ Sprint 7: Leave Requests ============
export async function getLeaveRequests(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('leave_requests').select('*, employees(name, department)').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createLeaveRequest(lr: Omit<LeaveRequest, 'id' | 'created_at' | 'approved_by' | 'approved_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('leave_requests').insert(ti(lr, 'leave_requests', tid)).select().single()
  if (error) throw error
  return data as LeaveRequest
}

export async function updateLeaveRequest(id: string, updates: Partial<LeaveRequest>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('leave_requests').update(updates), 'leave_requests', tid).eq('id', id).select().single()
  if (error) throw error
  return data as LeaveRequest
}

export async function deleteLeaveRequest(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('leave_requests').delete(), 'leave_requests', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 7: Contracts ============
export async function getContracts() {
  const tid = await getTenantId()
  let q = supabase.from('contracts').select('*, employees(name, position, department)').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createContract(c: Omit<Contract, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('contracts').insert(ti(c, 'contracts', tid)).select().single()
  if (error) throw error
  return data as Contract
}

export async function updateContract(id: string, updates: Partial<Contract>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('contracts').update(updates), 'contracts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Contract
}

export async function deleteContract(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('contracts').delete(), 'contracts', tid).eq('id', id)
  if (error) throw error
}


// ============ Sprint 7: Legal Declarations ============
export async function getLegalDeclarations(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('legal_declarations').select('*').order('due_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as LegalDeclaration[]
}

export async function createLegalDeclaration(ld: Omit<LegalDeclaration, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('legal_declarations').insert(ti(ld, 'legal_declarations', tid)).select().single()
  if (error) throw error
  return data as LegalDeclaration
}

export async function updateLegalDeclaration(id: string, updates: Partial<LegalDeclaration>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('legal_declarations').update(updates), 'legal_declarations', tid).eq('id', id).select().single()
  if (error) throw error
  return data as LegalDeclaration
}

export async function deleteLegalDeclaration(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('legal_declarations').delete(), 'legal_declarations', tid).eq('id', id)
  if (error) throw error
}


// ============ Payment Link Generation ============
export async function generatePaymentLink(reminderId: string) {
  const token = crypto.randomUUID()
  const url = `${window.location.origin}/pay/${token}`
  const tid = await getTenantId()
  let updateQ = supabase
    .from('collection_reminders')
    .update({
      payment_link_token: token,
      payment_link_url: url,
      payment_link_expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
      payment_status: 'pending',
    })
    .eq('id', reminderId)
  if (tid) updateQ = updateQ.eq('tenant_id', tid)
  const { data, error } = await updateQ
    .select()
    .single()
  if (error) throw error
  return data
}


// ============ Phase 4: Payroll Components ============
export async function getPayrollComponents() {
  const tid = await getTenantId()
  let q = supabase.from('payroll_components').select('*').order('display_order')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PayrollComponent[]
}
export async function createPayrollComponent(c: Omit<PayrollComponent, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payroll_components').insert(ti(c, 'payroll_components', tid)).select().single()
  if (error) throw error
  return data as PayrollComponent
}
export async function updatePayrollComponent(id: string, updates: Partial<PayrollComponent>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('payroll_components').update(updates), 'payroll_components', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PayrollComponent
}
export async function deletePayrollComponent(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payroll_components').delete(), 'payroll_components', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 4: Payroll Templates ============
export async function getPayrollTemplates() {
  const tid = await getTenantId()
  let q = supabase.from('payroll_templates').select('*').order('name')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PayrollTemplate[]
}
export async function createPayrollTemplate(t: Omit<PayrollTemplate, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payroll_templates').insert(ti(t, 'payroll_templates', tid)).select().single()
  if (error) throw error
  return data as PayrollTemplate
}
export async function deletePayrollTemplate(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payroll_templates').delete(), 'payroll_templates', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 4: Salary Advances ============
export async function getSalaryAdvances() {
  const tid = await getTenantId()
  let q = supabase.from('salary_advances').select('*, employees(first_name, last_name)').order('advance_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createSalaryAdvance(s: Omit<SalaryAdvance, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('salary_advances').insert(ti(s, 'salary_advances', tid)).select().single()
  if (error) throw error
  return data as SalaryAdvance
}
export async function updateSalaryAdvance(id: string, updates: Partial<SalaryAdvance>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('salary_advances').update(updates), 'salary_advances', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SalaryAdvance
}


// ============ Phase 4: Pay Recalls ============
export async function getPayRecalls() {
  const tid = await getTenantId()
  let q = supabase.from('pay_recalls').select('*, employees(first_name, last_name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createPayRecall(r: Omit<PayRecall, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('pay_recalls').insert(ti(r, 'pay_recalls', tid)).select().single()
  if (error) throw error
  return data as PayRecall
}


// ============ Phase 4: DSN Declarations ============
export async function getDsnDeclarations() {
  const tid = await getTenantId()
  let q = supabase.from('dsn_declarations').select('*').order('period', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DsnDeclaration[]
}
export async function createDsnDeclaration(d: Omit<DsnDeclaration, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('dsn_declarations').insert(ti(d, 'dsn_declarations', tid)).select().single()
  if (error) throw error
  return data as DsnDeclaration
}
export async function updateDsnDeclaration(id: string, updates: Partial<DsnDeclaration>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('dsn_declarations').update(updates), 'dsn_declarations', tid).eq('id', id).select().single()
  if (error) throw error
  return data as DsnDeclaration
}


// ============ Phase 4: DPAE Records ============
export async function getDpaeRecords() {
  const tid = await getTenantId()
  let q = supabase.from('dpae_records').select('*, employees(first_name, last_name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createDpaeRecord(d: Omit<DpaeRecord, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('dpae_records').insert(ti(d, 'dpae_records', tid)).select().single()
  if (error) throw error
  return data as DpaeRecord
}


// ============ Phase 4: Work Hardship ============
export async function getWorkHardship(employeeId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('work_hardship').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createWorkHardship(w: Omit<WorkHardship, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('work_hardship').insert(ti(w, 'work_hardship', tid)).select().single()
  if (error) throw error
  return data as WorkHardship
}
export async function updateWorkHardship(id: string, updates: Partial<WorkHardship>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('work_hardship').update(updates), 'work_hardship', tid).eq('id', id).select().single()
  if (error) throw error
  return data as WorkHardship
}
export async function deleteWorkHardship(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('work_hardship').delete(), 'work_hardship', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 4: Career History ============
export async function getCareerHistory(employeeId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('career_history').select('*, employees(first_name, last_name)').order('start_date')
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createCareerHistory(c: Omit<CareerHistory, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('career_history').insert(ti(c, 'career_history', tid)).select().single()
  if (error) throw error
  return data as CareerHistory
}
export async function updateCareerHistory(id: string, updates: Partial<CareerHistory>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('career_history').update(updates), 'career_history', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CareerHistory
}
export async function deleteCareerHistory(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('career_history').delete(), 'career_history', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 4: CPF Accounts ============
export async function getCpfAccounts(employeeId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('cpf_accounts').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createCpfAccount(c: Omit<CpfAccount, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('cpf_accounts').insert(ti(c, 'cpf_accounts', tid)).select().single()
  if (error) throw error
  return data as CpfAccount
}
export async function updateCpfAccount(id: string, updates: Partial<CpfAccount>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('cpf_accounts').update(updates), 'cpf_accounts', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CpfAccount
}
export async function deleteCpfAccount(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('cpf_accounts').delete(), 'cpf_accounts', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 4: Payroll Archives ============
export async function getPayrollArchives() {
  const tid = await getTenantId()
  let q = supabase.from('payroll_archives').select('*, employees(first_name, last_name)').order('period', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createPayrollArchive(a: Omit<PayrollArchive, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payroll_archives').insert(ti(a, 'payroll_archives', tid)).select().single()
  if (error) throw error
  return data as PayrollArchive
}


// ============ Phase 4: Legal Watch ============
export async function getLegalWatch() {
  const tid = await getTenantId()
  let q = supabase.from('legal_watch').select('*').order('published_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as LegalWatch[]
}
export async function createLegalWatch(l: Omit<LegalWatch, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('legal_watch').insert(ti(l, 'legal_watch', tid)).select().single()
  if (error) throw error
  return data as LegalWatch
}
export async function updateLegalWatch(id: string, updates: Partial<LegalWatch>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('legal_watch').update(updates), 'legal_watch', tid).eq('id', id).select().single()
  if (error) throw error
  return data as LegalWatch
}


// ============ Phase 4: Employee Documents ============
// Note: getEmployeeDocuments, deleteEmployeeDocument, distributePaySlips are in dematRh.ts (Sprint G)
export async function createEmployeeDocument(d: Omit<EmployeeDocument, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('employee_documents').insert(ti(d, 'employee_documents', tid)).select().single()
  if (error) throw error
  return data as EmployeeDocument
}


// ============ Phase 4: Expense Reports ============
export async function getExpenseReports() {
  const tid = await getTenantId()
  let q = supabase.from('expense_reports').select('*, employees(first_name, last_name)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createExpenseReport(e: Omit<ExpenseReport, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('expense_reports').insert(ti(e, 'expense_reports', tid)).select().single()
  if (error) throw error
  return data as ExpenseReport
}
export async function updateExpenseReport(id: string, updates: Partial<ExpenseReport>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('expense_reports').update(updates), 'expense_reports', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ExpenseReport
}


// ============ Phase 4: Interviews ============
export async function getInterviews(employeeId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('interviews').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}
export async function createInterview(i: Omit<Interview, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('interviews').insert(ti(i, 'interviews', tid)).select().single()
  if (error) throw error
  return data as Interview
}
export async function updateInterview(id: string, updates: Partial<Interview>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('interviews').update(updates), 'interviews', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Interview
}


// ============ Payment Terms (Modèles de règlement) ============

export async function getPaymentTerms(): Promise<PaymentTerm[]> {
  const tid = await getTenantId()
  let q = supabase.from('payment_terms').select('*').order('code', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PaymentTerm[]
}

export async function getPaymentTermById(id: string): Promise<PaymentTerm | null> {
  const tid = await getTenantId()
  let q = supabase.from('payment_terms').select('*').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) return null
  return data as PaymentTerm
}

export async function createPaymentTerm(pt: Omit<PaymentTerm, 'id' | 'tenant_id' | 'created_at' | 'updated_at'>): Promise<PaymentTerm> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payment_terms').insert({ ...pt, tenant_id: tid }).select().single()
  if (error) throw error
  return data as PaymentTerm
}

export async function updatePaymentTerm(id: string, updates: Partial<PaymentTerm>): Promise<PaymentTerm> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('payment_terms').update(updates), 'payment_terms', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PaymentTerm
}

export async function deletePaymentTerm(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payment_terms').delete(), 'payment_terms', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7B: Payment Promises ============

export async function getPaymentPromises(): Promise<PaymentPromise[]> {
  const tid = await getTenantId()
  let q = supabase.from('payment_promises').select('*').order('promised_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PaymentPromise[]
}

export async function createPaymentPromise(pp: Omit<PaymentPromise, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<PaymentPromise> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payment_promises').insert({ ...pp, tenant_id: tid }).select().single()
  if (error) throw error
  return data as PaymentPromise
}

export async function updatePaymentPromise(id: string, updates: Partial<PaymentPromise>): Promise<PaymentPromise> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('payment_promises').update(updates), 'payment_promises', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PaymentPromise
}

export async function deletePaymentPromise(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payment_promises').delete(), 'payment_promises', tid).eq('id', id)
  if (error) throw error
}


// ============ Phase 7B: Mark line as BAP (Bon à Payer) ============

export async function markLineBAP(lineId: string, marked: boolean): Promise<void> {
  const tid = await getTenantId()
  const updates = marked
    ? { marked_bap: true, marked_bap_date: new Date().toISOString().slice(0, 10) }
    : { marked_bap: false, marked_bap_date: null }
  const { error } = await tud(supabase.from('journal_lines').update(updates), 'journal_lines', tid).eq('id', lineId)
  if (error) throw error
}


// ============ Phase 7D: Payment Templates Compta (Modèles de règlement compta) ============

export async function getPaymentTemplatesCompta(): Promise<PaymentTemplateCompta[]> {
  const tid = await getTenantId()
  let q = supabase.from('payment_templates_compta').select('*').order('code')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as PaymentTemplateCompta[]
}

export async function createPaymentTemplateCompta(pt: Omit<PaymentTemplateCompta, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<PaymentTemplateCompta> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('payment_templates_compta').insert({ ...pt, tenant_id: tid }).select().single()
  if (error) throw error
  return data as PaymentTemplateCompta
}

export async function updatePaymentTemplateCompta(id: string, updates: Partial<PaymentTemplateCompta>): Promise<PaymentTemplateCompta> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('payment_templates_compta').update(updates), 'payment_templates_compta', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PaymentTemplateCompta
}

export async function deletePaymentTemplateCompta(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payment_templates_compta').delete(), 'payment_templates_compta', tid).eq('id', id)
  if (error) throw error
}

