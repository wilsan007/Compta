import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { MessageSquare, Send } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { Modal } from './Modal'
import { getTaskComments, addTaskComment } from '@/lib/queries/projectManagement'
import type { TaskComment } from '@/types/projectManagement'
import { Avatar } from './Avatar'

interface CommentCellColumnProps {
  taskId: string
}

export function CommentCellColumn({ taskId }: CommentCellColumnProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [open, setOpen] = useState(false)
  const [comments, setComments] = useState<TaskComment[]>([])
  const [content, setContent] = useState('')
  const [sending, setSending] = useState(false)

  const loadComments = useCallback(async () => {
    try {
      const data = await getTaskComments(taskId)
      setComments(data)
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    }
  }, [taskId, toast, tCommon])

  useEffect(() => {
    if (open) loadComments().catch(err => console.error('loadComments:', err))
  }, [open, loadComments])

  async function handleSend() {
    if (!content.trim()) return
    setSending(true)
    try {
      await addTaskComment(taskId, content.trim())
      setContent('')
      await loadComments()
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setSending(false)
    }
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="p-1 rounded hover:bg-[var(--color-neutral-100)] relative"
        title={t('comments.title')}
      >
        <MessageSquare className="w-3.5 h-3.5 text-[var(--color-text-tertiary)]" />
        {comments.length > 0 && (
          <span className="absolute -top-1 -right-1 w-3.5 h-3.5 rounded-full bg-[var(--color-primary)] text-white text-[8px] flex items-center justify-center">
            {comments.length}
          </span>
        )}
      </button>

      <Modal open={open} onClose={() => setOpen(false)} title={t('comments.title')} maxWidth="32rem">
        <div className="space-y-3">
          <div className="space-y-2 max-h-60 overflow-y-auto">
            {comments.length === 0 ? (
              <p className="text-center text-sm text-[var(--color-text-tertiary)] py-4">
                {t('comments.empty')}
              </p>
            ) : (
              comments.map((comment) => (
                <div key={comment.id} className="flex gap-2 px-2 py-2 rounded hover:bg-[var(--color-neutral-50)]">
                  <Avatar name={comment.author_id || '?'} size="sm" />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-[var(--color-text-tertiary)] mb-0.5">
                      {new Date(comment.created_at).toLocaleString()}
                    </p>
                    <p className="text-sm text-[var(--color-text)]">{comment.content}</p>
                  </div>
                </div>
              ))
            )}
          </div>

          <div className="flex gap-2 pt-2 border-t border-[var(--color-border)]">
            <textarea
              value={content}
              onChange={(e) => setContent(e.target.value)}
              placeholder={t('comments.placeholder')}
              rows={2}
              className="flex-1 px-3 py-2 text-sm border border-[var(--color-border)] rounded bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)] resize-none"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) handleSend()
              }}
            />
            <button
              onClick={handleSend}
              disabled={sending || !content.trim()}
              className="px-3 py-2 rounded-lg bg-[var(--color-primary)] text-white hover:opacity-90 disabled:opacity-50" aria-label={tCommon('actions.send')} title={tCommon('actions.send')}>
              <Send className="w-4 h-4" aria-hidden="true" />
            </button>
          </div>
        </div>
      </Modal>
    </>
  )
}
