import { supabase } from './supabase'

async function getTenantId(): Promise<string | null> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null
  const { data } = await supabase
    .from('tenant_users')
    .select('tenant_id')
    .eq('user_id', session.user.id)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  return data?.tenant_id ?? null
}

export type AnalyticDistribution = Record<string, Record<string, number>>

export function validateDistribution(dist: AnalyticDistribution): boolean {
  for (const planId of Object.keys(dist)) {
    const sections = dist[planId]
    const total = Object.values(sections).reduce((s, v) => s + v, 0)
    if (Math.abs(total - 100) > 0.01) return false
  }
  return true
}

export function distributeEvenly(sectionIds: string[]): Record<string, number> {
  if (sectionIds.length === 0) return {}
  const pct = 100 / sectionIds.length
  const result: Record<string, number> = {}
  for (const id of sectionIds) result[id] = Math.round(pct * 100) / 100
  return result
}

export function computeAmounts(
  dist: AnalyticDistribution,
  lineAmount: number
): Record<string, Record<string, number>> {
  const result: Record<string, Record<string, number>> = {}
  for (const planId of Object.keys(dist)) {
    result[planId] = {}
    for (const sectionId of Object.keys(dist[planId])) {
      const pct = dist[planId][sectionId]
      result[planId][sectionId] = Math.round(lineAmount * pct) / 100
    }
  }
  return result
}

export function flattenDistribution(
  dist: AnalyticDistribution
): { planId: string; sectionId: string; percentage: number }[] {
  const result: { planId: string; sectionId: string; percentage: number }[] = []
  for (const planId of Object.keys(dist)) {
    for (const sectionId of Object.keys(dist[planId])) {
      result.push({ planId, sectionId, percentage: dist[planId][sectionId] })
    }
  }
  return result
}

export async function saveDistributionLines(
  journalLineId: string,
  dist: AnalyticDistribution,
  lineAmount: number
): Promise<void> {
  const tid = await getTenantId()
  await supabase
    .from('analytic_distribution_lines')
    .delete()
    .eq('journal_line_id', journalLineId)

  const amounts = computeAmounts(dist, lineAmount)
  const rows = flattenDistribution(dist).map((f) => ({
    tenant_id: tid,
    journal_line_id: journalLineId,
    plan_id: f.planId,
    section_id: f.sectionId,
    percentage: f.percentage,
    amount: amounts[f.planId][f.sectionId],
  }))

  if (rows.length > 0) {
    const { error } = await supabase.from('analytic_distribution_lines').insert(rows)
    if (error) throw error
  }
}

export async function getDistributionLines(
  journalLineId: string
): Promise<AnalyticDistribution> {
  const { data, error } = await supabase
    .from('analytic_distribution_lines')
    .select('plan_id, section_id, percentage')
    .eq('journal_line_id', journalLineId)

  if (error) throw error

  const dist: AnalyticDistribution = {}
  for (const row of data || []) {
    const planId = row.plan_id
    const sectionId = row.section_id
    if (!planId || !sectionId) continue
    if (!dist[planId]) dist[planId] = {}
    dist[planId][sectionId] = Number(row.percentage)
  }
  return dist
}
