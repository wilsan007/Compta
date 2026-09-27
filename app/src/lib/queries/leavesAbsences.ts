import { supabase } from '@/lib/supabase'
import type { Joined } from '@/types/dbRow'
import { fetchAllRows, getTenantId, nextDocumentNumber, ti, tud } from './core'
// W4 (RH-06, RH-09) : bornes de période calculées et intersection des congés.
import { periodBounds, periodOf, periodOverlapFilter } from '@/lib/payrollPeriods'
import type {
  LeaveBalance, PublicHoliday, LeaveRule, ApprovalWorkflow,
  LeaveProvision, StaffRequirement, Employee, LeaveRequest,
  MealVoucherConfig, PayrollVariableElement, SepaPaymentOrder,
  PaySlipClarified, PayrollComponent,
} from '@/types'

/**
 * Clé d'unicité des éléments de paie : `uniq_payroll_element_source` (256).
 * Un même document source ne produit qu'un élément — c'est aussi l'arbitre
 * que PostgREST reçoit, pour que rejouer un import n'échoue pas et ne double
 * rien (RH-10).
 */
const PAYROLL_ELEMENT_KEYS = 'tenant_id,employee_id,period,element_type,source,source_id'

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
    const { data: existing, error: existError } = await supabase.from('leave_balances')
      .select('id').eq('employee_id', employeeId).eq('leave_type', bal.leave_type).eq('year', toYear)
      .maybeSingle()
    if (existError) throw existError
    if (existing) {
      await tud(supabase.from('leave_balances').update({ carry_over: carryOver }), 'leave_balances', tid).eq('id', existing.id)
    } else {
      // W6 : l'alimentation des soldes de congés ne peut pas échouer en
      // silence — c'est elle qui décide du report de l'année suivante.
      const { error: insErr } = await supabase.from('leave_balances').insert(ti({
        employee_id: employeeId, leave_type: bal.leave_type, year: toYear,
        acquired: 0, taken: 0, pending: 0, remaining: carryOver, carry_over: carryOver,
      }, 'leave_balances', tid))
      if (insErr) throw insErr
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
      const { data: existing, error } = await supabase.from('leave_balances')
        .select('id').eq('employee_id', emp.id).eq('leave_type', rule.leave_type).eq('year', year)
        .maybeSingle()
      if (error) throw error
      if (!existing) {
        // W6 : une société dont les soldes de congés ne s'initialisent pas le
        // sait désormais (l'erreur montait dans le vide).
        const { error: initErr } = await supabase.from('leave_balances').insert(ti({
          employee_id: emp.id, leave_type: rule.leave_type, year,
          acquired, taken: 0, pending: 0, remaining: acquired, carry_over: 0,
        }, 'leave_balances', tid))
        if (initErr) throw initErr
      }
    }
  }
}

// ============ Leave Requests (extension) ============
export async function getMyLeaveRequests(): Promise<LeaveRequest[]> {
  const tid = await getTenantId()
  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError) throw userError
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
    ...(data || {}), status: 'pending',
  }, 'leave_requests', tid)).select().single()
  if (error) throw error
  // W9 (TRV-15) : le solde n'est PLUS débité ici. Le mouvement vit en base
  // (déclencheur `apply_leave_balance` de la 263) : le faire aussi dans l'écran
  // le comptait deux fois, et un import ou un appel direct le perdait.
  return result as LeaveRequest
}

export async function cancelMyLeaveRequest(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('leave_requests').update({ status: 'cancelled' }), 'leave_requests', tid).eq('id', id)
  if (error) throw error
  // W9 (TRV-15) : la restitution du solde est faite par le déclencheur de la
  // base, qui connaît l'état d'origine (`pending` ou `approved`) — pas l'écran.
}

// LOT7-04 : cette fonction échouait systématiquement, pour DEUX raisons cumulées,
// toutes deux vérifiées sur un PostgREST 16.3 réel :
//  1. `leave_requests` porte deux clés étrangères vers `employees` (`employee_id` et
//     `approved_by`) : l'embed `employees(...)` est ambigu et PostgREST répond
//     **HTTP 300 / PGRST201**. Il faut nommer la contrainte à utiliser.
//  2. le select demandait `manager_id`, colonne qui n'existe pas sur `employees` —
//     **HTTP 400 / 42703 « column employees_1.manager_id does not exist »**. Il
//     n'existe aucun lien hiérarchique sur `employees` en base (seules `projects` et
//     `expense_reports` ont un `manager_id`).
// Conséquence : la page d'approbation des congés (`ManagerLeaveApprovalsPage`) ne
// pouvait rien afficher. Son unique appel se fait sans `managerId`, donc le filtre
// hiérarchique n'a de toute façon jamais été exercé.
// Le paramètre est conservé pour ne pas casser la signature, mais il lève désormais
// au lieu de rendre une liste vide : filtrer sur un champ inexistant renverrait
// silencieusement « aucune demande à approuver ».
export async function getPendingLeaveRequests(
  managerId?: string
): Promise<(LeaveRequest & { employees: Joined<'employees', 'name' | 'department'> })[]> {
  if (managerId) {
    throw new Error(
      "getPendingLeaveRequests : filtrage par manager non disponible — `employees` ne porte aucun lien hiérarchique en base. Ajouter la colonne et une migration avant d'utiliser ce paramètre."
    )
  }
  const tid = await getTenantId()
  let q = supabase
    .from('leave_requests')
    .select('*, employees!leave_requests_employee_id_fkey(name, department)')
    .eq('status', 'pending')
    .order('start_date', { ascending: false })
    .order('id')
  if (tid) q = q.eq('tenant_id', tid)
  const data = await fetchAllRows<LeaveRequest & { employees: Joined<'employees', 'name' | 'department'> }>(
    q, { label: 'getPendingLeaveRequests' }
  )
  return data
}

export async function approveLeaveRequest(id: string, _managerId: string, comment?: string): Promise<void> {
  const tid = await getTenantId()
  const { error: readError } = await supabase.from('leave_requests').select('id').eq('id', id).maybeSingle()
  if (readError) throw readError
  const { error } = await tud(supabase.from('leave_requests').update({
    status: 'approved', approved_at: new Date().toISOString(), approved_by: _managerId, reason: comment || undefined,
  }), 'leave_requests', tid).eq('id', id)
  if (error) throw error
  // W9 (TRV-15) : le transfert « en attente » → « pris » est fait par le
  // déclencheur `apply_leave_balance` de la base. L'écran ne touche plus au
  // solde : son calcul était faux dès qu'un import ou un appel direct écrivait
  // la même décision.
}

export async function rejectLeaveRequest(id: string, _managerId: string, comment?: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('leave_requests').update({
    status: 'rejected', approved_by: _managerId, reason: comment || undefined,
  }), 'leave_requests', tid).eq('id', id)
  if (error) throw error
  // W9 (TRV-15) : la restitution du « en attente » est faite par la base.
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

  // W9 (cohérence UI ↔ base, suite de RH-05) : le taux journalier d'une
  // provision de congés est LE diviseur de la société — celui que la paie
  // applique (RPC `payroll_divisors`, 256). Le `/ 21` que l'écran portait
  // encore était le cinquième diviseur : la même journée valait 100,00 € pour
  // la paie et 123,81 € dans la provision.
  const { data: divisors, error: divErr } = await supabase.rpc('payroll_divisors')
  if (divErr) throw divErr
  const joursDivisor = Number((divisors as any)?.jours ?? 0)
  if (!(joursDivisor > 0)) {
    throw new Error("Provision de congés : le diviseur mensuel « jours » de la société est introuvable — la provision ne peut pas être valorisée sans lui.")
  }

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
    const dailyRate = Number(emp.salary) / joursDivisor
    const cpProv = cpDays * dailyRate
    const rttProv = rttDays * dailyRate
    const recProv = recDays * dailyRate
    const total = cpProv + rttProv + recProv
    const { data: existing, error } = await supabase.from('leave_provisions')
      .select('id').eq('employee_id', emp.id).eq('period', period).maybeSingle()
    if (error) throw error
    if (existing) {
      const { data: updated } = await tud(supabase.from('leave_provisions').update({
        cp_remaining_days: cpDays, rtt_remaining_days: rttDays, recovery_remaining_days: recDays,
        daily_rate: dailyRate, cp_provision: cpProv, rtt_provision: rttProv,
        recovery_provision: recProv, total_provision: total, status: 'calculated',
      }), 'leave_provisions', tid).eq('id', existing.id).select().single()
      if (updated) results.push(updated as LeaveProvision)
    } else {
      const { data: created, error: createError } = await supabase.from('leave_provisions').insert(ti({
        employee_id: emp.id, period, cp_remaining_days: cpDays, rtt_remaining_days: rttDays,
        recovery_remaining_days: recDays, daily_rate: dailyRate, cp_provision: cpProv,
        rtt_provision: rttProv, recovery_provision: recProv, total_provision: total,
        status: 'calculated',
      }, 'leave_provisions', tid)).select().single()
      if (createError) throw createError
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
  const bounds = periodBounds(period)
  // LOT7-04 : deux clés étrangères relient `leave_requests` à `employees`
  // (`employee_id` et `approved_by`) : sans nommer la contrainte, PostgREST répond
  // 300/PGRST201 et l'export des absences vers la paie échouait.
  let q = supabase.from('leave_requests').select('*, employees!leave_requests_employee_id_fkey(name, department)')
    .eq('status', 'approved')
    // W4 (RH-09) : INTERSECTION de périodes, et non « contenu dans la période ».
    // Un congé du 28/04 au 03/05 est donc compté dans les deux bulletins — il
    // n'est plus omis des deux.
    .or(periodOverlapFilter(bounds))
    .order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : alimentation de la paie. Une absence oubliée = un bulletin faux.
  const data = await fetchAllRows<any>(q, { label: 'exportLeaveDataToPayroll/leave_requests' })
  return data.map((lr: any) => ({
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
    // W4 (RH-10) : la source est LE LOT DE PAIE et l'insertion est un upsert qui
    // ignore le doublon — relancer l'import ne double plus l'élément (la
    // contrainte `uniq_payroll_element_source` le garantit aussi en base).
    // Et le type est `meal_vouchers` (pluriel) : c'est celui que lit le moteur
    // de bulletins (`calculate_payslip`). En `meal_voucher`, la ligne existait
    // mais n'entrait dans aucun net.
    const { error: writeError } = await supabase.from('payroll_variable_elements').upsert(ti({
      employee_id: calc.employee_id,
      pay_run_id: payRunId,
      period,
      element_type: 'meal_vouchers',
      description: `Titres restaurant ${period}`,
      quantity: calc.nb_vouchers,
      unit_price: calc.voucher_value,
      amount: calc.employee_amount,
      source: 'meal_voucher',
      source_id: payRunId,
      integrated: false,
    }, 'payroll_variable_elements', tid), { onConflict: PAYROLL_ELEMENT_KEYS, ignoreDuplicates: true })
    // W0 : une écriture qui échoue sans le dire est pire qu'une écriture absente.
    if (writeError) throw writeError
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

/**
 * W5 (RH-04) : LE calcul des heures supplémentaires appartient à la base. Le
 * pointage approuvé pose déjà son élément (`overtime_minutes` mesurés sur
 * l'horaire prévu → `payroll_overtime_amount` pour le taux et le montant). Le
 * front ne recalcule plus rien — il n'a plus de seuil à lui (l'ancien « > 8 h »
 * contredisait celui de la base) ni de taux à lui (le « × 1,25 » était en dur).
 *
 * Ce que l'écran fait encore, et qui lui appartient : RATTACHER au lot de paie
 * les éléments que la base a écrits avant que le lot n'existe. C'est ce que
 * l'ancien import ne faisait pas : son `upsert` était avalé par l'index unique
 * de la 256 (l'élément existait déjà) et l'élément restait sans `pay_run_id`,
 * donc hors du bulletin (`calculate_payslip` lit par `pay_run_id`).
 *
 * Renvoie le nombre d'éléments rattachés (0 = tout était déjà rattaché).
 */
export async function attachTimesheetElements(payRunId: string, month: number, year: number): Promise<number> {
  const tid = await getTenantId()
  const period = `${year}-${String(month).padStart(2, '0')}`
  let q = supabase.from('payroll_variable_elements')
    .update({ pay_run_id: payRunId })
    .eq('source', 'timesheet')
    .eq('period', period)
    .is('pay_run_id', null)
    // `integrated` peut être NULL (les alimentations de la base ne le posent pas
    // toujours) : « non intégré » couvre les deux écritures.
    .or('integrated.is.null,integrated.eq.false')
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.select('id')
  if (error) throw error
  return data?.length ?? 0
}

export async function importLeaveElements(payRunId: string, month: number, year: number): Promise<void> {
  const tid = await getTenantId()
  const period = `${year}-${String(month).padStart(2, '0')}`
  const bounds = periodBounds(period)
  let q = supabase.from('leave_requests').select('*').eq('status', 'approved')
    // W4 (RH-09) : INTERSECTION — le congé qui traverse deux mois entre dans les
    // deux bulletins, au lieu de n'entrer dans aucun.
    .or(periodOverlapFilter(bounds))
  if (tid) q = q.eq('tenant_id', tid)
  const { data: leaves, error } = await q
  if (error) throw error
  if (!leaves) return
  // W4 (RH-05) : taux journalier = diviseur JOURS de la société (le même que le
  // déclencheur `deduct_unpaid_leave_on_approval`), jamais « / 21 ».
  const { data: divisors, error: divisorsError } = await supabase.rpc('payroll_divisors')
  if (divisorsError) throw divisorsError
  const dailyDivisor = Number((divisors as any)?.jours || 0)
  for (const lr of leaves) {
    if (lr.leave_type === 'unpaid') {
      const empSalary = await supabase.from('employees').select('salary').eq('id', lr.employee_id).maybeSingle()
      const dailyRate = dailyDivisor > 0 ? Number(empSalary.data?.salary || 0) / dailyDivisor : 0
      // W4 (RH-10) : le type est `unpaid_leave_deduction` — celui que le moteur
      // de bulletins retranche du brut. En `absence`, la ligne était ignorée.
      const { error: writeError } = await supabase.from('payroll_variable_elements').upsert(ti({
        employee_id: lr.employee_id, pay_run_id: payRunId, period,
        element_type: 'unpaid_leave_deduction', description: `Absence ${lr.leave_type} ${period}`,
        quantity: Number(lr.days), unit_price: dailyRate, amount: Number(lr.days) * dailyRate,
        source: 'leave_request', source_id: lr.id, integrated: false,
      }, 'payroll_variable_elements', tid), { onConflict: PAYROLL_ELEMENT_KEYS, ignoreDuplicates: true })
      if (writeError) throw writeError
    }
  }
}

export async function importExpenseElements(payRunId: string, month: number, year: number): Promise<void> {
  const tid = await getTenantId()
  const period = `${year}-${String(month).padStart(2, '0')}`
  const bounds = periodBounds(period)
  let q = supabase.from('expense_reports').select('*').eq('status', 'approved')
    // W4 (RH-06, RH-07) : bornes calculées, et la période de la note d'abord —
    // `created_at` ne décide plus seul de la période de paie.
    .or(`period.eq.${period},and(period.is.null,created_at.gte.${bounds.first},created_at.lte.${bounds.last}T23:59:59)`)
    .order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : import des notes de frais dans la paie — aucune ne doit être omise.
  const expenses = await fetchAllRows<any>(q, { label: 'importExpenseElements/expense_reports' })
  for (const exp of expenses) {
    // W4 (RH-07) : le montant est `total_amount`. `amount` n'existe pas sur
    // `expense_reports` : la note entrait en paie pour 0 (et, quand le type était
    // `other`, elle sortait du net au lieu d'y entrer).
    const { error: writeError } = await supabase.from('payroll_variable_elements').upsert(ti({
      employee_id: exp.employee_id, pay_run_id: payRunId,
      period: exp.period || periodOf(exp.created_at || `${period}-01`),
      element_type: 'expense_reimbursement', description: `Note de frais ${exp.number || period}`,
      quantity: null, unit_price: null, amount: Number(exp.total_amount ?? 0),
      source: 'expense_report', source_id: exp.id, integrated: false,
    }, 'payroll_variable_elements', tid), { onConflict: PAYROLL_ELEMENT_KEYS, ignoreDuplicates: true })
    if (writeError) throw writeError
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
  // LOT7-04 : la colonne s'appelle `bank_iban`, pas `iban` — 400/42703. La génération
  // du fichier SEPA de virement des salaires échouait donc toujours.
  let q = supabase.from('pay_slips').select('*, employees(name, bank_iban)').eq('pay_run_id', payRunId).eq('status', 'paid')
  if (tid) q = q.eq('tenant_id', tid)
  const { data: slips, error } = await q
  if (error) throw error
  if (!slips || slips.length === 0) throw new Error('No paid payslips found')
  const totalAmount = slips.reduce((s: number, sl: any) => s + Number(sl.net_salary), 0)
  const number = await nextDocumentNumber('SEPA')
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
  const { data: existing, error } = await supabase.from('pay_slip_clarified').select('id').eq('pay_slip_id', paySlipId).maybeSingle()
  if (error) throw error
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

// ============ W9 — le registre d'absence (263) ============
// Une seule vérité par jour et par salarié, alimentée par les quatre sources
// (congé approuvé, arrêt de maladie, arrêt de travail, pointage d'absence) et
// calculée par la BASE. L'écran LIT, il ne recompose pas la logique de
// priorité : deux écrans qui la recomposeraient divergeraient au premier
// changement de règle.

export type AbsenceKind =
  | 'annual' | 'rtt' | 'sick' | 'work_accident' | 'maternity'
  | 'unpaid' | 'personal' | 'mission' | 'stoppage' | 'unjustified'

export type AbsenceDay = {
  employee_id: string
  employee_name: string
  day: string
  absence_kind: AbsenceKind
  absence_label: string
  origin: 'leave_request' | 'sick_leaf' | 'work_stoppage' | 'timesheet'
  justification_state: 'pending' | 'provided' | 'missing'
  blocks_work: boolean
  allows_expenses: boolean
  paid: boolean
  pay_rule_code: string | null
}

export type AbsenceSummary = {
  employee_id: string
  from: string
  to: string
  days_total: number
  days_paid: number
  days_unpaid: number
  working_days: number
  unjustified_days: number
  by_kind: Record<string, number>
}

export type AbsenceConflict = {
  employee_id: string
  employee_name: string
  day: string
  absence_kind: AbsenceKind
  conflict_type: 'pointage' | 'heures_supplementaires' | 'temps_projet' | 'temps_facturable' | 'frais'
  detail: string
}

/**
 * Le calendrier d'absence de la société active (RPC `absence_calendar`, 263).
 * Borné à 400 jours côté base : une plage plus large est refusée, pas tronquée.
 */
export async function getAbsenceCalendar(
  employeeId?: string,
  from?: string,
  to?: string
): Promise<AbsenceDay[]> {
  // Les paramètres NON fournis sont omis, jamais passés à `null` : la base a
  // des défauts (le mois courant), et un `null` explicite les écraserait —
  // `d.day BETWEEN NULL AND …` ne rendrait alors aucune ligne, en silence.
  const args: Record<string, unknown> = {}
  if (employeeId) args.p_employee = employeeId
  if (from) args.p_from = from
  if (to) args.p_to = to
  const { data, error } = await supabase.rpc('absence_calendar', args)
  if (error) throw error
  return (data ?? []) as AbsenceDay[]
}

/** Le résumé chiffré d'une plage, pour le contrôle de paie et le calendrier RH. */
export async function getAbsenceSummary(
  employeeId: string, from: string, to: string
): Promise<AbsenceSummary | null> {
  const tid = await getTenantId()
  if (!tid) throw new Error("Résumé d'absence : aucune société active.")
  const { data, error } = await supabase.rpc('absence_summary', {
    p_tenant: tid, p_employee: employeeId, p_from: from, p_to: to,
  })
  if (error) throw error
  return (data ?? null) as AbsenceSummary | null
}

/**
 * Les anomalies : une absence ET un pointage, des heures supplémentaires, du
 * temps projet (facturable ou non) ou une ligne de frais (RPC
 * `absence_conflicts_current`, 264 / TRV-16). Le contrôle NOMME, il ne répare
 * pas — c'est l'écran « Anomalies ».
 */
export async function getAbsenceConflicts(
  from?: string,
  to?: string
): Promise<AbsenceConflict[]> {
  const args: Record<string, unknown> = {}
  if (from) args.p_from = from
  if (to) args.p_to = to
  const { data, error } = await supabase.rpc('absence_conflicts_current', args)
  if (error) throw error
  return (data ?? []) as AbsenceConflict[]
}

export type AbsenceConflictEntry = {
  id: string
  employee_id: string
  day: string
  kept_kind: AbsenceKind
  kept_origin: string
  dropped_kind: AbsenceKind
  dropped_origin: string
  detected_at: string
}

/**
 * Le journal des arbitrages (`absence_conflict_log`, 263 / TRV-02) : quand deux
 * sources déclarent la même journée, la priorité tranche **et** laisse une
 * trace. L'écran l'affiche parce qu'un conflit silencieux est indécidable pour
 * l'utilisateur : sans cette liste, un jour « maladie » à la place d'un jour
 * « congé payé » ne s'explique pas.
 */
export async function getAbsenceConflictLog(
  from?: string,
  to?: string
): Promise<AbsenceConflictEntry[]> {
  const tid = await getTenantId()
  let q = supabase.from('absence_conflict_log')
    .select('id, employee_id, day, kept_kind, kept_origin, dropped_kind, dropped_origin, detected_at')
    .order('day', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (from) q = q.gte('day', from)
  if (to) q = q.lte('day', to)
  return fetchAllRows<AbsenceConflictEntry>(q, { label: 'getAbsenceConflictLog' })
}

