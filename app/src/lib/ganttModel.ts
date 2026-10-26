// Modèle du Gantt : les LIGNES affichées et, pour chaque barre, les BORNES dans
// lesquelles on peut la glisser. Les mêmes règles que la base (801, 802) — la
// base reste juge ; le Gantt les applique PENDANT le glissement pour que la
// barre s'arrête au bord au lieu d'être refusée au lâcher.
import type { DependencyType, ProjectDependency, ProjectTask, ProjectTaskDependency } from '@/types/projectManagement'
import { addDaysToDay, diffDays, maxDay, minDay, parseDay } from '@/lib/dayMath'
import { groupByProject, depthMap, NO_PROJECT } from '@/lib/taskTree'

export interface GanttProject {
  id: string
  name: string
  progress: number
  start_date: string | null
  end_date: string | null
}

export type GanttRow =
  | {
      kind: 'project'
      id: string // id du projet, ou NO_PROJECT
      name: string
      color: string
      start: string | null
      end: string | null
      progress: number
      count: number
      draggable: boolean // un projet sans dates (ou « sans projet ») ne se déplace pas
    }
  | {
      kind: 'task'
      id: string
      task: ProjectTask
      depth: number
      color: string
      start: string | null
      end: string | null
      progress: number
      hasChildren: boolean
    }

export type GanttMode = 'tasks' | 'projects'

const NO_PROJECT_COLOR = '#97a0af'

export function buildGanttRows(
  mode: GanttMode,
  tasks: ProjectTask[],
  projects: GanttProject[],
  colors: Map<string, string>,
  collapsed: Set<string>,
  noProjectLabel: string
): GanttRow[] {
  const projectRow = (p: GanttProject, count: number, span?: { start: string | null; end: string | null }): GanttRow => ({
    kind: 'project',
    id: p.id,
    name: p.name,
    color: colors.get(p.id) || NO_PROJECT_COLOR,
    start: p.start_date ?? span?.start ?? null,
    end: p.end_date ?? span?.end ?? null,
    progress: p.progress || 0,
    count,
    draggable: !!(p.start_date && p.end_date),
  })

  if (mode === 'projects') {
    return projects.map((p) => projectRow(p, tasks.filter((t) => t.project_id === p.id && !t.parent_id).length))
  }

  const groups = groupByProject(tasks, projects.map((p) => p.id))
  const depths = depthMap(tasks)
  const parents = new Set(tasks.filter((t) => t.parent_id).map((t) => t.parent_id as string))
  const byId = new Map(tasks.map((t) => [t.id, t]))
  const projectById = new Map(projects.map((p) => [p.id, p]))
  const rows: GanttRow[] = []

  for (const g of groups) {
    const span = {
      start: minDay(...g.tasks.map((t) => t.start_date)),
      end: maxDay(...g.tasks.map((t) => t.due_date)),
    }
    const p = projectById.get(g.projectId)
    if (p) rows.push(projectRow(p, g.tasks.length, span))
    else
      rows.push({
        kind: 'project',
        id: g.projectId,
        name: g.projectId === NO_PROJECT ? noProjectLabel : '—',
        color: NO_PROJECT_COLOR,
        start: span.start,
        end: span.end,
        progress: 0,
        count: g.tasks.length,
        draggable: false,
      })
    if (collapsed.has(`project:${g.projectId}`)) continue
    for (const t of g.tasks) {
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
      rows.push({
        kind: 'task',
        id: t.id,
        task: t,
        depth: depths.get(t.id) ?? 0,
        color: (t.project_id && colors.get(t.project_id)) || (p ? colors.get(p.id) : undefined) || NO_PROJECT_COLOR,
        start: t.start_date || t.due_date,
        end: t.due_date || t.start_date,
        progress: t.progress || 0,
        hasChildren: parents.has(t.id),
      })
    }
  }
  return rows
}

// ------------------------------------------------------------------ bornes
export interface Bounds {
  minStart: string | null // au plus tôt (parent, projet, prédécesseurs)
  maxEnd: string | null // au plus tard (parent, projet)
  minEnd: string | null // fin au plus tôt (liens fin→fin, début→fin)
  childMinStart: string | null // un redimensionnement ne coupe pas un enfant
  childMaxEnd: string | null
}

// Écart minimal imposé par un lien, côté successeur (mêmes règles que 802).
function requiredBy(type: DependencyType, lag: number, pred: { start: string | null; end: string | null }) {
  const l = lag || 0
  switch (type) {
    case 'start-to-start':
      return { start: pred.start ? addDaysToDay(pred.start, l) : null, end: null }
    case 'finish-to-finish':
      return { start: null, end: pred.end ? addDaysToDay(pred.end, l) : null }
    case 'start-to-finish':
      return { start: null, end: pred.start ? addDaysToDay(pred.start, l) : null }
    default:
      return { start: pred.end ? addDaysToDay(pred.end, 1 + l) : null, end: null }
  }
}

export function taskBounds(
  task: ProjectTask,
  tasksById: Map<string, ProjectTask>,
  projectsById: Map<string, GanttProject>,
  children: ProjectTask[],
  predecessors: ProjectTaskDependency[]
): Bounds {
  const parent = task.parent_id ? tasksById.get(task.parent_id) : undefined
  const project = task.project_id ? projectsById.get(task.project_id) : undefined
  const fromPreds = predecessors.map((d) => {
    const pred = tasksById.get(d.depends_on_task_id)
    return pred ? requiredBy(d.dependency_type, d.lag_days, { start: pred.start_date, end: pred.due_date }) : { start: null, end: null }
  })
  return {
    minStart: maxDay(parent?.start_date, project?.start_date, ...fromPreds.map((r) => r.start)),
    maxEnd: minDay(parent?.due_date, project?.end_date),
    minEnd: maxDay(...fromPreds.map((r) => r.end)),
    childMinStart: minDay(...children.map((c) => c.start_date)),
    childMaxEnd: maxDay(...children.map((c) => c.due_date)),
  }
}

export function projectBounds(
  projectsById: Map<string, GanttProject>,
  tasksOfProject: ProjectTask[],
  predecessors: ProjectDependency[]
): Bounds {
  const fromPreds = predecessors.map((d) => {
    const pred = projectsById.get(d.depends_on_project_id)
    return pred?.end_date ? addDaysToDay(pred.end_date, 1 + (d.lag_days || 0)) : null
  })
  return {
    minStart: maxDay(...fromPreds),
    maxEnd: null,
    minEnd: null,
    childMinStart: minDay(...tasksOfProject.map((t) => t.start_date)),
    childMaxEnd: maxDay(...tasksOfProject.map((t) => t.due_date)),
  }
}

// ------------------------------------------------------------------ glissement borné
export type DragType = 'move' | 'resize-start' | 'resize-end'

// Nouvelles dates d'une barre glissée de `delta` jours, ramenées dans ses bornes.
// Un déplacement garde la durée ; un redimensionnement garde au moins un jour et
// ne coupe aucun enfant.
export function applyDrag(
  type: DragType,
  start: string,
  end: string,
  delta: number,
  b: Bounds
): { start: string; end: string } {
  const s = parseDay(start)!
  const e = parseDay(end)!
  const off = (bound: string | null, from: Date) => (bound ? diffDays(from, parseDay(bound)!) : null)

  if (type === 'move') {
    let lo = -Infinity
    let hi = Infinity
    const a = off(b.minStart, s)
    if (a !== null) lo = Math.max(lo, a)
    const c = off(b.minEnd, e)
    if (c !== null) lo = Math.max(lo, c)
    const z = off(b.maxEnd, e)
    if (z !== null) hi = Math.min(hi, z)
    const d = lo > hi ? 0 : Math.min(hi, Math.max(lo, delta))
    return { start: addDaysToDay(start, d), end: addDaysToDay(end, d) }
  }

  if (type === 'resize-start') {
    let d = delta
    const lo = off(b.minStart, s)
    if (lo !== null) d = Math.max(d, lo)
    const hiChild = off(b.childMinStart, s)
    if (hiChild !== null) d = Math.min(d, hiChild)
    d = Math.min(d, diffDays(s, e)) // au moins un jour
    return { start: addDaysToDay(start, d), end }
  }

  let d = delta
  const hi = off(b.maxEnd, e)
  if (hi !== null) d = Math.min(d, hi)
  const loChild = off(b.childMaxEnd, e)
  if (loChild !== null) d = Math.max(d, loChild)
  const loDep = off(b.minEnd, e)
  if (loDep !== null) d = Math.max(d, loDep)
  d = Math.max(d, -diffDays(s, e)) // au moins un jour
  return { start, end: addDaysToDay(end, d) }
}

// ------------------------------------------------------------------ tracé des liens
export interface BarBox {
  x1: number // début de la barre
  x2: number // fin de la barre
  y: number // milieu de la ligne
}

// Tracé « à angles droits » des outils de planification (MS Project, TeamGantt) :
// on sort de l'ancre du prédécesseur, on rejoint la ligne du successeur, on entre
// par son ancre. Quand le successeur commence avant l'ancre (chevauchement), le
// trait contourne par l'interligne au lieu de traverser les barres.
export function dependencyPath(type: DependencyType, from: BarBox, to: BarBox, rowHeight: number): string {
  const out = type === 'start-to-start' || type === 'start-to-finish' ? from.x1 : from.x2
  const into = type === 'finish-to-finish' || type === 'start-to-finish' ? to.x2 : to.x1
  const outDir = out === from.x1 ? -1 : 1
  const inDir = into === to.x1 ? -1 : 1 // côté par lequel on entre
  const gap = 8
  const ox = out + outDir * gap
  const ix = into + inDir * gap
  if (inDir === -1 && ix >= ox) {
    return `M ${out} ${from.y} H ${ox} V ${to.y} H ${into}`
  }
  if (inDir === 1 && ix <= ox && outDir === 1) {
    return `M ${out} ${from.y} H ${Math.max(ox, ix)} V ${to.y} H ${into}`
  }
  const mid = to.y + (to.y >= from.y ? -rowHeight / 2 : rowHeight / 2)
  return `M ${out} ${from.y} H ${ox} V ${mid} H ${ix} V ${to.y} H ${into}`
}
