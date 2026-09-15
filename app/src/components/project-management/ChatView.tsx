import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { MessageSquare, Send, Hash } from 'lucide-react'
import { useTaskContext } from '@/contexts/TaskContext'
import { useProjectContext } from '@/contexts/ProjectContext'
import { getTaskComments, addTaskComment } from '@/lib/queries/projectManagement'
import type { TaskComment } from '@/types/projectManagement'

interface ChatViewProps {
  projectId?: string
}

interface ChatChannel {
  id: string
  type: 'project' | 'task'
  label: string
  taskId?: string
  taskTitle?: string
}

export function ChatView({ projectId }: ChatViewProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { tasks, loading: tasksLoading } = useTaskContext()
  const { projects } = useProjectContext()
  const [channels, setChannels] = useState<ChatChannel[]>([])
  const [activeChannel, setActiveChannel] = useState<ChatChannel | null>(null)
  const [messages, setMessages] = useState<TaskComment[]>([])
  const [input, setInput] = useState('')
  const [loadingMessages, setLoadingMessages] = useState(false)
  const [sending, setSending] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)

  const projectNames = useMemo(() => {
    const map = new Map<string, string>()
    projects.forEach((p) => map.set(p.id, p.name))
    return map
  }, [projects])

  // Build channels from projects + tasks
  useEffect(() => {
    if (tasksLoading) return
    const chans: ChatChannel[] = []

    // Project channel(s)
    if (projectId) {
      const projName = projectNames.get(projectId) || t('chat.projectChannel')
      chans.push({ id: `proj-${projectId}`, type: 'project', label: projName })
    } else {
      // General channel for all projects
      chans.push({ id: 'proj-general', type: 'project', label: t('chat.general') })
    }

    // Task channels (only tasks with comments or recent activity)
    const filtered = projectId ? tasks.filter((t) => t.project_id === projectId) : tasks
    for (const task of filtered) {
      if (task.status === 'done' || task.status === 'canceled') continue
      chans.push({
        id: `task-${task.id}`,
        type: 'task',
        label: task.title,
        taskId: task.id,
        taskTitle: task.title,
      })
    }

    setChannels(chans)
    if (chans.length > 0) {
      setActiveChannel((current) => current ?? chans[0])
    }
  }, [tasks, tasksLoading, projectId, projectNames, t])

  // Load messages for active channel
  const loadMessages = useCallback(async () => {
    if (!activeChannel) return
    if (activeChannel.type === 'project') {
      // For project channel, show recent comments across all tasks in the project
      setMessages([])
      return
    }
    if (!activeChannel.taskId) return
    setLoadingMessages(true)
    try {
      const data = await getTaskComments(activeChannel.taskId)
      setMessages(data.reverse()) // Reverse to show oldest first
    } catch {
      setMessages([])
    } finally {
      setLoadingMessages(false)
    }
  }, [activeChannel])

  useEffect(() => {
    loadMessages().catch(err => console.error('loadMessages:', err))
  }, [loadMessages])

  // Auto-scroll to bottom
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const handleSend = useCallback(async () => {
    if (!input.trim() || !activeChannel?.taskId) return
    setSending(true)
    try {
      const comment = await addTaskComment(activeChannel.taskId, input.trim())
      setMessages((prev) => [...prev, comment])
      setInput('')
    } catch (err: any) {
      console.error("catch:", err)
      // ignore
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError'))
    } finally {
      setSending(false)
    }
  }, [input, activeChannel, toast, tCommon])

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  if (tasksLoading) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  return (
    <div className="flex h-full">
      {/* Channels sidebar */}
      <div className="w-56 border-r border-[var(--color-border)] bg-[var(--color-surface)] flex flex-col flex-shrink-0">
        <div className="px-3 py-2.5 border-b border-[var(--color-border)]">
          <h3 className="text-xs font-bold uppercase tracking-wider text-[var(--color-text-secondary)] flex items-center gap-1.5">
            <MessageSquare className="w-3.5 h-3.5" />
            {t('chat.channels')}
          </h3>
        </div>
        <div className="flex-1 overflow-y-auto">
          {channels.map((ch) => (
            <button
              key={ch.id}
              onClick={() => setActiveChannel(ch)}
              className={cn(
                'w-full text-left px-3 py-2 text-sm transition-colors flex items-center gap-2',
                activeChannel?.id === ch.id
                  ? 'bg-[var(--color-primary)]/10 text-[var(--color-primary)] font-medium'
                  : 'text-[var(--color-text-secondary)] hover:bg-[var(--color-neutral-50)]'
              )}
            >
              {ch.type === 'project' ? (
                <Hash className="w-3.5 h-3.5 flex-shrink-0" />
              ) : (
                <span className="w-1.5 h-1.5 rounded-full bg-[var(--color-text-tertiary)] flex-shrink-0" />
              )}
              <span className="truncate">{ch.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Chat area */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Chat header */}
        <div className="flex items-center gap-2 px-4 py-2.5 border-b border-[var(--color-border)] bg-[var(--color-surface)]">
          {activeChannel?.type === 'project' ? (
            <Hash className="w-4 h-4 text-[var(--color-text-secondary)]" />
          ) : (
            <MessageSquare className="w-4 h-4 text-[var(--color-text-secondary)]" />
          )}
          <h3 className="text-sm font-semibold truncate">{activeChannel?.label || t('chat.noChannel')}</h3>
          {activeChannel?.type === 'task' && (
            <span className="text-[10px] text-[var(--color-text-secondary)] bg-[var(--color-neutral-100)] px-2 py-0.5 rounded-full">
              {t('chat.taskChannel')}
            </span>
          )}
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-3 bg-[var(--color-background)]">
          {loadingMessages ? (
            <div className="flex items-center justify-center h-full">
              <p className="text-sm text-[var(--color-text-secondary)]">{t('loading')}</p>
            </div>
          ) : messages.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full gap-2">
              <MessageSquare className="w-10 h-10 text-[var(--color-text-secondary)] opacity-40" />
              <p className="text-sm text-[var(--color-text)] font-medium">{t('chat.noMessages')}</p>
              <p className="text-xs text-[var(--color-text-secondary)]">{t('chat.noMessagesDesc')}</p>
            </div>
          ) : (
            messages.map((msg) => (
              <div key={msg.id} className="flex gap-3 group">
                <div className="w-8 h-8 rounded-full bg-[var(--color-primary)] text-white flex items-center justify-center text-xs font-medium flex-shrink-0">
                  {(msg.author_id || '?').charAt(0).toUpperCase()}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-baseline gap-2">
                    <span className="text-sm font-medium text-[var(--color-text)]">
                      {msg.author_id || t('chatter.unknown')}
                    </span>
                    <span className="text-[10px] text-[var(--color-text-secondary)]">
                      {new Date(msg.created_at).toLocaleString()}
                    </span>
                  </div>
                  <p className="text-sm text-[var(--color-text)] mt-0.5 whitespace-pre-wrap break-words">
                    {msg.content}
                  </p>
                </div>
              </div>
            ))
          )}
          <div ref={messagesEndRef} />
        </div>

        {/* Input */}
        <div className="border-t border-[var(--color-border)] bg-[var(--color-surface)] p-3">
          {activeChannel?.type === 'project' ? (
            <div className="flex items-center justify-center py-4 text-sm text-[var(--color-text-secondary)]">
              {t('chat.projectChannelDesc')}
            </div>
          ) : (
            <div className="flex items-end gap-2">
              <textarea
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder={t('chat.placeholder')}
                rows={1}
                className="flex-1 px-3 py-2 text-sm rounded-lg border border-[var(--color-border)] bg-[var(--color-neutral-50)] text-[var(--color-text)] placeholder:text-[var(--color-text-tertiary)] focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:border-transparent resize-none max-h-32"
                style={{ minHeight: '38px' }}
              />
              <button
                onClick={handleSend}
                disabled={!input.trim() || sending}
                className="flex items-center justify-center w-9 h-9 rounded-lg bg-[var(--color-primary)] text-white hover:bg-[var(--color-primary-dark)] disabled:opacity-40 disabled:cursor-not-allowed transition-colors flex-shrink-0"
              >
                <Send className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
