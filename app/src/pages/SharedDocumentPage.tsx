import { useState, useEffect } from 'react'
import { useParams } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { Button, Card, EmptyState, SkeletonTable } from '@/components/ui'
import { getDocumentShare } from '@/lib/queries'
import { useToast } from '@/lib/toast'
import { FileText, Download, Eye, Clock } from 'lucide-react'
import type { DocumentShare } from '@/types'

export function SharedDocumentPage() {
  const { token } = useParams<{ token: string }>()
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()

  const [share, setShare] = useState<DocumentShare | null>(null)
  const [loading, setLoading] = useState(true)
  const [expired, setExpired] = useState(false)

  useEffect(() => {
    if (!token) return
    (async () => {
      try {
        const s = await getDocumentShare(token)
        setShare(s)
        if (s?.expires_at && new Date(s.expires_at) < new Date()) {
          setExpired(true)
        }
      } catch (err: any) {
        toast('error', tCommon('toast.error'), err.message)
      } finally {
        setLoading(false)
      }
    })()
  }, [token])

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center p-6">
        <Card className="w-full max-w-md">
          <SkeletonTable rows={3} cols={2} />
        </Card>
      </div>
    )
  }

  if (!share) {
    return (
      <div className="min-h-screen flex items-center justify-center p-6">
        <Card className="w-full max-w-md">
          <EmptyState icon={<FileText className="w-8 h-8" />} title={tCommon('noData')} />
        </Card>
      </div>
    )
  }

  if (expired) {
    return (
      <div className="min-h-screen flex items-center justify-center p-6">
        <Card className="w-full max-w-md">
          <EmptyState icon={<Clock className="w-8 h-8" />} title={t('sharing.expired')} description={t('sharing.expiredDescription')} />
        </Card>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-6">
      <Card className="w-full max-w-2xl">
        <div className="text-center mb-6">
          <div className="w-16 h-16 rounded-full bg-[var(--color-primary)] bg-opacity-10 flex items-center justify-center mx-auto mb-4">
            <FileText className="w-8 h-8 text-[var(--color-primary)]" />
          </div>
          <h1 className="text-2xl font-bold">{t('sharing.title')}</h1>
        </div>

        <div className="space-y-4">
          <div className="flex justify-between py-2 border-b border-[var(--color-border)]">
            <span className="text-sm text-[var(--color-text-secondary)]">{t('sharing.sharedWith')}</span>
            <span className="text-sm">{share.shared_with_email}</span>
          </div>
          <div className="flex justify-between py-2 border-b border-[var(--color-border)]">
            <span className="text-sm text-[var(--color-text-secondary)]">{t('sharing.documentType')}</span>
            <span className="text-sm capitalize">{share.document_type}</span>
          </div>
          {share.expires_at && (
            <div className="flex justify-between py-2 border-b border-[var(--color-border)]">
              <span className="text-sm text-[var(--color-text-secondary)]">{t('sharing.expiresIn')}</span>
              <span className="text-sm">{new Date(share.expires_at).toLocaleDateString()}</span>
            </div>
          )}
          {share.viewed && (
            <div className="flex items-center gap-2 text-sm text-[var(--color-text-secondary)]">
              <Eye className="w-4 h-4" /> {tCommon('status.viewed')}
            </div>
          )}

          <div className="flex gap-2 mt-6">
            <Button className="flex-1" onClick={() => window.print()}>
              <Download className="w-4 h-4" /> {tCommon('actions.download')}
            </Button>
          </div>
        </div>
      </Card>
    </div>
  )
}
