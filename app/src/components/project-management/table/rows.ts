// Les lignes du tableau, UNE liste pour les deux panneaux (colonnes fixes à
// gauche, colonnes d'actions à droite). Chaque ligne a une hauteur fixe : c'est
// ce qui garde les deux panneaux alignés au pixel pendant le défilement.
import type { ProjectTask } from '@/types/projectManagement'
import { depthMap, groupByProject, NO_PROJECT } from '@/lib/taskTree'
import { BAND_H, ROW_H, SUB_ROW_H } from './kit'

// Une seule ligne « Ajouter une tâche… » (wadashaqayn en pose cinq : elles
// allongeaient le tableau sans rien offrir de plus que la première).
const GHOST_ROWS = 1
const NO_PROJECT_COLOR = '#97a0af'

export interface ProjectSummary {
  id: string
  name: string
  progress: number
  start_date: string | null
  end_date: string | null
}

export type TableRow =
  | { kind: 'band'; key: string; projectId: string; name: string | null; color: string; summary?: ProjectSummary; count: number; folded: boolean }
  | { kind: 'task'; key: string; task: ProjectTask; depth: number; number: string; color: string; isSub: boolean; hasChildren: boolean; folded: boolean }
  | { kind: 'ghost'; key: string; index: number }

export const rowHeight = (r: TableRow) => (r.kind === 'band' ? BAND_H : r.kind === 'task' && r.isSub ? SUB_ROW_H : ROW_H)

export const projectCollapseKey = (projectId: string) => `project:${projectId}`

export function buildTableRows(
  tasks: ProjectTask[],
  projects: ProjectSummary[],
  colors: Map<string, string>,
  collapsed: Set<string>,
  withGhosts: boolean
): TableRow[] {
  const groups = groupByProject(tasks, projects.map((p) => p.id))
  const depths = depthMap(tasks)
  const byId = new Map(tasks.map((t) => [t.id, t]))
  const parents = new Set(tasks.filter((t) => t.parent_id && byId.has(t.parent_id)).map((t) => t.parent_id as string))
  const summaries = new Map(projects.map((p) => [p.id, p]))
  const rows: TableRow[] = []

  // Numéros affichés « 1 », « 1.2 », « 1.2.1 » : la position dans l'arbre (le
  // champ display_order n'est pas tenu à la création).
  const numbers = new Map<string, string>()
  const childCount = new Map<string, number>()
  let roots = 0

  for (const g of groups) {
    const color = g.projectId === NO_PROJECT ? NO_PROJECT_COLOR : colors.get(g.projectId) || NO_PROJECT_COLOR
    const key = projectCollapseKey(g.projectId)
    const folded = collapsed.has(key)
    rows.push({
      kind: 'band',
      key: `band:${g.projectId}`,
      projectId: g.projectId,
      name: g.projectId === NO_PROJECT ? null : summaries.get(g.projectId)?.name ?? null,
      color,
      summary: summaries.get(g.projectId),
      count: g.tasks.length,
      folded,
    })
    for (const t of g.tasks) {
      const parentNo = t.parent_id ? numbers.get(t.parent_id) : undefined
      let no: string
      if (parentNo) {
        const n = (childCount.get(t.parent_id as string) || 0) + 1
        childCount.set(t.parent_id as string, n)
        no = `${parentNo}.${n}`
      } else {
        no = String(++roots)
      }
      numbers.set(t.id, no)
      if (folded) continue
      // masquée si un ancêtre est replié
      let hidden = false
      let cur = t.parent_id ? byId.get(t.parent_id) : undefined
      const seen = new Set<string>()
      while (cur && !seen.has(cur.id)) {
        if (collapsed.has(cur.id)) {
          hidden = true
          break
        }
        seen.add(cur.id)
        cur = cur.parent_id ? byId.get(cur.parent_id) : undefined
      }
      if (hidden) continue
      const depth = depths.get(t.id) ?? 0
      rows.push({
        kind: 'task',
        key: t.id,
        task: t,
        depth,
        number: no,
        color: (t.project_id && colors.get(t.project_id)) || color,
        isSub: depth > 0,
        hasChildren: parents.has(t.id),
        folded: collapsed.has(t.id),
      })
    }
  }
  if (withGhosts) for (let i = 0; i < GHOST_ROWS; i++) rows.push({ kind: 'ghost', key: `ghost:${i}`, index: i })
  return rows
}
