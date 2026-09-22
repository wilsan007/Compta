import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Search, Plus, LayoutGrid } from 'lucide-react'
import { DynamicTable } from '@/components/project-management/DynamicTable'
import { KanbanBoard } from '@/components/project-management/KanbanBoard'
import { GanttChart } from '@/components/project-management/GanttChart'
import { GraphView } from '@/components/project-management/GraphView'
import { PivotView } from '@/components/project-management/PivotView'
import { BurndownChart } from '@/components/project-management/BurndownChart'
import { MyTasksView } from '@/components/project-management/MyTasksView'
import { CalendarView } from '@/components/project-management/CalendarView'
import { LargeScreenView } from '@/components/project-management/LargeScreenView'
import { WorkloadView } from '@/components/project-management/WorkloadView'
import { ActivityView } from '@/components/project-management/ActivityView'
import { TimelineView } from '@/components/project-management/TimelineView'
import { NotificationsView } from '@/components/project-management/NotificationsView'
import { MindMapView } from '@/components/project-management/MindMapView'
import { BoxView } from '@/components/project-management/BoxView'
import { DocView } from '@/components/project-management/DocView'
import { ChatView } from '@/components/project-management/ChatView'
import { TaskCreationDialog } from '@/components/project-management/TaskCreationDialog'
import { Breadcrumb } from '@/components/ui'
import { TaskProvider, useTaskContext } from '@/contexts/TaskContext'
import { ProjectProvider } from '@/contexts/ProjectContext'
import type { TaskCreateInput } from '@/types/projectManagement'

type ViewType =
  | 'table' | 'kanban' | 'gantt' | 'graph' | 'pivot' | 'burndown'
  | 'my-tasks' | 'calendar' | 'large-screen' | 'workload'
  | 'activity' | 'timeline' | 'notifications'
  | 'mind-map' | 'box' | 'doc' | 'chat'

interface ProjectManagementPageProps {
  projectId?: string
  initialView?: ViewType
}

export function ProjectManagementPage({ projectId, initialView }: ProjectManagementPageProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tNav } = useTranslation('nav')
  const view: ViewType = initialView || 'table'
  const [searchQuery, setSearchQuery] = useState('')
  const [taskDialogOpen, setTaskDialogOpen] = useState(false)

  return (
    <div className="flex flex-col h-full">
      <Breadcrumb items={[{ label: tNav('groups.projectManagement') }, { label: t('title') }]} />

      {/* Top toolbar */}
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-[var(--color-border)] bg-[var(--color-surface)] gap-3">
        <div className="flex items-center gap-2 min-w-0">
          <div className="flex items-center justify-center w-7 h-7 rounded-lg bg-[var(--color-primary)]/10 text-[var(--color-primary)] flex-shrink-0">
            <LayoutGrid className="w-4 h-4" />
          </div>
          <div className="min-w-0">
            <h1 className="text-base font-semibold text-[var(--color-text)] truncate">{t('title')}</h1>
            <p className="text-xs text-[var(--color-text-secondary)] truncate">{t('subtitle')}</p>
          </div>
        </div>

        <div className="flex items-center gap-2 flex-shrink-0">
          <div className="relative hidden sm:block">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder={t('actions.search')}
              className="w-40 lg:w-56 pl-8 pr-3 py-1.5 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)] text-[var(--color-text)] placeholder:text-[var(--color-text-tertiary)] focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:border-transparent transition-all"
            />
          </div>
          <button
            onClick={() => setTaskDialogOpen(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg bg-[var(--color-primary)] text-white hover:bg-[var(--color-primary-dark)] transition-colors"
          >
            <Plus className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">{t('actions.newTask')}</span>
          </button>
        </div>
      </div>

      {/* Full-width content area */}
      <div className="flex-1 overflow-hidden bg-[var(--color-background)]">
        <ProjectProvider>
        <TaskProvider projectId={projectId}>
          <div className="h-full overflow-hidden">
            {view === 'table' && <DynamicTable projectId={projectId} />}
            {view === 'kanban' && <KanbanBoard projectId={projectId} />}
            {view === 'gantt' && <GanttChart projectId={projectId} />}
            {view === 'graph' && <GraphView projectId={projectId} />}
            {view === 'pivot' && <PivotView projectId={projectId} />}
            {view === 'burndown' && <BurndownChart projectId={projectId} />}
            {view === 'my-tasks' && <MyTasksView projectId={projectId} />}
            {view === 'calendar' && <CalendarView projectId={projectId} />}
            {view === 'large-screen' && <LargeScreenView projectId={projectId} />}
            {view === 'workload' && <WorkloadView projectId={projectId} />}
            {view === 'timeline' && <TimelineView projectId={projectId} />}
            {view === 'activity' && <ActivityView projectId={projectId} />}
            {view === 'notifications' && <NotificationsView />}
            {view === 'mind-map' && <MindMapView projectId={projectId} />}
            {view === 'box' && <BoxView projectId={projectId} />}
            {view === 'doc' && <DocView projectId={projectId} />}
            {view === 'chat' && <ChatView projectId={projectId} />}
            <ToolbarTaskDialog
              open={taskDialogOpen}
              onClose={() => setTaskDialogOpen(false)}
              projectId={projectId}
            />
          </div>
        </TaskProvider>
        </ProjectProvider>
      </div>
    </div>
  )
}

function ToolbarTaskDialog({ open, onClose, projectId }: { open: boolean; onClose: () => void; projectId?: string }) {
  const { createTask } = useTaskContext()
  const handleCreate = (task: TaskCreateInput) => {
    createTask(task)
  }
  return (
    <TaskCreationDialog
      open={open}
      onClose={onClose}
      onConfirm={handleCreate}
      projectId={projectId}
    />
  )
}
