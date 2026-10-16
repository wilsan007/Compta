// F.5 / CRM-01 — séquences de relance : la cadence décrite (pas encore planifiée).
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from '@/lib/queries/core'

export interface CrmSequence {
  id: string
  name: string
  description: string | null
  is_active: boolean
  created_at: string
}

export interface CrmSequenceStep {
  id: string
  sequence_id: string
  step_order: number
  delay_days: number
  channel: string
  subject: string | null
  body: string | null
}

export const SEQUENCE_CHANNELS = ['email', 'call', 'task', 'sms'] as const

export async function getCrmSequences(): Promise<CrmSequence[]> {
  const { data, error } = await supabase
    .from('crm_sequences')
    .select('id, name, description, is_active, created_at')
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as CrmSequence[]
}

export async function createCrmSequence(input: { name: string; description?: string | null }): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('crm_sequences').insert(
    ti({ name: input.name, description: input.description || null }, 'crm_sequences', tid),
  )
  if (error) throw error
}

export async function deleteCrmSequence(id: string): Promise<void> {
  const { error } = await supabase.from('crm_sequences').delete().eq('id', id)
  if (error) throw error
}

export async function getCrmSequenceSteps(sequenceId: string): Promise<CrmSequenceStep[]> {
  const { data, error } = await supabase
    .from('crm_sequence_steps')
    .select('id, sequence_id, step_order, delay_days, channel, subject, body')
    .eq('sequence_id', sequenceId)
    .order('step_order')
  if (error) throw error
  return (data ?? []) as CrmSequenceStep[]
}

export async function createCrmSequenceStep(input: {
  sequenceId: string
  stepOrder: number
  delayDays: number
  channel: string
  subject?: string | null
  body?: string | null
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('crm_sequence_steps').insert(
    ti(
      {
        sequence_id: input.sequenceId,
        step_order: input.stepOrder,
        delay_days: input.delayDays,
        channel: input.channel,
        subject: input.subject || null,
        body: input.body || null,
      },
      'crm_sequence_steps',
      tid,
    ),
  )
  if (error) throw error
}

export async function deleteCrmSequenceStep(id: string): Promise<void> {
  const { error } = await supabase.from('crm_sequence_steps').delete().eq('id', id)
  if (error) throw error
}
