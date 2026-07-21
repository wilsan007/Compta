import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getVatReturns, submitEdiTva } from '@/lib/queries'
import { useLocale } from '@/hooks/useLocale'
import { Send, FileCheck } from 'lucide-react'
import type { VatReturn } from '@/types'
import { useToast } from '@/lib/toast'

export function EdiTvaPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatDate } = useLocale()
  const [returns, setReturns] = useState<VatReturn[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getVatReturns()
      setReturns(data || [])
    } catch (err) {
      console.error('Failed to load VAT returns:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleSubmit(id: string) {
    if (!window.confirm(t('ediTva.submitConfirm'))) return
    try {
      await submitEdiTva(id)
      toast('success', tCommon('common.success'), t('ediTva.submitSuccess'))
      await loadData()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    }
  }

  const tableHeaders = [t('ediTva.period'), t('ediTva.amount'), t('ediTva.ediId'), t('ediTva.status'), t('ediTva.submittedAt'), tCommon('common.table.actions')]

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb') }, { label: t('treatment.breadcrumb') }, { label: t('ediTva.breadcrumb') }]} />
      <PageHeader
        title={t('ediTva.title')}
        subtitle={t('ediTva.subtitle')}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={6} />
      ) : returns.length === 0 ? (
        <EmptyState
          icon={<FileCheck className="w-8 h-8" />}
          title={t('ediTva.noReturns')}
          description={t('ediTva.noReturnsDescription')}
        />
      ) : (
        <Card>
          <Table headers={tableHeaders}>
            {returns.map((ret: any) => (
              <TableRow key={ret.id}>
                <TableCell className="text-sm font-medium">{ret.period || ret.label || '—'}</TableCell>
                <TableCell className="font-mono text-xs text-right">{Number(ret.amount || 0).toFixed(2)}</TableCell>
                <TableCell className="font-mono text-xs">{ret.edi_tva_id || '—'}</TableCell>
                <TableCell>
                  <Badge variant={ret.edi_status === 'acknowledged' ? 'success' : ret.edi_status === 'submitted' ? 'warning' : ret.edi_status === 'rejected' ? 'danger' : 'neutral'}>
                    {t(`ediTva.statuses.${ret.edi_status || 'not_submitted'}`)}
                  </Badge>
                </TableCell>
                <TableCell className="text-xs">{ret.edi_submitted_at ? formatDate(ret.edi_submitted_at) : '—'}</TableCell>
                <TableCell>
                  {(ret.edi_status || 'not_submitted') === 'not_submitted' && (
                    <button onClick={() => handleSubmit(ret.id)} className="flex items-center gap-1 px-2 py-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)] text-xs">
                      <Send className="w-3.5 h-3.5" /> {t('ediTva.submit')}
                    </button>
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
