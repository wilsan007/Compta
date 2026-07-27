import { supabase } from '@/lib/supabase'
import { getTenantId, ti, tud } from './core'
import type { SavedFilter } from '@/types'

// ============ Saved Filters ============

export async function getSavedFilters(pageName: string): Promise<SavedFilter[]> {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email || ''
  let q = supabase
    .from('saved_filters')
    .select('*')
    .eq('user_email', userEmail)
    .eq('page_name', pageName)
    .order('created_at', { ascending: false })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as SavedFilter[]
}

export async function createSavedFilter(filter: Omit<SavedFilter, 'id' | 'created_at'>): Promise<SavedFilter> {
  const tid = await getTenantId()
  const { data, error } = await supabase
    .from('saved_filters')
    .insert(ti(filter, 'saved_filters', tid))
    .select()
    .single()
  if (error) throw error
  return data as SavedFilter
}

export async function deleteSavedFilter(id: string): Promise<void> {
  const tid = await getTenantId()
  const { error } = await tud(supabase.from('saved_filters').delete(), 'saved_filters', tid).eq('id', id)
  if (error) throw error
}

export async function setDefaultFilter(id: string, pageName: string): Promise<void> {
  const tid = await getTenantId()
  const { data: { session } } = await supabase.auth.getSession()
  const userEmail = session?.user?.email || ''
  // Unset previous default
  await tud(supabase.from('saved_filters').update({ is_default: false }), 'saved_filters', tid)
    .eq('user_email', userEmail)
    .eq('page_name', pageName)
    .eq('is_default', true)
  // Set new default
  await tud(supabase.from('saved_filters').update({ is_default: true }), 'saved_filters', tid).eq('id', id)
}

// ============ Revenue Simulation ============

export async function getRevenueSimulation(period: 'month' | 'quarter' | 'year', growthRate: number) {
  const tid = await getTenantId()
  const now = new Date()
  let startDate = new Date(now)
  if (period === 'month') startDate.setMonth(now.getMonth() - 11)
  else if (period === 'quarter') startDate.setMonth(now.getMonth() - 11)
  else if (period === 'year') startDate.setFullYear(now.getFullYear() - 2)

  let q = supabase
    .from('invoices')
    .select('date, total')
    .eq('status', 'paid')
    .gte('date', startDate.toISOString().split('T')[0])
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error

  const invoices = data || []
  const byMonth: Record<string, number> = {}
  for (const inv of invoices as any[]) {
    const d = new Date(inv.date).toISOString().slice(0, 7)
    byMonth[d] = (byMonth[d] || 0) + Number(inv.total || 0)
  }

  const months = Object.keys(byMonth).sort()
  const currentRevenue = months.reduce((s, m) => s + byMonth[m], 0)
  const projectedRevenue = currentRevenue * (1 + growthRate / 100)

  const projection: { month: string; current: number; projected: number }[] = []
  for (const m of months) {
    projection.push({
      month: m,
      current: byMonth[m],
      projected: byMonth[m] * (1 + growthRate / 100),
    })
  }

  return { currentRevenue, projectedRevenue, projection }
}

// ============ Margin Analysis ============

export async function getMarginAnalysis(
  period: 'month' | 'quarter' | 'year',
  dimension: 'product' | 'customer' | 'category'
) {
  const tid = await getTenantId()
  const now = new Date()
  let startDate = new Date(now)
  if (period === 'month') startDate.setMonth(now.getMonth() - 1)
  else if (period === 'quarter') startDate.setMonth(now.getMonth() - 3)
  else if (period === 'year') startDate.setFullYear(now.getFullYear() - 1)

  let q = supabase
    .from('invoice_lines')
    .select(`
      line_total,
      quantity,
      unit_price,
      product_id,
      product:products(name, category),
      invoice:invoices!inner(customer_id, date, status, customer:customers(name))
    `)
    .eq('invoice.status', 'paid')
    .gte('invoice.date', startDate.toISOString().split('T')[0])
  if (tid) q = q.eq('invoice.tenant_id', tid)
  const { data, error } = await q
  if (error) throw error

  const lines = data || []
  const groups: Record<string, { revenue: number; cost: number; margin: number; marginPercent: number }> = {}

  for (const line of lines as any[]) {
    const revenue = Number(line.line_total || 0)
    const cost = Number(line.quantity || 0) * Number(line.unit_price || 0) * 0.7 // estimated cost at 70% of price
    const margin = revenue - cost

    let key = 'Unknown'
    if (dimension === 'product') key = line.product?.name || 'No product'
    else if (dimension === 'customer') key = line.invoice?.customer?.name || 'No customer'
    else if (dimension === 'category') key = line.product?.category || 'No category'

    if (!groups[key]) groups[key] = { revenue: 0, cost: 0, margin: 0, marginPercent: 0 }
    groups[key].revenue += revenue
    groups[key].cost += cost
    groups[key].margin += margin
  }

  for (const key of Object.keys(groups)) {
    groups[key].marginPercent = groups[key].revenue > 0 ? (groups[key].margin / groups[key].revenue) * 100 : 0
  }

  const result = Object.entries(groups)
    .map(([name, vals]) => ({ name, ...vals }))
    .sort((a, b) => b.revenue - a.revenue)

  return result
}
