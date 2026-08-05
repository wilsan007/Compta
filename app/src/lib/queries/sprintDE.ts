import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from './core'
import type { WorkStoppage, IjssHistory, WorkHardshipRecord, CpfTransaction, MedicalExam, ExpenseCategory, ExpenseReportLine, InterviewCampaign, EmployeeObjective, EmployeeExitProcess, ExpenseReport, CpfAccount } from '@/types'

// ============ Sprint D: Work Stoppages (Arrêts de travail) ============

export async function getWorkStoppages(employeeId?: string, status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('work_stoppages').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  if (status) q = q.eq('status', status)
  const { data, error } = await q.order('start_date', { ascending: false })
  if (error) throw error
  return data as any[]
}

export async function createWorkStoppage(data: Omit<WorkStoppage, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('work_stoppages').insert(ti(data, 'work_stoppages', tid)).select().single()
  if (error) throw error
  return result as WorkStoppage
}

export async function updateWorkStoppage(id: string, updates: Partial<WorkStoppage>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('work_stoppages').update(updates), 'work_stoppages', tid).eq('id', id).select().single()
  if (error) throw error
  return data as WorkStoppage
}

export async function closeWorkStoppage(id: string, repriseDate: string, repriseType: string) {
  return updateWorkStoppage(id, { reprise_date: repriseDate, reprise_type: repriseType as any, status: 'closed', end_date: repriseDate })
}

export function calculateIjssBrut(ijssNet: number): number {
  return ijssNet / (1 - 0.067)
}

export async function calculateIjssEstimate(employeeId: string, startDate: string, endDate: string, stoppageType: string) {
  const tid = await getTenantId()
  let q = supabase.from('pay_slips').select('net_salary, gross_salary, period_start').eq('employee_id', employeeId).order('period_start', { ascending: false }).limit(3)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: slips, error } = await q
  if (error) throw error
  if (!slips || slips.length === 0) return { dailyRate: 0, estimatedAmount: 0, days: 0 }
  const avgGross = slips.reduce((s: number, p: any) => s + (p.gross_salary || 0), 0) / slips.length
  const dailyRate = avgGross / 30
  const start = new Date(startDate)
  const end = new Date(endDate)
  const days = Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24)) + 1
  const careDays = stoppageType === 'maladie' ? Math.min(3, days) : 0
  const payableDays = Math.max(0, days - careDays)
  return { dailyRate, estimatedAmount: dailyRate * payableDays, days, careDays }
}

export async function importBpij(workStoppageId: string, bpijNumber: string, ijssNetReceived: number) {
  const tid = await getTenantId()
  const ijssBrut = calculateIjssBrut(ijssNetReceived)
  const { data, error } = await tud(supabase.from('work_stoppages').update({
    bpij_number: bpijNumber, bpij_imported_at: new Date().toISOString(), ijss_net_amount: ijssNetReceived, ijss_brut_amount: ijssBrut,
  }), 'work_stoppages', tid).eq('id', workStoppageId).select().single()
  if (error) throw error
  return data as WorkStoppage
}

export async function regularizeIjss(workStoppageId: string, actualAmount: number) {
  const tid = await getTenantId()
  let sq = supabase.from('work_stoppages').select('ijss_net_amount').eq('id', workStoppageId)
  if (tid) sq = sq.eq('tenant_id', tid)
  const { data: stoppage } = await sq.single()
  const estimated = (stoppage as any)?.ijss_net_amount || 0
  const diff = actualAmount - estimated
  const { data, error } = await tud(supabase.from('work_stoppages').update({
    regularization_amount: Math.abs(diff), regularization_type: diff >= 0 ? 'positive' : 'negative', status: 'regularized',
  }), 'work_stoppages', tid).eq('id', workStoppageId).select().single()
  if (error) throw error
  return data as WorkStoppage
}

// ============ IJSS History ============

export async function getIjssHistory(workStoppageId: string) {
  const tid = await getTenantId()
  let q = supabase.from('ijss_history').select('*').eq('work_stoppage_id', workStoppageId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('period')
  if (error) throw error
  return data as IjssHistory[]
}

export async function getIjssHistoryByEmployee(employeeId: string) {
  const tid = await getTenantId()
  let q = supabase.from('ijss_history').select('*, work_stoppages(stoppage_type, start_date, end_date)').eq('employee_id', employeeId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('period', { ascending: false })
  if (error) throw error
  return data as any[]
}

export async function integrateIjssInPayslip(ijssHistoryId: string, payslipId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('ijss_history').update({ integrated_in_payslip: true, payslip_id: payslipId }), 'ijss_history', tid).eq('id', ijssHistoryId).select().single()
  if (error) throw error
  return data as IjssHistory
}

// ============ Work Hardship Records (C3P) ============

export async function getWorkHardshipRecords(employeeId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('work_hardship_records').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createWorkHardshipRecord(data: Omit<WorkHardshipRecord, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('work_hardship_records').insert(ti(data, 'work_hardship_records', tid)).select().single()
  if (error) throw error
  return result as WorkHardshipRecord
}

export async function updateWorkHardshipRecord(id: string, updates: Partial<WorkHardshipRecord>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('work_hardship_records').update(updates), 'work_hardship_records', tid).eq('id', id).select().single()
  if (error) throw error
  return data as WorkHardshipRecord
}

export async function calculateC3pPoints(employeeId: string) {
  const records = await getWorkHardshipRecords(employeeId)
  const levelMultiplier: Record<string, number> = { low: 1, medium: 2, high: 4 }
  return records.reduce((sum, r) => sum + (r.duration_months || 0) * (levelMultiplier[r.exposure_level] || 1), 0)
}

export async function declareWorkHardship(employeeId: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('work_hardship_records').update({ declaration_status: 'declared', declared_at: new Date().toISOString() }), 'work_hardship_records', tid).eq('employee_id', employeeId).eq('declaration_status', 'pending')
  if (error) throw error
}

// ============ CPF ============

export async function getCpfAccount(employeeId: string) {
  const tid = await getTenantId()
  let q = supabase.from('cpf_accounts').select('*, employees(first_name, last_name)').eq('employee_id', employeeId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return data as any
}

export async function updateCpfBalance(employeeId: string, hours: number, amount: number) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('cpf_accounts').update({ balance_hours: hours, balance_amount: amount, last_sync_date: new Date().toISOString() }), 'cpf_accounts', tid).eq('employee_id', employeeId).select().single()
  if (error) throw error
  return data as CpfAccount
}

export async function getCpfTransactions(employeeId: string) {
  const tid = await getTenantId()
  let q = supabase.from('cpf_transactions').select('*').eq('employee_id', employeeId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('created_at', { ascending: false })
  if (error) throw error
  return data as CpfTransaction[]
}

export async function createCpfTransaction(data: Omit<CpfTransaction, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('cpf_transactions').insert(ti(data, 'cpf_transactions', tid)).select().single()
  if (error) throw error
  return result as CpfTransaction
}

export async function getCpfAlerts() {
  const tid = await getTenantId()
  let q = supabase.from('cpf_accounts').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []).filter((a: any) => a.balance_hours > 100 || (a.last_sync_date && new Date(a.last_sync_date).getTime() < Date.now() - 180 * 24 * 60 * 60 * 1000))
}

// ============ Medical Exams ============

export async function getMedicalExams(employeeId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('medical_exams').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  const { data, error } = await q.order('scheduled_date', { ascending: false })
  if (error) throw error
  return data as any[]
}

export async function createMedicalExam(data: Omit<MedicalExam, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('medical_exams').insert(ti(data, 'medical_exams', tid)).select().single()
  if (error) throw error
  return result as MedicalExam
}

export async function updateMedicalExam(id: string, updates: Partial<MedicalExam>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('medical_exams').update(updates), 'medical_exams', tid).eq('id', id).select().single()
  if (error) throw error
  return data as MedicalExam
}

export async function getUpcomingMedicalExams(months: number = 3) {
  const tid = await getTenantId()
  const limitDate = new Date(); limitDate.setMonth(limitDate.getMonth() + months)
  let q = supabase.from('medical_exams').select('*, employees(first_name, last_name)').is('completed_date', null).lte('scheduled_date', limitDate.toISOString().split('T')[0])
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('scheduled_date')
  if (error) throw error
  return data as any[]
}

export async function getMedicalExamAlerts() {
  const tid = await getTenantId()
  const today = new Date().toISOString().split('T')[0]
  let q = supabase.from('medical_exams').select('*, employees(first_name, last_name)').is('completed_date', null).lt('scheduled_date', today)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

// ============ Expense Categories ============

export async function getExpenseCategories(activeOnly?: boolean) {
  const tid = await getTenantId()
  let q = supabase.from('expense_categories').select('*')
  if (tid) q = q.eq('tenant_id', tid)
  if (activeOnly) q = q.eq('active', true)
  const { data, error } = await q.order('code')
  if (error) throw error
  return data as ExpenseCategory[]
}

export async function createExpenseCategory(data: Omit<ExpenseCategory, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('expense_categories').insert(ti(data, 'expense_categories', tid)).select().single()
  if (error) throw error
  return result as ExpenseCategory
}

export async function updateExpenseCategory(id: string, updates: Partial<ExpenseCategory>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('expense_categories').update(updates), 'expense_categories', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ExpenseCategory
}

// ============ Expense Report Lines ============

export async function getExpenseReportLines(reportId: string) {
  const tid = await getTenantId()
  let q = supabase.from('expense_report_lines').select('*, expense_categories(label, code)').eq('expense_report_id', reportId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('date')
  if (error) throw error
  return data as any[]
}

export async function addExpenseReportLine(reportId: string, line: Omit<ExpenseReportLine, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('expense_report_lines').insert(ti({ ...line, expense_report_id: reportId }, 'expense_report_lines', tid)).select().single()
  if (error) throw error
  return data as ExpenseReportLine
}

export async function updateExpenseReportLine(id: string, updates: Partial<ExpenseReportLine>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('expense_report_lines').update(updates), 'expense_report_lines', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ExpenseReportLine
}

export async function deleteExpenseReportLine(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('expense_report_lines').delete(), 'expense_report_lines', tid).eq('id', id)
  if (error) throw error
}

export async function checkExpenseCeiling(lineId: string) {
  const tid = await getTenantId()
  let q = supabase.from('expense_report_lines').select('*, expense_categories(max_amount, max_monthly)').eq('id', lineId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  const line = data as any; const cat = line.expense_categories
  if (cat?.max_amount && line.amount_ttc > cat.max_amount) {
    await tud(supabase.from('expense_report_lines').update({ ceiling_exceeded: true }), 'expense_report_lines', tid).eq('id', lineId)
    return true
  }
  return false
}

// ============ Expense Reports (self-service) ============

export async function getMyExpenseReports() {
  const tid = await getTenantId()
  let q = supabase.from('expense_reports').select('*')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('created_at', { ascending: false })
  if (error) throw error
  return data as ExpenseReport[]
}

export async function createMyExpenseReport(data: Partial<ExpenseReport>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('expense_reports').insert(ti({ ...data, status: 'draft' }, 'expense_reports', tid)).select().single()
  if (error) throw error
  return result as ExpenseReport
}

export async function updateMyExpenseReport(id: string, updates: Partial<ExpenseReport>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('expense_reports').update(updates), 'expense_reports', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ExpenseReport
}

export async function submitMyExpenseReport(id: string) {
  return updateMyExpenseReport(id, { status: 'submitted', submitted_at: new Date().toISOString() })
}

export async function deleteMyExpenseReport(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('expense_reports').delete(), 'expense_reports', tid).eq('id', id).eq('status', 'draft')
  if (error) throw error
}

export async function getPendingExpenseReports(managerId?: string) {
  const tid = await getTenantId()
  let q = supabase.from('expense_reports').select('*, employees(first_name, last_name)').eq('status', 'submitted')
  if (tid) q = q.eq('tenant_id', tid)
  if (managerId) q = q.eq('manager_id', managerId)
  const { data, error } = await q.order('submitted_at')
  if (error) throw error
  return data as any[]
}

export async function approveExpenseReport(id: string, managerId: string, comment: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('expense_reports').update({ status: 'approved', approved_by: managerId, approved_at: new Date().toISOString(), manager_comment: comment }), 'expense_reports', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ExpenseReport
}

export async function rejectExpenseReport(id: string, managerId: string, comment: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('expense_reports').update({ status: 'rejected', approved_by: managerId, approved_at: new Date().toISOString(), manager_comment: comment }), 'expense_reports', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ExpenseReport
}

export async function markExpenseReimbursed(id: string, reimbursementDate: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('expense_reports').update({ status: 'reimbursed', reimbursement_date: reimbursementDate }), 'expense_reports', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ExpenseReport
}

// ============ Interview Campaigns ============

export async function getInterviewCampaigns(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('interview_campaigns').select('*')
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q.order('start_date', { ascending: false })
  if (error) throw error
  return data as InterviewCampaign[]
}

export async function createInterviewCampaign(data: Omit<InterviewCampaign, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('interview_campaigns').insert(ti(data, 'interview_campaigns', tid)).select().single()
  if (error) throw error
  return result as InterviewCampaign
}

export async function launchInterviewCampaign(id: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('interview_campaigns').update({ status: 'active' }), 'interview_campaigns', tid).eq('id', id).select().single()
  if (error) throw error
  return data as InterviewCampaign
}

export async function closeCampaign(id: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('interview_campaigns').update({ status: 'closed' }), 'interview_campaigns', tid).eq('id', id).select().single()
  if (error) throw error
  return data as InterviewCampaign
}

// ============ Objectives ============

export async function getMyObjectives() {
  const tid = await getTenantId()
  let q = supabase.from('employee_objectives').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('created_at', { ascending: false })
  if (error) throw error
  return data as any[]
}

export async function getObjectivesByEmployee(employeeId: string) {
  const tid = await getTenantId()
  let q = supabase.from('employee_objectives').select('*').eq('employee_id', employeeId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.order('created_at', { ascending: false })
  if (error) throw error
  return data as EmployeeObjective[]
}

export async function getObjectivesByCampaign(campaignId: string) {
  const tid = await getTenantId()
  let q = supabase.from('employee_objectives').select('*, employees(first_name, last_name)').eq('campaign_id', campaignId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function createObjective(data: Omit<EmployeeObjective, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('employee_objectives').insert(ti(data, 'employee_objectives', tid)).select().single()
  if (error) throw error
  return result as EmployeeObjective
}

export async function updateObjectiveProgress(id: string, currentValue: number) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('employee_objectives').update({ current_value: currentValue, updated_at: new Date().toISOString() }), 'employee_objectives', tid).eq('id', id).select().single()
  if (error) throw error
  return data as EmployeeObjective
}

// ============ Sprint E: Employee Exit ============

export async function createExitProcess(employeeId: string, exitDate: string, exitReason: string) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('employee_exit_processes').insert(ti({ employee_id: employeeId, exit_date: exitDate, exit_reason: exitReason, step: 1, status: 'in_progress' }, 'employee_exit_processes', tid)).select().single()
  if (error) throw error
  return data as EmployeeExitProcess
}

export async function getExitProcess(id: string) {
  const tid = await getTenantId()
  let q = supabase.from('employee_exit_processes').select('*, employees(first_name, last_name, department, position)').eq('id', id)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  return data as any
}

export async function getExitProcesses(status?: string) {
  const tid = await getTenantId()
  let q = supabase.from('employee_exit_processes').select('*, employees(first_name, last_name)')
  if (tid) q = q.eq('tenant_id', tid)
  if (status) q = q.eq('status', status)
  const { data, error } = await q.order('created_at', { ascending: false })
  if (error) throw error
  return data as any[]
}

export async function calculateFinalSettlement(exitProcessId: string) {
  const tid = await getTenantId()
  let sq = supabase.from('employee_exit_processes').select('*').eq('id', exitProcessId)
  if (tid) sq = sq.eq('tenant_id', tid)
  const { data: proc } = await sq.single()
  const p = proc as any; if (!p) throw new Error('Exit process not found')
  const totalGross = (p.cp_indemnity || 0) + (p.rtt_indemnity || 0) + (p.recovery_indemnity || 0) + (p.bonus_amount || 0) + (p.overtime_amount || 0) - (p.advance_deduction || 0)
  const totalNet = totalGross * 0.78
  const { data, error } = await tud(supabase.from('employee_exit_processes').update({ total_gross: totalGross, total_net: totalNet, step: 3 }), 'employee_exit_processes', tid).eq('id', exitProcessId).select().single()
  if (error) throw error
  return data as EmployeeExitProcess
}

export async function generateExitDocuments(exitProcessId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('employee_exit_processes').update({
    documents_generated: true, step: 4,
    work_certificate_url: `/documents/exit/${exitProcessId}/work_certificate.pdf`,
    settlement_receipt_url: `/documents/exit/${exitProcessId}/settlement_receipt.pdf`,
    pole_emploi_attestation_url: `/documents/exit/${exitProcessId}/pole_emploi_attestation.pdf`,
  }), 'employee_exit_processes', tid).eq('id', exitProcessId).select().single()
  if (error) throw error
  return data as EmployeeExitProcess
}

export async function markDsnExitGenerated(exitProcessId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('employee_exit_processes').update({
    dsn_exit_generated: true, dsn_exit_url: `/documents/exit/${exitProcessId}/dsn_exit.xml`, step: 5,
  }), 'employee_exit_processes', tid).eq('id', exitProcessId).select().single()
  if (error) throw error
  return data as EmployeeExitProcess
}

export async function transmitDsnExit(exitProcessId: string) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('employee_exit_processes').update({ dsn_exit_transmitted: true }), 'employee_exit_processes', tid).eq('id', exitProcessId).select().single()
  if (error) throw error
  return data as EmployeeExitProcess
}

export async function completeExitProcess(exitProcessId: string) {
  const tid = await getTenantId()
  let sq = supabase.from('employee_exit_processes').select('employee_id').eq('id', exitProcessId)
  if (tid) sq = sq.eq('tenant_id', tid)
  const { data: proc } = await sq.single()
  const p = proc as any
  if (p?.employee_id) { await tud(supabase.from('employees').update({ status: 'inactive' }), 'employees', tid).eq('id', p.employee_id) }
  const { data, error } = await tud(supabase.from('employee_exit_processes').update({ status: 'completed', step: 6, completed_at: new Date().toISOString() }), 'employee_exit_processes', tid).eq('id', exitProcessId).select().single()
  if (error) throw error
  return data as EmployeeExitProcess
}
