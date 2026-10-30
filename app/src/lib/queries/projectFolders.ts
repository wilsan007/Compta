import { supabase } from '@/lib/supabase'
import { silentFailureReporter } from '@/lib/silentFailureGuard'
import { fetchAllRows, getTenantId, type RangeableQuery } from './core'
import type { FolderDocument } from '@/lib/projectFolders'
import type { ResourceEmployee, ResourceTimeEntry } from '@/lib/resourceUsage'

// Lectures des écrans « Dossiers de documents » et « Utilisation des
// ressources ». Toutes paginées (PostgREST tronque à 1 000 lignes) et bornées à
// la société active.

// `order` : colonnes du tri TOTAL (la pagination l'exige). Par défaut `id` ;
// `project_task_assignees` n'a pas d'`id`, sa clé est (task_id, employee_id).
// `tenantColumn: false` : cette table n'a pas non plus de `tenant_id` — la RLS
// l'isole par la tâche (voir `getTaskAssignees`), filtrer par colonne échouerait.
//
// Les tables sont désignées par un nom : le client typé ne sait pas suivre un nom
// dynamique, d'où cette vue structurelle du seul sous-ensemble de filtres utilisé.
interface Filterable<T> extends RangeableQuery<T> {
  eq(column: string, value: string): Filterable<T>
  gte(column: string, value: string): Filterable<T>
  lt(column: string, value: string): Filterable<T>
  lte(column: string, value: string): Filterable<T>
  order(column: string, options: { ascending: boolean }): Filterable<T>
}

const fromTable = <T>(table: string, columns: string): Filterable<T> =>
  supabase.from(table).select(columns) as unknown as Filterable<T>

async function readAll<T>(
  table: string,
  columns: string,
  tweak?: (q: Filterable<T>) => Filterable<T>,
  order: string[] = ['id'],
  tenantColumn = true
): Promise<T[]> {
  const tid = tenantColumn ? await getTenantId() : null
  return fetchAllRows<T>(
    () => {
      let q = fromTable<T>(table, columns)
      if (tid) q = q.eq('tenant_id', tid)
      if (tweak) q = tweak(q)
      for (const col of order) q = q.order(col, { ascending: true })
      return q
    },
    { label: `projectFolders:${table}` }
  )
}

interface EmployeeRef {
  id: string
  name: string
}

export interface FolderSourceRows {
  documents: FolderDocument[]
  assignments: { task_id: string; employee_id: string }[]
  employees: EmployeeRef[]
  members: { project_id: string; employee_id: string; role: string }[]
  timeEntries: { task_id: string | null; duration_seconds: number | null; hourly_rate: number | null }[]
}

export async function getFolderSourceRows(): Promise<FolderSourceRows> {
  const [docs, proofs, assignments, employees, members, timeEntries] = await Promise.all([
    readAll<Omit<FolderDocument, 'kind'>>('task_documents', 'id, task_id, file_name, file_path, file_size, mime_type, created_at'),
    readAll<Omit<FolderDocument, 'kind'>>(
      'task_action_attachments',
      'id, task_id, file_name, file_path, file_size, mime_type, created_at'
    ),
    readAll<{ task_id: string; employee_id: string }>('project_task_assignees', 'task_id, employee_id', undefined, [
      'task_id',
      'employee_id',
    ], false),
    readAll<EmployeeRef>('employees', 'id, name'),
    readAll<{ project_id: string; employee_id: string; role: string }>('project_members', 'id, project_id, employee_id, role'),
    readAll<{ task_id: string | null; duration_seconds: number | null; hourly_rate: number | null }>(
      'project_time_entries',
      'id, task_id, duration_seconds, hourly_rate'
    ),
  ])
  return {
    documents: [
      ...docs.map((d) => ({ ...d, kind: 'document' as const })),
      ...proofs.map((d) => ({ ...d, kind: 'proof' as const })),
    ],
    assignments,
    employees,
    members,
    timeEntries,
  }
}

export interface ResourceSourceRows {
  employees: ResourceEmployee[]
  assignments: { task_id: string; employee_id: string }[]
  timeEntries: ResourceTimeEntry[]
  absenceDays: { employee_id: string; day: string }[]
  // false quand le registre des absences n'est pas lisible par cet utilisateur
  absencesAvailable: boolean
}

export async function getResourceSourceRows(from: string, to: string): Promise<ResourceSourceRows> {
  // début de la période, et lendemain de sa fin (borne haute exclue)
  const next = new Date(`${to}T00:00:00Z`)
  next.setUTCDate(next.getUTCDate() + 1)
  const upper = next.toISOString().slice(0, 10)

  const [employees, assignments, timeEntries] = await Promise.all([
    readAll<ResourceEmployee>('employees', 'id, name, position, department, weekly_hours'),
    readAll<{ task_id: string; employee_id: string }>('project_task_assignees', 'task_id, employee_id', undefined, [
      'task_id',
      'employee_id',
    ], false),
    readAll<ResourceTimeEntry>('project_time_entries', 'id, employee_id, task_id, project_id, start_time, duration_seconds', (q) =>
      q.gte('start_time', from).lt('start_time', upper)
    ),
  ])

  // Le registre des absences est réservé aux rôles RH : sans lui la capacité est
  // simplement brute, et l'écran le dit.
  let absenceDays: { employee_id: string; day: string }[] = []
  let absencesAvailable = true
  try {
    const tid = await getTenantId()
    absenceDays = await fetchAllRows<{ employee_id: string; day: string }>(
      () => {
        let q = fromTable<{ employee_id: string; day: string }>('employee_absence_days', 'employee_id, day')
          .gte('day', from)
          .lte('day', to)
        if (tid) q = q.eq('tenant_id', tid)
        return q.order('day', { ascending: true }).order('employee_id', { ascending: true })
      },
      { label: 'projectFolders:employee_absence_days' }
    )
  } catch (err) {
    silentFailureReporter.report({
      type: 'absences-unreadable',
      severity: 'warning',
      message: err instanceof Error ? err.message : String(err),
      table: 'employee_absence_days',
    })
    absencesAvailable = false
  }

  return { employees, assignments, timeEntries, absenceDays, absencesAvailable }
}
