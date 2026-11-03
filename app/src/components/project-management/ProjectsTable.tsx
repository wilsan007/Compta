import { useEffect, useMemo, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { getEmployeesShared } from '@/lib/employeesShared'
import { orderAsTree } from '@/lib/taskTree'
import type { ProjectTask } from '@/types/projectManagement'
import { ResizablePanel } from './ResizablePanel'
import { Pill, STATUS_STYLE } from './table/kit'
import { ProgressCell } from './table/cells'

export interface ProjectCard {
  id: string
  name: string
  status: string
  progress: number
  manager_id: string | null
  start_date: string | null
  end_date: string | null
}

interface ProjectsTableProps {
  projects: ProjectCard[]
  tasks: ProjectTask[]
  projectColorMap: Map<string, string>
}

const PROJECT_STATUS_STYLE: Record<string, string> = {
  planning: 'bg-gray-500 text-white border-gray-500',
  active: 'bg-blue-500 text-white border-blue-500',
  completed: 'bg-green-500 text-white border-green-500',
  on_hold: 'bg-yellow-500 text-white border-yellow-500',
  cancelled: 'bg-gray-400 text-white border-gray-400',
}

// Le mode PROJETS du tableau, comme la vue projets de wadashaqayn : la liste des
// projets (numérotés, colorés) à gauche, leurs tâches à droite ; un clic sur un
// projet fait défiler jusqu'à ses tâches.
export function ProjectsTable({ projects, tasks, projectColorMap }: ProjectsTableProps) {
  const { t } = useTranslation('taskManagement')
  const [selected, setSelected] = useState<string | null>(null)
  const [managers, setManagers] = useState<Map<string, string>>(new Map())
  const tasksRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    getEmployeesShared()
      .then((list) => setManagers(new Map(list.map((e) => [e.id, e.name]))))
      .catch(() => setManagers(new Map()))
  }, [])

  const ordered = useMemo(() => orderAsTree(tasks), [tasks])
  const byProject = useMemo(() => {
    const m = new Map<string, ProjectTask[]>()
    for (const task of ordered) {
      const k = task.project_id && projects.some((p) => p.id === task.project_id) ? task.project_id : ''
      const list = m.get(k)
      if (list) list.push(task)
      else m.set(k, [task])
    }
    return m
  }, [ordered, projects])

  const focus = (id: string) => {
    setSelected(id)
    setTimeout(() => {
      const el = document.getElementById(`project-tasks-${id}`)
      const box = tasksRef.current
      if (el && box) box.scrollTo({ top: el.offsetTop - box.offsetTop - 20, behavior: 'smooth' })
    }, 50)
  }

  const statusLabel = (s: string) => t(`dyn.projectStatus.${s}`, { defaultValue: s })

  const list = (
    <div className="h-full border-e border-[var(--color-border)]">
      <div className="border-b border-[var(--color-border)] bg-[var(--color-neutral-50)] p-4">
        <h3 className="text-lg font-semibold">📁 {t('gantt.projects')}</h3>
      </div>
      <div className="max-h-[600px] space-y-3 overflow-y-auto p-4">
        {projects.map((p, i) => {
          const color = projectColorMap.get(p.id) || '#97a0af'
          const n = (byProject.get(p.id) || []).filter((x) => !x.parent_id).length
          return (
            <button
              key={p.id}
              type="button"
              onClick={() => focus(p.id)}
              className={cn(
                'card w-full p-4 text-left transition-all',
                selected === p.id ? 'shadow-lg ring-2 ring-[var(--color-primary)]' : 'hover:shadow-md'
              )}
            >
              <div className="space-y-3">
                <div className="flex items-center justify-between gap-2">
                  <div className="flex min-w-0 items-center gap-2">
                    <span className="rounded px-2 py-1 text-sm font-bold" style={{ backgroundColor: `${color}33`, color }}>#{i + 1}</span>
                    <h4 className="truncate text-[1.1rem] font-bold" style={{ color }}>{p.name}</h4>
                  </div>
                  <Pill className={PROJECT_STATUS_STYLE[p.status] || 'bg-gray-500 text-white'}>{statusLabel(p.status)}</Pill>
                </div>
                <div className="space-y-2">
                  <div className="text-sm text-[var(--color-text-secondary)]">
                    {t('dyn.manager', { name: (p.manager_id && managers.get(p.manager_id)) || t('dyn.unassigned') })}
                  </div>
                  <ProgressCell value={p.progress || 0} color={color} small={false} />
                  <div className="text-xs text-[var(--color-text-tertiary)]">{t('dyn.tasksCount', { count: n })}</div>
                </div>
              </div>
            </button>
          )
        })}
        {projects.length === 0 && <p className="py-8 text-center text-sm text-[var(--color-text-tertiary)]">{t('projectsTable.empty')}</p>}
      </div>
    </div>
  )

  const taskCard = (task: ProjectTask, color: string) => {
    const sub = !!task.parent_id
    return (
      <div
        key={task.id}
        className={cn('card border-s-4 p-3 transition-all', sub && 'ms-8 border-s-[3px] italic opacity-85')}
        style={{ borderInlineStartColor: color }}
      >
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0 flex-1">
            <h5 className={cn('truncate font-medium', sub && 'text-[var(--color-text-secondary)]')}>{task.title}</h5>
            <div className="text-sm text-[var(--color-text-tertiary)]">{t('dyn.assignedToName', { name: task.assignee || t('dyn.unassigned') })}</div>
          </div>
          <div className="space-y-1 text-right">
            <Pill className={STATUS_STYLE[task.status]}>{t(`status.${task.status}`)}</Pill>
            <ProgressCell value={task.progress || 0} color={color} small={false} />
          </div>
        </div>
      </div>
    )
  }

  const right = (
    <div className="h-full">
      <div className="border-b border-[var(--color-border)] bg-[var(--color-neutral-50)] p-4">
        <h3 className="text-lg font-semibold">📝 {t('dyn.tasksAssociated')}</h3>
        <p className="mt-1 text-xs text-[var(--color-text-tertiary)]">{t('dyn.clickProjectHint')}</p>
      </div>
      <div ref={tasksRef} className="relative max-h-[600px] space-y-4 overflow-y-auto p-4">
        {projects.map((p, i) => {
          const list = byProject.get(p.id) || []
          if (list.length === 0) return null
          const color = projectColorMap.get(p.id) || '#97a0af'
          const on = selected === p.id
          return (
            <div key={p.id} id={`project-tasks-${p.id}`} className={cn('space-y-2 transition-all', on && 'rounded-lg bg-[color-mix(in_srgb,var(--color-primary)_5%,transparent)] p-3 ring-2 ring-[color-mix(in_srgb,var(--color-primary)_30%,transparent)]')}>
              <div className={cn('flex items-center gap-2 border-b pb-1 text-[1.1rem] font-bold', on ? 'border-[var(--color-primary)]' : 'border-[var(--color-border)]')} style={{ color }}>
                <span className="rounded px-2 py-0.5 text-sm font-bold" style={{ backgroundColor: `${color}33`, color }}>#{i + 1}</span>
                📁 {p.name}
                {on && <span className="ms-2 text-xs font-normal text-[var(--color-primary)]">{t('dyn.selectedProject')}</span>}
              </div>
              <div className="flex flex-col space-y-2 ps-4">{list.map((task) => taskCard(task, color))}</div>
            </div>
          )
        })}
        {(byProject.get('') || []).length > 0 && (
          <div className="space-y-2">
            <div className="border-b border-[var(--color-border)] pb-1 font-bold text-[var(--color-text-secondary)]">📝 {t('dyn.tasksWithoutProject')}</div>
            <div className="space-y-2 ps-4">{(byProject.get('') || []).map((task) => taskCard(task, '#97a0af'))}</div>
          </div>
        )}
      </div>
    </div>
  )

  return (
    <div className="overflow-hidden rounded-lg border border-[var(--color-border)]" style={{ height: 680 }}>
      <ResizablePanel left={list} right={right} initialLeftWidth={40} minLeftWidth={30} maxLeftWidth={60} />
    </div>
  )
}
