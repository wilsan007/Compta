import { useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Badge, Button } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { getTenantId } from '@/lib/queries/core'
import { CreditCard, Plus } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'

export function PosPaymentMethodsPage() {
  const { t } = useTranslation('pos')
  const { t: tNav } = useTranslation('nav')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [methods, setMethods] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    try {
      const tid = await getTenantId()
      const { data, error } = await supabase
        .from('pos_payment_methods')
        .select('*')
        .eq('tenant_id', tid)
        .eq('is_active', true)
        .order('display_order')
      if (error) throw error
      setMethods(data || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  loadData().catch(err => console.error('loadData:', err))

  const typeLabels: Record<string, string> = {
    cash: t('type_cash'), card: t('type_card'), check: t('type_check'),
    voucher: t('type_voucher'), transfer: t('type_transfer'), other: t('type_other'),
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('pos'), path: '/pos' }, { label: t('payment_methods') }]} />
      <PageHeader title={t('payment_methods')} />

      <Card>
        {loading ? (
          <SkeletonTable cols={5} rows={3} />
        ) : methods.length === 0 ? (
          <EmptyState
            icon={<CreditCard className="w-12 h-12" />}
            title={t('no_payment_methods')}
            action={<Button><Plus className="w-4 h-4 mr-2" />{t('add_method')}</Button>}
          />
        ) : (
          <Table headers={[t('name'), t('type'), t('account_code'), t('opens_drawer'), t('order')]}>
            {methods.map((m) => (
              <TableRow key={m.id}>
                <TableCell className="font-medium">{m.name}</TableCell>
                <TableCell><Badge>{typeLabels[m.type] || m.type}</Badge></TableCell>
                <TableCell className="font-mono">{m.account_code}</TableCell>
                <TableCell>{m.opens_cash_drawer ? '✓' : '—'}</TableCell>
                <TableCell>{m.display_order}</TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </Card>
    </div>
  )
}
