import { compareDisplayOrder } from '@/lib/actionColumns'
import type { ProjectTask } from '@/types/projectManagement'

export const NO_PROJECT = 'no-project'

export interface ProjectGroup<T> {
  projectId: string // NO_PROJECT pour les tâches sans projet
  tasks: T[] // dans l'ordre de l'arbre : chaque mère suivie de ses descendants
}

type TreeTask = Pick<ProjectTask, 'id' | 'parent_id' | 'project_id' | 'display_order'> & { start_date?: string | null }

// Ordre d'arbre : une mère, puis ses sous-tâches (récursivement), frères triés par
// `display_order`. Trier seulement par `display_order` séparait une sous-tâche de
// sa mère dès que les numéros n'étaient pas tenus (`'0'` partout à la création).
// Une tâche dont la mère n'est pas dans la liste (filtre) est traitée en racine.
export function orderAsTree<T extends TreeTask>(tasks: T[]): T[] {
  const ids = new Set(tasks.map((t) => t.id))
  const children = new Map<string, T[]>()
  const roots: T[] = []
  for (const t of tasks) {
    if (t.parent_id && ids.has(t.parent_id) && t.parent_id !== t.id) {
      const list = children.get(t.parent_id)
      if (list) list.push(t)
      else children.set(t.parent_id, [t])
    } else {
      roots.push(t)
    }
  }
  // À numéro égal (`'0'` partout à la création), la date de début départage :
  // l'ordre de lecture de la base n'est pas un ordre.
  const byOrder = (a: T, b: T) =>
    compareDisplayOrder(a.display_order, b.display_order) ||
    String(a.start_date || '9999').localeCompare(String(b.start_date || '9999'))
  const out: T[] = []
  const seen = new Set<string>()
  const visit = (t: T) => {
    if (seen.has(t.id)) return // une boucle de parenté ne doit pas figer l'écran
    seen.add(t.id)
    out.push(t)
    for (const c of (children.get(t.id) || []).sort(byOrder)) visit(c)
  }
  for (const r of [...roots].sort(byOrder)) visit(r)
  // ce qui n'a pas été atteint (cycle) est rendu à la fin plutôt que perdu
  for (const t of tasks) if (!seen.has(t.id)) out.push(t)
  return out
}

// Regroupe par projet, dans l'ordre des projets donné ; « sans projet » en dernier.
// Une sous-tâche reste dans le groupe de sa racine, même si son `project_id` diffère.
export function groupByProject<T extends TreeTask>(tasks: T[], projectOrder: string[]): ProjectGroup<T>[] {
  const ordered = orderAsTree(tasks)
  const byId = new Map(ordered.map((t) => [t.id, t]))
  const rootOf = (t: T): T => {
    let cur = t
    const seen = new Set<string>()
    while (cur.parent_id && byId.has(cur.parent_id) && !seen.has(cur.id)) {
      seen.add(cur.id)
      cur = byId.get(cur.parent_id)!
    }
    return cur
  }
  const groups = new Map<string, T[]>()
  for (const t of ordered) {
    const key = rootOf(t).project_id || NO_PROJECT
    const list = groups.get(key)
    if (list) list.push(t)
    else groups.set(key, [t])
  }
  const result: ProjectGroup<T>[] = []
  for (const pid of projectOrder) {
    const list = groups.get(pid)
    if (list) {
      result.push({ projectId: pid, tasks: list })
      groups.delete(pid)
    }
  }
  // projets inconnus de la liste (droits, filtre), puis « sans projet »
  for (const [pid, list] of groups) if (pid !== NO_PROJECT) result.push({ projectId: pid, tasks: list })
  if (groups.has(NO_PROJECT)) result.push({ projectId: NO_PROJECT, tasks: groups.get(NO_PROJECT)! })
  return result
}

// Profondeur dans l'arbre affiché (0 = racine), indépendante de `task_level`.
export function depthMap<T extends TreeTask>(tasks: T[]): Map<string, number> {
  const byId = new Map(tasks.map((t) => [t.id, t]))
  const depth = new Map<string, number>()
  const get = (t: T, guard = 0): number => {
    if (depth.has(t.id)) return depth.get(t.id)!
    const parent = t.parent_id ? byId.get(t.parent_id) : undefined
    const d = parent && guard < 50 ? get(parent, guard + 1) + 1 : 0
    depth.set(t.id, d)
    return d
  }
  for (const t of tasks) get(t)
  return depth
}
