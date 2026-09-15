import { supabase } from '../supabase'
import { getTenantId, nextDocumentNumber, ti, tud } from './core'
import type { SocialDeclaration, CiceConfig, PasRate, AtRate, BdesIndicator, HonorariumRecord } from '@/types'

// ============ Social Declarations (CRUD) ============
export async function getSocialDeclarations(type?: string, period?: string, status?: string): Promise<SocialDeclaration[]> {
  const tid = await getTenantId()
  let q = supabase.from('social_declarations').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (type) q = q.eq('declaration_type', type)
  if (period) q = q.eq('period', period)
  if (status) q = q.eq('status', status)
  const { data, error } = await q
  if (error) throw error
  return data as SocialDeclaration[]
}

export async function createSocialDeclaration(data: Omit<SocialDeclaration, 'id' | 'created_at'>): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti(data, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

export async function updateSocialDeclaration(id: string, updates: Partial<SocialDeclaration>): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('social_declarations').update(updates), 'social_declarations', tid).eq('id', id).select().single()
  if (error) throw error
  return data as SocialDeclaration
}

// ============ DSN (IntuiDSN wizard) ============
export async function checkDsnAnomalies(_period: string): Promise<any[]> {
  const tid = await getTenantId()
  const anomalies: any[] = []
  let empQ = supabase.from('employees').select('id, name, social_security_number, hire_date, contract_type').eq('status', 'active')
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: employees } = await empQ
  if (employees) {
    for (const emp of employees) {
      if (!emp.social_security_number) {
        anomalies.push({ employee_id: emp.id, employee_name: emp.name, field: 'social_security_number', message: 'Numéro de sécurité sociale manquant' })
      }
      if (!emp.hire_date) {
        anomalies.push({ employee_id: emp.id, employee_name: emp.name, field: 'hire_date', message: "Date d'embauche manquante" })
      }
    }
  }
  return anomalies
}

export async function generateDsnFile(period: string, subtype?: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const anomalies = await checkDsnAnomalies(period)
  const { data: decl, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DSN'),
    declaration_type: 'dsn',
    subtype: subtype || 'monthly',
    period,
    status: 'generated',
    file_format: 'xml',
    generated_at: new Date().toISOString(),
    anomalies,
    employee_count: 0,
    details: {},
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return decl as SocialDeclaration
}

export async function transmitDsn(declarationId: string): Promise<{ declaration: SocialDeclaration; simulation: boolean; message?: string }> {
  // CNF-01.3 : Appeler l'Edge Function et propager le mode simulation
  const { data: fnResult, error } = await supabase.functions.invoke('transmit-dsn', {
    body: { dsn_id: declarationId, declarationId },
  })
  if (error) throw error
  // LOT7-08 : ne marquer « transmise » que sur confirmation réelle de net-entreprises
  if (!(fnResult as any)?.success || (fnResult as any)?.mode === 'simulation') {
    throw new Error((fnResult as any)?.error || (fnResult as any)?.message || 'Transmission DSN non confirmée')
  }
  const simulation = false
  const message = (fnResult as any)?.message

  const declaration = await updateSocialDeclaration(declarationId, {
    status: 'transmitted',
    transmitted_at: new Date().toISOString(),
    response_message: message || null,
  })

  return { declaration, simulation, message }
}

export async function getDsnHistory(): Promise<SocialDeclaration[]> {
  return getSocialDeclarations('dsn')
}

export async function getDsnReturnCodes(declarationId: string): Promise<{ code: string; message: string } | null> {
  const tid = await getTenantId()
  let q = supabase.from('social_declarations').select('response_code, response_message, status').eq('id', declarationId)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q.single()
  if (error) throw error
  if (!data || !data.response_code) return null
  return { code: data.response_code, message: data.response_message || '' }
}

// ============ DSN événementielles ============
export async function generateDsnStoppage(workStoppageId: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DSN-EVT-STOP'),
    declaration_type: 'dsn',
    subtype: 'event_stoppage',
    status: 'generated',
    file_format: 'xml',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 1,
    details: { work_stoppage_id: workStoppageId },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

export async function generateDsnReprise(workStoppageId: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DSN-EVT-REPRISE'),
    declaration_type: 'dsn',
    subtype: 'event_reprise',
    status: 'generated',
    file_format: 'xml',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 1,
    details: { work_stoppage_id: workStoppageId },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

export async function generateDsnExit(exitProcessId: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DSN-EVT-EXIT'),
    declaration_type: 'dsn',
    subtype: 'event_exit',
    status: 'generated',
    file_format: 'xml',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 1,
    details: { exit_process_id: exitProcessId },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

export async function generateDsnHire(employeeId: string, contractId: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DSN-EVT-HIRE'),
    declaration_type: 'dsn',
    subtype: 'event_hire',
    status: 'generated',
    file_format: 'xml',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 1,
    details: { employee_id: employeeId, contract_id: contractId },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ DADS-U ============
export async function generateDadsU(period: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DADS-U'),
    declaration_type: 'dads_u',
    period,
    status: 'generated',
    file_format: 'xml',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: {},
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ DUCS ============
export async function generateDucs(period: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DUCS'),
    declaration_type: 'ducs',
    period,
    status: 'generated',
    file_format: 'csv',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: {},
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ AED ============
export async function generateAed(employeeId: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('AED'),
    declaration_type: 'aed',
    status: 'generated',
    file_format: 'pdf',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 1,
    details: { employee_id: employeeId },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ DPAE ============
export async function generateDpae(employeeId: string, contractId: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DPAE'),
    declaration_type: 'dpae',
    status: 'generated',
    file_format: 'pdf',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 1,
    details: { employee_id: employeeId, contract_id: contractId },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ DTS-MSA ============
export async function generateDtsMsa(period: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('DTS-MSA'),
    declaration_type: 'dts_msa',
    period,
    status: 'generated',
    file_format: 'xml',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: {},
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ BTP ============
export async function generateCibtp(period: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('CIBTP'),
    declaration_type: 'cibtp',
    period,
    status: 'generated',
    file_format: 'pdf',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: {},
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

export async function generateCongesPayesBtp(period: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('CP-BTP'),
    declaration_type: 'conges_payes_btp',
    period,
    status: 'generated',
    file_format: 'pdf',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: {},
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ CICE ============
export async function getCiceConfig(year?: number): Promise<CiceConfig[]> {
  const tid = await getTenantId()
  let q = supabase.from('cice_config').select('*').order('year', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (year) q = q.eq('year', year)
  const { data, error } = await q
  if (error) throw error
  return data as CiceConfig[]
}

export async function updateCiceConfig(id: string, updates: Partial<CiceConfig>): Promise<CiceConfig> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('cice_config').update(updates), 'cice_config', tid).eq('id', id).select().single()
  if (error) throw error
  return data as CiceConfig
}

export async function calculateCice(year: number): Promise<any[]> {
  const tid = await getTenantId()
  const configs = await getCiceConfig(year)
  const config = configs.find(c => c.active)
  if (!config) throw new Error('No active CICE config for year ' + year)
  let empQ = supabase.from('employees').select('id, name, gross_salary').eq('status', 'active')
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: employees, error } = await empQ
  if (error) throw error
  if (!employees) return []
  const results: any[] = []
  for (const emp of employees) {
    const salary = Number(emp.gross_salary) || 0
    const eligible = salary <= (config.eligible_salary_cap || 999999)
    if (eligible) {
      results.push({
        employee_id: emp.id,
        employee_name: emp.name,
        gross_salary: salary,
        cice_amount: salary * (config.rate / 100),
      })
    }
  }
  return results
}

export async function generateCiceFile(year: number): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('CICE'),
    declaration_type: 'cice',
    period_year: year,
    status: 'generated',
    file_format: 'csv',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: { year },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ Autres déclarations ============
export async function generateRefusCdi(period: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('REFUS-CDI'),
    declaration_type: 'refus_cdi',
    period,
    status: 'generated',
    file_format: 'pdf',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: {},
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

export async function generateCt2025(period: string): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('CT2025'),
    declaration_type: 'ct2025',
    period,
    status: 'generated',
    file_format: 'pdf',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: {},
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ PASRAU ============
export async function generatePasrau(year: number): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('PASRAU'),
    declaration_type: 'pasrau',
    period_year: year,
    subtype: 'annual',
    status: 'generated',
    file_format: 'xml',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: { year },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ PAS & AT Rates ============
export async function getPasRates(employeeId?: string): Promise<(PasRate & { employees?: { name: string } })[]> {
  const tid = await getTenantId()
  let q = supabase.from('pas_rates').select('*, employees(name)').order('effective_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function importPasRates(file: File): Promise<void> {
  const tid = await getTenantId()
  const text = await file.text()
  const lines = text.split('\\n').filter(l => l.trim())
  for (const line of lines.slice(1)) {
    const cols = line.split(';')
    if (cols.length >= 3) {
      await supabase.from('pas_rates').insert(ti({
        employee_id: cols[0],
        rate: parseFloat(cols[1]) / 100,
        effective_date: cols[2],
        source: 'import',
      }, 'pas_rates', tid))
    }
  }
}

export async function updatePasRate(id: string, updates: Partial<PasRate>): Promise<PasRate> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('pas_rates').update(updates), 'pas_rates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as PasRate
}

export async function getAtRates(employeeId?: string): Promise<(AtRate & { employees?: { name: string } })[]> {
  const tid = await getTenantId()
  let q = supabase.from('at_rates').select('*, employees(name)').order('effective_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (employeeId) q = q.eq('employee_id', employeeId)
  const { data, error } = await q
  if (error) throw error
  return data as any[]
}

export async function importAtRates(file: File): Promise<void> {
  const tid = await getTenantId()
  const text = await file.text()
  const lines = text.split('\\n').filter(l => l.trim())
  for (const line of lines.slice(1)) {
    const cols = line.split(';')
    if (cols.length >= 3) {
      await supabase.from('at_rates').insert(ti({
        employee_id: cols[0],
        rate: parseFloat(cols[1]) / 100,
        bonus_malus_rate: cols[2] ? parseFloat(cols[2]) / 100 : 0,
        effective_date: cols[3] || new Date().toISOString().split('T')[0],
        risk_category: cols[4] || null,
      }, 'at_rates', tid))
    }
  }
}

export async function updateAtRate(id: string, updates: Partial<AtRate>): Promise<AtRate> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('at_rates').update(updates), 'at_rates', tid).eq('id', id).select().single()
  if (error) throw error
  return data as AtRate
}

// ============ BDES ============
export async function getBdesIndicators(year: number, category?: string): Promise<BdesIndicator[]> {
  const tid = await getTenantId()
  let q = supabase.from('bdes_indicators').select('*').eq('year', year).order('category')
  if (tid) q = q.eq('tenant_id', tid)
  if (category) q = q.eq('category', category)
  const { data, error } = await q
  if (error) throw error
  return data as BdesIndicator[]
}

export async function calculateBdesIndicators(year: number): Promise<BdesIndicator[]> {
  const tid = await getTenantId()
  const indicators: Omit<BdesIndicator, 'id' | 'created_at'>[] = []
  let empQ = supabase.from('employees').select('id, name, gender, hire_date, contract_type, gross_salary, department').eq('status', 'active')
  if (tid) empQ = empQ.eq('tenant_id', tid)
  const { data: employees } = await empQ
  if (employees) {
    const total = employees.length
    const male = employees.filter(e => e.gender === 'M').length
    const female = employees.filter(e => e.gender === 'F').length
    indicators.push({ tenant_id: tid, year, category: 'effectifs', indicator_name: 'Effectif total', indicator_value: total, indicator_unit: 'count', breakdown: { male, female }, target_value: null, previous_year_value: null, notes: null })
    indicators.push({ tenant_id: tid, year, category: 'effectifs', indicator_name: 'Répartition F/H', indicator_value: female / (total || 1) * 100, indicator_unit: 'percent', breakdown: { male, female }, target_value: 50, previous_year_value: null, notes: null })
    const totalSalary = employees.reduce((sum, e) => sum + (Number(e.gross_salary) || 0), 0)
    indicators.push({ tenant_id: tid, year, category: 'remuneration', indicator_name: 'Masse salariale', indicator_value: totalSalary, indicator_unit: 'currency', breakdown: {}, target_value: null, previous_year_value: null, notes: null })
    const maleAvgSalary = male > 0 ? employees.filter(e => e.gender === 'M').reduce((s, e) => s + (Number(e.gross_salary) || 0), 0) / male : 0
    const femaleAvgSalary = female > 0 ? employees.filter(e => e.gender === 'F').reduce((s, e) => s + (Number(e.gross_salary) || 0), 0) / female : 0
    indicators.push({ tenant_id: tid, year, category: 'egalite_f_h', indicator_name: 'Écart rémunération F/H', indicator_value: maleAvgSalary > 0 ? (maleAvgSalary - femaleAvgSalary) / maleAvgSalary * 100 : 0, indicator_unit: 'percent', breakdown: { male_avg: maleAvgSalary, female_avg: femaleAvgSalary }, target_value: 0, previous_year_value: null, notes: null })
  }
  for (const ind of indicators) {
    await supabase.from('bdes_indicators').insert(ti(ind, 'bdes_indicators', tid))
  }
  return getBdesIndicators(year)
}

export async function calculateEqualityIndicators(year: number): Promise<BdesIndicator[]> {
  return calculateBdesIndicators(year)
}

export async function generateBdesReport(year: number): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('BDES'),
    declaration_type: 'other',
    period_year: year,
    status: 'generated',
    file_format: 'pdf',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: { year, type: 'bdes' },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ Bilan social ============
export async function generateSocialReport(year: number): Promise<SocialDeclaration> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('social_declarations').insert(ti({
    number: await nextDocumentNumber('BILAN-SOCIAL'),
    declaration_type: 'other',
    period_year: year,
    status: 'generated',
    file_format: 'pdf',
    generated_at: new Date().toISOString(),
    anomalies: [],
    employee_count: 0,
    details: { year, type: 'social_report' },
  }, 'social_declarations', tid)).select().single()
  if (error) throw error
  return row as SocialDeclaration
}

// ============ Honoraires ============
export async function getHonorariumRecords(period?: string): Promise<HonorariumRecord[]> {
  const tid = await getTenantId()
  let q = supabase.from('honorarium_records').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  if (period) q = q.eq('period', period)
  const { data, error } = await q
  if (error) throw error
  return data as HonorariumRecord[]
}

export async function createHonorariumRecord(data: Omit<HonorariumRecord, 'id' | 'created_at'>): Promise<HonorariumRecord> {
  const tid = await getTenantId()
  const { data: row, error } = await supabase.from('honorarium_records').insert(ti(data, 'honorarium_records', tid)).select().single()
  if (error) throw error
  return row as HonorariumRecord
}

export async function updateHonorariumRecord(id: string, updates: Partial<HonorariumRecord>): Promise<HonorariumRecord> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('honorarium_records').update(updates), 'honorarium_records', tid).eq('id', id).select().single()
  if (error) throw error
  return data as HonorariumRecord
}

export async function generateHonorariumAccounting(id: string): Promise<void> {
  await updateHonorariumRecord(id, { status: 'accounted' })
}
