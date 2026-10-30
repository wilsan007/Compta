import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { Plus, LayoutGrid } from 'lucide-react'
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
import { ProjectFoldersView } from '@/components/project-management/ProjectFoldersView'
import { AttentionView } from '@/components/project-management/AttentionView'
import { ResourceUsageView } from '@/components/project-management/ResourceUsageView'
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
  | 'folders' | 'resources' | 'attention'

interface ProjectManagementPageProps {
  projectId?: string
  initialView?: ViewType
}

export function ProjectManagementPage({ projectId, initialView }: ProjectManagementPageProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tNav } = useTranslation('nav')
  const view: ViewType = initialView || 'table'
  const [taskDialogOpen, setTaskDialogOpen] = useState(false)

  return (
    <div className="flex flex-col h-full">
      {/* Vue tableau : ni fil d'Ariane ni bandeau « Gestion de Projets » — le
          tableau dynamique a sa propre barre (titre, création, export) et prend
          toute la page (demandé le 25/10). Les autres vues gardent le bandeau. */}
      {view !== 'table' && (
      <>
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

        {/* Le champ de recherche qui vivait ici n'était lu par AUCUNE vue (placebo). */}
        <div className="flex items-center gap-2 flex-shrink-0">
          <button
            onClick={() => setTaskDialogOpen(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg bg-[var(--color-primary)] text-white hover:bg-[var(--color-primary-dark)] transition-colors"
          >
            <Plus className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">{t('actions.newTask')}</span>
          </button>
        </div>
      </div>
      </>
      )}

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
            {view === 'folders' && <ProjectFoldersView projectId={projectId} />}
            {view === 'resources' && <ResourceUsageView projectId={projectId} />}
            {view === 'attention' && <AttentionView projectId={projectId} />}
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
  const { createTask, allTasks } = useTaskContext()
  const { t } = useTranslation('taskManagement')
  const { toast } = useToast()
  const handleCreate = (task: TaskCreateInput) => {
    createTask(task).catch((err: Error) => toast('error', t('saveError'), err.message))
  }
  return (
    <TaskCreationDialog
      open={open}
      onClose={onClose}
      onConfirm={handleCreate}
      projectId={projectId}
      parentCandidates={allTasks}
    />
  )
}
