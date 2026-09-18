import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import { getRhKnowledgeBase, createRhKnowledgeBaseArticle, updateRhKnowledgeBaseArticle, deleteRhKnowledgeBaseArticle, incrementArticleViews } from '@/lib/queries/dematRh'
import type { RhKnowledgeBaseArticle } from '@/types'
import { useToast } from '@/lib/toast'
import { Plus, Edit, Trash2, Eye } from 'lucide-react'

export function RhKnowledgeBasePage() {
  const { t } = useTranslation('hr')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [articles, setArticles] = useState<RhKnowledgeBaseArticle[]>([])
  const [category, setCategory] = useState('')
  const [search, setSearch] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [formTitle, setFormTitle] = useState('')
  const [formCategory, setFormCategory] = useState('paie')
  const [formContent, setFormContent] = useState('')
  const [formTags, setFormTags] = useState('')
  const [formPublished, setFormPublished] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getRhKnowledgeBase(category || undefined, search || undefined)
      setArticles(data)
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally {
      setLoading(false)
    }
  }, [category, search, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const handleSave = async () => {
    try {
      const tags = formTags.split(',').map(t => t.trim()).filter(Boolean)
      if (editId) {
        await updateRhKnowledgeBaseArticle(editId, {
          title: formTitle,
          category: formCategory,
          content: formContent,
          tags,
          published: formPublished,
        })
        toast('success', tCommon('common.saved'))
      } else {
        await createRhKnowledgeBaseArticle({
          tenant_id: null,
          title: formTitle,
          content: formContent,
          category: formCategory,
          tags,
          author_id: null,
          published: formPublished,
          views: 0,
        })
        toast('success', tCommon('common.saved'))
      }
      setShowForm(false)
      setEditId(null)
      setFormTitle(''); setFormContent(''); setFormTags('')
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleEdit = (article: RhKnowledgeBaseArticle) => {
    setEditId(article.id)
    setFormTitle(article.title)
    setFormCategory(article.category || 'paie')
    setFormContent(article.content)
    setFormTags(article.tags.join(', '))
    setFormPublished(article.published)
    setShowForm(true)
  }

  const handleView = async (article: RhKnowledgeBaseArticle) => {
    try {
      await incrementArticleViews(article.id)
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const handleDelete = async (id: string) => {
    try {
      await deleteRhKnowledgeBaseArticle(id)
      toast('success', tCommon('common.deleted'))
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sections.hr') }, { label: t('knowledgeBase.title') }]} />
      <PageHeader title={t('knowledgeBase.title')} subtitle={t('knowledgeBase.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="flex-1">
          <Input label={t('knowledgeBase.search')} value={search} onChange={(e) => setSearch(e.target.value)} placeholder={t('knowledgeBase.searchPlaceholder')} />
        </div>
        <Select label={t('knowledgeBase.category')} value={category} onChange={(e) => setCategory(e.target.value)} options={[
          { value: '', label: tCommon('table.all') },
          { value: 'paie', label: t('knowledgeBase.categories.paie') },
          { value: 'conges', label: t('knowledgeBase.categories.conges') },
          { value: 'contrats', label: t('knowledgeBase.categories.contrats') },
          { value: 'droit', label: t('knowledgeBase.categories.droit') },
          { value: 'procedure', label: t('knowledgeBase.categories.procedure') },
          { value: 'other', label: t('knowledgeBase.categories.other') },
        ]} />
        <Button onClick={() => { setEditId(null); setFormTitle(''); setFormContent(''); setFormTags(''); setFormPublished(false); setShowForm(true) }}><Plus className="w-4 h-4 mr-2" />{t('knowledgeBase.newArticle')}</Button>
      </div>

      {loading ? <SkeletonTable /> : articles.length === 0 ? (
        <EmptyState title={t('knowledgeBase.noArticles')} />
      ) : (
        <Card>
          <Table headers={[t('knowledgeBase.title'), t('knowledgeBase.category'), t('knowledgeBase.views'), t('knowledgeBase.status'), t('knowledgeBase.date'), t('knowledgeBase.actions')]}>
            {articles.map(article => (
              <TableRow key={article.id}>
                <TableCell className="text-sm font-medium">{article.title}</TableCell>
                <TableCell><Badge variant="neutral">{t(`knowledgeBase.categories.${article.category || 'other'}`)}</Badge></TableCell>
                <TableCell className="text-xs"><span className="flex items-center gap-1"><Eye className="w-3 h-3" />{article.views}</span></TableCell>
                <TableCell><Badge variant={article.published ? 'success' : 'warning'}>{article.published ? t('knowledgeBase.published') : t('knowledgeBase.draft')}</Badge></TableCell>
                <TableCell className="text-xs">{new Date(article.updated_at).toLocaleDateString()}</TableCell>
                <TableCell>
                  <Button size="sm" variant="ghost" onClick={() => handleView(article)} ariaLabel={tCommon('actions.view')}><Eye className="w-4 h-4" aria-hidden="true" /></Button>
                  <Button size="sm" variant="ghost" onClick={() => handleEdit(article)} ariaLabel={tCommon('actions.edit')}><Edit className="w-4 h-4" aria-hidden="true" /></Button>
                  <Button size="sm" variant="ghost" onClick={() => handleDelete(article.id)} ariaLabel={tCommon('actions.delete')}><Trash2 className="w-4 h-4 text-red-500" aria-hidden="true" /></Button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <Card className="w-full max-w-lg p-6">
            <h3 className="font-medium mb-4">{editId ? t('knowledgeBase.editArticle') : t('knowledgeBase.newArticle')}</h3>
            <div className="space-y-3">
              <Input label={t('knowledgeBase.title')} value={formTitle} onChange={(e) => setFormTitle(e.target.value)} />
              <Select label={t('knowledgeBase.category')} value={formCategory} onChange={(e) => setFormCategory(e.target.value)} options={[
                { value: 'paie', label: t('knowledgeBase.categories.paie') },
                { value: 'conges', label: t('knowledgeBase.categories.conges') },
                { value: 'contrats', label: t('knowledgeBase.categories.contrats') },
                { value: 'droit', label: t('knowledgeBase.categories.droit') },
                { value: 'procedure', label: t('knowledgeBase.categories.procedure') },
                { value: 'other', label: t('knowledgeBase.categories.other') },
              ]} />
              <Input label={t('knowledgeBase.tags')} value={formTags} onChange={(e) => setFormTags(e.target.value)} placeholder="paie, brut, cotisations" />
              <div>
                <label className="block text-sm font-medium mb-1">{t('knowledgeBase.content')}</label>
                <textarea className="w-full px-3 py-2 border rounded text-sm" rows={6} value={formContent} onChange={(e) => setFormContent(e.target.value)} />
              </div>
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={formPublished} onChange={(e) => setFormPublished(e.target.checked)} />
                <span className="text-sm">{t('knowledgeBase.published')}</span>
              </label>
            </div>
            <div className="flex gap-2 mt-4">
              <Button onClick={handleSave} disabled={!formTitle || !formContent}>{tCommon('actions.save')}</Button>
              <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('actions.cancel')}</Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
