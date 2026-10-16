import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Input, Select, Badge, EmptyState, Breadcrumb, Skeleton } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import { confirmSync } from '@/lib/confirm'
import {
  getBusinessConnectors,
  createBusinessConnector,
  deleteBusinessConnector,
  CONNECTOR_TYPES,
  AUTH_TYPES,
  type BusinessConnector,
} from '@/lib/queries/businessConnectors'
import { Plug, Plus, Trash2 } from 'lucide-react'

export function BusinessConnectorsPage() {
  const { t } = useTranslation('settings')
  const { t: tNav } = useTranslation('nav')
  const { toast } = useToast()

  const [connectors, setConnectors] = useState<BusinessConnector[]>([])
  const [loading, setLoading] = useState(true)

  const [name, setName] = useState('')
  const [connectorType, setConnectorType] = useState<string>('rest')
  const [baseUrl, setBaseUrl] = useState('')
  const [authType, setAuthType] = useState<string>('none')
  const [authRef, setAuthRef] = useState('')

  const loadAll = useCallback(async () => {
    try {
      setConnectors(await getBusinessConnectors())
    } catch (err) {
      toast('error', t('businessConnectors.title'), errorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { loadAll() }, [loadAll])

  async function handleCreate() {
    if (!name.trim() || !baseUrl.trim()) return
    try {
      await createBusinessConnector({
        name: name.trim(),
        connectorType,
        baseUrl: baseUrl.trim(),
        authType,
        authRef,
      })
      setName(''); setBaseUrl(''); setAuthRef('')
      await loadAll()
    } catch (err) {
      toast('error', t('businessConnectors.title'), errorMessage(err))
    }
  }

  async function handleDelete(id: string) {
    if (!confirmSync(t('businessConnectors.confirmDelete'))) return
    try {
      await deleteBusinessConnector(id)
      await loadAll()
    } catch (err) {
      toast('error', t('businessConnectors.title'), errorMessage(err))
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: tNav('groups.system') }, { label: t('businessConnectors.title') }]} />
      <PageHeader title={t('businessConnectors.title')} subtitle={t('businessConnectors.subtitle')} />

      {loading ? (
        <Skeleton className="h-40 w-full" />
      ) : (
        <div className="space-y-6">
          <Card>
            <div className="flex items-center gap-2 mb-3">
              <Plug className="w-5 h-5 text-[var(--color-primary)]" aria-hidden="true" />
              <h3 className="font-semibold">{t('businessConnectors.createTitle')}</h3>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-6 gap-2">
              <Input label={t('businessConnectors.name')} value={name} onChange={(e) => setName(e.target.value)} />
              <Select label={t('businessConnectors.type')} value={connectorType} onChange={(e) => setConnectorType(e.target.value)}>
                {CONNECTOR_TYPES.map((c) => <option key={c} value={c}>{t(`businessConnectors.types.${c}`)}</option>)}
              </Select>
              <Input label={t('businessConnectors.baseUrl')} value={baseUrl}
                onChange={(e) => setBaseUrl(e.target.value)} placeholder="https://api.exemple.com" />
              <Select label={t('businessConnectors.auth')} value={authType} onChange={(e) => setAuthType(e.target.value)}>
                {AUTH_TYPES.map((a) => <option key={a} value={a}>{t(`businessConnectors.authTypes.${a}`)}</option>)}
              </Select>
              <Input label={t('businessConnectors.authRef')} value={authRef}
                onChange={(e) => setAuthRef(e.target.value)} disabled={authType === 'none'} placeholder="NOM_DU_SECRET" />
              <div className="flex items-end">
                <Button onClick={handleCreate} disabled={!name.trim() || !baseUrl.trim()}>
                  <Plus className="w-4 h-4 mr-1" aria-hidden="true" />{t('businessConnectors.create')}
                </Button>
              </div>
            </div>
            <p className="text-xs text-[var(--color-text-secondary)] mt-2">{t('businessConnectors.urlHint')}</p>
          </Card>

          {connectors.length === 0 ? (
            <EmptyState icon={<Plug className="w-8 h-8" aria-hidden="true" />} title={t('businessConnectors.empty')} />
          ) : (
            <Card>
              <ul className="divide-y divide-[var(--color-border)]">
                {connectors.map((c) => (
                  <li key={c.id} className="flex items-center justify-between py-2">
                    <div>
                      <span className="font-medium">{c.name}</span>{' '}
                      <Badge variant="neutral">{t(`businessConnectors.types.${c.connector_type}`)}</Badge>{' '}
                      <span className="text-sm text-[var(--color-text-secondary)]">
                        {c.base_url}
                        {c.auth_ref ? ` · ${t(`businessConnectors.authTypes.${c.auth_type}`)} : ${c.auth_ref}` : ''}
                      </span>
                    </div>
                    <button
                      type="button"
                      onClick={() => handleDelete(c.id)}
                      aria-label={t('businessConnectors.remove')}
                      title={t('businessConnectors.remove')}
                      className="text-[var(--color-danger)] min-w-[24px] min-h-[24px]"
                    >
                      <Trash2 className="w-4 h-4" aria-hidden="true" />
                    </button>
                  </li>
                ))}
              </ul>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}

