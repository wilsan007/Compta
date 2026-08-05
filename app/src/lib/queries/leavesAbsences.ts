import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from './core'
import type {
  LeaveBalance, PublicHoliday, LeaveRule, ApprovalWorkflow,
  LeaveProvision, StaffRequirement, Employee, LeaveRequest,
  MealVoucherConfig, PayrollVariableElement, SepaPaymentOrder,
  PaySlipClarified, PayrollComponent,
} from '@/types'

// ============ Leave Balances ============
export async function getLeaveBalances(employeeId?: string, year?: number): Promise<LeaveBalance[]> {
  const tid = await getTenantId()
  let q = supabase.from('leave_balances').select('*, employees(name, department)').order('year', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  if (year) q = q.eq('year', year)
  const { data, error } = await q
  if (error) throw error
  return data as LeaveBalance[]
}

export async function updateLeaveBalance(id: string, updates: Partial<LeaveBalance>): Promise<LeaveBalance> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('leave_balances').update(updates), 'leave_balances', tid).eq('id', id).select().single()
  if (error) throw error
  return data as LeaveBalance
}

export async function recalculateLeaveBalance(employeeId: string, leaveType: string, year: number): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('leave_balances').select('*').eq('employee_id', employeeId).eq('leave_type', leaveType).eq('year', year)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: balances, error } = await q
  if (error) throw error
  if (!balances || balances.length === 0) return
  const bal = balances[0]
  const remaining = Number(bal.acquired) + Number(bal.carry_over) - Number(bal.taken) - Number(bal.pending)
  await tud(supabase.from('leave_balances').update({ remaining, updated_at: new Date().toISOString() }), 'leave_balances', tid).eq('id', bal.id)
}

export async function carryOverLeaveBalances(employeeId: string, fromYear: number, toYear: number): Promise<void> {
  const tid = await getTenantId()
  let q = supabase.from('leave_balances').select('*').eq('employee_id', employeeId).eq('year', fromYear)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: balances, error } = await q
  if (error) throw error
  if (!balances) return
  for (const bal of balances) {
    const remaining = Number(bal.acquired) + Number(bal.carry_over) - Number(bal.taken)
    if (remaining <= 0) continue
    let rulesQ = supabase.from('leave_rules').select('max_carry_over').eq('leave_type', bal.leave_type)
    if (tid) rulesQ = rulesQ.eq('tenant_id', tid)
    const { data: rules } = await rulesQ.limit(1).maybeSingle()
    const maxCarry = rules ? Number(rules.max_carry_over) : 0
    const carryOver = Math.min(remaining, maxCarry)
    const { data: existing } = await supabase.from('leave_balances')
      .select('id').eq('employee_id', employeeId).eq('leave_type', bal.leave_type).eq('year', toYear)
      .maybeSingle()
    if (existing) {
      await tud(supabase.from('leave_balances').update({ carry_over: carryOver }), 'leave_balances', tid).eq('id', existing.id)
    } else {
      await supabase.from('leave_balances').insert(ti({
        employee_id: employeeId, leave_type: bal.leave_type, year: toYear,
        acquired: 0, taken: 0, pending: 0, remaining: carryOver, carry_over: carryOver,
      }, 'leave_balances', tid))
    }
  }
}

export async function initializeYearLeaveBalances(year: number): Promise<void> {
  const tid = await getTenantId()
  let empQ = supabase.from('employees').select('id, department').eq('status', 'active')
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: employees, error: empErr } = await empQ
  if (empErr) throw empErr
  if (!employees) return
  let rulesQ = supabase.from('leave_rules').select('*').eq('active', true)
  if (tid) rulesQ = rulesQ.eq('tenant_id', tid)
  const { data: rules, error: rulesErr } = await rulesQ
  if (rulesErr) throw rulesErr
  if (!rules) return
  for (const emp of employees) {
    for (const rule of rules) {
      const acquired = Number(rule.accrual_rate) * 12
      const { data: existing } = await supabase.from('leave_balances')
        .select('id').eq('employee_id', emp.id).eq('leave_type', rule.leave_type).eq('year', year)
        .maybeSingle()
      if (!existing) {
        await supabase.from('leave_balances').insert(ti({
          employee_id: emp.id, leave_type: rule.leave_type, year,
          acquired, taken: 0, pending: 0, remaining: acquired, carry_over: 0,
        }, 'leave_balances', tid))
      }
    }
  }
}

// ============ Leave Requests (extension) ============
export async function getMyLeaveRequests(): Promise<LeaveRequest[]> {
  const tid = await getTenantId()
  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) return []
  let q = supabase.from('leave_requests').select('*').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as LeaveRequest[]
}

export async function createMyLeaveRequest(data: {
  employee_id: string
  leave_type: string
  start_date: string
  end_date: string
  days: number
  reason?: string
}): Promise<LeaveRequest> {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('leave_requests').insert(ti({
    ...data, status: 'pending',
  }, 'leave_requests', tid)).select().single()
  if (error) throw error
  const balQ = supabase.from('leave_balances').select('*').eq('employee_id', data.employee_id).eq('leave_type', data.leave_type)
  const { data: bal } = await balQ.maybeSingle()
  if (bal) {
    const newPending = Number(bal.pending) + data.days
    const newRemaining = Number(bal.acquired) + Number(bal.carry_over) - Number(bal.taken) - newPending
    await tud(supabase.from('leave_balances').update({ pending: newPending, remaining: newRemaining }), 'leave_balances', tid).eq('id', bal.id)
  }
  return result as LeaveRequest
}

export async function cancelMyLeaveRequest(id: string): Promise<void> {
  const tid = await getTenantId()
  const { data: lr } = await supabase.from('leave_requests').select('*').eq('id', id).maybeSingle()
  if (!lr) return
  await tud(supabase.from('leave_requests').update({ status: 'cancelled' }), 'leave_requests', tid).eq('id', id)
  if (lr.status === 'pending') {
    const { data: bal } = await supabase.from('leave_balances').select('*').eq('employee_id', lr.employee_id).eq('leave_type', lr.leave_type).maybeSingle()
    if (bal) {
      const newPending = Math.max(0, Number(bal.pending) - Number(lr.days))
      const newRemaining = Number(bal.acquired) + Number(bal.carry_over) - Number(bal.taken) - newPending
      await tud(supabase.from('leave_balances').update({ pending: newPending, remaining: newRemaining }), 'leave_balances', tid).eq('id', bal.id)
    }
  }
}

export async function getPendingLeaveRequests(managerId?: string): Promise<any[]> {
  const tid = await getTenantId()
  let q = supabase.from('leave_requests').select('*, employees(name, department, manager_id)').eq('status', 'pending').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  if (managerId && data) {
    return data.filter((r: any) => r.employees?.manager_id === managerId)
  }
  return data as any[]
}

export async function approveLeaveRequest(id: string, _managerId: string, comment?: string): Promise<void> {
  const tid = await getTenantId()
  const { data: lr } = await supabase.from('leave_requests').select('*').eq('id', id).maybeSingle()
  if (!lr) return
  await tud(supabase.from('leave_requests').update({
    status: 'approved', approved_at: new Date().toISOString(), approved_by: _managerId, reason: comment || lr.reason,
  }), 'leave_requests', tid).eq('id', id)
  const { data: bal } = await supabase.from('leave_balances').select('*').eq('employee_id', lr.employee_id).eq('leave_type', lr.leave_type).maybeSingle()
  if (bal) {
    const newPending = Math.max(0, Number(bal.pending) - Number(lr.days))
    const newTaken = Number(bal.taken) + Number(lr.days)
    const newRemaining = Number(bal.acquired) + Number(bal.carry_over) - newTaken - newPending
    await tud(supabase.from('leave_balances').update({ pending: newPending, taken: newTaken, remaining: newRemaining }), 'leave_balances', tid).eq('id', bal.id)
  }
}

export async function rejectLeaveRequest(id: string, _managerId: string, comment?: string): Promise<void> {
  const tid = await getTenantId()
  const { data: lr } = await supabase.from('leave_requests').select('*').eq('id', id).maybeSingle()
  if (!lr) return
  await tud(supabase.from('leave_requests').update({
    status: 'rejected', approved_by: _managerId, reason: comment || lr.reason,
  }), 'leave_requests', tid).eq('id', id)
  if (lr.status === 'pending') {
    const { data: bal } = await supabase.from('leave_balances').select('*').eq('employee_id', lr.employee_id).eq('leave_type', lr.leave_type).maybeSingle()
    if (bal) {
      const newPending = Math.max(0, Number(bal.pending) - Number(lr.days))
      const newRemaining = Number(bal.acquired) + Number(bal.carry_over) - Number(bal.taken) - newPending
      await tud(supabase.from('leave_balances').update({ pending: newPending, remaining: newRemaining }), 'leave_balances', tid).eq('id', bal.id)
    }
  }
}

// ============ Public Holidays ============
export async function getPublicHolidays(year?: number, region?: string): Promise<PublicHoliday[]> {
  const tid = await getTenantId()
  let q = supabase.from('public_holidays').select('*').order('holiday_date', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  if (year) q = q.gte('holiday_date', `${year}-01-01`).lte('holiday_date', `${year}-12-31`)
  if (region) q = q.eq('region', region)
  const { data, error } = await q
  if (error) throw error
  return data as PublicHoliday[]
}

export async function createPublicHoliday(data: Omit<PublicHoliday, 'id' | 'created_at'>): Promise<PublicHoliday> {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('public_holidays').insert(ti(data, 'public_holidays', tid)).select().single()
  if (error) throw error
  return result as PublicHoliday
}

export async function deletePublicHoliday(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('public_holidays').delete(), 'public_holidays', tid).eq('id', id)
  if (error) throw error
}

// ============ Leave Rules ============
export async function getLeaveRules(activeOnly?: boolean): Promise<LeaveRule[]> {
  const tid = await getTenantId()
  let q = supabase.from('leave_rules').select('*').order('leave_type', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  if (activeOnly) q = q.eq('active', true)
  const { data, error } = await q
  if (error) throw error
  return data as LeaveRule[]
}

export async function createLeaveRule(data: Omit<LeaveRule, 'id' | 'created_at'>): Promise<LeaveRule> {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('leave_rules').insert(ti(data, 'leave_rules', tid)).select().single()
  if (error) throw error
  return result as LeaveRule
}

export async function updateLeaveRule(id: string, updates: Partial<LeaveRule>): Promise<LeaveRule> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('leave_rules').update(updates), 'leave_rules', tid).eq('id', id).select().single()
  if (error) throw error
  return data as LeaveRule
}

export async function deleteLeaveRule(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('leave_rules').delete(), 'leave_rules', tid).eq('id', id)
  if (error) throw error
}

// ============ Approval Workflows ============
export async function getApprovalWorkflows(entityType?: string): Promise<ApprovalWorkflow[]> {
  const tid = await getTenantId()
  let q = supabase.from('approval_workflows').select('*').order('name', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  if (entityType) q = q.eq('entity_type', entityType)
  const { data, error } = await q
  if (error) throw error
  return data as ApprovalWorkflow[]
}

export async function createApprovalWorkflow(data: Omit<ApprovalWorkflow, 'id' | 'created_at'>): Promise<ApprovalWorkflow> {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('approval_workflows').insert(ti(data, 'approval_workflows', tid)).select().single()
  if (error) throw error
  return result as ApprovalWorkflow
}

export async function updateApprovalWorkflow(id: string, updates: Partial<ApprovalWorkflow>): Promise<ApprovalWorkflow> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('approval_workflows').update(updates), 'approval_workflows', tid).eq('id', id).select().single()
  if (error) throw error
  return data as ApprovalWorkflow
}

// ============ Leave Provisions ============
export async function getLeaveProvisions(period?: string): Promise<LeaveProvision[]> {
  const tid = await getTenantId()
  let q = supabase.from('leave_provisions').select('*, employees(name, department)').order('period', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (period) q = q.eq('period', period)
  const { data, error } = await q
  if (error) throw error
  return data as LeaveProvision[]
}

export async function calculateLeaveProvisions(period: string): Promise<LeaveProvision[]> {
  const tid = await getTenantId()
  const year = parseInt(period.split('-')[0])
  let empQ = supabase.from('employees').select('id, name, salary').eq('status', 'active')
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: employees, error: empErr } = await empQ
  if (empErr) throw empErr
  if (!employees) return []
  const results: LeaveProvision[] = []
  for (const emp of employees) {
    let balQ = supabase.from('leave_balances').select('*').eq('employee_id', emp.id).eq('year', year)
    if (tid) balQ = balQ.eq('tenant_id', tid)
    const { data: balances } = await balQ
    const cpBal = balances?.find((b: any) => b.leave_type === 'annual')
    const rttBal = balances?.find((b: any) => b.leave_type === 'rtt')
    const recBal = balances?.find((b: any) => b.leave_type === 'recovery')
    const cpDays = cpBal ? Number(cpBal.remaining) : 0
    const rttDays = rttBal ? Number(rttBal.remaining) : 0
    const recDays = recBal ? Number(recBal.remaining) : 0
    const dailyRate = Number(emp.salary) / 21
    const cpProv = cpDays * dailyRate
    const rttProv = rttDays * dailyRate
    const recProv = recDays * dailyRate
    const total = cpProv + rttProv + recProv
    const { data: existing } = await supabase.from('leave_provisions')
      .select('id').eq('employee_id', emp.id).eq('period', period).maybeSingle()
    if (existing) {
      const { data: updated } = await tud(supabase.from('leave_provisions').update({
        cp_remaining_days: cpDays, rtt_remaining_days: rttDays, recovery_remaining_days: recDays,
        daily_rate: dailyRate, cp_provision: cpProv, rtt_provision: rttProv,
        recovery_provision: recProv, total_provision: total, status: 'calculated',
      }), 'leave_provisions', tid).eq('id', existing.id).select().single()
      if (updated) results.push(updated as LeaveProvision)
    } else {
      const { data: created } = await supabase.from('leave_provisions').insert(ti({
        employee_id: emp.id, period, cp_remaining_days: cpDays, rtt_remaining_days: rttDays,
        recovery_remaining_days: recDays, daily_rate: dailyRate, cp_provision: cpProv,
        rtt_provision: rttProv, recovery_provision: recProv, total_provision: total,
        status: 'calculated',
      }, 'leave_provisions', tid)).select().single()
      if (created) results.push(created as LeaveProvision)
    }
  }
  return results
}

export async function postLeaveProvisions(period: string): Promise<void> {
  const tid = await getTenantId()
  await tud(supabase.from('leave_provisions').update({ status: 'posted' }), 'leave_provisions', tid).eq('period', period).eq('status', 'calculated')
}

// ============ Staff Requirements ============
export async function getStaffRequirements(department?: string): Promise<StaffRequirement[]> {
  const tid = await getTenantId()
  let q = supabase.from('staff_requirements').select('*').order('department', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  if (department) q = q.eq('department', department)
  const { data, error } = await q
  if (error) throw error
  return data as StaffRequirement[]
}

export async function createStaffRequirement(data: Omit<StaffRequirement, 'id' | 'created_at'>): Promise<StaffRequirement> {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('staff_requirements').insert(ti(data, 'staff_requirements', tid)).select().single()
  if (error) throw error
  return result as StaffRequirement
}

export async function updateStaffRequirement(id: string, updates: Partial<StaffRequirement>): Promise<StaffRequirement> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('staff_requirements').update(updates), 'staff_requirements', tid).eq('id', id).select().single()
  if (error) throw error
  return data as StaffRequirement
}

// ============ Helpers ============
export function calculateWorkingDays(startDate: string, endDate: string, holidays: PublicHoliday[], method: string): number {
  const start = new Date(startDate)
  const end = new Date(endDate)
  let count = 0
  const holidayDates = new Set(holidays.map(h => h.holiday_date))
  const cur = new Date(start)
  while (cur <= end) {
    const day = cur.getDay()
    const dateStr = cur.toISOString().split('T')[0]
    const isHoliday = holidayDates.has(dateStr)
    if (method === 'calendar_days') {
      if (!isHoliday) count++
    } else if (method === 'working_days') {
      if (day >= 1 && day <= 5 && !isHoliday) count++
    } else if (method === 'working_days_excl_saturday') {
      if (day >= 1 && day <= 6 && !isHoliday) count++
    }
    cur.setDate(cur.getDate() + 1)
  }
  return count
}

export async function checkLeaveConflict(employeeId: string, startDate: string, endDate: string): Promise<boolean> {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) || !/^\d{4}-\d{2}-\d{2}$/.test(endDate)) throw new Error('Invalid date format')
  const tid = await getTenantId()
  let q = supabase.from('leave_requests')
    .select('id').eq('employee_id', employeeId).eq('status', 'approved')
    .or(`start_date.lte.${endDate},end_date.gte.${startDate}`)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data && data.length > 0)
}

export async function checkMinStaffRequired(department: string, startDate: string, endDate: string): Promise<{ ok: boolean; current: number; required: number }> {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) || !/^\d{4}-\d{2}-\d{2}$/.test(endDate)) throw new Error('Invalid date format')
  const tid = await getTenantId()
  let reqQ = supabase.from('staff_requirements').select('*').eq('department', department).eq('active', true)
  if (tid) reqQ = reqQ.eq('tenant_id', tid)
  const { data: reqs } = await reqQ
  if (!reqs || reqs.length === 0) return { ok: true, current: 0, required: 0 }
  const req = reqs[0]
  let empQ = supabase.from('employees').select('id').eq('department', department).eq('status', 'active')
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: emps } = await empQ
  const totalEmps = emps?.length || 0
  let leaveQ = supabase.from('leave_requests').select('employee_id').eq('status', 'approved')
    .or(`start_date.lte.${endDate},end_date.gte.${startDate}`)
  if (tid) leaveQ = leaveQ.eq('tenant_id', tid)
  const { data: onLeave } = await leaveQ
  const onLeaveCount = onLeave?.length || 0
  const available = totalEmps - onLeaveCount
  return { ok: available >= req.min_staff, current: available, required: req.min_staff }
}

export async function exportLeaveDataToPayroll(period: string): Promise<any[]> {
  const tid = await getTenantId()
  let q = supabase.from('leave_requests').select('*, employees(name, department)')
    .eq('status', 'approved')
    .gte('start_date', `${period}-01`).lte('end_date', `${period}-31`)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []).map((lr: any) => ({
    employee_id: lr.employee_id,
    employee_name: lr.employees?.name,
    leave_type: lr.leave_type,
    days: lr.days,
    period,
    element_type: 'absence',
    amount: 0,
    source: 'leave_request',
    source_id: lr.id,
  }))
}

// ============ Meal Vouchers ============
export async function getMealVoucherConfig(): Promise<MealVoucherConfig | null> {
  const tid = await getTenantId()
  let q = supabase.from('meal_voucher_config').select('*').eq('active', true).limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return data as MealVoucherConfig | null
}

export async function updateMealVoucherConfig(id: string, updates: Partial<MealVoucherConfig>): Promise<MealVoucherConfig> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('meal_voucher_config').update(updates), 'meal_voucher_config', tid).eq('id', id).select().single()
  if (error) throw error
  return data as MealVoucherConfig
}

export async function calculateMealVouchers(month: number, year: number): Promise<any[]> {
  const tid = await getTenantId()
  const config = await getMealVoucherConfig()
  if (!config) return []
  let empQ = supabase.from('employees').select('id, name, department').eq('status', 'active')
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: employees, error } = await empQ
  if (error) throw error
  if (!employees) return []
  const eligibleDays = config.eligible_days.map(Number)
  const daysInMonth = new Date(year, month, 0).getDate()
  let workingDays = 0
  for (let d = 1; d <= daysInMonth; d++) {
    const dow = new Date(year, month - 1, d).getDay()
    if (eligibleDays.includes(dow)) workingDays++
  }
  const nbVouchers = Math.min(workingDays, config.max_per_month)
  const totalValue = nbVouchers * Number(config.voucher_value)
  const employerAmount = totalValue * Number(config.employer_share) / 100
  const employeeAmount = totalValue * Number(config.employee_share) / 100
  return employees.map((emp: any) => ({
    employee_id: emp.id,
    employee_name: emp.name,
    department: emp.department,
    working_days: workingDays,
    nb_vouchers: nbVouchers,
    voucher_value: Number(config.voucher_value),
    employer_amount: employerAmount,
    employee_amount: employeeAmount,
    total: totalValue,
  }))
}

export async function generateMealVoucherElements(payRunId: string, month: number, year: number): Promise<void> {
  const tid = await getTenantId()
  const calculations = await calculateMealVouchers(month, year)
  const period = `${year}-${String(month).padStart(2, '0')}`
  for (const calc of calculations) {
    await supabase.from('payroll_variable_elements').insert(ti({
      employee_id: calc.employee_id,
      pay_run_id: payRunId,
      period,
      element_type: 'meal_voucher',
      description: `Titres restaurant ${period}`,
      quantity: calc.nb_vouchers,
      unit_price: calc.voucher_value,
      amount: calc.employee_amount,
      source: 'import',
      integrated: false,
    }, 'payroll_variable_elements', tid))
  }
}

// ============ Variable Elements ============
export async function getVariableElements(payRunId?: string, employeeId?: string, period?: string): Promise<PayrollVariableElement[]> {
  const tid = await getTenantId()
  let q = supabase.from('payroll_variable_elements').select('*, employees(name, department)').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (payRunId) q = q.eq('pay_run_id', payRunId)
  if (employeeId) q = q.eq('employee_id', employeeId)
  if (period) q = q.eq('period', period)
  const { data, error } = await q
  if (error) throw error
  return data as PayrollVariableElement[]
}

export async function createVariableElement(data: Omit<PayrollVariableElement, 'id' | 'created_at'>): Promise<PayrollVariableElement> {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('payroll_variable_elements').insert(ti(data, 'payroll_variable_elements', tid)).select().single()
  if (error) throw error
  return result as PayrollVariableElement
}

export async function updateVariableElement(id: string, updates: Partial<PayrollVariableElement>): Promise<PayrollVariableElement> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('payroll_variable_elements').update(updates), 'payroll_variable_elements', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PayrollVariableElement
}

export async function deleteVariableElement(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('payroll_variable_elements').delete(), 'payroll_variable_elements', tid).eq('id', id)
  if (error) throw error
}

export async function importTimesheetElements(payRunId: string, month: number, year: number): Promise<void> {
  const tid = await getTenantId()
  const period = `${year}-${String(month).padStart(2, '0')}`
  let q = supabase.from('timesheets').select('*, employees(name)').eq('status', 'approved')
    .gte('date', `${period}-01`).lte('date', `${period}-31`)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: timesheets, error } = await q
  if (error) throw error
  if (!timesheets) return
  for (const ts of timesheets) {
    const hours = Number(ts.hours || 0)
    const overtimeHours = Math.max(0, hours - 8)
    if (overtimeHours > 0) {
      const empSalary = await supabase.from('employees').select('salary').eq('id', ts.employee_id).maybeSingle()
      const hourlyRate = Number(empSalary.data?.salary || 0) / 151.67
      const overtimeRate = hourlyRate * 1.25
      await supabase.from('payroll_variable_elements').insert(ti({
        employee_id: ts.employee_id, pay_run_id: payRunId, period,
        element_type: 'overtime', description: `Heures sup ${period}`,
        quantity: overtimeHours, unit_price: overtimeRate, amount: overtimeHours * overtimeRate,
        source: 'timesheet', source_id: ts.id, integrated: false,
      }, 'payroll_variable_elements', tid))
    }
  }
}

export async function importLeaveElements(payRunId: string, month: number, year: number): Promise<void> {
  const tid = await getTenantId()
  const period = `${year}-${String(month).padStart(2, '0')}`
  let q = supabase.from('leave_requests').select('*').eq('status', 'approved')
    .gte('start_date', `${period}-01`).lte('end_date', `${period}-31`)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: leaves, error } = await q
  if (error) throw error
  if (!leaves) return
  for (const lr of leaves) {
    if (lr.leave_type === 'unpaid') {
      const empSalary = await supabase.from('employees').select('salary').eq('id', lr.employee_id).maybeSingle()
      const dailyRate = Number(empSalary.data?.salary || 0) / 21
      await supabase.from('payroll_variable_elements').insert(ti({
        employee_id: lr.employee_id, pay_run_id: payRunId, period,
        element_type: 'absence', description: `Absence ${lr.leave_type} ${period}`,
        quantity: Number(lr.days), unit_price: dailyRate, amount: Number(lr.days) * dailyRate,
        source: 'leave_request', source_id: lr.id, integrated: false,
      }, 'payroll_variable_elements', tid))
    }
  }
}

export async function importExpenseElements(payRunId: string, month: number, year: number): Promise<void> {
  const tid = await getTenantId()
  const period = `${year}-${String(month).padStart(2, '0')}`
  let q = supabase.from('expense_reports').select('*').eq('status', 'approved')
    .gte('created_at', `${period}-01`).lt('created_at', `${period}-31T23:59:59`)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: expenses, error } = await q
  if (error) throw error
  if (!expenses) return
  for (const exp of expenses) {
    await supabase.from('payroll_variable_elements').insert(ti({
      employee_id: exp.employee_id, pay_run_id: payRunId, period,
      element_type: 'other', description: `Note de frais ${period}`,
      quantity: null, unit_price: null, amount: Number(exp.amount),
      source: 'expense_report', source_id: exp.id, integrated: false,
    }, 'payroll_variable_elements', tid))
  }
}

// ============ Reverse Calculation ============
export function calculateGrossFromNet(
  targetNet: number,
  components: PayrollComponent[],
  _employeeProfile: Employee
): { grossSalary: number; breakdown: { code: string; name: string; amount: number }[] } {
  let gross = targetNet / 0.78
  for (let i = 0; i < 10; i++) {
    let totalDeductions = 0
    const breakdown: { code: string; name: string; amount: number }[] = []
    for (const comp of components) {
      if (comp.type === 'deduction' || comp.type === 'contribution') {
        const empRate = Number(comp.rate_employee) / 100
        let amount = gross * empRate
        if (comp.ceiling_amount && amount > Number(comp.ceiling_amount)) {
          amount = Number(comp.ceiling_amount)
        }
        totalDeductions += amount
        breakdown.push({ code: comp.code, name: comp.name, amount })
      }
    }
    const taxRate = 0.10
    const taxAmount = (gross - totalDeductions) * taxRate
    totalDeductions += taxAmount
    breakdown.push({ code: 'IR', name: 'Impôt sur le revenu', amount: taxAmount })
    const net = gross - totalDeductions
    if (Math.abs(net - targetNet) < 0.01) {
      return { grossSalary: gross, breakdown }
    }
    gross += (targetNet - net)
  }
  return { grossSalary: gross, breakdown: [] }
}

// ============ SEPA ============
export async function generateSepaFile(payRunId: string, executionDate: string): Promise<SepaPaymentOrder> {
  const tid = await getTenantId()
  let q = supabase.from('pay_slips').select('*, employees(name, iban)').eq('pay_run_id', payRunId).eq('status', 'paid')
  if (tid) q = q.eq('tenant_id', tid)
  const { data: slips, error } = await q
  if (error) throw error
  if (!slips || slips.length === 0) throw new Error('No paid payslips found')
  const totalAmount = slips.reduce((s: number, sl: any) => s + Number(sl.net_salary), 0)
  const number = `SEPA-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`
  const { data: order, error: orderErr } = await supabase.from('sepa_payment_orders').insert(ti({
    pay_run_id: payRunId, number, execution_date: executionDate,
    total_amount: totalAmount, currency: 'EUR', employee_count: slips.length,
    file_url: null, file_generated_at: new Date().toISOString(), status: 'generated',
  }, 'sepa_payment_orders', tid)).select().single()
  if (orderErr) throw orderErr
  return order as SepaPaymentOrder
}

export async function getSepaPaymentOrders(): Promise<SepaPaymentOrder[]> {
  const tid = await getTenantId()
  let q = supabase.from('sepa_payment_orders').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as SepaPaymentOrder[]
}

export async function transmitSepaOrder(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('sepa_payment_orders').update({
    status: 'transmitted', transmitted_at: new Date().toISOString(),
  }), 'sepa_payment_orders', tid).eq('id', id)
  if (error) throw error
}

// ============ Double storage ============
export async function generateClarifiedPaySlip(paySlipId: string): Promise<PaySlipClarified> {
  const tid = await getTenantId()
  const { data: slip, error: slipErr } = await supabase.from('pay_slips').select('*').eq('id', paySlipId).maybeSingle()
  if (slipErr) throw slipErr
  if (!slip) throw new Error('Payslip not found')
  const lines = [
    { category: 'gross', label: 'Salaire brut', amount: Number(slip.total_gross) },
    { category: 'deduction', label: 'Cotisations sociales salariales', amount: -Number(slip.social_security_employee) },
    { category: 'tax', label: 'Prélèvement à la source', amount: -Number(slip.income_tax) },
    { category: 'deduction', label: 'Autres déductions', amount: -Number(slip.other_deductions) },
    { category: 'net', label: 'Net à payer', amount: Number(slip.net_salary) },
  ]
  const { data: existing } = await supabase.from('pay_slip_clarified').select('id').eq('pay_slip_id', paySlipId).maybeSingle()
  if (existing) {
    const { data: updated, error } = await tud(supabase.from('pay_slip_clarified').update({
      gross_salary: slip.total_gross, social_charges_employee: slip.social_security_employee,
      income_tax: slip.income_tax, total_deductions: slip.total_deductions,
      net_before_tax: slip.total_gross - Number(slip.social_security_employee) - Number(slip.other_deductions),
      net_after_tax: slip.net_salary, lines,
    }), 'pay_slip_clarified', tid).eq('id', existing.id).select().single()
    if (error) throw error
    return updated as PaySlipClarified
  }
  const { data: created, error: createErr } = await supabase.from('pay_slip_clarified').insert(ti({
    pay_slip_id: paySlipId, employee_id: slip.employee_id,
    period: `${slip.period_start} - ${slip.period_end}`,
    gross_salary: slip.total_gross, social_charges_employee: slip.social_security_employee,
    social_charges_employer: slip.employer_contributions, income_tax: slip.income_tax,
    net_before_tax: slip.total_gross - Number(slip.social_security_employee) - Number(slip.other_deductions),
    net_after_tax: slip.net_salary, total_deductions: slip.total_deductions, lines,
  }, 'pay_slip_clarified', tid)).select().single()
  if (createErr) throw createErr
  return created as PaySlipClarified
}

// ============ Payroll Analytic Entries ============
export async function generatePayrollAnalyticEntries(payRunId: string): Promise<any[]> {
  const tid = await getTenantId()
  let q = supabase.from('pay_slips').select('*, employees(department)').eq('pay_run_id', payRunId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: slips, error } = await q
  if (error) throw error
  if (!slips) return []
  return slips.map((sl: any) => ({
    pay_slip_id: sl.id,
    employee_id: sl.employee_id,
    department: sl.employees?.department || 'N/A',
    gross_amount: Number(sl.total_gross),
    employer_charges: Number(sl.employer_contributions),
    net_amount: Number(sl.net_salary),
    cost_center: sl.employees?.department || 'N/A',
  }))
}
