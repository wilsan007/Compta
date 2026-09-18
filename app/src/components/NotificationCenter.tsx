// @ts-nocheck
import { useEffect, useState, useRef } from 'react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { supabase } from '@/lib/supabase'
import { Bell, Check, X, AlertTriangle, Info, CheckCircle, AlertCircle } from 'lucide-react'

interface Notification {
  id: string
  category: string
  severity: 'info' | 'warning' | 'error' | 'success'
  title: string
  message: string
  link: string | null
  read_at: string | null
  created_at: string
}

const SEVERITY_ICONS = {
  info: Info,
  warning: AlertTriangle,
  error: AlertCircle,
  success: CheckCircle,
}

const SEVERITY_COLORS = {
  info: 'text-[var(--color-primary)]',
  warning: 'text-[var(--color-warning)]',
  error: 'text-[var(--color-danger)]',
  success: 'text-[var(--color-success)]',
}

export function NotificationCenter() {
  const { _t } = useTranslation()
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [notifications, setNotifications] = useState<Notification[]>([])
  const [unreadCount, setUnreadCount] = useState(0)
  const [loading, setLoading] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  async function loadNotifications() {
    setLoading(true)
    try {
      const [listRes, countRes] = await Promise.all([
        supabase.from('notifications').select('*').order('created_at', { ascending: false }).limit(20),
        supabase.rpc('get_unread_notification_count'),
      ])
      if (listRes.data) setNotifications(listRes.data as Notification[])
      if (typeof countRes.data === 'number') setUnreadCount(countRes.data)
    } catch (err: any) {
      console.error("catch:", err)
      // Table may not exist — silently ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setLoading(false)
    }
  }

  async function markRead(id: string) {
    try {
      await supabase.rpc('mark_notification_read', { p_notification_id: id })
      setNotifications(prev => prev.map(n => n.id === id ? { ...n, read_at: new Date().toISOString() } : n))
      setUnreadCount(prev => Math.max(0, prev - 1))
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  async function markAllRead() {
    try {
      await supabase.rpc('mark_all_notifications_read')
      setNotifications(prev => prev.map(n => ({ ...n, read_at: n.read_at || new Date().toISOString() })))
      setUnreadCount(0)
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
  }

  useEffect(() => {
    if (open) loadNotifications().catch(err => console.error('loadNotifications:', err))
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [open])

  useEffect(() => {
    loadNotifications().catch(err => console.error('loadNotifications:', err))
    const channel = supabase
      .channel('notifications')
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications' },
        (payload) => {
          setNotifications(prev => [payload.new as Notification, ...prev])
          setUnreadCount(prev => prev + 1)
        }
      )
      .on('postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'notifications' },
        (payload) => {
          setNotifications(prev => prev.map(n => n.id === (payload.new as Notification).id ? payload.new as Notification : n))
          setUnreadCount(prev => prev.filter(n => !n.read_at).length)
        }
      )
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  // oxlint-disable-next-line react-hooks/exhaustive-deps -- chargement volontairement limite aux valeurs listees
  }, [])

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen(!open)}
        className="relative p-2 rounded-lg hover:bg-[var(--color-neutral-100)]"
        title="Notifications"
      >
        <Bell className="w-5 h-5" />
        {unreadCount > 0 && (
          <span className="absolute -top-0.5 -right-0.5 bg-[var(--color-danger)] text-white text-[10px] font-bold rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1">
            {unreadCount > 99 ? '99+' : unreadCount}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 mt-2 w-96 bg-[var(--color-surface)] border border-[var(--color-border)] rounded-lg shadow-lg z-50 max-h-[500px] flex flex-col">
          <div className="flex items-center justify-between p-3 border-b border-[var(--color-border)]">
            <h3 className="font-semibold text-sm">Notifications</h3>
            <div className="flex gap-2">
              {unreadCount > 0 && (
                <button onClick={markAllRead} className="text-xs text-[var(--color-primary)] hover:underline flex items-center gap-1">
                  <Check className="w-3 h-3" /> Tout marquer lu
                </button>
              )}
              <button onClick={() => setOpen(false)} className="text-[var(--color-text-secondary)] hover:text-[var(--color-text)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}>
                <X className="w-4 h-4" aria-hidden="true" /></button>
            </div>
          </div>

          <div className="overflow-y-auto flex-1">
            {loading ? (
              <div className="p-4 text-center text-sm text-[var(--color-text-secondary)]">Chargement...</div>
            ) : notifications.length === 0 ? (
              <div className="p-8 text-center text-sm text-[var(--color-text-secondary)]">
                <Bell className="w-8 h-8 mx-auto mb-2 opacity-30" />
                Aucune notification
              </div>
            ) : (
              notifications.map(n => {
                const Icon = SEVERITY_ICONS[n.severity] || Info
                return (
                  <div
                    key={n.id}
                    className={`p-3 border-b border-[var(--color-border)] hover:bg-[var(--color-neutral-50)] cursor-pointer ${!n.read_at ? 'bg-[var(--color-primary-50)]' : ''}`}
                    onClick={() => {
                      if (!n.read_at) markRead(n.id)
                      if (n.link) window.location.href = n.link
                    }}
                  >
                    <div className="flex gap-3">
                      <Icon className={`w-5 h-5 flex-shrink-0 mt-0.5 ${SEVERITY_COLORS[n.severity] || SEVERITY_COLORS.info}`} />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between gap-2">
                          <p className="font-medium text-sm truncate">{n.title}</p>
                          {!n.read_at && <span className="w-2 h-2 bg-[var(--color-primary)] rounded-full flex-shrink-0" />}
                        </div>
                        <p className="text-xs text-[var(--color-text-secondary)] mt-0.5 line-clamp-2">{n.message}</p>
                        <p className="text-[10px] text-[var(--color-text-tertiary)] mt-1">
                          {new Date(n.created_at).toLocaleString('fr-FR')}
                        </p>
                      </div>
                    </div>
                  </div>
                )
              })
            )}
          </div>
        </div>
      )}
    </div>
  )
}
