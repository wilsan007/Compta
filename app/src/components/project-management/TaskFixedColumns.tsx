import { useTranslation } from 'react-i18next'

export function TaskFixedColumns() {
  const { t } = useTranslation('taskManagement')

  const columns = [
    { key: 'title', label: t('columns.title'), width: '250px' },
    { key: 'project', label: t('columns.project'), width: '120px' },
    { key: 'assignee', label: t('columns.assignee'), width: '100px' },
    { key: 'status', label: t('columns.status'), width: '110px' },
    { key: 'priority', label: t('columns.priority'), width: '90px' },
    { key: 'startDate', label: t('columns.startDate'), width: '110px' },
    { key: 'dueDate', label: t('columns.dueDate'), width: '110px' },
    { key: 'effort', label: t('columns.effort'), width: '70px' },
    { key: 'progress', label: t('columns.progress'), width: '100px' },
    { key: 'actions', label: t('columns.actions'), width: '80px' },
    { key: 'documents', label: t('columns.documents'), width: '50px' },
    { key: 'comments', label: t('columns.comments'), width: '50px' },
  ]

  return (
    <thead className="sticky top-0 z-20">
      <tr className="bg-gradient-to-r from-[var(--color-primary)] to-[var(--color-primary-dark,--color-primary)] text-white">
        {columns.map((col) => (
          <th
            key={col.key}
            className="px-3 py-2 text-left text-xs font-semibold whitespace-nowrap"
            style={{ width: col.width, minWidth: col.width }}
          >
            {col.label}
          </th>
        ))}
      </tr>
    </thead>
  )
}
