// UX-03 : Remplacement de window.confirm par un composant accessible
import { useState, useCallback, createContext, useContext, type ReactNode } from 'react'
import { ConfirmDialog } from '@/components/ConfirmDialog'

interface ConfirmOptions {
  title?: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  variant?: 'danger' | 'primary'
}

interface ConfirmContextValue {
  confirm: (options: ConfirmOptions) => Promise<boolean>
}

const ConfirmContext = createContext<ConfirmContextValue | null>(null)

export function ConfirmProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<{
    open: boolean
    message: string
    title: string
    confirmLabel?: string
    cancelLabel?: string
    variant: 'danger' | 'primary'
    resolve?: (value: boolean) => void
  }>({
    open: false,
    message: '',
    title: '',
    variant: 'danger',
  })

  const confirm = useCallback((options: ConfirmOptions): Promise<boolean> => {
    return new Promise((resolve) => {
      setState({
        open: true,
        message: options.message,
        title: options.title || 'Confirmation',
        confirmLabel: options.confirmLabel,
        cancelLabel: options.cancelLabel,
        variant: options.variant || 'danger',
        resolve,
      })
    })
  }, [])

  const handleConfirm = useCallback(() => {
    state.resolve?.(true)
    setState((s) => ({ ...s, open: false, resolve: undefined }))
  }, [state])

  const handleCancel = useCallback(() => {
    state.resolve?.(false)
    setState((s) => ({ ...s, open: false, resolve: undefined }))
  }, [state])

  return (
    <ConfirmContext.Provider value={{ confirm }}>
      {children}
      <ConfirmDialog
        open={state.open}
        title={state.title}
        message={state.message}
        confirmLabel={state.confirmLabel}
        cancelLabel={state.cancelLabel}
        variant={state.variant}
        onConfirm={handleConfirm}
        onCancel={handleCancel}
      />
    </ConfirmContext.Provider>
  )
}

export function useConfirm(): (options: ConfirmOptions) => Promise<boolean> {
  const ctx = useContext(ConfirmContext)
  if (!ctx) {
    // Fallback vers window.confirm si pas de provider (compatibilité)
    return (options: ConfirmOptions) => Promise.resolve(window.confirm(options.message))
  }
  return ctx.confirm
}
