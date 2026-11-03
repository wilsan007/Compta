import type { ProjectTask } from '@/types/projectManagement'

// Utilisation des ressources humaines sur une période.
//
//   capacité   = jours ouvrés de la période × (heures hebdo ÷ 5), moins les
//                jours d'absence inscrits au registre des absences ;
//   planifié   = heures estimées des tâches de la personne, étalées sur les
//                jours ouvrés entre le début et l'échéance, puis ramenées à
//                la part qui tombe dans la période ;
//   réalisé    = temps réellement saisi sur la période.
//
// Taux d'utilisation = planifié ÷ capacité (la charge qu'on lui a donnée) ;
// taux réalisé = réalisé ÷ capacité (ce qu'elle a effectivement fait).

const DEFAULT_WEEKLY_HOURS = 35
// Au-dessus : surchargé. En dessous : sous-utilisé.
const OVERLOAD_THRESHOLD = 100
const UNDERLOAD_THRESHOLD = 50

export type UsageStatus = 'overloaded' | 'balanced' | 'underloaded' | 'unknown'

export interface ResourceEmployee {
  id: string
  name: string
  position: string | null
  department: string | null
  weekly_hours: number | null
}

export type ResourceTask = Pick<
  ProjectTask,
  'id' | 'project_id' | 'parent_id' | 'title' | 'status' | 'start_date' | 'due_date' | 'effort_estimate_h' | 'assignee'
>

export interface ResourceTimeEntry {
  employee_id: string | null
  task_id: string | null
  project_id: string | null
  start_time: string
  duration_seconds: number | null
}

export interface ResourceUsageInput {
  from: string // AAAA-MM-JJ, inclus
  to: string // AAAA-MM-JJ, inclus
  today: string
  employees: ResourceEmployee[]
  tasks: ResourceTask[]
  assignments: { task_id: string; employee_id: string }[]
  timeEntries: ResourceTimeEntry[]
  absenceDays: { employee_id: string; day: string }[]
  projectNames: Map<string, string>
  noProjectLabel: string
  // limite le calcul à un projet (la capacité, elle, reste celle de la personne)
  projectId?: string | null
}

interface ResourceProjectLine {
  projectId: string | null
  name: string
  tasks: number
  plannedHours: number
  loggedHours: number
}

export interface ResourceRow {
  key: string
  employeeId: string | null
  name: string
  position: string | null
  // personne citée sur une tâche mais absente de la liste des salariés
  unlinked: boolean
  weeklyHours: number
  capacityHours: number
  absenceDays: number
  plannedHours: number
  loggedHours: number
  plannedRate: number | null
  loggedRate: number | null
  status: UsageStatus
  tasks: number // tâches de la période
  openTasks: number
  overdueTasks: number
  unscheduledTasks: number // ouvertes, sans date : elles n'entrent dans aucune période
  unestimatedTasks: number // de la période, sans heures estimées
  projects: number
  byProject: ResourceProjectLine[]
}

export interface ResourceUsageResult {
  rows: ResourceRow[]
  totals: {
    people: number
    capacityHours: number
    plannedHours: number
    loggedHours: number
    plannedRate: number | null
    loggedRate: number | null
    overloaded: number
    underloaded: number
  }
  // tâches de la période que personne n'a en charge
  unassignedTasks: number
}

// ---------- dates (jours calendaires, sans fuseau) ----------

const DAY_MS = 86_400_000

const toIndex = (iso: string): number => {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number)
  return Math.floor(Date.UTC(y, m - 1, d) / DAY_MS)
}

const isWeekday = (idx: number): boolean => {
  // 1970-01-01 est un jeudi
  const dow = (((idx + 4) % 7) + 7) % 7 // 0 = dimanche
  return dow !== 0 && dow !== 6
}

// Jours ouvrés (lundi → vendredi) entre deux indices, bornes incluses.
function weekdaysBetween(a: number, b: number): number {
  if (b < a) return 0
  let n = 0
  // jusqu'à quelques années : la boucle reste négligeable devant le réseau
  for (let i = a; i <= b; i++) if (isWeekday(i)) n++
  return n
}

// Part (en heures) d'un travail de `hours` heures étalé entre `s` et `e` qui
// tombe dans [from, to].
export function hoursInPeriod(hours: number, s: string, e: string, from: string, to: string): number {
  if (!(hours > 0)) return 0
  let a = toIndex(s)
  let b = toIndex(e)
  if (b < a) [a, b] = [b, a]
  const f = toIndex(from)
  const t = toIndex(to)
  const lo = Math.max(a, f)
  const hi = Math.min(b, t)
  if (hi < lo) return 0
  const span = weekdaysBetween(a, b)
  if (span > 0) return (hours * weekdaysBetween(lo, hi)) / span
  // étendue qui ne couvre que des jours de week-end : on étale sur les jours calendaires
  return (hours * (hi - lo + 1)) / (b - a + 1)
}

const norm = (s: string): string =>
  s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .trim()
    .toLocaleLowerCase()

const round1 = (n: number): number => Math.round(n * 10) / 10

export function usageStatus(plannedRate: number | null): UsageStatus {
  if (plannedRate === null) return 'unknown'
  if (plannedRate > OVERLOAD_THRESHOLD) return 'overloaded'
  if (plannedRate < UNDERLOAD_THRESHOLD) return 'underloaded'
  return 'balanced'
}

interface Acc {
  key: string
  employeeId: string | null
  name: string
  position: string | null
  unlinked: boolean
  weeklyHours: number
  absenceDays: number
  planned: number
  logged: number
  tasks: Set<string>
  open: Set<string>
  overdue: Set<string>
  unscheduled: Set<string>
  unestimated: Set<string>
  perProject: Map<string, { tasks: Set<string>; planned: number; logged: number }>
}

export function computeResourceUsage(input: ResourceUsageInput): ResourceUsageResult {
  const { from, to, today } = input
  const wantProject = input.projectId || null

  const byEmployeeId = new Map(input.employees.map((e) => [e.id, e]))
  const byName = new Map(input.employees.map((e) => [norm(e.name), e]))
  const accs = new Map<string, Acc>()

  const accFor = (employee: ResourceEmployee | null, fallbackName?: string): Acc => {
    const key = employee ? employee.id : `name:${norm(fallbackName || '')}`
    let a = accs.get(key)
    if (!a) {
      a = {
        key,
        employeeId: employee ? employee.id : null,
        name: employee ? employee.name : (fallbackName || '').trim(),
        position: employee ? employee.position : null,
        unlinked: !employee,
        weeklyHours: employee && (employee.weekly_hours ?? 0) > 0 ? Number(employee.weekly_hours) : DEFAULT_WEEKLY_HOURS,
        absenceDays: 0,
        planned: 0,
        logged: 0,
        tasks: new Set(),
        open: new Set(),
        overdue: new Set(),
        unscheduled: new Set(),
        unestimated: new Set(),
        perProject: new Map(),
      }
      accs.set(key, a)
    }
    return a
  }
  const lineFor = (a: Acc, projectKey: string) => {
    let l = a.perProject.get(projectKey)
    if (!l) {
      l = { tasks: new Set(), planned: 0, logged: 0 }
      a.perProject.set(projectKey, l)
    }
    return l
  }

  // qui est en charge de quoi : la table de liaison, à défaut le nom saisi
  const ownersOf = new Map<string, Acc[]>()
  const addOwner = (taskId: string, acc: Acc) => {
    const list = ownersOf.get(taskId)
    if (!list) ownersOf.set(taskId, [acc])
    else if (!list.includes(acc)) list.push(acc)
  }
  for (const a of input.assignments) {
    const emp = byEmployeeId.get(a.employee_id)
    if (emp) addOwner(a.task_id, accFor(emp))
  }
  for (const t of input.tasks) {
    if (ownersOf.has(t.id)) continue
    const own = (t.assignee || '').trim()
    if (!own) continue
    const emp = byName.get(norm(own)) || null
    addOwner(t.id, emp ? accFor(emp) : accFor(null, own))
  }

  // une mère ne compte que ce que ses sous-tâches n'estiment pas déjà
  const childEstimate = new Map<string, number>()
  for (const t of input.tasks) {
    if (t.parent_id) childEstimate.set(t.parent_id, (childEstimate.get(t.parent_id) || 0) + Math.max(0, Number(t.effort_estimate_h) || 0))
  }

  const projectKeyOf = (id: string | null) => id || '__none__'
  let unassigned = 0

  for (const t of input.tasks) {
    if (t.status === 'canceled') continue
    if (wantProject && t.project_id !== wantProject) continue
    const owners = ownersOf.get(t.id) || []
    const closed = t.status === 'done'

    const s = t.start_date || t.due_date
    const e = t.due_date || t.start_date
    if (!s || !e) {
      if (!closed) for (const o of owners) o.unscheduled.add(t.id)
      continue
    }
    const lo = s <= e ? s : e
    const hi = s <= e ? e : s
    if (hi < from || lo > to) continue // hors période

    if (owners.length === 0) {
      unassigned++
      continue
    }

    const own = Math.max(0, Number(t.effort_estimate_h) || 0)
    const hours = Math.max(0, own - (childEstimate.get(t.id) || 0))
    const share = hoursInPeriod(hours, lo, hi, from, to) / owners.length

    for (const o of owners) {
      o.tasks.add(t.id)
      if (!closed) o.open.add(t.id)
      if (!closed && t.due_date && t.due_date < today) o.overdue.add(t.id)
      if (own <= 0) o.unestimated.add(t.id)
      o.planned += share
      const line = lineFor(o, projectKeyOf(t.project_id))
      line.tasks.add(t.id)
      line.planned += share
    }
  }

  // temps réellement saisi
  const taskById = new Map(input.tasks.map((t) => [t.id, t]))
  const fromIdx = toIndex(from)
  const toIdx = toIndex(to)
  for (const en of input.timeEntries) {
    if (!en.employee_id) continue
    const emp = byEmployeeId.get(en.employee_id)
    if (!emp) continue
    const day = toIndex(en.start_time)
    if (day < fromIdx || day > toIdx) continue
    const projectId = en.project_id || (en.task_id ? taskById.get(en.task_id)?.project_id ?? null : null)
    if (wantProject && projectId !== wantProject) continue
    const h = (Number(en.duration_seconds) || 0) / 3600
    if (h <= 0) continue
    const a = accFor(emp)
    a.logged += h
    lineFor(a, projectKeyOf(projectId)).logged += h
  }

  // capacité
  const workdays = weekdaysBetween(fromIdx, toIdx)
  const absentByEmp = new Map<string, Set<string>>()
  for (const ab of input.absenceDays) {
    const idx = toIndex(ab.day)
    if (idx < fromIdx || idx > toIdx || !isWeekday(idx)) continue
    const set = absentByEmp.get(ab.employee_id) || new Set<string>()
    set.add(ab.day.slice(0, 10))
    absentByEmp.set(ab.employee_id, set)
  }

  const rows: ResourceRow[] = []
  for (const a of accs.values()) {
    if (a.tasks.size === 0 && a.unscheduled.size === 0 && a.logged === 0) continue
    a.absenceDays = a.employeeId ? absentByEmp.get(a.employeeId)?.size || 0 : 0
    const capacity = Math.max(0, (workdays - a.absenceDays) * (a.weeklyHours / 5))
    const plannedRate = capacity > 0 ? Math.round((a.planned / capacity) * 100) : null
    const loggedRate = capacity > 0 ? Math.round((a.logged / capacity) * 100) : null
    const byProject: ResourceProjectLine[] = [...a.perProject.entries()]
      .map(([k, l]) => ({
        projectId: k === '__none__' ? null : k,
        name: k === '__none__' ? input.noProjectLabel : input.projectNames.get(k) || k,
        tasks: l.tasks.size,
        plannedHours: round1(l.planned),
        loggedHours: round1(l.logged),
      }))
      .sort((x, y) => y.plannedHours + y.loggedHours - (x.plannedHours + x.loggedHours))
    rows.push({
      key: a.key,
      employeeId: a.employeeId,
      name: a.name,
      position: a.position,
      unlinked: a.unlinked,
      weeklyHours: a.weeklyHours,
      capacityHours: round1(capacity),
      absenceDays: a.absenceDays,
      plannedHours: round1(a.planned),
      loggedHours: round1(a.logged),
      plannedRate,
      loggedRate,
      status: usageStatus(plannedRate),
      tasks: a.tasks.size,
      openTasks: a.open.size,
      overdueTasks: a.overdue.size,
      unscheduledTasks: a.unscheduled.size,
      unestimatedTasks: a.unestimated.size,
      projects: a.perProject.size,
      byProject,
    })
  }
  rows.sort((x, y) => (y.plannedRate ?? -1) - (x.plannedRate ?? -1) || x.name.localeCompare(y.name))

  const capacityHours = rows.reduce((s, r) => s + r.capacityHours, 0)
  const plannedHours = rows.reduce((s, r) => s + r.plannedHours, 0)
  const loggedHours = rows.reduce((s, r) => s + r.loggedHours, 0)
  return {
    rows,
    totals: {
      people: rows.length,
      capacityHours: round1(capacityHours),
      plannedHours: round1(plannedHours),
      loggedHours: round1(loggedHours),
      plannedRate: capacityHours > 0 ? Math.round((plannedHours / capacityHours) * 100) : null,
      loggedRate: capacityHours > 0 ? Math.round((loggedHours / capacityHours) * 100) : null,
      overloaded: rows.filter((r) => r.status === 'overloaded').length,
      underloaded: rows.filter((r) => r.status === 'underloaded').length,
    },
    unassignedTasks: unassigned,
  }
}

// ---------- périodes proposées ----------

export type PeriodPreset = 'thisWeek' | 'thisMonth' | 'lastMonth' | 'thisQuarter' | 'thisYear'

const iso = (d: Date): string =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

export function presetRange(preset: PeriodPreset, now: Date = new Date()): { from: string; to: string } {
  const y = now.getFullYear()
  const m = now.getMonth()
  switch (preset) {
    case 'thisWeek': {
      const dow = (now.getDay() + 6) % 7 // lundi = 0
      const monday = new Date(y, m, now.getDate() - dow)
      const sunday = new Date(y, m, now.getDate() - dow + 6)
      return { from: iso(monday), to: iso(sunday) }
    }
    case 'lastMonth':
      return { from: iso(new Date(y, m - 1, 1)), to: iso(new Date(y, m, 0)) }
    case 'thisQuarter': {
      const q = Math.floor(m / 3) * 3
      return { from: iso(new Date(y, q, 1)), to: iso(new Date(y, q + 3, 0)) }
    }
    case 'thisYear':
      return { from: iso(new Date(y, 0, 1)), to: iso(new Date(y, 11, 31)) }
    case 'thisMonth':
    default:
      return { from: iso(new Date(y, m, 1)), to: iso(new Date(y, m + 1, 0)) }
  }
}
