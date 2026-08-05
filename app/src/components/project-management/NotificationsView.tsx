import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Bell, CheckCheck, Circle } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { getNotifications, markNotificationRead, markAllNotificationsRead } from '@/lib/queries/projectManagementSprint1'
import type { ProjectNotification } from '@/types/projectManagement'

export function NotificationsView() {
  const { t } = useTranslation('taskManagement')
  const { user } = useAuth()
  const [notifications, setNotifications] = useState<ProjectNotification[]>([])
  const [loading, setLoading] = useState(true)
  const [showUnread, setShowUnread] = useState(false)

  const loadNotifications = useCallback(async () => {
    if (!user?.id) return
    setLoading(true)
    try {
      const data = await getNotifications(user.id, showUnread)
      setNotifications(data)
    } catch {
      // ignore
    } finally {
      setLoading(false)
    }
  }, [showUnread, user?.id])

  useEffect(() => {
    loadNotifications()
  }, [loadNotifications])

  const handleMarkRead = async (id: string) => {
    try {
      await markNotificationRead(id)
      setNotifications((prev) => prev.map((n) => (n.id === id ? { ...n, is_read: true } : n)))
    } catch {
      // ignore
    }
  }

  const handleMarkAllRead = async () => {
    if (!user?.id) return
    try {
      await markAllNotificationsRead(user.id)
      setNotifications((prev) => prev.map((n) => ({ ...n, is_read: true })))
    } catch {
      // ignore
    }
  }

  const typeIcons: Record<string, string> = {
    task_assigned: '👤',
    status_changed: '🔄',
    comment_added: '💬',
    due_date_approaching: '⏰',
    task_overdue: '🚨',
    mention: '@',
    watcher_update: '👁️',
    project_member_added: '👥',
    task_completed: '✅',
    progress_changed: '📊',
    payment_overdue: '💳',
    stock_critical: '📦',
    stock_warning: '⚠️',
    budget_exceeded: '💰',
    approval_request: '🔐',
    invitation_pending: '✉️',
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  const unreadCount = notifications.filter((n) => !n.is_read).length

  return (
    <div className="h-full overflow-auto p-4">
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Bell className="w-5 h-5" />
            {t('notifications.title')}
            {unreadCount > 0 && (
              <span className="px-2 py-0.5 rounded-full bg-red-500 text-white text-xs">{unreadCount}</span>
            )}
          </h2>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowUnread(!showUnread)}
            className={`px-3 py-1 text-xs rounded-lg transition-colors ${
              showUnread
                ? 'bg-[var(--color-primary)] text-white'
                : 'bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]'
            }`}
          >
            {t('notifications.unread')}
          </button>
          {unreadCount > 0 && (
            <button
              onClick={handleMarkAllRead}
              className="flex items-center gap-1 px-3 py-1 text-xs rounded-lg bg-[var(--color-neutral-100)] hover:bg-[var(--color-neutral-200)] transition-colors"
            >
              <CheckCheck className="w-3 h-3" />
              {t('notifications.markAllRead')}
            </button>
          )}
        </div>
      </div>

      {notifications.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 gap-2">
          <Bell className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" />
          <p className="text-[var(--color-text)] font-medium">{t('notifications.noNotifications')}</p>
          <p className="text-sm text-[var(--color-text-secondary)]">{t('notifications.noNotificationsDesc')}</p>
        </div>
      ) : (
        <div className="space-y-1">
          {notifications.map((notif) => (
            <div
              key={notif.id}
              className={`flex items-start gap-3 p-3 rounded-lg border transition-colors cursor-pointer ${
                notif.is_read
                  ? 'border-[var(--color-border)] bg-[var(--color-surface)]'
                  : 'border-[var(--color-primary)] bg-[var(--color-primary)]/5'
              }`}
              onClick={() => !notif.is_read && handleMarkRead(notif.id)}
            >
              <span className="text-lg flex-shrink-0">{typeIcons[notif.notification_type] || '🔔'}</span>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium">{notif.title}</span>
                  {!notif.is_read && <Circle className="w-2 h-2 fill-[var(--color-primary)] text-[var(--color-primary)]" />}
                </div>
                {notif.message && <p className="text-xs text-[var(--color-text-secondary)] mt-0.5">{notif.message}</p>}
                <span className="text-[10px] text-[var(--color-text-secondary)] mt-1 block">
                  {new Date(notif.created_at).toLocaleString()}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
