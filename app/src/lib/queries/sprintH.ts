import { supabase } from '@/lib/supabase'
import { fetchAllRows, getTenantId, ti, tud } from './core'
import type { RhDashboardConfig, RhReport, EmployeeActivityLog } from '@/types'

// ============ Employee Activity Logs ============

export async function logEmployeeActivity(employeeId: string, activityType: string, description: string, metadata?: Record<string, any>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('employee_activity_logs')
    .insert(ti({ employee_id: employeeId, activity_type: activityType, description, metadata: metadata || {} }, 'employee_activity_logs', tid))
    .select().single()
  if (error) throw error
  return data as EmployeeActivityLog
}

export async function getEmployeeActivity(employeeId: string, limit?: number) {
  const tid = await getTenantId()
  let q = supabase.from('employee_activity_logs').select('*').eq('employee_id', employeeId)
  if (tid) q = q.eq('tenant_id', tid)
  q = q.order('created_at', { ascending: false })
  if (limit) q = q.limit(limit)
  const { data, error } = await q
  if (error) throw error
  return data as EmployeeActivityLog[]
}

export async function getMyActivity(limit?: number) {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email
  if (!userEmail) throw new Error('Not authenticated')
  let q = supabase.from('employees').select('id').eq('email', userEmail)
  if (tid) q = q.eq('tenant_id', tid)
  const { data: emp } = await q.single()
  if (!emp?.id) throw new Error('Employee not found')
  return getEmployeeActivity(emp.id, limit)
}

// ============ Employee Dashboard ============

export async function getEmployeeDashboardData() {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email
  if (!userEmail) throw new Error('Not authenticated')

  let empQ = supabase.from('employees').select('*').eq('email', userEmail)
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: emp } = await empQ.single()
  if (!emp) throw new Error('Employee not found')
  const employeeId = emp.id

  const [balances, pendingLeaves, pendingExpenses, upcomingInterviews, activity] = await Promise.all([
    (() => { let q = supabase.from('leave_balances').select('*').eq('employee_id', employeeId); if (tid) q = q.eq('tenant_id', tid); return q.then(r => r.data || []) })(),
    (() => { let q = supabase.from('leave_requests').select('*').eq('employee_id', employeeId).eq('status', 'pending'); if (tid) q = q.eq('tenant_id', tid); return q.then(r => r.data || []) })(),
    (() => { let q = supabase.from('expense_reports').select('*').eq('employee_id', employeeId).eq('status', 'draft'); if (tid) q = q.eq('tenant_id', tid); return q.then(r => r.data || []) })(),
    (() => { let q = supabase.from('interview_campaigns').select('*').eq('status', 'active').limit(1); if (tid) q = q.eq('tenant_id', tid); return q.then(r => r.data || []) })(),
    getEmployeeActivity(employeeId, 10),
  ])

  return {
    employee: emp,
    leaveBalances: balances,
    pendingLeaveCount: pendingLeaves.length,
    pendingExpenseAmount: pendingExpenses.reduce((s: number, r: any) => s + Number(r.total_amount || 0), 0),
    upcomingInterview: upcomingInterviews[0] || null,
    recentActivity: activity,
  }
}

// ============ Employee Profile ============

export async function getMyProfile() {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email
  if (!userEmail) throw new Error('Not authenticated')
  let q = supabase.from('employees').select('*').eq('email', userEmail)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  return data
}

export async function updateMyProfile(updates: Record<string, any>) {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email
  if (!userEmail) throw new Error('Not authenticated')
  const { data, error } = await tud(supabase.from('employees').update(updates), 'employees', tid).eq('email', userEmail).select().single()
  if (error) throw error
  return data
}

export async function getEmployeeAlerts(employeeId?: string) {
  const tid = await getTenantId()
  const alerts: any[] = []

  let empId = employeeId
  if (!empId) {
    const { data: { session } } = await supabase.auth.getSession()
    const userEmail = session?.user?.email
    if (!userEmail) return alerts
    let eq = supabase.from('employees').select('id').eq('email', userEmail)
    if (tid) eq = eq.eq('tenant_id', tid)
    const { data: emp } = await eq.single()
    if (!emp?.id) return alerts
    empId = emp.id
  }

  let eq2 = supabase.from('employees').select('*').eq('id', empId)
  if (tid) eq2 = eq2.eq('tenant_id', tid)
  const { data: emp } = await eq2.single()
  if (emp?.hire_date && String(emp?.contract_type).toLowerCase() === 'cdd') {
    const hireDate = new Date(emp.hire_date)
    const trialEnd = new Date(hireDate)
    trialEnd.setMonth(trialEnd.getMonth() + (emp.trial_period_months || 3))
    const daysLeft = Math.ceil((trialEnd.getTime() - Date.now()) / (1000 * 60 * 60 * 24))
    if (daysLeft > 0 && daysLeft <= 30) {
      alerts.push({ type: 'trial_period', days: daysLeft })
    }
  }

  let mq = supabase.from('medical_exams').select('*').eq('employee_id', empId).is('completed_date', null).order('scheduled_date').limit(1)
  if (tid) mq = mq.eq('tenant_id', tid)
  const { data: medExam } = await mq.maybeSingle()
  if (medExam) {
    const examDate = new Date(medExam.scheduled_date)
    const daysLeft = Math.ceil((examDate.getTime() - Date.now()) / (1000 * 60 * 60 * 24))
    if (daysLeft < 0) {
      alerts.push({ type: 'medical_overdue' })
    } else if (daysLeft <= 30) {
      alerts.push({ type: 'medical_scheduled', days: daysLeft })
    }
  }

  let cq = supabase.from('cpf_accounts').select('*').eq('employee_id', empId)
  if (tid) cq = cq.eq('tenant_id', tid)
  const { data: cpf } = await cq.maybeSingle()
  if (cpf && Number(cpf.balance_hours) > 0) {
    alerts.push({ type: 'cpf_available', hours: cpf.balance_hours })
  }

  return alerts
}

// ============ RH Dashboard ============

export async function getRhDashboardData() {
  const tid = await getTenantId()

  const now = new Date()
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()

  // LOT7-03 : tableau de bord RH — effectif, masse salariale et compteurs CPF sont des
  // agrégats. Au-delà de 1 000 salariés, tous les chiffres affichés étaient faux.
  const page = (table: string, build: (q: any) => any = (q) => q) => {
    let q = supabase.from(table).select('*').order('id')
    if (tid) q = q.eq('tenant_id', tid)
    return fetchAllRows<any>(build(q), { label: `getRhDashboardData/${table}` })
  }
  const [employees, pendingLeaves, pendingExpenses, workStoppages, medicalExams, exitProcesses, hardshipRecords, cpfAccounts] = await Promise.all([
    page('employees'),
    page('leave_requests', (q) => q.eq('status', 'pending')),
    page('expense_reports', (q) => q.eq('status', 'submitted')),
    page('work_stoppages', (q) => q.eq('status', 'current')),
    page('medical_exams', (q) => q.is('completed_date', null)),
    page('employee_exit_processes', (q) => q.eq('status', 'in_progress')),
    page('work_hardship_records'),
    page('cpf_accounts'),
  ])

  const activeEmployees = employees.filter((e: any) => e.status === 'active')
  const totalPayroll = activeEmployees.reduce((s: number, e: any) => s + Number(e.salary || 0), 0)
  const monthlyHires = employees.filter((e: any) => e.hire_date && new Date(e.hire_date) >= new Date(monthStart)).length
  const monthlyExits = employees.filter((e: any) => e.status === 'inactive' && e.updated_at && new Date(e.updated_at) >= new Date(monthStart)).length
  const totalCpfHours = cpfAccounts.reduce((s: number, c: any) => s + Number(c.balance_hours || 0), 0)
  const medicalOverdue = medicalExams.filter((m: any) => new Date(m.scheduled_date) < now).length

  return {
    effectifs: {
      total: employees.length,
      active: activeEmployees.length,
      hiresThisMonth: monthlyHires,
      exitsThisMonth: monthlyExits,
    },
    payroll: {
      total: totalPayroll,
      avgSalary: activeEmployees.length ? totalPayroll / activeEmployees.length : 0,
    },
    leaves: {
      pendingCount: pendingLeaves.length,
    },
    expenses: {
      pendingCount: pendingExpenses.length,
      pendingAmount: pendingExpenses.reduce((s: number, r: any) => s + Number(r.total_amount || 0), 0),
    },
    workStoppages: {
      current: workStoppages.length,
    },
    medical: {
      toPlan: medicalExams.length,
      overdue: medicalOverdue,
    },
    exits: {
      inProgress: exitProcesses.length,
    },
    hardship: {
      totalExposed: hardshipRecords.length,
    },
    cpf: {
      totalHours: totalCpfHours,
      employeesWithBalance: cpfAccounts.filter((c: any) => Number(c.balance_hours) > 0).length,
    },
  }
}

// ============ RH Reports ============

export async function getRhReports(type?: string) {
  const tid = await getTenantId()
  let q = supabase.from('rh_reports').select('*')
  if (tid) q = q.eq('tenant_id', tid)
  if (type) q = q.eq('report_type', type)
  const { data, error } = await q.order('created_at', { ascending: false })
  if (error) throw error
  return data as RhReport[]
}

export async function createRhReport(data: Omit<RhReport, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data: result, error } = await supabase.from('rh_reports').insert(ti(data, 'rh_reports', tid)).select().single()
  if (error) throw error
  return result as RhReport
}

export async function deleteRhReport(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('rh_reports').delete(), 'rh_reports', tid).eq('id', id)
  if (error) throw error
}

export async function calculateReportData(reportId: string) {
  const tid = await getTenantId()
  let rq = supabase.from('rh_reports').select('*').eq('id', reportId)
  if (tid) rq = rq.eq('tenant_id', tid)
  const { data: report } = await rq.single()
  if (!report) throw new Error('Report not found')

  let calculatedData: any = {}

  switch (report.report_type) {
    case 'effectifs': {
      let empsQ = supabase.from('employees').select('*')
      if (tid) empsQ = empsQ.eq('tenant_id', tid)
      const { data: emps } = await empsQ
      calculatedData = {
        total: emps?.length || 0,
        active: emps?.filter((e: any) => e.status === 'active').length || 0,
        byDepartment: emps?.reduce((acc: Record<string, number>, e: any) => {
          const dept = e.department || 'N/A'
          acc[dept] = (acc[dept] || 0) + 1
          return acc
        }, {}) || {},
      }
      break
    }
    case 'remuneration': {
      let empsQ2 = supabase.from('employees').select('*').eq('status', 'active')
      if (tid) empsQ2 = empsQ2.eq('tenant_id', tid)
      const { data: emps } = await empsQ2
      const salaries = emps?.map((e: any) => Number(e.salary || 0)) || []
      calculatedData = {
        total: salaries.reduce((s: number, v: number) => s + v, 0),
        average: salaries.length ? salaries.reduce((s: number, v: number) => s + v, 0) / salaries.length : 0,
        min: salaries.length ? Math.min(...salaries) : 0,
        max: salaries.length ? Math.max(...salaries) : 0,
        byDepartment: emps?.reduce((acc: Record<string, { count: number; total: number }>, e: any) => {
          const dept = e.department || 'N/A'
          if (!acc[dept]) acc[dept] = { count: 0, total: 0 }
          acc[dept].count++
          acc[dept].total += Number(e.salary || 0)
          return acc
        }, {}) || {},
      }
      break
    }
    case 'absenteeism': {
      let lq = supabase.from('leave_requests').select('*').eq('status', 'approved')
      if (tid) lq = lq.eq('tenant_id', tid)
      const { data: leaves } = await lq
      calculatedData = {
        total: leaves?.length || 0,
        byType: leaves?.reduce((acc: Record<string, number>, l: any) => {
          acc[l.leave_type] = (acc[l.leave_type] || 0) + 1
          return acc
        }, {}) || {},
      }
      break
    }
    case 'turnover': {
      let empsQ3 = supabase.from('employees').select('*')
      if (tid) empsQ3 = empsQ3.eq('tenant_id', tid)
      const { data: emps } = await empsQ3
      const active = emps?.filter((e: any) => e.status === 'active').length || 0
      const inactive = emps?.filter((e: any) => e.status === 'inactive').length || 0
      calculatedData = {
        active,
        inactive,
        turnoverRate: active + inactive > 0 ? (inactive / (active + inactive)) * 100 : 0,
      }
      break
    }
    case 'training': {
      let cq2 = supabase.from('cpf_transactions').select('*')
      if (tid) cq2 = cq2.eq('tenant_id', tid)
      const { data: cpf } = await cq2
      calculatedData = {
        totalTransactions: cpf?.length || 0,
        totalHours: cpf?.reduce((s: number, t: any) => s + Number(t.hours_used || 0), 0) || 0,
      }
      break
    }
    case 'costs': {
      let empsQ4 = supabase.from('employees').select('*').eq('status', 'active')
      if (tid) empsQ4 = empsQ4.eq('tenant_id', tid)
      const { data: emps } = await empsQ4
      calculatedData = {
        byDepartment: emps?.reduce((acc: Record<string, number>, e: any) => {
          const dept = e.department || 'N/A'
          acc[dept] = (acc[dept] || 0) + Number(e.salary || 0)
          return acc
        }, {}) || {},
        total: emps?.reduce((s: number, e: any) => s + Number(e.salary || 0), 0) || 0,
      }
      break
    }
  }

  const { data, error } = await tud(supabase.from('rh_reports').update({
    data: calculatedData,
    data_calculated_at: new Date().toISOString(),
  }), 'rh_reports', tid).eq('id', reportId).select().single()
  if (error) throw error
  return data as RhReport
}

// ============ RH Statistics ============

export async function getEffectifEvolution(months: number = 12) {
  const tid = await getTenantId()
  let q = supabase.from('employees').select('hire_date, status, updated_at').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : courbe d'évolution des effectifs sur 12 mois — agrégat sur tout le personnel.
  const emps = await fetchAllRows<any>(q, { label: 'getEffectifEvolution/employees' })

  const result: { month: string; hires: number; exits: number; net: number }[] = []
  const now = new Date()

  for (let i = months - 1; i >= 0; i--) {
    const monthStart = new Date(now.getFullYear(), now.getMonth() - i, 1)
    const monthEnd = new Date(now.getFullYear(), now.getMonth() - i + 1, 0, 23, 59, 59)
    const monthLabel = monthStart.toLocaleDateString('fr', { month: 'short', year: '2-digit' })

    const hires = emps.filter(e => {
      if (!e.hire_date) return false
      const d = new Date(e.hire_date)
      return d >= monthStart && d <= monthEnd
    }).length

    const exits = emps.filter(e => {
      if (e.status !== 'inactive' || !e.updated_at) return false
      const d = new Date(e.updated_at)
      return d >= monthStart && d <= monthEnd
    }).length

    result.push({ month: monthLabel, hires, exits, net: hires - exits })
  }
  return result
}

export async function getSalaryAnalysis(groupBy: 'department' | 'category' | 'gender' | 'age_range') {
  const tid = await getTenantId()
  let q = supabase.from('employees').select('*').eq('status', 'active').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : analyse des rémunérations par groupe — moyenne faussée si tronquée.
  const emps = await fetchAllRows<any>(q, { label: 'getSalaryAnalysis/employees' })

  const groups: Record<string, { count: number; total: number; average: number }> = {}
  for (const emp of emps) {
    let key = 'N/A'
    if (groupBy === 'department') key = emp.department || 'N/A'
    else if (groupBy === 'category') key = emp.category || 'N/A'
    else if (groupBy === 'gender') key = emp.gender || 'N/A'
    else if (groupBy === 'age_range') {
      if (!emp.birth_date) key = 'Unknown'
      else {
        const age = Math.floor((Date.now() - new Date(emp.birth_date).getTime()) / (365.25 * 24 * 60 * 60 * 1000))
        if (age < 25) key = '<25'
        else if (age < 35) key = '25-34'
        else if (age < 45) key = '35-44'
        else if (age < 55) key = '45-54'
        else key = '55+'
      }
    }
    if (!groups[key]) groups[key] = { count: 0, total: 0, average: 0 }
    groups[key].count++
    groups[key].total += Number(emp.salary || 0)
  }
  for (const k of Object.keys(groups)) {
    groups[k].average = groups[k].count > 0 ? groups[k].total / groups[k].count : 0
  }
  return groups
}

export async function getAbsenceStats(groupBy: 'department' | 'type' | 'month') {
  const tid = await getTenantId()
  let q = supabase.from('leave_requests').select('*, employees(department)').eq('status', 'approved').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : statistiques d'absentéisme — comptage sur toutes les absences approuvées.
  const leaves = await fetchAllRows<any>(q, { label: 'getAbsenceStats/leave_requests' })

  const groups: Record<string, number> = {}
  for (const leave of leaves) {
    let key = 'N/A'
    if (groupBy === 'department') key = (leave as any).employees?.department || 'N/A'
    else if (groupBy === 'type') key = leave.leave_type || 'N/A'
    else if (groupBy === 'month') {
      const d = new Date(leave.start_date)
      key = d.toLocaleDateString('fr', { month: 'short', year: '2-digit' })
    }
    groups[key] = (groups[key] || 0) + 1
  }
  return groups
}

export async function getTurnoverRate(_period: string) {
  const tid = await getTenantId()
  let q = supabase.from('employees').select('*').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : taux de rotation = ratio sur l'effectif complet.
  const emps = await fetchAllRows<any>(q, { label: 'getTurnoverRate/employees' })
  const active = emps.filter(e => e.status === 'active').length
  const inactive = emps.filter(e => e.status === 'inactive').length
  const total = active + inactive
  return { rate: total > 0 ? (inactive / total) * 100 : 0, active, inactive }
}

export async function getCostByCenter(_period: string) {
  const tid = await getTenantId()
  let q = supabase.from('employees').select('*').eq('status', 'active').order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : coût par centre — somme des salaires de tout l'effectif actif.
  const emps = await fetchAllRows<any>(q, { label: 'getCostByCenter/employees' })
  const groups: Record<string, number> = {}
  for (const emp of emps) {
    const center = emp.department || 'N/A'
    groups[center] = (groups[center] || 0) + Number(emp.salary || 0)
  }
  return groups
}

// ============ Dashboard Config ============

export async function getDashboardConfig(dashboardType: string) {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email || 'unknown'
  let q = supabase.from('rh_dashboard_configs').select('*').eq('user_email', userEmail).eq('dashboard_type', dashboardType)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.maybeSingle()
  if (error) throw error
  return data as RhDashboardConfig | null
}

export async function saveDashboardConfig(dashboardType: string, widgets: RhDashboardConfig['widgets'], filters: Record<string, any>) {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email || 'unknown'

  const existing = await getDashboardConfig(dashboardType)
  if (existing) {
    const { data, error } = await tud(supabase.from('rh_dashboard_configs').update({
      widgets, filters, updated_at: new Date().toISOString(),
    }), 'rh_dashboard_configs', tid).eq('id', existing.id).select().single()
    if (error) throw error
    return data as RhDashboardConfig
  } else {
    const { data, error } = await supabase.from('rh_dashboard_configs').insert(ti({
      user_email: userEmail, dashboard_type: dashboardType, widgets, filters,
    }, 'rh_dashboard_configs', tid)).select().single()
    if (error) throw error
    return data as RhDashboardConfig
  }
}
