import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Badge, EmptyState, Breadcrumb } from '@/components/ui'
import { SearchableSelect } from '@/components/SearchableSelect'
import { useToast } from '@/lib/toast'
import { confirmDialog } from '@/lib/confirm'
import { Upload, ShieldAlert, CheckCircle2, AlertTriangle } from 'lucide-react'
import { getLegislationPacks } from '@/lib/queries/accounting'
import {
  isPlatformAdmin, listChartPackStatus, parseChartCsv, uploadChartPack, publishChartPack,
  type ChartPackRow, type ChartPackStatus, type UploadResult, type PublishResult,
} from '@/lib/queries/chartPacks'
import type { LegislationPack } from '@/types'

// Téléversement et publication du plan comptable d'un pays (réservé à l'éditeur).
// La publication bascule automatiquement les sociétés du pays restées au plan
// provisoire et sans écriture validée (migration 201).
export function ChartPacksAdminPage() {
  const { t } = useTranslation('settings')
  const { toast } = useToast()
  const [allowed, setAllowed] = useState<boolean | null>(null)
  const [packs, setPacks] = useState<LegislationPack[]>([])
  const [statuses, setStatuses] = useState<ChartPackStatus[]>([])
  const [packCode, setPackCode] = useState('DJ')
  const [fileName, setFileName] = useState('')
  const [rows, setRows] = useState<ChartPackRow[]>([])
  const [fileErrors, setFileErrors] = useState<string[]>([])
  const [upload, setUpload] = useState<UploadResult | null>(null)
  const [publish, setPublish] = useState<PublishResult | null>(null)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    const [p, s] = await Promise.all([getLegislationPacks(), listChartPackStatus()])
    setPacks(p)
    setStatuses(s)
  }, [])

  useEffect(() => {
    isPlatformAdmin().then((ok) => {
      setAllowed(ok)
      if (ok) load().catch((e) => toast('error', t('chartPacks.title'), String(e)))
    })
  }, [load, toast, t])

  const status = statuses.find((s) => s.pack_code === packCode)
  const isPublished = status?.status === 'published'

  async function handleFile(file: File | undefined) {
    setUpload(null)
    setPublish(null)
    if (!file) return
    setFileName(file.name)
    const parsed = parseChartCsv(await file.text())
    setRows(parsed.rows)
    setFileErrors(parsed.errors)
  }

  async function handleUpload() {
    setBusy(true)
    setPublish(null)
    try {
      const res = await uploadChartPack(packCode, rows)
      setUpload(res)
      if (res.success) toast('success', t('chartPacks.title'), t('chartPacks.uploaded', { count: res.accounts }))
      await load()
    } catch (e) {
      toast('error', t('chartPacks.title'), e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function handlePublish() {
    const ok = await confirmDialog({
      title: t('chartPacks.title'),
      message: t('chartPacks.publishConfirm', { pack: packCode }),
      variant: 'primary',
    })
    if (!ok) return
    setBusy(true)
    try {
      const res = await publishChartPack(packCode)
      setPublish(res)
      toast('success', t('chartPacks.title'), t('chartPacks.published'))
      await load()
    } catch (e) {
      toast('error', t('chartPacks.title'), e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  if (allowed === null) return null
  if (!allowed) {
    return (
      <EmptyState
        icon={<ShieldAlert className="w-8 h-8" />}
        title={t('chartPacks.forbiddenTitle')}
        description={t('chartPacks.forbidden')}
      />
    )
  }

  const canPublish = !isPublished && status?.status === 'draft' && status.account_count > 0
    && (upload?.missing_required?.length ?? 0) === 0

  return (
    <div className="space-y-6">
      <Breadcrumb items={[{ label: t('chartPacks.breadcrumb'), path: '/settings' }, { label: t('chartPacks.title') }]} />
      <PageHeader title={t('chartPacks.title')} subtitle={t('chartPacks.subtitle')} />

      <Card title={t('chartPacks.statusTitle')}>
        <div className="p-6 space-y-2">
          {statuses.map((s) => (
            <div key={s.pack_code} className="flex items-center justify-between text-sm">
              <span>{packs.find((p) => p.code === s.pack_code)?.name ?? s.pack_code}</span>
              <span className="flex items-center gap-3">
                <span className="text-[var(--color-text-secondary)]">{t('chartPacks.accounts', { count: s.account_count })}</span>
                <Badge variant={s.status === 'published' ? 'success' : 'warning'}>
                  {t(s.status === 'published' ? 'chartPacks.statusPublished' : 'chartPacks.statusDraft')}
                </Badge>
              </span>
            </div>
          ))}
        </div>
      </Card>

      <Card title={t('chartPacks.uploadTitle')}>
        <div className="p-6 space-y-4">
          <div className="space-y-1.5 max-w-sm">
            <label className="text-sm font-medium">{t('chartPacks.pack')}</label>
            <SearchableSelect
              value={packCode}
              onChange={(v) => { setPackCode(v); setUpload(null); setPublish(null) }}
              options={packs.filter((p) => p.code !== 'FR').map((p) => ({ value: p.code, label: `${p.country_name} — ${p.name}` }))}
              className="w-full"
            />
          </div>

          <p className="text-xs text-[var(--color-text-secondary)]">{t('chartPacks.format')}</p>

          {isPublished ? (
            <p className="text-sm">{t('chartPacks.alreadyPublished')}</p>
          ) : (
            <>
              <label className="inline-flex items-center gap-2 cursor-pointer text-sm">
                <Upload className="w-4 h-4" />
                <span>{fileName || t('chartPacks.chooseFile')}</span>
                <input type="file" accept=".csv,text/csv" className="hidden" onChange={(e) => handleFile(e.target.files?.[0])} />
              </label>

              {fileErrors.map((err) => <p key={err} className="text-sm text-[var(--color-danger)]">{err}</p>)}
              {rows.length > 0 && fileErrors.length === 0 && (
                <p className="text-sm">{t('chartPacks.rowsRead', { count: rows.length })}</p>
              )}

              <div className="flex gap-3">
                <Button onClick={handleUpload} disabled={busy || rows.length === 0 || fileErrors.length > 0} loading={busy}>
                  {t('chartPacks.upload')}
                </Button>
                <Button variant="secondary" onClick={handlePublish} disabled={busy || !canPublish}>
                  {t('chartPacks.publish')}
                </Button>
              </div>
            </>
          )}

          {upload && !upload.success && (
            <div className="space-y-1">
              <p className="text-sm font-medium text-[var(--color-danger)]">{t('chartPacks.lineErrors')}</p>
              <ul className="text-sm list-disc pl-5 max-h-64 overflow-y-auto">
                {upload.errors?.map((e) => (
                  <li key={`${e.line}-${e.error}`}>{t('chartPacks.lineError', { line: e.line, code: e.code ?? '', error: e.error })}</li>
                ))}
              </ul>
            </div>
          )}

          {upload?.success && (upload.missing_required?.length ?? 0) > 0 && (
            <div className="flex gap-2 text-sm text-[var(--color-warning,#b45309)]">
              <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{t('chartPacks.missingRequired', { codes: upload.missing_required?.join(', ') })}</span>
            </div>
          )}

          {publish && (
            <div className="flex gap-2 text-sm">
              <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5 text-[var(--color-success,#15803d)]" />
              <div>
                <p>{t('chartPacks.switched', { count: publish.tenants.filter((x) => x.switched).length })}</p>
                {publish.tenants.some((x) => !x.switched) && (
                  <p>{t('chartPacks.notSwitched', { count: publish.tenants.filter((x) => !x.switched).length })}</p>
                )}
              </div>
            </div>
          )}
        </div>
      </Card>
    </div>
  )
}
