import { createContext, useContext, useState, useCallback, type ReactNode } from 'react'
import { CheckCircle, AlertCircle, Info, XCircle, X } from 'lucide-react'
import { cn } from '@/lib/utils'

type ToastType = 'success' | 'error' | 'warning' | 'info'

interface Toast {
  id: string
  type: ToastType
  title: string
  message?: string
}

interface ToastContextType {
  toast: (type: ToastType, title: string, message?: string) => void
}

const ToastContext = createContext<ToastContextType | undefined>(undefined)

const icons = {
  success: CheckCircle,
  error: XCircle,
  warning: AlertCircle,
  info: Info,
}

const colors = {
  success: 'text-[var(--color-success)]',
  error: 'text-[var(--color-danger)]',
  warning: 'text-[var(--color-warning)]',
  info: 'text-[var(--color-primary)]',
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])

  const remove = useCallback((id: string) => {
    setToasts((t) => t.filter((toast) => toast.id !== id))
  }, [])

  const toast = useCallback((type: ToastType, title: string, message?: string) => {
    const id = Math.random().toString(36).substring(7)
    setToasts((t) => [...t, { id, type, title, message }])
    setTimeout(() => remove(id), 5000)
  }, [remove])

  return (
    <ToastContext.Provider value={{ toast }}>
      {children}
      <div className="fixed bottom-4 right-4 z-[9999] flex flex-col gap-2 max-w-sm">
        {toasts.map((t) => {
          const Icon = icons[t.type]
          return (
            <div
              key={t.id}
              className={cn(
                'card p-4 flex items-start gap-3 animate-slide-in',
                'shadow-lg border-l-4',
                t.type === 'success' && 'border-l-[var(--color-success)]',
                t.type === 'error' && 'border-l-[var(--color-danger)]',
                t.type === 'warning' && 'border-l-[var(--color-warning)]',
                t.type === 'info' && 'border-l-[var(--color-primary)]',
              )}
            >
              <Icon className={cn('w-5 h-5 flex-shrink-0 mt-0.5', colors[t.type])} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-[var(--color-text)]">{t.title}</p>
                {t.message && <p className="text-xs text-[var(--color-text-secondary)] mt-1">{t.message}</p>}
              </div>
              <button onClick={() => remove(t.id)} className="text-[var(--color-text-secondary)] hover:text-[var(--color-text)]">
                <X className="w-4 h-4" />
              </button>
            </div>
          )
        })}
      </div>
    </ToastContext.Provider>
  )
}

export function useToast() {
  const ctx = useContext(ToastContext)
  if (!ctx) throw new Error('useToast must be used within ToastProvider')
  return ctx
}
