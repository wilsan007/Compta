import type { ProjectTask, TaskAction } from '@/types/projectManagement'

// Une colonne d'action = un titre d'action, partagé par toutes les tâches qui le
// portent (« Valider le devis » sur dix tâches = une seule colonne). La clé ignore
// la casse et les espaces en trop pour que « Valider le devis » et « valider  le
// devis » ne fassent pas deux colonnes.
export interface ActionColumn {
  key: string
  title: string
  // nombre de tâches qui portent cette action (tooltip d'en-tête)
  taskCount: number
}

export interface ActionMatrix {
  columns: ActionColumn[]
  // taskId -> (clé de colonne -> action) : l'accès d'une cellule est O(1),
  // là où chercher par titre dans la liste des actions de la tâche est O(n) par cellule.
  byTask: Map<string, Map<string, TaskAction>>
}

export function actionKey(title: string): string {
  return title.trim().replace(/\s+/g, ' ').toLocaleLowerCase()
}

// `display_order` est un texte (« 1 », « 1.2 », « 10 »). Le comparer comme du texte
// range « 10 » avant « 2 » ; on compare segment par segment, en nombres.
export function compareDisplayOrder(a: string | null | undefined, b: string | null | undefined): number {
  const pa = (a || '0').split('.')
  const pb = (b || '0').split('.')
  const n = Math.max(pa.length, pb.length)
  for (let i = 0; i < n; i++) {
    const x = Number(pa[i] ?? 0)
    const y = Number(pb[i] ?? 0)
    const dx = Number.isFinite(x) ? x : 0
    const dy = Number.isFinite(y) ? y : 0
    if (dx !== dy) return dx - dy
  }
  return 0
}

export function sortTasksByDisplayOrder<T extends Pick<ProjectTask, 'display_order'>>(tasks: T[]): T[] {
  // Array.prototype.sort est stable : à rang égal, l'ordre de lecture est conservé.
  return [...tasks].sort((a, b) => compareDisplayOrder(a.display_order, b.display_order))
}

// `orderedTaskIds` : les tâches dans l'ordre d'affichage. Les colonnes suivent leur
// première apparition dans cet ordre, donc les actions de la première tâche sont à
// gauche, et elles ne bougent pas quand on replie une sous-tâche.
export function buildActionMatrix(orderedTaskIds: string[], actions: TaskAction[]): ActionMatrix {
  const perTask = new Map<string, TaskAction[]>()
  for (const action of actions) {
    const list = perTask.get(action.task_id)
    if (list) list.push(action)
    else perTask.set(action.task_id, [action])
  }

  const columns: ActionColumn[] = []
  const columnIndex = new Map<string, ActionColumn>()
  const byTask = new Map<string, Map<string, TaskAction>>()

  for (const taskId of orderedTaskIds) {
    const list = perTask.get(taskId)
    if (!list) continue
    const cells = new Map<string, TaskAction>()
    for (const action of list) {
      const key = actionKey(action.title)
      if (!key || cells.has(key)) continue // deux actions de même titre sur une tâche : la première gagne
      cells.set(key, action)
      let col = columnIndex.get(key)
      if (!col) {
        col = { key, title: action.title.trim(), taskCount: 0 }
        columnIndex.set(key, col)
        columns.push(col)
      }
      col.taskCount++
    }
    byTask.set(taskId, cells)
  }

  return { columns, byTask }
}
