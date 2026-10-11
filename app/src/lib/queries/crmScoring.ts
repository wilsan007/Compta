// F.5 / CRM-02 — scoring de lead : des règles pondérées, et un moteur qui dit POURQUOI.
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from '@/lib/queries/core'

export interface CrmScoringRule {
  id: string
  name: string
  field: string
  operator: string
  value: string | null
  points: number
  is_active: boolean
  position: number
}

export interface LeadScore {
  score: number
  matched_rules: string[]
}

export const SCORING_OPERATORS = [
  'equals', 'not_equals', 'contains', 'greater_than', 'less_than', 'is_set', 'is_not_set',
] as const

export async function getCrmScoringRules(): Promise<CrmScoringRule[]> {
  const { data, error } = await supabase
    .from('crm_scoring_rules')
    .select('id, name, field, operator, value, points, is_active, position')
    .order('position')
  if (error) throw error
  return (data ?? []) as CrmScoringRule[]
}

export async function createCrmScoringRule(input: {
  name: string
  field: string
  operator: string
  value?: string | null
  points: number
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('crm_scoring_rules').insert(
    ti(
      {
        name: input.name,
        field: input.field,
        operator: input.operator,
        value: input.operator === 'is_set' || input.operator === 'is_not_set' ? null : (input.value ?? null),
        points: input.points,
      },
      'crm_scoring_rules',
      tid,
    ),
  )
  if (error) throw error
}

export async function deleteCrmScoringRule(id: string): Promise<void> {
  const { error } = await supabase.from('crm_scoring_rules').delete().eq('id', id)
  if (error) throw error
}

/** Applique les règles actives de la société à des faits — et rend le total ET ses raisons. */
export async function scoreLead(facts: Record<string, string>): Promise<LeadScore> {
  const { data, error } = await supabase.rpc('crm_lead_score', { p_facts: facts })
  if (error) throw error
  return (data as LeadScore) ?? { score: 0, matched_rules: [] }
}
