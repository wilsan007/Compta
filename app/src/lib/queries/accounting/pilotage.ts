// ============================================================================
// Comptabilite — pilotage.ts
// Extrait de l'ancien src/lib/queries/accounting.ts (4238 l.) le 2026-10-01.
// Decoupage par domaine ; imports recalcules ; aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { fetchAllRows, getTenantId, ti, tud } from '../core'
import { type Project, type DashboardStats, type AuditLog, type FiscalBackup, type DashboardWidget } from '@/types'

// ============ Projects ============
export async function getProjects() {
  const tid = await getTenantId()
  let q = supabase.from('projects').select('*').order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as Project[]
}



// ============ Dashboard Aggregates ============
// M5 (278) : les trois tableaux de bord lisent LE GRAND LIVRE par une seule RPC.
export type Kpis = { from: string; to: string; revenue: number; expenses: number; receivables: number; payables: number; cash: number; draft_entries: number; posted_entries: number }

async function currentFiscalYearBounds(): Promise<{ from: string; to: string }> {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_years').select('start_date, end_date').order('start_date', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  const today = new Date().toISOString().slice(0, 10)
  const years = (data || []) as Array<{ start_date: string; end_date: string }>
  const fy = years.find((y) => y.start_date <= today && today <= y.end_date) ?? years.find((y) => y.start_date <= today) ?? years[0]
  return fy ? { from: fy.start_date, to: fy.end_date } : { from: `${today.slice(0, 4)}-01-01`, to: `${today.slice(0, 4)}-12-31` }
}

export async function getKpis(from?: string, to?: string): Promise<Kpis> {
  const bounds = from && to ? { from, to } : await currentFiscalYearBounds()
  const { data, error } = await supabase.rpc('get_kpis', { p_from: bounds.from, p_to: bounds.to })
  if (error) throw error
  const k = (data || {}) as Record<string, unknown>
  const n = (v: unknown) => Number(v) || 0
  return { from: bounds.from, to: bounds.to, revenue: n(k.revenue), expenses: n(k.expenses), receivables: n(k.receivables), payables: n(k.payables), cash: n(k.cash), draft_entries: n(k.draft_entries), posted_entries: n(k.posted_entries) }
}

async function countRows(table: 'invoices' | 'purchase_invoices', filter?: (q: any) => any): Promise<number> {
  const tid = await getTenantId()
  let q: any = supabase.from(table).select('id', { count: 'exact', head: true })
  if (tid) q = q.eq('tenant_id', tid)
  if (filter) q = filter(q)
  const { count, error } = await q
  if (error) throw error
  return count ?? 0
}

export async function getDashboardStats(): Promise<DashboardStats> {
  const tid = await getTenantId()
  if (!tid) return { totalRevenue: 0, outstandingInvoice: 0, outstandingBills: 0, bankBalance: 0, totalDebtors: 0, totalCreditors: 0, invoiceCount: 0, billCount: 0 }
  // M5 (278) : une seule vérité — le grand livre. Encours clients et fournisseurs
  // sont les soldes 411 / 401 (avant : `customers.balance`, que rien ne tient, et
  // des factures filtrées par un statut qu'une facture validée n'avait pas).
  const [k, invoiceCount, billCount] = await Promise.all([getKpis(), countRows('invoices'), countRows('purchase_invoices')])
  return {
    totalRevenue: k.revenue,
    outstandingInvoice: k.receivables,
    outstandingBills: k.payables,
    bankBalance: k.cash,
    totalDebtors: k.receivables,
    totalCreditors: k.payables,
    invoiceCount,
    billCount,
  }
}

export async function getDashboardChartData(): Promise<{
  monthly: Array<{ month: string; revenus: number; depenses: number }>
  cashFlow: Array<{ key: 'inflow' | 'outflow' | 'net'; name: string; value: number; color: string }>
  overdueCount: number
  overdueTotal: number
}> {
  const tid = await getTenantId()
  const now = new Date()
  const yearStart = new Date(now.getFullYear(), 0, 1)
  const months = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sep', 'Oct', 'Nov', 'Déc']

  let invQ = supabase
    .from('invoices')
    .select('date, total, status')
    .gte('date', yearStart.toISOString().split('T')[0])
    .in('status', ['paid', 'sent', 'viewed', 'overdue'])
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: invoices } = await invQ

  let purQ = supabase
    .from('purchase_invoices')
    .select('date, total, status')
    .gte('date', yearStart.toISOString().split('T')[0])
    .in('status', ['paid', 'received', 'overdue', 'sent'])
  if (tid) purQ = purQ.eq('tenant_id', tid)
  const { data: purchaseInvoices } = await purQ

  const monthly = months.map((m) => ({
    month: m,
    revenus: 0,
    depenses: 0,
  }))

  for (const inv of invoices || []) {
    const m = new Date(inv.date).getMonth()
    if (m >= 0 && m < 12) monthly[m].revenus += Number(inv.total)
  }
  for (const pur of purchaseInvoices || []) {
    const m = new Date(pur.date).getMonth()
    if (m >= 0 && m < 12) monthly[m].depenses += Number(pur.total)
  }

  const currentMonth = now.getMonth()
  const monthlyTrimmed = monthly.slice(0, currentMonth + 1)

  const totalRevenus = monthlyTrimmed.reduce((s, m) => s + m.revenus, 0)
  const totalDepenses = monthlyTrimmed.reduce((s, m) => s + m.depenses, 0)
  const soldeNet = totalRevenus - totalDepenses

  const cashFlow = [
    { key: 'inflow' as const, name: 'Encaissements', value: totalRevenus, color: '#00875a' },
    { key: 'outflow' as const, name: 'Décaissements', value: totalDepenses, color: '#de350b' },
    { key: 'net' as const, name: 'Solde net', value: soldeNet, color: '#0066cc' },
  ]

  let overQ = supabase
    .from('invoices')
    .select('total, amount_due')
    .eq('status', 'overdue')
  if (tid) overQ = overQ.eq('tenant_id', tid)
  const { data: overdue } = await overQ

  const overdueCount = overdue?.length || 0
  const overdueTotal = (overdue || []).reduce((s, i) => s + Number(i.amount_due || i.total), 0)

  return { monthly: monthlyTrimmed, cashFlow, overdueCount, overdueTotal }
}

export async function getRecentActivity(): Promise<Array<{
  id: string
  type: 'invoice' | 'payment' | 'customer' | 'supplier' | 'bank'
  icon: string
  title: string
  description: string
  time: string
  color: string
}>> {
  const tid = await getTenantId()
  const activities: Array<{
    id: string
    type: 'invoice' | 'payment' | 'customer' | 'supplier' | 'bank'
    icon: string
    title: string
    description: string
    time: string
    color: string
  }> = []

  let invQ = supabase
    .from('invoices')
    .select('id, number, customer_name, total, date, status')
    .order('created_at', { ascending: false })
    .limit(5)
  if (tid) invQ = invQ.eq('tenant_id', tid)
  const { data: recentInvoices } = await invQ

  for (const inv of recentInvoices || []) {
    const statusLabel = inv.status === 'overdue' ? 'en retard' : inv.status === 'paid' ? 'payée' : 'créée'
    activities.push({
      id: `inv-${inv.id}`,
      type: 'invoice',
      icon: inv.status === 'overdue' ? 'AlertCircle' : 'FileText',
      title: `Facture ${inv.number} ${statusLabel}`,
      description: `${inv.customer_name || 'Client'} - ${Number(inv.total).toLocaleString('fr-FR')}`,
      time: inv.date,
      color: inv.status === 'overdue' ? 'text-[var(--color-danger)]' : inv.status === 'paid' ? 'text-[var(--color-success)]' : 'text-[var(--color-primary)]',
    })
  }

  let purQ = supabase
    .from('purchase_invoices')
    .select('id, number, supplier_name, total, date')
    .order('created_at', { ascending: false })
    .limit(3)
  if (tid) purQ = purQ.eq('tenant_id', tid)
  const { data: recentPurchases } = await purQ

  for (const pur of recentPurchases || []) {
    activities.push({
      id: `pur-${pur.id}`,
      type: 'supplier',
      icon: 'Package',
      title: `Facture fournisseur ${pur.number} reçue`,
      description: `${pur.supplier_name || 'Fournisseur'} - ${Number(pur.total).toLocaleString('fr-FR')}`,
      time: pur.date,
      color: 'text-[var(--color-warning)]',
    })
  }

  let bnkQ = supabase
    .from('bank_transactions')
    .select('id, description, amount, type, date')
    .order('date', { ascending: false })
    .limit(3)
  if (tid) bnkQ = bnkQ.eq('tenant_id', tid)
  const { data: recentBank } = await bnkQ

  for (const bnk of recentBank || []) {
    activities.push({
      id: `bnk-${bnk.id}`,
      type: 'bank',
      icon: 'Banknote',
      title: bnk.type === 'credit' ? 'Encaissement bancaire' : 'Décaissement bancaire',
      description: `${bnk.description} - ${Number(bnk.amount).toLocaleString('fr-FR')}`,
      time: bnk.date,
      color: bnk.type === 'credit' ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]',
    })
  }

  activities.sort((a, b) => new Date(b.time).getTime() - new Date(a.time).getTime())
  return activities.slice(0, 8)
}



// ============ Projects (full CRUD) ============
export async function createProject(project: Omit<Project, 'id' | 'created_at' | 'updated_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('projects').insert({ ...project, tenant_id: tid }).select().single()
  if (error) throw error
  return data as Project
}

export async function updateProject(id: string, updates: Partial<Project>) {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('projects').update(updates), 'projects', tid).eq('id', id).select().single()
  if (error) throw error
  return data as Project
}

export async function deleteProject(id: string) {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('projects').delete(), 'projects', tid).eq('id', id)
  if (error) throw error
}



// ============ Sprint 8: Audit Log ============
export async function getAuditLog(entityType?: string, action?: string) {
  const tid = await getTenantId()
  let q = supabase.from('audit_log').select('*').order('created_at', { ascending: false }).limit(200)
  if (tid) q = q.eq('tenant_id', tid)
  if (entityType) q = q.eq('entity_type', entityType)
  if (action) q = q.eq('action', action)
  const { data, error } = await q
  if (error) {
    console.warn('audit_log query failed:', error.message)
    return []
  }
  return data as AuditLog[]
}

export async function createAuditLog(entry: Omit<AuditLog, 'id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('audit_log').insert(ti(entry, 'audit_log', tid)).select().single()
  if (error) throw error
  return data as AuditLog
}



// ============ Sprint 8: Financial Dashboard ============
export async function getFinancialDashboard() {
  const tid = await getTenantId()
  if (!tid) return { revenue: 0, expenses: 0, margin: 0, marginPct: 0, cashPosition: 0, pendingEntries: 0, totalEntries: 0, invoiceCount: 0, supplierInvoiceCount: 0 }
  // M5 (278) : CA (70x) et charges (6x) comptabilisés de l'exercice, trésorerie (5x) :
  // avant, TTC des seules factures PAYÉES — un CA qui ne correspondait à aucun état.
  const [k, invoiceCount, supplierInvoiceCount] = await Promise.all([
    getKpis(),
    countRows('invoices', (q) => q.eq('validation_status', 'validated')),
    countRows('purchase_invoices', (q) => q.neq('status', 'draft')),
  ])
  const margin = k.revenue - k.expenses
  return {
    revenue: k.revenue,
    expenses: k.expenses,
    margin,
    marginPct: k.revenue > 0 ? (margin / k.revenue) * 100 : 0,
    cashPosition: k.cash,
    pendingEntries: k.draft_entries,
    totalEntries: k.draft_entries + k.posted_entries,
    invoiceCount,
    supplierInvoiceCount,
  }
}



// ============ Fiscal Backups ============
export async function getFiscalBackups() {
  const tid = await getTenantId()
  let q = supabase.from('fiscal_backups').select('*').order('created_at', { ascending: false }).order('id')
  if (tid) q = q.eq('tenant_id', tid)
  // LOT7-03 : piste d'audit fiscale — la liste des sauvegardes doit être complète.
  return await fetchAllRows<FiscalBackup>(q, { label: 'getFiscalBackups' })
}

export async function createFiscalBackup(backup: Omit<FiscalBackup, 'id' | 'tenant_id' | 'created_at'>) {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('fiscal_backups')
    .insert({ ...backup, tenant_id: tid })
    .select()
    .single()
  if (error) throw error
  return data as FiscalBackup
}

export async function deleteFiscalBackup(id: string) {
  const tid = await getTenantId()
  if (!tid) throw new Error('No tenant context')
  const { error } = await supabase
    .from('fiscal_backups')
    .delete()
    .eq('id', id)
    .eq('tenant_id', tid)
  if (error) throw error
}



// ============ Phase 7C: Dashboard Widgets ============

export async function getDashboardWidgets(userId: string): Promise<DashboardWidget[]> {
  const tid = await getTenantId()
  let q = supabase.from('dashboard_widgets').select('*').eq('user_id', userId).order('position', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return data as DashboardWidget[]
}

export async function createDashboardWidget(dw: Omit<DashboardWidget, 'id' | 'created_at' | 'updated_at' | 'tenant_id'>): Promise<DashboardWidget> {
  const tid = await getTenantId()
  const { data, error } = await supabase.from('dashboard_widgets').insert({ ...dw, tenant_id: tid }).select().single()
  if (error) throw error
  return data as DashboardWidget
}

export async function updateDashboardWidget(id: string, updates: Partial<DashboardWidget>): Promise<DashboardWidget> {
  const tid = await getTenantId()
  const { data, error } = await tud(supabase.from('dashboard_widgets').update(updates), 'dashboard_widgets', tid).eq('id', id).select().single()
  if (error) throw error
  return data as DashboardWidget
}

export async function deleteDashboardWidget(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('dashboard_widgets').delete(), 'dashboard_widgets', tid).eq('id', id)
  if (error) throw error
}
