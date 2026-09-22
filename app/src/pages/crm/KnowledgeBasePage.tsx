import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select, Input } from '@/components/ui'
import { getKbArticles, createKbArticle, updateKbArticle, deleteKbArticle, incrementKbViews, rateKbArticle } from '@/lib/queries/crmAdvanced'
import { useToast } from '@/lib/toast'
import { Plus, X, BookOpen, Trash2, ThumbsUp, ThumbsDown, Search, Pencil } from 'lucide-react'
import type { KnowledgeBaseArticle } from '@/types'

const CATEGORIES = ['faq', 'guide', 'troubleshooting', 'policy'] as const
const STATUSES = ['draft', 'published', 'archived'] as const

export function KnowledgeBasePage() {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [articles, setArticles] = useState<KnowledgeBaseArticle[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editArticle, setEditArticle] = useState<KnowledgeBaseArticle | null>(null)
  const [search, setSearch] = useState('')
  const [filterCategory, setFilterCategory] = useState('')
  const [filterStatus, setFilterStatus] = useState('')

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getKbArticles()
      setArticles(data || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [tCommon, toast])

  useEffect(() => { load() }, [load])

  const filtered = articles.filter(a => {
    if (search && !a.title.toLowerCase().includes(search.toLowerCase()) && !a.content.toLowerCase().includes(search.toLowerCase())) return false
    if (filterCategory && a.category !== filterCategory) return false
    if (filterStatus && a.status !== filterStatus) return false
    return true
  })

  async function handleView(id: string) {
    try {
      await incrementKbViews(id)
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleRate(id: string, helpful: boolean) {
    try {
      await rateKbArticle(id, helpful)
      toast('success', tCommon('toast.success'), tCommon('toast.updated'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleDelete(id: string) {
    try {
      await deleteKbArticle(id)
      toast('success', tCommon('toast.success'), tCommon('toast.deleted'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  function getStatusBadge(status: string): 'neutral' | 'success' | 'warning' {
    if (status === 'published') return 'success'
    if (status === 'archived') return 'warning'
    return 'neutral'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <BookOpen className="w-6 h-6 text-[var(--color-primary)]" />
            {t('knowledgeBase.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('knowledgeBase.subtitle')}</p>
        </div>
        <Button onClick={() => { setEditArticle(null); setShowForm(true) }}>
          <Plus className="w-4 h-4" /> {t('knowledgeBase.new')}
        </Button>
      </div>

      <div className="flex items-center gap-4 mb-4">
        <div className="relative flex-1 max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
          <input type="text" placeholder={t('knowledgeBase.search')} value={search} onChange={(e) => setSearch(e.target.value)} className="input pl-9" />
        </div>
        <Select value={filterCategory} onChange={(e) => setFilterCategory(e.target.value)} options={[
          { value: '', label: tCommon('filters.all') },
          ...CATEGORIES.map(c => ({ value: c, label: t(`knowledgeBase.${c}`) })),
        ]} />
        <Select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} options={[
          { value: '', label: tCommon('filters.all') },
          ...STATUSES.map(s => ({ value: s, label: t(`knowledgeBase.${s}`) })),
        ]} />
      </div>

      {loading ? (
        <div className="space-y-2">{[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}</div>
      ) : filtered.length === 0 ? (
        <EmptyState icon={<BookOpen className="w-8 h-8" />} title={t('knowledgeBase.noArticles')} description={t('knowledgeBase.noArticlesDescription')} />
      ) : (
        <Table headers={[t('knowledgeBase.title'), t('knowledgeBase.category'), t('knowledgeBase.status'), t('knowledgeBase.views'), t('knowledgeBase.helpful'), t('knowledgeBase.isPublic'), tCommon('table.actions')]}>
          {filtered.map(a => (
            <TableRow key={a.id}>
              <TableCell className="font-medium">
                <button onClick={() => handleView(a.id)} className="hover:underline text-left">{a.title}</button>
              </TableCell>
              <TableCell className="text-xs">{a.category ? t(`knowledgeBase.${a.category}`) : '-'}</TableCell>
              <TableCell><Badge variant={getStatusBadge(a.status)}>{t(`knowledgeBase.${a.status}`)}</Badge></TableCell>
              <TableCell className="font-mono text-xs">{a.views}</TableCell>
              <TableCell className="text-xs">
                <div className="flex gap-1">
                  <button onClick={() => handleRate(a.id, true)} className="flex items-center gap-1 text-[var(--color-success)] hover:underline">
                    <ThumbsUp className="w-3 h-3" /> {a.helpful_count}
                  </button>
                  <button onClick={() => handleRate(a.id, false)} className="flex items-center gap-1 text-[var(--color-danger)] hover:underline ml-2">
                    <ThumbsDown className="w-3 h-3" /> {a.not_helpful_count}
                  </button>
                </div>
              </TableCell>
              <TableCell><Badge variant={a.is_public ? 'success' : 'neutral'}>{a.is_public ? tCommon('common.yes') : tCommon('common.no')}</Badge></TableCell>
              <TableCell>
                <div className="flex gap-1">
                  <button onClick={() => { setEditArticle(a); setShowForm(true) }} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-text-secondary)]" aria-label={tCommon('actions.edit')} title={tCommon('actions.edit')}>
                    <Pencil className="w-4 h-4" aria-hidden="true" /></button>
                  <button onClick={() => handleDelete(a.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}>
                    <Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}

      {showForm && (
        <KbForm article={editArticle} onClose={() => { setShowForm(false); setEditArticle(null) }} onSaved={() => { setShowForm(false); setEditArticle(null); load() }} />
      )}
    </div>
  )
}

function KbForm({ article, onClose, onSaved }: { article: KnowledgeBaseArticle | null; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('crm')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [title, setTitle] = useState(article?.title || '')
  const [category, setCategory] = useState<KnowledgeBaseArticle['category']>('faq')
  const [content, setContent] = useState(article?.content || '')
  const [tagsInput, setTagsInput] = useState((article?.tags || []).join(', '))
  const [isPublic, setIsPublic] = useState(article?.is_public || false)
  const [status, setStatus] = useState<KnowledgeBaseArticle['status']>('draft')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!title || !content) return
    setSaving(true)
    try {
      const tags = tagsInput.split(',').map(t => t.trim()).filter(Boolean)
      if (article) {
        await updateKbArticle(article.id, { title, category, content, tags, is_public: isPublic, status })
      } else {
        await createKbArticle({
          tenant_id: null,
          title,
          category,
          content,
          tags: tags.length > 0 ? tags : null,
          author: null,
          status,
          views: 0,
          helpful_count: 0,
          not_helpful_count: 0,
          is_public: isPublic,
        })
      }
      toast('success', tCommon('toast.success'), tCommon('toast.saved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{article ? t('knowledgeBase.edit') : t('knowledgeBase.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('knowledgeBase.title')} required value={title} onChange={(e) => setTitle(e.target.value)} />
          <Select label={t('knowledgeBase.category')} value={category || ''} onChange={(e) => setCategory(e.target.value as any)} options={CATEGORIES.map(c => ({ value: c, label: t(`knowledgeBase.${c}`) }))} />
          <div>
            <label className="text-sm font-medium mb-1 block">{t('knowledgeBase.content')}</label>
            <textarea required value={content} onChange={(e) => setContent(e.target.value)} rows={8} className="input font-mono text-sm" placeholder="Markdown..." />
          </div>
          <Input label={t('knowledgeBase.tags')} placeholder="tag1, tag2" value={tagsInput} onChange={(e) => setTagsInput(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Select label={t('knowledgeBase.status')} value={status} onChange={(e) => setStatus(e.target.value as any)} options={STATUSES.map(s => ({ value: s, label: t(`knowledgeBase.${s}`) }))} />
            <div>
              <label className="text-sm font-medium mb-1 block">{t('knowledgeBase.isPublic')}</label>
              <label className="flex items-center gap-2 mt-2">
                <input type="checkbox" checked={isPublic} onChange={(e) => setIsPublic(e.target.checked)} />
                <span className="text-sm">{t('knowledgeBase.isPublic')}</span>
              </label>
            </div>
          </div>
          <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? tCommon('actions.saving') : tCommon('actions.save')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
