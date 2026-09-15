import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, EmptyState } from '@/components/ui'
import { MessageSquare, Send, Paperclip, AtSign, Clock } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { cn } from '@/lib/utils'
import { formatDate } from '@/lib/utils'
import type { ProjectTask, TaskComment } from '@/types/projectManagement'
import { getTaskComments, addTaskComment } from '@/lib/queries/projectManagement'

interface TaskChatterProps {
  task: ProjectTask
  className?: string
}

export function TaskChatter({ task, className }: TaskChatterProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [comments, setComments] = useState<TaskComment[]>([])
  const [loading, setLoading] = useState(true)
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)

  const loadComments = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getTaskComments(task.id)
      setComments(data)
    } catch {
      setComments([])
    } finally {
      setLoading(false)
    }
  }, [task.id])

  useEffect(() => {
    loadComments().catch(err => console.error('loadComments:', err))
  }, [loadComments])

  async function handleSend() {
    if (!input.trim()) return
    setSending(true)
    try {
      const newComment = await addTaskComment(task.id, input.trim())
      setComments((prev) => [newComment, ...prev])
      setInput('')
    } catch (err: any) {
      console.error("catch:", err)
      /* ignore */
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setSending(false)
    }
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault()
      handleSend()
    }
  }

  return (
    <div className={cn('flex flex-col h-full', className)} role="region" aria-label={t('chatter.title')}>
      <div className="flex items-center gap-2 px-4 py-3 border-b border-[var(--color-border)]">
        <MessageSquare className="w-4 h-4 text-[var(--color-primary)]" />
        <h3 className="text-sm font-semibold text-[var(--color-text)]">{t('chatter.title')}</h3>
        <span className="text-xs text-[var(--color-text-secondary)] ml-auto">{comments.length} {t('chatter.messages')}</span>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {loading ? (
          <div className="text-center text-sm text-[var(--color-text-secondary)] py-8">{t('loading')}</div>
        ) : comments.length === 0 ? (
          <EmptyState icon={<MessageSquare className="w-8 h-8" />} title={t('chatter.noMessages')} description={t('chatter.noMessagesDesc')} />
        ) : (
          comments.map((comment) => (
            <div key={comment.id} className="flex flex-col gap-1">
              <div className="flex items-center gap-2">
                <div className="w-7 h-7 rounded-full bg-[var(--color-primary)] text-white flex items-center justify-center text-xs font-medium">
                  {(comment.author_id || '?').slice(0, 2).toUpperCase()}
                </div>
                <div className="flex-1">
                  <span className="text-xs font-medium text-[var(--color-text)]">
                    {comment.author_id || t('chatter.unknown')}
                  </span>
                  <span className="text-xs text-[var(--color-text-secondary)] ml-2 flex items-center gap-1 inline-flex">
                    <Clock className="w-3 h-3" /> {formatDate(comment.created_at)}
                  </span>
                </div>
              </div>
              <div className="ml-9 p-3 rounded-lg bg-[var(--color-neutral-50)] border border-[var(--color-border)] text-sm text-[var(--color-text)]">
                {comment.content}
              </div>
            </div>
          ))
        )}
      </div>

      <div className="border-t border-[var(--color-border)] p-3">
        <div className="flex items-end gap-2">
          <div className="flex-1">
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder={t('chatter.placeholder')}
              rows={2}
              className="w-full px-3 py-2 text-sm border border-[var(--color-border)] rounded-lg bg-[var(--color-surface)] outline-none focus:border-[var(--color-primary)] resize-none"
              aria-label={t('chatter.placeholder')}
            />
            <div className="flex items-center gap-1 mt-1">
              <button className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" title={t('chatter.attach')}>
                <Paperclip className="w-3.5 h-3.5" />
              </button>
              <button className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" title={t('chatter.mention')}>
                <AtSign className="w-3.5 h-3.5" />
              </button>
              <span className="text-xs text-[var(--color-text-secondary)] ml-auto">
                {t('chatter.cmdEnter')}
              </span>
            </div>
          </div>
          <Button
            onClick={handleSend}
            disabled={!input.trim() || sending}
            size="sm"
            className="mb-5"
          >
            <Send className="w-4 h-4" />
            {t('chatter.send')}
          </Button>
        </div>
      </div>
    </div>
  )
}
