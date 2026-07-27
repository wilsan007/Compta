import { useState, useEffect } from 'react'
import { useParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Button, Card, EmptyState, SkeletonTable } from '@/components/ui'
import { getOnlinePaymentByToken, updateOnlinePaymentStatus } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { formatCurrency } from '@/lib/utils'
import { CreditCard, CheckCircle, XCircle, Loader2 } from 'lucide-react'
import type { OnlinePayment } from '@/types'

export function OnlinePaymentPage() {
  const { token } = useParams<{ token: string }>()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  const [payment, setPayment] = useState<OnlinePayment | null>(null)
  const [loading, setLoading] = useState(true)
  const [paying, setPaying] = useState(false)
  const [paid, setPaid] = useState(false)

  useEffect(() => {
    if (!token) return
    (async () => {
      try {
        const p = await getOnlinePaymentByToken(token)
        setPayment(p)
        if (p?.status === 'completed') setPaid(true)
      } catch (err: any) {
        toast('error', tCommon('toast.error'), err.message)
      } finally {
        setLoading(false)
      }
    })()
  }, [token])

  async function handlePay() {
    if (!payment) return
    setPaying(true)
    try {
      await updateOnlinePaymentStatus(payment.id, 'completed')
      setPaid(true)
      toast('success', tCommon('toast.success'), t('onlinePayment.paymentSuccess'))
    } catch (err: any) {
      toast('error', tCommon('toast.error'), t('onlinePayment.paymentFailed'))
    } finally {
      setPaying(false)
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center p-6">
        <Card className="w-full max-w-md">
          <SkeletonTable rows={3} cols={2} />
        </Card>
      </div>
    )
  }

  if (!payment) {
    return (
      <div className="min-h-screen flex items-center justify-center p-6">
        <Card className="w-full max-w-md">
          <EmptyState icon={<XCircle className="w-8 h-8" />} title={t('onlinePayment.paymentFailed')} />
        </Card>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-6">
      <Card className="w-full max-w-md">
        <div className="text-center mb-6">
          <div className="w-16 h-16 rounded-full bg-[var(--color-primary)] bg-opacity-10 flex items-center justify-center mx-auto mb-4">
            <CreditCard className="w-8 h-8 text-[var(--color-primary)]" />
          </div>
          <h1 className="text-2xl font-bold">{t('onlinePayment.title')}</h1>
        </div>

        <div className="space-y-4">
          <div className="flex justify-between py-2 border-b border-[var(--color-border)]">
            <span className="text-sm text-[var(--color-text-secondary)]">{t('onlinePayment.invoiceNumber')}</span>
            <span className="text-sm font-mono">{(payment as any).invoice?.number || '—'}</span>
          </div>
          <div className="flex justify-between py-2 border-b border-[var(--color-border)]">
            <span className="text-sm text-[var(--color-text-secondary)]">{t('onlinePayment.amount')}</span>
            <span className="text-xl font-bold">{formatCurrency(payment.amount)}</span>
          </div>
          <div className="flex justify-between py-2 border-b border-[var(--color-border)]">
            <span className="text-sm text-[var(--color-text-secondary)]">{t('onlinePayment.paymentProvider')}</span>
            <span className="text-sm capitalize">{payment.payment_provider || '—'}</span>
          </div>

          {paid ? (
            <div className="text-center py-6">
              <CheckCircle className="w-12 h-12 text-[var(--color-success)] mx-auto mb-3" />
              <p className="text-lg font-medium text-[var(--color-success)]">{t('onlinePayment.paymentSuccess')}</p>
            </div>
          ) : (
            <Button className="w-full" size="lg" onClick={handlePay} loading={paying} disabled={paying}>
              {paying ? <Loader2 className="w-5 h-5 animate-spin" /> : <CreditCard className="w-5 h-5" />}
              {t('onlinePayment.payNow')}
            </Button>
          )}
        </div>
      </Card>
    </div>
  )
}
