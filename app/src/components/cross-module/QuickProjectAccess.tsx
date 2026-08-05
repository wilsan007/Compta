import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { QuickAccessModal } from './QuickAccessModal'
import { Button, EmptyState, Table, TableRow, TableCell, Badge } from '@/components/ui'
import { getProjects } from '@/lib/queries'
import { useModuleAwareAccess } from './useModuleAwareAccess'
import { FolderKanban, ExternalLink, Search } from 'lucide-react'
import type { Project } from '@/types'

interface QuickProjectAccessProps {
  onClose: () => void
  onSaved?: (project: Project) => void
  forceInline?: boolean
}

/**
 * Cross-module Quick Access for Projects.
 * - If projectManagement module is active → link to /project-management
 * - If projectManagement module is NOT active → inline list (read-only, projects are created in PM)
 */
export function QuickProjectAccess({ onClose, onSaved, forceInline }: QuickProjectAccessProps) {
  const { t } = useTranslation('crossModule')
  const { t: tCommon } = useTranslation('common')
  const { getAccessStrategy } = useModuleAwareAccess()

  const strategy = forceInline ? 'inline' : getAccessStrategy('projectManagement')
  const [projects, setProjects] = useState<Project[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setProjects(await getProjects())
    } catch {
      /* ignore */
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (strategy === 'inline') loadData()
  }, [strategy, loadData])

  const filtered = projects.filter((p) =>
    !search || p.name.toLowerCase().includes(search.toLowerCase()),
  )

  if (strategy === 'full' && !forceInline) {
    return (
      <QuickAccessModal title={t('project.title')} onClose={onClose}>
        <EmptyState
          icon={<FolderKanban className="w-8 h-8" />}
          title={t('project.moduleActive')}
          description={t('project.moduleActiveDescription')}
          action={
            <Link to="/project-management" onClick={onClose}>
              <Button><ExternalLink className="w-4 h-4" /> {t('project.goToProjects')}</Button>
            </Link>
          }
        />
      </QuickAccessModal>
    )
  }

  return (
    <QuickAccessModal title={t('project.title')} onClose={onClose}>
      <div className="space-y-4">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              placeholder={t('project.search')}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)]"
            />
          </div>
        </div>

        {loading ? (
          <p className="text-sm text-[var(--color-text-secondary)] text-center py-8">{tCommon('common.loading')}</p>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<FolderKanban className="w-8 h-8" />}
            title={t('project.noProjects')}
            description={t('project.noProjectsDescription')}
          />
        ) : (
          <Table headers={[t('project.name'), t('project.status'), t('project.budget')]}>
            {filtered.slice(0, 20).map((p) => (
              <TableRow key={p.id} onClick={() => { onSaved?.(p); onClose() }}>
                <TableCell className="font-medium">{p.name}</TableCell>
                <TableCell>
                  <Badge variant={p.status === 'active' ? 'success' : p.status === 'completed' ? 'primary' : p.status === 'on_hold' ? 'warning' : 'neutral'}>
                    {t(`project.statuses.${p.status}`)}
                  </Badge>
                </TableCell>
                <TableCell className="font-mono text-xs">{Number(p.budget).toLocaleString()}</TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </div>
    </QuickAccessModal>
  )
}
