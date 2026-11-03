import { useEffect, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Download, Loader2, Upload } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { getCurrentLocale } from '@/lib/utils'
import { downloadProjectFile, getTaskActionAttachments, uploadActionProof } from '@/lib/queries/projectManagement'
import type { TaskAction, TaskActionAttachment } from '@/types/projectManagement'
import { Modal } from '../Modal'

// Les preuves d'une action : la liste (téléchargeable) et l'ajout d'un fichier.
// Une action ne se coche qu'avec au moins une preuve (803).
export function ActionProofDialog({ action, onClose, onUploaded }: { action: TaskAction | null; onClose: () => void; onUploaded: () => void }) {
  const { t } = useTranslation('taskManagement')
  const { toast } = useToast()
  const [files, setFiles] = useState<TaskActionAttachment[]>([])
  const [busy, setBusy] = useState(false)
  const input = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!action) return
    getTaskActionAttachments(action.id)
      .then(setFiles)
      .catch((e: Error) => toast('error', t('saveError'), e.message))
  }, [action, toast, t])

  const upload = async (file: File) => {
    if (!action) return
    setBusy(true)
    try {
      const added = await uploadActionProof(action, file)
      setFiles((f) => [added, ...f])
      toast('success', t('dyn.uploadDone'))
      onUploaded()
    } catch (e) {
      toast('error', t('dyn.uploadFailed'), (e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal open={!!action} onClose={onClose} title={action ? t('dyn.proofsOf', { title: action.title }) : ''} maxWidth="28rem">
      <div className="space-y-3">
        <p className="text-sm text-[var(--color-text-secondary)]">{t('dyn.proofRequiredHint')}</p>
        <input
          ref={input}
          type="file"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0]
            e.target.value = ''
            if (f) void upload(f)
          }}
        />
        <button
          type="button"
          disabled={busy}
          onClick={() => input.current?.click()}
          className="flex w-full items-center justify-center gap-2 rounded-lg border border-dashed border-[var(--color-border)] px-3 py-3 text-sm hover:bg-[var(--color-neutral-50)] disabled:opacity-50"
        >
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4 text-green-600" />}
          {t('dyn.addFile')}
        </button>
        {files.map((f) => (
          <div key={f.id} className="flex items-center justify-between rounded bg-[var(--color-neutral-50)] p-2">
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{f.file_name}</p>
              <p className="text-xs text-[var(--color-text-tertiary)]">{new Date(f.created_at).toLocaleDateString(getCurrentLocale())}</p>
            </div>
            <button
              type="button"
              className="flex h-8 w-8 items-center justify-center rounded hover:bg-[var(--color-neutral-100)]"
              aria-label={t('dyn.download', { name: f.file_name })}
              onClick={async () => {
                try {
                  const blob = await downloadProjectFile(f.file_path)
                  const url = URL.createObjectURL(blob)
                  const a = document.createElement('a')
                  a.href = url
                  a.download = f.file_name
                  a.click()
                  setTimeout(() => URL.revokeObjectURL(url), 1000)
                } catch (e) {
                  toast('error', t('dyn.downloadFailed'), (e as Error).message)
                }
              }}
            >
              <Download className="h-4 w-4" />
            </button>
          </div>
        ))}
      </div>
    </Modal>
  )
}
