import type { ProjectTask } from '@/types/projectManagement'

// Dossiers de documents d'un projet : le projet est le dossier racine, ses
// tâches de premier niveau sont ses sous-dossiers, leurs sous-tâches les
// sous-dossiers suivants. Chaque dossier porte une SYNTHÈSE calculée sur tout
// son contenu (documents, personnes, délai, budget décaissé, avancement).

export const NO_PROJECT_FOLDER = 'no-project'

type FolderKind = 'project' | 'task'
export type DeadlineState = 'none' | 'done' | 'late' | 'soon' | 'ontrack'

// Une échéance à moins de 7 jours est « proche ».
const DEADLINE_SOON_DAYS = 7

interface FolderProject {
  id: string
  name: string
  color: string | null
  budget: number | null
  actual_cost: number | null
  start_date: string | null
  end_date: string | null
  progress: number | null
  manager_id: string | null
  status: string | null
}

export interface FolderDocument {
  id: string
  task_id: string
  file_name: string
  file_path: string
  file_size: number | null
  mime_type: string | null
  created_at: string
  // `proof` : pièce jointe à une action de la tâche (preuve d'avancement).
  kind: 'document' | 'proof'
}

export interface FolderSources {
  projects: FolderProject[]
  tasks: ProjectTask[]
  documents: FolderDocument[]
  // noms des personnes en charge, par tâche
  peopleByTask: Map<string, string[]>
  // coût du temps passé (heures × taux), par tâche
  timeCostByTask: Map<string, number>
  // personnes rattachées au projet lui-même (responsable, membres)
  managerByProject: Map<string, string>
  membersByProject: Map<string, string[]>
  // libellé du « projet » qui regroupe les tâches sans projet
  noProjectLabel: string
}

export interface FolderRef {
  kind: FolderKind
  id: string
}

export interface FolderSummary {
  id: string
  kind: FolderKind
  name: string
  color: string | null
  subfolders: number // enfants directs
  tasks: number // descendants, tous niveaux
  documents: number // dans tout le dossier, sous-dossiers compris
  directDocuments: number // posés sur ce dossier lui-même
  people: string[]
  start: string | null
  end: string | null
  deadline: DeadlineState
  daysLeft: number | null // négatif = jours de retard
  budget: number
  spentMaterial: number
  spentTime: number
  spent: number
  // null quand il n'y a pas de budget : un taux sans base ne veut rien dire
  disbursementRate: number | null
  progress: number
}

const CLOSED = new Set(['done', 'canceled'])

const num = (v: unknown): number => {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

const clampPct = (v: number): number => Math.min(100, Math.max(0, Math.round(v)))

export const todayIso = (d: Date = new Date()): string => {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

const dayIndex = (iso: string): number => {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number)
  return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000)
}

export function daysBetween(fromIso: string, toIso: string): number {
  return dayIndex(toIso) - dayIndex(fromIso)
}

export function deadlineState(
  end: string | null,
  finished: boolean,
  today: string
): { state: DeadlineState; daysLeft: number | null } {
  if (finished) return { state: 'done', daysLeft: end ? daysBetween(today, end) : null }
  if (!end) return { state: 'none', daysLeft: null }
  const left = daysBetween(today, end)
  if (left < 0) return { state: 'late', daysLeft: left }
  if (left <= DEADLINE_SOON_DAYS) return { state: 'soon', daysLeft: left }
  return { state: 'ontrack', daysLeft: left }
}

// Noms sans doublon (casse et espaces ignorés), dans l'ordre de première apparition.
function uniqueNames(lists: Array<string[] | undefined | null>): string[] {
  const seen = new Set<string>()
  const out: string[] = []
  for (const list of lists) {
    for (const raw of list || []) {
      const name = (raw || '').trim()
      const key = name.toLocaleLowerCase()
      if (!name || seen.has(key)) continue
      seen.add(key)
      out.push(name)
    }
  }
  return out
}

// Personnes en charge de chaque tâche : les affectations multiples (table de
// liaison) d'abord, à défaut le nom saisi sur la tâche.
export function buildPeopleByTask(
  tasks: Pick<ProjectTask, 'id' | 'assignee'>[],
  assignments: { task_id: string; employee_id: string }[],
  employeeNames: Map<string, string>
): Map<string, string[]> {
  const byTask = new Map<string, string[]>()
  for (const a of assignments) {
    const name = employeeNames.get(a.employee_id)
    if (!name) continue
    const list = byTask.get(a.task_id)
    if (list) list.push(name)
    else byTask.set(a.task_id, [name])
  }
  for (const t of tasks) {
    const own = (t.assignee || '').trim()
    if (own) byTask.set(t.id, uniqueNames([byTask.get(t.id), [own]]))
  }
  return byTask
}

export function buildTimeCostByTask(
  entries: { task_id: string | null; duration_seconds: number | null; hourly_rate: number | null }[]
): Map<string, number> {
  const out = new Map<string, number>()
  for (const e of entries) {
    if (!e.task_id) continue
    const cost = (num(e.duration_seconds) / 3600) * num(e.hourly_rate)
    if (cost > 0) out.set(e.task_id, (out.get(e.task_id) || 0) + cost)
  }
  return out
}

interface FolderIndex {
  tasksById: Map<string, ProjectTask>
  childrenOf: Map<string, ProjectTask[]>
  rootsOfProject: Map<string, ProjectTask[]>
  docsByTask: Map<string, FolderDocument[]>
}

export function buildFolderIndex(src: Pick<FolderSources, 'tasks' | 'documents'>): FolderIndex {
  const tasksById = new Map(src.tasks.map((t) => [t.id, t]))
  const childrenOf = new Map<string, ProjectTask[]>()
  const rootsOfProject = new Map<string, ProjectTask[]>()
  for (const t of src.tasks) {
    const parentKnown = !!t.parent_id && t.parent_id !== t.id && tasksById.has(t.parent_id)
    if (parentKnown) {
      const list = childrenOf.get(t.parent_id as string)
      if (list) list.push(t)
      else childrenOf.set(t.parent_id as string, [t])
    } else {
      const key = t.project_id || NO_PROJECT_FOLDER
      const list = rootsOfProject.get(key)
      if (list) list.push(t)
      else rootsOfProject.set(key, [t])
    }
  }
  const docsByTask = new Map<string, FolderDocument[]>()
  for (const d of src.documents) {
    const list = docsByTask.get(d.task_id)
    if (list) list.push(d)
    else docsByTask.set(d.task_id, [d])
  }
  return { tasksById, childrenOf, rootsOfProject, docsByTask }
}

// Toutes les tâches sous `roots`, `roots` compris, en parcours en profondeur
// dans l'ordre des frères (l'ordre des personnes affichées en dépend). Une
// boucle de parenté ne fige rien.
function subtree(index: FolderIndex, roots: ProjectTask[]): ProjectTask[] {
  const out: ProjectTask[] = []
  const seen = new Set<string>()
  const stack = [...roots].reverse()
  while (stack.length) {
    const t = stack.pop() as ProjectTask
    if (seen.has(t.id)) continue
    seen.add(t.id)
    out.push(t)
    const kids = index.childrenOf.get(t.id) || []
    for (let i = kids.length - 1; i >= 0; i--) stack.push(kids[i])
  }
  return out
}

// Budget d'une tâche : le sien s'il est posé, sinon la somme de ses sous-tâches
// (jamais les deux, ce serait compter deux fois).
function taskBudget(index: FolderIndex, task: ProjectTask, seen = new Set<string>()): number {
  if (seen.has(task.id)) return 0
  seen.add(task.id)
  const own = num(task.budget)
  if (own > 0) return own
  return (index.childrenOf.get(task.id) || []).reduce((s, c) => s + taskBudget(index, c, seen), 0)
}

function childTasks(index: FolderIndex, parent: FolderRef): ProjectTask[] {
  return parent.kind === 'project' ? index.rootsOfProject.get(parent.id) || [] : index.childrenOf.get(parent.id) || []
}

function summarize(
  src: FolderSources,
  index: FolderIndex,
  ref: FolderRef,
  today: string
): FolderSummary | null {
  const direct = childTasks(index, ref)
  const inside = subtree(index, direct)

  let name: string
  let color: string | null = null
  let ownStart: string | null = null
  let ownEnd: string | null = null
  let ownProgress: number | null = null
  let finished = false
  let budget = 0
  let spentMaterial = 0
  let directDocs = 0
  let leadPeople: string[] = []
  let project: FolderProject | undefined
  let task: ProjectTask | undefined

  if (ref.kind === 'project') {
    if (ref.id === NO_PROJECT_FOLDER) {
      name = src.noProjectLabel
    } else {
      project = src.projects.find((p) => p.id === ref.id)
      if (!project) return null
      name = project.name
      color = project.color
      ownStart = project.start_date
      ownEnd = project.end_date
      ownProgress = project.progress
      finished = project.status === 'completed'
      spentMaterial = num(project.actual_cost)
      const manager = src.managerByProject.get(project.id)
      leadPeople = uniqueNames([manager ? [manager] : [], src.membersByProject.get(project.id)])
      budget = num(project.budget) > 0 ? num(project.budget) : direct.reduce((s, t) => s + taskBudget(index, t), 0)
    }
  } else {
    task = index.tasksById.get(ref.id)
    if (!task) return null
    name = task.title
    ownStart = task.start_date
    ownEnd = task.due_date
    ownProgress = task.progress
    finished = CLOSED.has(task.status)
    directDocs = index.docsByTask.get(task.id)?.length || 0
    budget = taskBudget(index, task)
  }

  // Le contenu du dossier : pour un projet, toutes ses tâches ; pour une tâche,
  // elle-même puis ses descendants.
  const scope = ref.kind === 'task' ? uniqueTasks([task as ProjectTask, ...inside]) : inside

  const documents = scope.reduce((s, t) => s + (index.docsByTask.get(t.id)?.length || 0), 0)
  const spentTime = scope.reduce((s, t) => s + (src.timeCostByTask.get(t.id) || 0), 0)
  const people = uniqueNames([leadPeople, ...scope.map((t) => src.peopleByTask.get(t.id))])

  const starts = scope.map((t) => t.start_date).filter((d): d is string => !!d)
  const ends = scope.map((t) => t.due_date).filter((d): d is string => !!d)
  const start = ownStart || (starts.length ? starts.reduce((a, b) => (a < b ? a : b)) : null)
  const end = ownEnd || (ends.length ? ends.reduce((a, b) => (a > b ? a : b)) : null)

  const progress = clampPct(ownProgress ?? 0)
  const dl = deadlineState(end, finished || progress >= 100, today)
  const spent = spentMaterial + spentTime

  return {
    id: ref.id,
    kind: ref.kind,
    name,
    color,
    subfolders: direct.length,
    tasks: ref.kind === 'task' ? scope.length - 1 : scope.length,
    documents,
    directDocuments: directDocs,
    people,
    start,
    end,
    deadline: dl.state,
    daysLeft: dl.daysLeft,
    budget,
    spentMaterial,
    spentTime,
    spent,
    disbursementRate: budget > 0 ? Math.round((spent / budget) * 100) : null,
    progress,
  }
}

function uniqueTasks(list: ProjectTask[]): ProjectTask[] {
  const seen = new Set<string>()
  return list.filter((t) => (seen.has(t.id) ? false : (seen.add(t.id), true)))
}

export function summarizeFolder(src: FolderSources, ref: FolderRef, today: string = todayIso()): FolderSummary | null {
  return summarize(src, buildFolderIndex(src), ref, today)
}

// Les dossiers que l'on voit en ouvrant `parent` : les projets à la racine, sinon
// les sous-dossiers du dossier ouvert (tâches de premier niveau, puis sous-tâches).
export function listFolders(
  src: FolderSources,
  parent: FolderRef | null,
  today: string = todayIso()
): FolderSummary[] {
  const index = buildFolderIndex(src)
  const refs: FolderRef[] = parent
    ? childTasks(index, parent).map((t) => ({ kind: 'task' as const, id: t.id }))
    : [
        ...src.projects.map((p) => ({ kind: 'project' as const, id: p.id })),
        ...((index.rootsOfProject.get(NO_PROJECT_FOLDER)?.length ?? 0) > 0
          ? [{ kind: 'project' as const, id: NO_PROJECT_FOLDER }]
          : []),
      ]
  const out: FolderSummary[] = []
  for (const r of refs) {
    const s = summarize(src, index, r, today)
    if (s) out.push(s)
  }
  return out
}

export function documentsOf(src: Pick<FolderSources, 'tasks' | 'documents'>, ref: FolderRef): FolderDocument[] {
  if (ref.kind !== 'task') return []
  return src.documents
    .filter((d) => d.task_id === ref.id)
    .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
}

// Le chemin « projet > tâche > sous-tâche » d'un dossier, pour le fil d'Ariane.
export function folderTrail(src: FolderSources, last: FolderRef | null): FolderRef[] {
  if (!last) return []
  if (last.kind === 'project') return [last]
  const index = buildFolderIndex(src)
  const chain: FolderRef[] = []
  const seen = new Set<string>()
  let cur = index.tasksById.get(last.id)
  while (cur && !seen.has(cur.id)) {
    seen.add(cur.id)
    chain.unshift({ kind: 'task', id: cur.id })
    const parent = cur.parent_id ? index.tasksById.get(cur.parent_id) : undefined
    if (parent) {
      cur = parent
    } else {
      chain.unshift({ kind: 'project', id: cur.project_id || NO_PROJECT_FOLDER })
      break
    }
  }
  return chain
}

export function filterFolders(folders: FolderSummary[], query: string): FolderSummary[] {
  const q = query.trim().toLocaleLowerCase()
  if (!q) return folders
  return folders.filter(
    (f) => f.name.toLocaleLowerCase().includes(q) || f.people.some((p) => p.toLocaleLowerCase().includes(q))
  )
}

// ---------- assemblage des sources ----------

export interface FolderProjectInput {
  id: string
  name: string
  color?: string | null
  budget?: number | string | null
  actual_cost?: number | string | null
  start_date?: string | null
  end_date?: string | null
  progress?: number | string | null
  manager_id?: string | null
  status?: string | null
}

export interface FolderRowsInput {
  documents: FolderDocument[]
  assignments: { task_id: string; employee_id: string }[]
  employees: { id: string; name: string }[]
  members: { project_id: string; employee_id: string }[]
  timeEntries: { task_id: string | null; duration_seconds: number | null; hourly_rate: number | null }[]
}

// Les lectures brutes + les tâches et projets déjà chargés → les sources d'une
// synthèse. Partagé par l'écran des dossiers et celui des points d'attention :
// les deux doivent compter la même chose.
export function assembleFolderSources(args: {
  rows: FolderRowsInput
  tasks: ProjectTask[]
  projects: FolderProjectInput[]
  noProjectLabel: string
  projectId?: string
}): FolderSources {
  const { rows, projectId } = args
  const employeeNames = new Map(rows.employees.map((e) => [e.id, e.name]))
  const tasks = projectId ? args.tasks.filter((t) => t.project_id === projectId) : args.tasks
  const projects = projectId ? args.projects.filter((p) => p.id === projectId) : args.projects

  const managerByProject = new Map<string, string>()
  for (const p of projects) {
    const name = p.manager_id ? employeeNames.get(p.manager_id) : undefined
    if (name) managerByProject.set(p.id, name)
  }
  const membersByProject = new Map<string, string[]>()
  for (const m of rows.members) {
    const name = employeeNames.get(m.employee_id)
    if (!name) continue
    const list = membersByProject.get(m.project_id)
    if (list) list.push(name)
    else membersByProject.set(m.project_id, [name])
  }

  return {
    projects: projects.map((p) => ({
      id: p.id,
      name: p.name,
      color: p.color || null,
      budget: num(p.budget),
      actual_cost: num(p.actual_cost),
      start_date: p.start_date || null,
      end_date: p.end_date || null,
      progress: num(p.progress),
      manager_id: p.manager_id || null,
      status: p.status || null,
    })),
    tasks,
    documents: rows.documents,
    peopleByTask: buildPeopleByTask(tasks, rows.assignments, employeeNames),
    timeCostByTask: buildTimeCostByTask(rows.timeEntries),
    managerByProject,
    membersByProject,
    noProjectLabel: args.noProjectLabel,
  }
}
