import { useTranslation } from 'react-i18next'
import { DropdownMenu } from './DropdownMenu'
import { MoreVertical, Pencil, Copy, Trash2 } from 'lucide-react'

interface TaskRowActionsProps {
  onEdit: () => void
  onDuplicate: () => void
  onDelete: () => void
}

export function TaskRowActions({ onEdit, onDuplicate, onDelete }: TaskRowActionsProps) {
  const { t } = useTranslation('common')

  return (
    <DropdownMenu
      trigger={
        <button className="p-1 rounded hover:bg-[var(--color-neutral-100)] opacity-0 group-hover:opacity-100 transition-opacity" aria-label={t('actions.more')} title={t('actions.more')}>
          <MoreVertical className="w-4 h-4 text-[var(--color-text-secondary)]" aria-hidden="true" />
        </button>
      }
      items={[
        { label: t('actions.edit'), icon: <Pencil className="w-3.5 h-3.5" />, onClick: onEdit },
        { label: t('actions.duplicate'), icon: <Copy className="w-3.5 h-3.5" />, onClick: onDuplicate },
        { divider: true, label: '', onClick: () => {} },
        { label: t('actions.delete'), icon: <Trash2 className="w-3.5 h-3.5" />, onClick: onDelete, variant: 'danger' },
      ]}
    />
  )
}
