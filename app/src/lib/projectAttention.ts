import {
  buildFolderIndex,
  daysBetween,
  summarizeFolder,
  type FolderSources,
  type DeadlineState,
} from '@/lib/projectFolders'
import type { ResourceUsageResult } from '@/lib/resourceUsage'
import type { ProjectTask } from '@/types/projectManagement'

// « Points d'attention » : ce qui demande une action aujourd'hui, et un feu
// tricolore par projet. Rien n'est saisi : tout vient des synthèses de dossier
// (retard, décaissement, avancement) et du taux d'utilisation des personnes.

type AttentionKind =
  | 'projectLate'
  | 'overBudget'
  | 'burnAhead'
  | 'taskLate'
  | 'blocked'
  | 'unassigned'
  | 'overloaded'

type AttentionSeverity = 'high' | 'medium'
export type Health = 'red' | 'amber' | 'green'

// Une tâche en retard de plus de 14 jours est urgente.
const TASK_LATE_URGENT_DAYS = 14
// Décaissé au moins 25 points au-dessus de l'avancement, et déjà à 30 % : on dépense plus vite qu'on n'avance.
const BURN_GAP_POINTS = 25
const BURN_MIN_RATE = 30
// Une tâche sans responsable inquiète quand elle commence ou s'achève dans les 14 jours.
const UNASSIGNED_HORIZON_DAYS = 14

export interface AttentionItem {
  id: string
  kind: AttentionKind
  severity: AttentionSeverity
  projectId: string | null
  projectName: string
  // une personne surchargée est UN point d'attention, rattaché à tous les projets qu'elle porte
  projectIds?: string[]
  taskId?: string
  taskTitle?: string
  person?: string
  days?: number
  rate?: number
  progress?: number
}

export interface ProjectHealth {
  projectId: string
  name: string
  color: string | null
  health: Health
  progress: number
  disbursementRate: number | null
  deadline: DeadlineState
  daysLeft: number | null
  end: string | null
  high: number
  items: number
}

export interface AttentionResult {
  projects: ProjectHealth[]
  items: AttentionItem[]
  counts: { red: number; amber: number; green: number; items: number; high: number }
}

const CLOSED = new Set(['done', 'canceled'])
const OVER_PROJECT_STATUS = new Set(['completed', 'cancelled'])

const isOpen = (t: ProjectTask): boolean => !CLOSED.has(t.status)

export function computeAttention(args: {
  sources: FolderSources
  usage: ResourceUsageResult | null
  today: string
}): AttentionResult {
  const { sources, usage, today } = args
  const index = buildFolderIndex(sources)
  const items: AttentionItem[] = []
  const projectName = new Map(sources.projects.map((p) => [p.id, p.name]))
  const nameOf = (id: string | null): string => (id ? projectName.get(id) || '' : sources.noProjectLabel)

  const activeProjects = sources.projects.filter((p) => !OVER_PROJECT_STATUS.has(p.status || ''))
  const activeIds = new Set(activeProjects.map((p) => p.id))

  const push = (it: Omit<AttentionItem, 'projectName'>) =>
    items.push({ ...it, projectName: nameOf(it.projectId) })

  // ----- au niveau du projet
  const summaries = new Map<string, ReturnType<typeof summarizeFolder>>()
  for (const p of activeProjects) {
    const s = summarizeFolder(sources, { kind: 'project', id: p.id }, today)
    summaries.set(p.id, s)
    if (!s) continue
    if (s.deadline === 'late') {
      push({ id: `pl:${p.id}`, kind: 'projectLate', severity: 'high', projectId: p.id, days: Math.abs(s.daysLeft ?? 0) })
    }
    if (s.budget > 0 && s.disbursementRate !== null) {
      if (s.disbursementRate > 100) {
        push({ id: `ob:${p.id}`, kind: 'overBudget', severity: 'high', projectId: p.id, rate: s.disbursementRate })
      } else if (s.disbursementRate >= BURN_MIN_RATE && s.disbursementRate - s.progress >= BURN_GAP_POINTS) {
        push({
          id: `ba:${p.id}`,
          kind: 'burnAhead',
          severity: 'medium',
          projectId: p.id,
          rate: s.disbursementRate,
          progress: s.progress,
        })
      }
    }
  }

  // ----- au niveau des tâches
  const hasOpenLateChild = (t: ProjectTask): boolean =>
    (index.childrenOf.get(t.id) || []).some((c) => isOpen(c) && !!c.due_date && c.due_date < today)
  const hasChildren = (t: ProjectTask): boolean => (index.childrenOf.get(t.id) || []).length > 0
  const horizon = (() => {
    const d = new Date(`${today}T00:00:00Z`)
    d.setUTCDate(d.getUTCDate() + UNASSIGNED_HORIZON_DAYS)
    return d.toISOString().slice(0, 10)
  })()

  for (const t of sources.tasks) {
    const pid = t.project_id
    if (pid && !activeIds.has(pid)) continue
    if (!isOpen(t)) continue

    if (t.due_date && t.due_date < today && !hasOpenLateChild(t)) {
      const late = daysBetween(t.due_date, today)
      push({
        id: `tl:${t.id}`,
        kind: 'taskLate',
        severity: late > TASK_LATE_URGENT_DAYS ? 'high' : 'medium',
        projectId: pid,
        taskId: t.id,
        taskTitle: t.title,
        days: late,
      })
    }

    if (t.status === 'blocked' || t.status === 'changes_requested') {
      push({ id: `bl:${t.id}`, kind: 'blocked', severity: 'medium', projectId: pid, taskId: t.id, taskTitle: t.title })
    }

    // une tâche mère est portée par ses sous-tâches : seules les feuilles réclament un responsable
    const nobody = (sources.peopleByTask.get(t.id) || []).length === 0
    const soon =
      (!!t.start_date && t.start_date <= horizon) || (!!t.due_date && t.due_date <= horizon)
    if (nobody && soon && !hasChildren(t)) {
      push({ id: `un:${t.id}`, kind: 'unassigned', severity: 'medium', projectId: pid, taskId: t.id, taskTitle: t.title })
    }
  }

  // ----- les personnes surchargées : une ligne par personne, rattachée à chaque projet qu'elle porte
  for (const row of usage?.rows || []) {
    if (row.status !== 'overloaded' || row.plannedRate === null) continue
    const mine = row.byProject.filter((l) => l.projectId && activeIds.has(l.projectId))
    if (mine.length === 0) continue
    const ids = mine.map((l) => l.projectId as string)
    items.push({
      id: `ov:${row.key}`,
      kind: 'overloaded',
      severity: 'medium',
      projectId: ids[0],
      projectIds: ids,
      projectName: ids.map((id) => nameOf(id)).join(' · '),
      person: row.name,
      rate: row.plannedRate,
    })
  }

  const rank = (i: AttentionItem) => (i.severity === 'high' ? 0 : 1)
  items.sort(
    (a, b) =>
      rank(a) - rank(b) ||
      (b.days ?? 0) - (a.days ?? 0) ||
      a.projectName.localeCompare(b.projectName) ||
      a.id.localeCompare(b.id)
  )

  // ----- le feu de chaque projet
  const projects: ProjectHealth[] = []
  for (const p of activeProjects) {
    const s = summaries.get(p.id)
    if (!s) continue
    const mine = items.filter((i) => i.projectId === p.id || i.projectIds?.includes(p.id))
    const high = mine.filter((i) => i.severity === 'high').length
    projects.push({
      projectId: p.id,
      name: p.name,
      color: p.color,
      health: high > 0 ? 'red' : mine.length > 0 ? 'amber' : 'green',
      progress: s.progress,
      disbursementRate: s.disbursementRate,
      deadline: s.deadline,
      daysLeft: s.daysLeft,
      end: s.end,
      high,
      items: mine.length,
    })
  }
  const order: Record<Health, number> = { red: 0, amber: 1, green: 2 }
  projects.sort((a, b) => order[a.health] - order[b.health] || b.items - a.items || a.name.localeCompare(b.name))

  return {
    projects,
    items,
    counts: {
      red: projects.filter((p) => p.health === 'red').length,
      amber: projects.filter((p) => p.health === 'amber').length,
      green: projects.filter((p) => p.health === 'green').length,
      items: items.length,
      high: items.filter((i) => i.severity === 'high').length,
    },
  }
}
