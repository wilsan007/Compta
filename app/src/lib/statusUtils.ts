import { useTranslation } from 'react-i18next'

type StatusVariant = 'success' | 'warning' | 'danger' | 'neutral' | 'primary'

const statusVariantMap: Record<string, StatusVariant> = {
  draft: 'neutral',
  sent: 'primary',
  viewed: 'primary',
  paid: 'success',
  overdue: 'danger',
  cancelled: 'neutral',
  partial: 'warning',
  accepted: 'success',
  rejected: 'danger',
  pending: 'warning',
  approved: 'success',
  submitted: 'primary',
  active: 'success',
  inactive: 'neutral',
  on_leave: 'warning',
  completed: 'success',
  on_hold: 'warning',
  fully_depreciated: 'neutral',
  disposed: 'neutral',
  recurring: 'primary',
  applied: 'success',
  open: 'primary',
  closed: 'neutral',
  in_progress: 'warning',
  validated: 'success',
  rejected_status: 'danger',
  confirmed: 'success',
  delivered: 'success',
  received: 'primary',
  shipped: 'primary',
  planned: 'primary',
  cancelled_status: 'neutral',
  maintenance: 'warning',
  worn: 'warning',
  ended: 'neutral',
  suspended: 'warning',
  terminated: 'danger',
  consumed: 'success',
}

export function useStatusLabels() {
  const { t } = useTranslation('common')

  function getStatusLabel(status: string): string {
    const key = `status.${status}`
    const label = t(key)
    return label === key ? status : label
  }

  function getStatusVariant(status: string): StatusVariant {
    return statusVariantMap[status] || 'neutral'
  }

  function getStatusInfo(status: string): { label: string; variant: StatusVariant } {
    return {
      label: getStatusLabel(status),
      variant: getStatusVariant(status),
    }
  }

  return { getStatusLabel, getStatusVariant, getStatusInfo }
}

export { statusVariantMap }
export type { StatusVariant }
