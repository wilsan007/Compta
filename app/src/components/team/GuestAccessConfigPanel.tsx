// GuestAccessConfigPanel — UI for configuring granular guest permissions
// Used in TeamPage EditRoleModal when projectManagement role is 'guest'

import { useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Eye, EyeOff } from 'lucide-react'
import type { GuestPermissions } from '@/types/documents'

interface GuestAccessConfigPanelProps {
  permissions: GuestPermissions
  onChange: (permissions: GuestPermissions) => void
}

const VIEW_OPTIONS: { key: keyof GuestPermissions['views']; labelKey: string }[] = [
  { key: 'table', labelKey: 'team:guestViews.table' },
  { key: 'kanban', labelKey: 'team:guestViews.kanban' },
  { key: 'gantt', labelKey: 'team:guestViews.gantt' },
  { key: 'calendar', labelKey: 'team:guestViews.calendar' },
  { key: 'timeline', labelKey: 'team:guestViews.timeline' },
  { key: 'box', labelKey: 'team:guestViews.box' },
  { key: 'mindmap', labelKey: 'team:guestViews.mindmap' },
  { key: 'graph', labelKey: 'team:guestViews.graph' },
  { key: 'pivot', labelKey: 'team:guestViews.pivot' },
  { key: 'burndown', labelKey: 'team:guestViews.burndown' },
  { key: 'workload', labelKey: 'team:guestViews.workload' },
  { key: 'activity', labelKey: 'team:guestViews.activity' },
  { key: 'documents', labelKey: 'team:guestViews.documents' },
  { key: 'chat', labelKey: 'team:guestViews.chat' },
]

const PER_PROJECT_OPTIONS: { key: keyof GuestPermissions['perProject']; labelKey: string }[] = [
  { key: 'tasks', labelKey: 'team:guestPerProject.tasks' },
  { key: 'subtasks', labelKey: 'team:guestPerProject.subtasks' },
  { key: 'documents', labelKey: 'team:guestPerProject.documents' },
  { key: 'comments', labelKey: 'team:guestPerProject.comments' },
  { key: 'addComments', labelKey: 'team:guestPerProject.addComments' },
  { key: 'addRemarks', labelKey: 'team:guestPerProject.addRemarks' },
  { key: 'assignees', labelKey: 'team:guestPerProject.assignees' },
  { key: 'dates', labelKey: 'team:guestPerProject.dates' },
  { key: 'budget', labelKey: 'team:guestPerProject.budget' },
  { key: 'progress', labelKey: 'team:guestPerProject.progress' },
]

export function GuestAccessConfigPanel({ permissions, onChange }: GuestAccessConfigPanelProps) {
  const { t } = useTranslation(['hr', 'common'])
  const [projectIdsInput, setProjectIdsInput] = useState(
    permissions.projectIds?.join(', ') || ''
  )

  const toggleView = useCallback((key: keyof GuestPermissions['views']) => {
    onChange({
      ...permissions,
      views: { ...permissions.views, [key]: !permissions.views[key] },
    })
  }, [permissions, onChange])

  const togglePerProject = useCallback((key: keyof GuestPermissions['perProject']) => {
    onChange({
      ...permissions,
      perProject: { ...permissions.perProject, [key]: !permissions.perProject[key] },
    })
  }, [permissions, onChange])

  const handleProjectIdsChange = useCallback((value: string) => {
    setProjectIdsInput(value)
    const ids = value.split(',').map(s => s.trim()).filter(Boolean)
    onChange({ ...permissions, projectIds: ids })
  }, [permissions, onChange])

  return (
    <div className="border border-[var(--color-border)] rounded-lg p-4 space-y-4 max-h-96 overflow-y-auto">
      <p className="text-sm font-medium">{t('team:guestConfigTitle')}</p>

      {/* Project IDs */}
      <div className="space-y-1">
        <label className="text-xs font-medium text-[var(--color-text-secondary)]">
          {t('team:guestProjectIds')}
        </label>
        <input
          type="text"
          value={projectIdsInput}
          onChange={(e) => handleProjectIdsChange(e.target.value)}
          placeholder={t('team:guestProjectIdsPlaceholder')}
          className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
        />
        <p className="text-xs text-[var(--color-text-secondary)]">
          {t('team:guestProjectIdsHelp')}
        </p>
      </div>

      {/* Views */}
      <div className="space-y-2">
        <p className="text-xs font-medium text-[var(--color-text-secondary)]">
          {t('team:guestViewsTitle')}
        </p>
        <div className="grid grid-cols-2 gap-2">
          {VIEW_OPTIONS.map(opt => {
            const checked = permissions.views?.[opt.key] || false
            return (
              <button
                key={opt.key}
                onClick={() => toggleView(opt.key)}
                className={`flex items-center gap-2 px-2 py-1.5 text-xs rounded border transition-colors ${
                  checked
                    ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]'
                    : 'bg-transparent text-[var(--color-text-secondary)] border-[var(--color-border)]'
                }`}
              >
                {checked ? <Eye className="h-3 w-3" /> : <EyeOff className="h-3 w-3" />}
                {t(opt.labelKey)}
              </button>
            )
          })}
        </div>
      </div>

      {/* Per-project permissions */}
      <div className="space-y-2">
        <p className="text-xs font-medium text-[var(--color-text-secondary)]">
          {t('team:guestPerProjectTitle')}
        </p>
        <div className="grid grid-cols-2 gap-2">
          {PER_PROJECT_OPTIONS.map(opt => {
            const checked = permissions.perProject?.[opt.key] || false
            return (
              <button
                key={opt.key}
                onClick={() => togglePerProject(opt.key)}
                className={`flex items-center gap-2 px-2 py-1.5 text-xs rounded border transition-colors ${
                  checked
                    ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]'
                    : 'bg-transparent text-[var(--color-text-secondary)] border-[var(--color-border)]'
                }`}
              >
                {checked ? <Eye className="h-3 w-3" /> : <EyeOff className="h-3 w-3" />}
                {t(opt.labelKey)}
              </button>
            )
          })}
        </div>
      </div>
    </div>
  )
}
