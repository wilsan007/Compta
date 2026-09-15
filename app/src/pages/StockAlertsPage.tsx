import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Button, Table, TableRow, TableCell, Badge, EmptyState, Select } from '@/components/ui'
import { formatDate } from '@/lib/utils'
import { getStockAlerts, acknowledgeStockAlert, resolveStockAlert, checkStockThresholds } from '@/lib/queries/catalogAdvanced'
import { useToast } from '@/lib/toast'
import { AlertTriangle, CheckCircle, Bell, ShieldCheck } from 'lucide-react'
import type { StockAlert, Product } from '@/types'

type AlertWithRelations = StockAlert & { product: Pick<Product, 'name' | 'sku'> | null, warehouse: { name: string } | null }

export function StockAlertsPage() {
  const { t } = useTranslation('stock')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [alerts, setAlerts] = useState<AlertWithRelations[]>([])
  const [loading, setLoading] = useState(true)
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'acknowledged' | 'resolved'>('all')
  const [filterType, setFilterType] = useState<'all' | 'low_stock' | 'out_of_stock' | 'overstock' | 'expiry'>('all')
  const [checking, setChecking] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const data = await getStockAlerts(filterStatus === 'all' ? undefined : filterStatus as any)
      setAlerts(data || [])
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [filterStatus, toast, tCommon])

  useEffect(() => { load() }, [load])

  const filtered = alerts.filter(a => filterType === 'all' || a.alert_type === filterType)

  async function handleAcknowledge(id: string) {
    try {
      await acknowledgeStockAlert(id)
      toast('success', tCommon('toast.success'), t('alerts.acknowledged'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleResolve(id: string) {
    try {
      await resolveStockAlert(id)
      toast('success', tCommon('toast.success'), t('alerts.resolved'))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    }
  }

  async function handleCheckThresholds() {
    setChecking(true)
    try {
      const created = await checkStockThresholds()
      toast('success', tCommon('toast.success'), t('alerts.alertsCreated', { count: created.length }))
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message)
    } finally {
      setChecking(false)
    }
  }

  function getAlertBadgeVariant(type: string): 'danger' | 'warning' | 'neutral' | 'success' {
    if (type === 'out_of_stock') return 'danger'
    if (type === 'low_stock') return 'warning'
    if (type === 'overstock') return 'neutral'
    return 'success'
  }

  function getStatusBadgeVariant(status: string): 'danger' | 'warning' | 'neutral' | 'success' {
    if (status === 'active') return 'danger'
    if (status === 'acknowledged') return 'warning'
    return 'success'
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <AlertTriangle className="w-6 h-6 text-[var(--color-warning)]" />
            {t('alerts.title')}
          </h1>
          <p className="text-sm text-[var(--color-text-secondary)] mt-1">{t('alerts.subtitle')}</p>
        </div>
        <Button onClick={handleCheckThresholds} disabled={checking}>
          <Bell className="w-4 h-4" /> {checking ? '...' : t('alerts.checkThresholds')}
        </Button>
      </div>

      <div className="flex items-center gap-4 mb-4">
        <Select
          value={filterStatus}
          onChange={(e) => setFilterStatus(e.target.value as any)}
          options={[
            { value: 'all', label: tCommon('filters.all') },
            { value: 'active', label: t('alerts.active') },
            { value: 'acknowledged', label: t('alerts.acknowledged') },
            { value: 'resolved', label: t('alerts.resolved') },
          ]}
        />
        <Select
          value={filterType}
          onChange={(e) => setFilterType(e.target.value as any)}
          options={[
            { value: 'all', label: tCommon('filters.all') },
            { value: 'low_stock', label: t('alerts.lowStock') },
            { value: 'out_of_stock', label: t('alerts.outOfStock') },
            { value: 'overstock', label: t('alerts.overstock') },
            { value: 'expiry', label: t('alerts.expiry') },
          ]}
        />
      </div>

      {loading ? (
        <div className="space-y-2">
          {[1, 2, 3].map(i => <div key={i} className="h-12 rounded animate-pulse bg-[var(--color-neutral-100)]" />)}
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<CheckCircle className="w-8 h-8" />}
          title={t('alerts.noAlerts')}
          description={t('alerts.noAlertsDescription')}
        />
      ) : (
        <Table headers={[t('alerts.type'), t('alerts.product'), t('alerts.warehouse'), t('alerts.currentValue'), t('alerts.threshold'), t('alerts.status'), t('alerts.triggeredAt'), tCommon('table.actions')]}>
          {filtered.map((a) => (
            <TableRow key={a.id}>
              <TableCell>
                <Badge variant={getAlertBadgeVariant(a.alert_type)}>
                  {t(`alerts.${a.alert_type === 'low_stock' ? 'lowStock' : a.alert_type === 'out_of_stock' ? 'outOfStock' : a.alert_type === 'overstock' ? 'overstock' : 'expiry'}`)}
                </Badge>
              </TableCell>
              <TableCell className="text-xs">{a.product?.name || '-'} {a.product?.sku ? `(${a.product.sku})` : ''}</TableCell>
              <TableCell className="text-xs">{a.warehouse?.name || '-'}</TableCell>
              <TableCell className="font-mono text-xs">{a.current_value != null ? Number(a.current_value) : '-'}</TableCell>
              <TableCell className="font-mono text-xs">{a.threshold != null ? Number(a.threshold) : '-'}</TableCell>
              <TableCell>
                <Badge variant={getStatusBadgeVariant(a.status)}>
                  {t(`alerts.${a.status}`)}
                </Badge>
              </TableCell>
              <TableCell className="text-xs">{formatDate(a.triggered_at)}</TableCell>
              <TableCell>
                <div className="flex gap-1">
                  {a.status === 'active' && (
                    <button onClick={() => handleAcknowledge(a.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]" title={t('alerts.acknowledge')}>
                      <Bell className="w-4 h-4" />
                    </button>
                  )}
                  {(a.status === 'active' || a.status === 'acknowledged') && (
                    <button onClick={() => handleResolve(a.id)} className="p-1 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-success)]" title={t('alerts.resolve')}>
                      <ShieldCheck className="w-4 h-4" />
                    </button>
                  )}
                </div>
              </TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}
