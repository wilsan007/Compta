import { useState, useCallback } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Badge, Button } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { getTenantId } from '@/lib/queries/core'
import { calculateLatePaymentPenalties } from '@/lib/queries/businessFunctions'
import { formatCurrency } from '@/lib/utils'
import { ShieldCheck } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { useToast } from '@/lib/toast'

export function CreditControlPage() {
  const { t } = useTranslation('sales')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()
  const { t: tCommon } = useTranslation('common')
  const [customers, setCustomers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [penaltyLoading, setPenaltyLoading] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    try {
      const tid = await getTenantId()
      const { data, error } = await supabase
        .from('customers')
        .select('id, name, credit_limit, credit_used, credit_blocked, credit_policy')
        .eq('tenant_id', tid)
        .order('name')
      if (error) throw error
      setCustomers(data || [])
    } catch (err: any) { console.error('Error:', err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) }
    finally { setLoading(false) }
  }, [toast, tCommon])

  loadData().catch(err => console.error('loadData:', err))

  const getExposure = (c: any) => {
    const used = Number(c.credit_used || 0)
    const limit = Number(c.credit_limit || 0)
    if (limit === 0) return { pct: 0, level: 'none' }
    const pct = (used / limit) * 100
    if (pct >= 100) return { pct, level: 'blocked' }
    if (pct >= 80) return { pct, level: 'warning' }
    return { pct, level: 'ok' }
  }

  async function handleCalculatePenalties() {
    setPenaltyLoading('all')
    try {
      const tid = await getTenantId()
      const { data: invoices, error } = await supabase
        .from('invoices')
        .select('id, number')
        .eq('tenant_id', tid)
        .lt('due_date', new Date().toISOString())
        .neq('status', 'paid')
      if (error) throw error
      if (!invoices || invoices.length === 0) {
        toast('info', tCommon('common.info'), t('no_overdue_invoices'))
        return
      }
      let total = 0
      for (const inv of invoices) {
        try {
          const result = await calculateLatePaymentPenalties(inv.id)
          total += Number(result?.penalty_amount ?? result ?? 0)
        } catch (e: any) { console.error('Penalty calc failed for', inv.id, e); toast('error', tCommon('toast.error'), e.message || tCommon('toast.loadError')) }
      }
      toast('success', tCommon('common.success'), t('penalties_result', { amount: total, count: invoices.length }))
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message || tCommon('common.error'))
    } finally {
      setPenaltyLoading(null)
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('sales'), path: '/sales' }, { label: t('credit_control') }]} />
      <PageHeader title={t('credit_control')} />

      <div className="mb-4 flex justify-end">
        <Button onClick={handleCalculatePenalties} disabled={penaltyLoading === 'all'}>
          <ShieldCheck className="w-4 h-4" /> {t('calculate_penalties')}
        </Button>
      </div>

      <Card>
        {loading ? (
          <SkeletonTable cols={5} rows={5} />
        ) : customers.length === 0 ? (
          <EmptyState icon={<ShieldCheck className="w-12 h-12" />} title={t('no_customers')} />
        ) : (
          <Table headers={[t('customer'), t('credit_limit'), t('credit_used'), t('exposure'), t('status')]}>
            {customers.map((c) => {
              const exp = getExposure(c)
              return (
                <TableRow key={c.id}>
                  <TableCell className="font-medium">{c.name}</TableCell>
                  <TableCell className="font-mono">{formatCurrency(c.credit_limit || 0)}</TableCell>
                  <TableCell className="font-mono">{formatCurrency(c.credit_used || 0)}</TableCell>
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <div className="w-24 bg-gray-200 rounded-full h-2">
                        <div
                          className={`h-2 rounded-full ${exp.level === 'blocked' ? 'bg-red-600' : exp.level === 'warning' ? 'bg-yellow-500' : 'bg-green-600'}`}
                          style={{ width: `${Math.min(exp.pct, 100)}%` }}
                        />
                      </div>
                      <span className="text-xs">{exp.pct.toFixed(0)}%</span>
                    </div>
                  </TableCell>
                  <TableCell>
                    {c.credit_blocked ? (
                      <Badge variant="danger">{t('blocked')}</Badge>
                    ) : exp.level === 'blocked' ? (
                      <Badge variant="danger">{t('over_limit')}</Badge>
                    ) : exp.level === 'warning' ? (
                      <Badge variant="warning">{t('warning')}</Badge>
                    ) : (
                      <Badge variant="success">{t('ok')}</Badge>
                    )}
                  </TableCell>
                </TableRow>
              )
            })}
          </Table>
        )}
      </Card>
    </div>
  )
}
