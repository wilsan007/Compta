// F.5 / PRJ-02 — capacité par ressource : quand un salarié est disponible, et combien.
// Le chevauchement est refusé par la base (déclencheur de la 708) : l'écran n'a pas
// à le prévenir, il a à MONTRER le refus.
import { supabase } from '@/lib/supabase'
import { getTenantId, ti } from '@/lib/queries/core'

export interface ResourceCapacity {
  id: string
  employee_id: string
  period_start: string
  period_end: string
  weekly_hours: number
  note: string | null
}

export interface EmployeeOption {
  id: string
  name: string
}

export async function getResourceCapacities(): Promise<ResourceCapacity[]> {
  const { data, error } = await supabase
    .from('resource_capacities')
    .select('id, employee_id, period_start, period_end, weekly_hours, note')
    .order('period_start', { ascending: false })
  if (error) throw error
  return (data ?? []) as ResourceCapacity[]
}

export async function createResourceCapacity(input: {
  employeeId: string
  periodStart: string
  periodEnd: string
  weeklyHours: number
  note?: string | null
}): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase.from('resource_capacities').insert(
    ti(
      {
        employee_id: input.employeeId,
        period_start: input.periodStart,
        period_end: input.periodEnd,
        weekly_hours: input.weeklyHours,
        note: input.note || null,
      },
      'resource_capacities',
      tid,
    ),
  )
  if (error) throw error
}

export async function deleteResourceCapacity(id: string): Promise<void> {
  const { error } = await supabase.from('resource_capacities').delete().eq('id', id)
  if (error) throw error
}

/** Les salariés, pour choisir la ressource. */
export async function getEmployeeOptions(): Promise<EmployeeOption[]> {
  const { data, error } = await supabase.from('employees').select('id, name').order('name')
  if (error) throw error
  return (data ?? []) as EmployeeOption[]
}
