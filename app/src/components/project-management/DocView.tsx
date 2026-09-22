import { useState, useEffect, useCallback, useRef } from 'react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'
import { cn } from '@/lib/utils'
import { FileText, Plus, Trash2, Save, Edit3, Eye } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getTenantId } from '@/lib/queries/core'

interface DocViewProps {
  projectId?: string
}

interface ProjectDoc {
  id: string
  tenant_id: string
  project_id: string | null
  title: string
  content: string
  created_at: string
  updated_at: string
  created_by: string | null
}

export function DocView({ projectId }: DocViewProps) {
  const { t } = useTranslation('taskManagement')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [docs, setDocs] = useState<ProjectDoc[]>([])
  const [selectedDoc, setSelectedDoc] = useState<ProjectDoc | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [editMode, setEditMode] = useState(false)
  const [title, setTitle] = useState('')
  const [content, setContent] = useState('')
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const loadDocs = useCallback(async () => {
    setLoading(true)
    try {
      const tid = await getTenantId()
      let q = supabase.from('project_docs').select('*').eq('tenant_id', tid).order('updated_at', { ascending: false })
      if (projectId) q = q.eq('project_id', projectId)
      const { data, error } = await q
      if (error) throw error
      setDocs((data || []) as ProjectDoc[])
    } catch {
      setDocs([])
    } finally {
      setLoading(false)
    }
  }, [projectId])

  useEffect(() => {
    loadDocs().catch(err => console.error('loadDocs:', err))
  }, [loadDocs])

  const handleNewDoc = useCallback(async () => {
    try {
      const tid = await getTenantId()
      const { data, error } = await supabase
        .from('project_docs')
        .insert({
          tenant_id: tid,
          project_id: projectId || null,
          title: t('doc.untitled'),
          content: '',
        })
        .select()
        .single()
      if (error) throw error
      const newDoc = data as ProjectDoc
      setDocs((prev) => [newDoc, ...prev])
      setSelectedDoc(newDoc)
      setTitle(newDoc.title)
      setContent(newDoc.content)
      setEditMode(true)
    } catch {
      // Table might not exist yet — create a local draft
      const draft: ProjectDoc = {
        id: `draft-${Date.now()}`,
        tenant_id: '',
        project_id: projectId || null,
        title: t('doc.untitled'),
        content: '',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        created_by: null,
      }
      setDocs((prev) => [draft, ...prev])
      setSelectedDoc(draft)
      setTitle(draft.title)
      setContent('')
      setEditMode(true)
    }
  }, [projectId, t])

  const handleSave = useCallback(async () => {
    if (!selectedDoc) return
    setSaving(true)
    try {
      if (selectedDoc.id.startsWith('draft-')) {
        const tid = await getTenantId()
        const { data, error } = await supabase
          .from('project_docs')
          .insert({
            tenant_id: tid,
            project_id: projectId || null,
            title,
            content,
          })
          .select()
          .single()
        if (error) throw error
        const saved = data as ProjectDoc
        setDocs((prev) => prev.map((d) => (d.id === selectedDoc.id ? saved : d)))
        setSelectedDoc(saved)
      } else {
        const tid = await getTenantId()
        const { error } = await supabase
          .from('project_docs')
          .update({ title, content, updated_at: new Date().toISOString() })
          .eq('id', selectedDoc.id)
          .eq('tenant_id', tid || '')
        if (error) throw error
        setDocs((prev) =>
          prev.map((d) => (d.id === selectedDoc.id ? { ...d, title, content, updated_at: new Date().toISOString() } : d))
        )
      }
    } catch {
      // Save locally even if DB fails
      setDocs((prev) =>
        prev.map((d) => (d.id === selectedDoc.id ? { ...d, title, content, updated_at: new Date().toISOString() } : d))
      )
    } finally {
      setSaving(false)
    }
  }, [selectedDoc, title, content, projectId])

  const handleDelete = useCallback(async (docId: string) => {
    if (!confirm(t('doc.deleteConfirm'))) return
    try {
      if (!docId.startsWith('draft-')) {
        const tid = await getTenantId()
        await supabase.from('project_docs').delete().eq('id', docId).eq('tenant_id', tid || '')
      }
      setDocs((prev) => prev.filter((d) => d.id !== docId))
      if (selectedDoc?.id === docId) {
        setSelectedDoc(null)
        setEditMode(false)
      }
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadingError'))
      // ignore
    }
  }, [selectedDoc, t, tCommon, toast])

  const handleSelectDoc = (doc: ProjectDoc) => {
    setSelectedDoc(doc)
    setTitle(doc.title)
    setContent(doc.content)
    setEditMode(false)
  }

  // Auto-save with debounce
  const scheduleAutoSave = useCallback(() => {
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current)
    saveTimerRef.current = setTimeout(() => {
      handleSave()
    }, 2000)
  }, [handleSave])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-[var(--color-text-secondary)]">{t('loading')}</p>
      </div>
    )
  }

  return (
    <div className="flex h-full">
      {/* Doc list sidebar */}
      <div className="w-64 border-r border-[var(--color-border)] bg-[var(--color-surface)] flex flex-col flex-shrink-0">
        <div className="p-3 border-b border-[var(--color-border)]">
          <button
            onClick={handleNewDoc}
            className="flex items-center gap-2 w-full px-3 py-2 text-sm font-medium rounded-lg bg-[var(--color-primary)] text-white hover:bg-[var(--color-primary-dark)] transition-colors"
          >
            <Plus className="w-4 h-4" />
            {t('doc.newDoc')}
          </button>
        </div>
        <div className="flex-1 overflow-y-auto">
          {docs.length === 0 ? (
            <div className="p-4 text-center">
              <FileText className="w-8 h-8 mx-auto text-[var(--color-text-secondary)] opacity-40 mb-2" />
              <p className="text-xs text-[var(--color-text-secondary)]">{t('doc.noDocs')}</p>
            </div>
          ) : (
            docs.map((doc) => (
              <button
                key={doc.id}
                onClick={() => handleSelectDoc(doc)}
                className={cn(
                  'w-full text-left px-3 py-2.5 border-b border-[var(--color-border)] hover:bg-[var(--color-neutral-50)] transition-colors group',
                  selectedDoc?.id === doc.id && 'bg-[var(--color-primary)]/5 border-l-2 border-l-[var(--color-primary)]'
                )}
              >
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium truncate flex-1">{doc.title || t('doc.untitled')}</span>
                  <button
                    onClick={(e) => {
                      e.stopPropagation()
                      handleDelete(doc.id)
                    }}
                    className="opacity-0 group-hover:opacity-100 text-[var(--color-text-secondary)] hover:text-red-500 transition-all flex-shrink-0 ml-2" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                    <Trash2 className="w-3.5 h-3.5" aria-hidden="true" /></button>
                </div>
                <span className="text-[10px] text-[var(--color-text-secondary)]">
                  {new Date(doc.updated_at).toLocaleDateString()}
                </span>
              </button>
            ))
          )}
        </div>
      </div>

      {/* Doc editor / viewer */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {!selectedDoc ? (
          <div className="flex flex-col items-center justify-center h-full gap-2">
            <FileText className="w-12 h-12 text-[var(--color-text-secondary)] opacity-50" />
            <p className="text-[var(--color-text)] font-medium">{t('doc.selectDoc')}</p>
            <p className="text-sm text-[var(--color-text-secondary)]">{t('doc.selectDocDesc')}</p>
          </div>
        ) : (
          <>
            {/* Toolbar */}
            <div className="flex items-center justify-between px-4 py-2 border-b border-[var(--color-border)] bg-[var(--color-surface)]">
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setEditMode(!editMode)}
                  className={cn(
                    'flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-lg transition-colors',
                    editMode
                      ? 'bg-[var(--color-primary)] text-white'
                      : 'border border-[var(--color-border)] hover:bg-[var(--color-neutral-50)]'
                  )}
                >
                  {editMode ? <Edit3 className="w-3 h-3" /> : <Eye className="w-3 h-3" />}
                  {editMode ? t('doc.editing') : t('doc.viewing')}
                </button>
                {saving && (
                  <span className="text-xs text-[var(--color-text-secondary)]">{t('doc.saving')}</span>
                )}
              </div>
              {editMode && (
                <button
                  onClick={handleSave}
                  className="flex items-center gap-1.5 px-3 py-1 text-xs font-medium rounded-lg bg-[var(--color-success)] text-white hover:opacity-90 transition-opacity"
                >
                  <Save className="w-3 h-3" />
                  {t('actions.save')}
                </button>
              )}
            </div>

            {/* Editor */}
            <div className="flex-1 overflow-auto p-6 bg-[var(--color-surface)]">
              {editMode ? (
                <div className="max-w-3xl mx-auto space-y-4">
                  <input
                    type="text"
                    value={title}
                    onChange={(e) => {
                      setTitle(e.target.value)
                      scheduleAutoSave()
                    }}
                    placeholder={t('doc.titlePlaceholder')}
                    className="w-full text-2xl font-bold text-[var(--color-text)] bg-transparent border-none outline-none placeholder:text-[var(--color-text-tertiary)]"
                  />
                  <textarea
                    value={content}
                    onChange={(e) => {
                      setContent(e.target.value)
                      scheduleAutoSave()
                    }}
                    placeholder={t('doc.contentPlaceholder')}
                    className="w-full min-h-[400px] text-sm text-[var(--color-text)] bg-transparent border-none outline-none resize-none placeholder:text-[var(--color-text-tertiary)] leading-relaxed"
                  />
                </div>
              ) : (
                <div className="max-w-3xl mx-auto">
                  <h1 className="text-2xl font-bold text-[var(--color-text)] mb-4">{title || t('doc.untitled')}</h1>
                  <div className="prose prose-sm max-w-none text-[var(--color-text)] whitespace-pre-wrap leading-relaxed">
                    {content || t('doc.emptyContent')}
                  </div>
                </div>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  )
}
