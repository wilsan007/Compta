import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Paperclip, Download, Upload, File as FileIcon } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { Modal } from './Modal'
import { getTaskDocuments, uploadTaskDocument } from '@/lib/queries/projectManagement'
import type { TaskDocument } from '@/types/projectManagement'

interface DocumentCellColumnProps {
  taskId: string
  projectId?: string | null
}

export function DocumentCellColumn({ taskId, projectId }: DocumentCellColumnProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [documents, setDocuments] = useState<TaskDocument[]>([])
  const [uploading, setUploading] = useState(false)

  const loadDocuments = useCallback(async () => {
    try {
      const docs = await getTaskDocuments(taskId)
      setDocuments(docs)
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    }
  }, [taskId, tCommon, toast])

  useEffect(() => {
    if (open) loadDocuments().catch(err => console.error('loadDocuments:', err))
  }, [open, loadDocuments])

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true)
    try {
      await uploadTaskDocument(taskId, file, projectId)
      await loadDocuments()
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
    } finally {
      setUploading(false)
    }
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="p-1 rounded hover:bg-[var(--color-neutral-100)] relative"
        title={t('documents.title')}
      >
        <Paperclip className="w-3.5 h-3.5 text-[var(--color-text-tertiary)]" />
        {documents.length > 0 && (
          <span className="absolute -top-1 -right-1 w-3.5 h-3.5 rounded-full bg-[var(--color-primary)] text-white text-[8px] flex items-center justify-center">
            {documents.length}
          </span>
        )}
      </button>

      <Modal open={open} onClose={() => setOpen(false)} title={t('documents.title')} maxWidth="32rem">
        <div className="space-y-3">
          <label className="flex items-center justify-center gap-2 px-4 py-6 border-2 border-dashed border-[var(--color-border)] rounded-lg cursor-pointer hover:border-[var(--color-primary)]">
            <Upload className="w-5 h-5 text-[var(--color-text-tertiary)]" />
            <span className="text-sm text-[var(--color-text-secondary)]">
              {uploading ? t('documents.uploading') : t('documents.upload')}
            </span>
            <input type="file" className="hidden" onChange={handleUpload} disabled={uploading} />
          </label>

          <div className="space-y-1 max-h-60 overflow-y-auto">
            {documents.length === 0 ? (
              <p className="text-center text-sm text-[var(--color-text-tertiary)] py-4">
                {t('documents.empty')}
              </p>
            ) : (
              documents.map((doc) => (
                <div key={doc.id} className="flex items-center gap-2 px-3 py-2 rounded hover:bg-[var(--color-neutral-100)]">
                  <FileIcon className="w-4 h-4 text-[var(--color-text-tertiary)] flex-shrink-0" />
                  <span className="text-sm flex-1 truncate">{doc.file_name}</span>
                  <span className="text-xs text-[var(--color-text-tertiary)]">
                    {doc.file_size ? `${(doc.file_size / 1024).toFixed(0)} KB` : ''}
                  </span>
                  <button className="p-1 rounded hover:bg-[var(--color-neutral-200)]" title={t('documents.download')}>
                    <Download className="w-3.5 h-3.5" />
                  </button>
                </div>
              ))
            )}
          </div>
        </div>
      </Modal>
    </>
  )
}
