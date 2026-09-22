import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getMyDocuments, acknowledgeDocument } from '@/lib/queries/dematRh'
import type { EmployeeDocument } from '@/types'
import { useToast } from '@/lib/toast'
import { Download, CheckCircle, PenTool, Lock } from 'lucide-react'

export function EmployeeDocumentsPage() {
  const { t } = useTranslation('employee')
  const { t: tCommon } = useTranslation('common')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [documents, setDocuments] = useState<EmployeeDocument[]>([])
  const [typeFilter, setTypeFilter] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const docs = await getMyDocuments()
      setDocuments(typeFilter ? docs.filter(d => d.document_type === typeFilter) : docs)
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    } finally {
      setLoading(false)
    }
  }, [typeFilter, toast, tCommon])

  useEffect(() => { loadData() }, [loadData])

  const handleAcknowledge = async (id: string) => {
    try {
      await acknowledgeDocument(id)
      toast('success', t('documents.acknowledge'))
      loadData().catch(err => console.error('loadData:', err))
    } catch (e: any) {
      toast('error', tCommon('common.error'), e.message)
    }
  }

  const docTypeBadge = (type: string) => {
    const variant: 'success' | 'primary' | 'neutral' = type === 'payslip' ? 'primary' : type === 'contract' ? 'success' : 'neutral'
    return <Badge variant={variant}>{t(`documents.types.${type}`)}</Badge>
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.hr') }, { label: t('documents.title') }]} />
      <PageHeader title={t('documents.title')} subtitle={t('documents.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <Select label={t('documents.type')} value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)} options={[
          { value: '', label: tCommon('table.all') },
          { value: 'payslip', label: t('documents.types.payslip') },
          { value: 'contract', label: t('documents.types.contract') },
          { value: 'certificate', label: t('documents.types.certificate') },
          { value: 'other', label: t('documents.types.other') },
        ]} />
      </div>

      <Card className="mb-4">
        <div className="flex items-center gap-3">
          <Lock className="w-8 h-8 text-blue-600" />
          <div>
            <h3 className="font-medium">{t('documents.coffreFort')}</h3>
            <p className="text-xs text-gray-500">{documents.length} {t('documents.totalDocuments')}</p>
          </div>
        </div>
      </Card>

      {loading ? <SkeletonTable /> : documents.length === 0 ? (
        <EmptyState title={t('documents.noDocuments')} />
      ) : (
        <Card>
          <Table headers={[t('documents.type'), t('documents.title_label'), t('documents.period'), t('documents.uploadDate'), t('documents.acknowledged'), t('documents.sign'), t('documents.actions')]}>
            {documents.map(doc => (
              <TableRow key={doc.id}>
                <TableCell>{docTypeBadge(doc.document_type)}</TableCell>
                <TableCell className="text-sm">{doc.title}</TableCell>
                <TableCell className="text-xs">{doc.period || '-'}</TableCell>
                <TableCell className="text-xs">{new Date(doc.created_at).toLocaleDateString()}</TableCell>
                <TableCell>{doc.acknowledged ? <CheckCircle className="w-4 h-4 text-green-600" /> : '-'}</TableCell>
                <TableCell>{doc.e_signed ? <PenTool className="w-4 h-4 text-blue-600" /> : '-'}</TableCell>
                <TableCell>
                  <Button size="sm" variant="ghost" ariaLabel={tCommon('actions.download')}><Download className="w-4 h-4" aria-hidden="true" /></Button>
                  {doc.requires_acknowledgment && !doc.acknowledged && (
                    <Button size="sm" variant="secondary" onClick={() => handleAcknowledge(doc.id)}>{t('documents.acknowledge')}</Button>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
