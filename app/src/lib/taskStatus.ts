import type { TaskStatus } from '@/types/projectManagement'

// La base range les statuts de tâche dans SON vocabulaire (douze fonctions le
// comparent : `in_progress`, `cancelled`) et normalise ce qu'on lui écrit
// (migration 800). L'écran garde le sien (`doing`, `canceled`), traduit ici, à
// la frontière : en lecture ET en écriture.
const FROM_DB: Record<string, TaskStatus> = {
  in_progress: 'doing',
  cancelled: 'canceled',
  completed: 'done',
}
const TO_DB: Partial<Record<TaskStatus, string>> = {
  doing: 'in_progress',
  canceled: 'cancelled',
}

export function taskStatusFromDb(status: string | null | undefined): TaskStatus {
  if (!status) return 'todo'
  return FROM_DB[status] ?? (status as TaskStatus)
}

export function taskStatusToDb(status: TaskStatus): string {
  return TO_DB[status] ?? status
}

// Applique la traduction à une ligne lue de `project_tasks` (une ligne sans
// statut — sélection partielle — est rendue telle quelle).
export function fromDbTask<T extends { status?: string | null }>(row: T): T {
  if (row.status == null) return row
  return { ...row, status: taskStatusFromDb(row.status) }
}

// Traduit le statut d'une écriture (création ou mise à jour), s'il y en a un.
export function toDbTaskWrite<T extends { status?: TaskStatus | string | null }>(payload: T): T {
  if (!payload.status) return payload
  return { ...payload, status: taskStatusToDb(payload.status as TaskStatus) }
}
