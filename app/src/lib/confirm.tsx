// UX-03 : Remplacement global de window.confirm
// Utilitaire qui permet de remplacer window.confirm par ConfirmDialog
// tout en gardant la compatibilité synchrone

import { ConfirmDialog } from '@/components/ConfirmDialog'
import { createRoot, type Root } from 'react-dom/client'

let dialogRoot: Root | null = null
let dialogContainer: HTMLDivElement | null = null

interface ConfirmOptions {
  title?: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  variant?: 'danger' | 'primary'
}

// Remplacement synchrone de window.confirm utilisant ConfirmDialog
// Affiche le dialog et retourne une Promise<boolean>
export async function confirmDialog(options: ConfirmOptions | string): Promise<boolean> {
  const opts = typeof options === 'string' ? { message: options } : options

  return new Promise((resolve) => {
    // Créer le container s'il n'existe pas
    if (!dialogContainer) {
      dialogContainer = document.createElement('div')
      dialogContainer.id = 'confirm-dialog-root'
      document.body.appendChild(dialogContainer)
      dialogRoot = createRoot(dialogContainer)
    }

    const cleanup = () => {
      if (dialogRoot) {
        dialogRoot.render(null)
      }
    }

    const handleConfirm = () => {
      cleanup()
      resolve(true)
    }

    const handleCancel = () => {
      cleanup()
      resolve(false)
    }

    if (dialogRoot) {
      dialogRoot.render(
        <ConfirmDialog
          open={true}
          title={opts.title || 'Confirmation'}
          message={opts.message}
          confirmLabel={opts.confirmLabel}
          cancelLabel={opts.cancelLabel}
          variant={opts.variant || 'danger'}
          onConfirm={handleConfirm}
          onCancel={handleCancel}
        />
      )
    }
  })
}

// Version synchrone pour la migration progressive
// Utilise window.confirm en fallback (sera remplacé progressivement par confirmDialog)
export function confirmSync(message: string): boolean {
  return window.confirm(message)
}
