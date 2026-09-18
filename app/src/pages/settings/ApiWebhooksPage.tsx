// @ts-nocheck
import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { PageHeader, Button, Table, TableRow, TableCell, Input, Select, Badge, EmptyState, Breadcrumb, SkeletonTable, Modal } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { useToast } from '@/lib/toast'
import { getTenantId } from '@/lib/queries/core'
import { Key, Webhook, Plus, Trash2, Copy, RefreshCw,  X, AlertTriangle, Activity } from 'lucide-react'
import { confirmSync } from '@/lib/confirm'

// LOT5-05 : Validation SSRF côté client — doit correspondre à is_allowed_webhook_url (SQL) et isAllowedWebhookUrl (Edge Function)
function isAllowedWebhookUrl(raw: string): boolean {
  let u: URL
  try { u = new URL(raw) } catch (e) { console.error('isAllowedWebhookUrl: invalid URL:', e); return false }
  if (u.protocol !== 'https:') return false
  const h = u.hostname.toLowerCase().replace(/^\[|\]$/g, '')
  if (h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal')) return false
  if (/^(127\.|10\.|192\.168\.|169\.254\.|0\.)/.test(h)) return false
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(h)) return false
  if (h === '::1' || h.startsWith('fd') || h.startsWith('fe80:')) return false
  return true
}

interface ApiKey {
  id: string
  name: string
  key_prefix: string
  permissions: string[]
  rate_limit_per_min: number
  active: boolean
  expires_at: string | null
  last_used_at: string | null
  created_at: string
}

interface WebhookEndpoint {
  id: string
  name: string
  url: string
  secret: string | null
  active_events: string[]
  active: boolean
  created_at: string
  updated_at: string
}

interface DeliveryLog {
  id: string
  endpoint_id: string
  url: string
  event: string
  status: string
  attempt: number
  response_code: number | null
  error_message: string | null
  delivered_at: string
}

const EVENT_TYPES = [
  'invoice.created', 'invoice.paid', 'invoice.overdue',
  'purchase_invoice.received', 'payment.received', 'payment.sent',
  'payslip.ready', 'dsn.submitted', 'vat_return.submitted',
  'customer.created', 'supplier.created', 'stock.movement',
  'fiscal_year.closed', 'bank_transaction.imported',
]

export function ApiWebhooksPage() {
  const { t } = useTranslation()
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [tab, setTab] = useState<'api-keys' | 'webhooks' | 'logs'>('api-keys')
  const [apiKeys, setApiKeys] = useState<ApiKey[]>([])
  const [webhooks, setWebhooks] = useState<WebhookEndpoint[]>([])
  const [logs, setLogs] = useState<DeliveryLog[]>([])
  const [loading, setLoading] = useState(true)
  const [showKeyModal, setShowKeyModal] = useState(false)
  const [showWebhookModal, setShowWebhookModal] = useState(false)
  const [newKeyName, setNewKeyName] = useState('')
  const [newKeyPerms, setNewKeyPerms] = useState<string[]>(['read'])
  const [newKeyLimit, setNewKeyLimit] = useState(100)
  const [createdKey, setCreatedKey] = useState<string | null>(null)
  const [whName, setWhName] = useState('')
  const [whUrl, setWhUrl] = useState('')
  const [whEvents, setWhEvents] = useState<string[]>(['*'])
  const [logsEndpoint, setLogsEndpoint] = useState<string>('all')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [keysRes, whRes] = await Promise.all([
        supabase.from('api_keys').select('*').order('created_at', { ascending: false }),
        supabase.from('webhook_endpoints').select('*').order('created_at', { ascending: false }),
      ])
      if (keysRes.data) setApiKeys(keysRes.data as ApiKey[])
      if (whRes.data) setWebhooks(whRes.data as WebhookEndpoint[])
    } catch (err: any) {
      toast('error', 'Error', err.message)
    } finally {
      setLoading(false)
    }
  }, [toast])

  const loadLogs = useCallback(async () => {
    let q = supabase.from('webhook_delivery_logs').select('*').order('delivered_at', { ascending: false }).limit(100)
    if (logsEndpoint !== 'all') q = q.eq('endpoint_id', logsEndpoint)
    const { data, error } = await q
    if (error) toast('error', 'Error', error.message)
    else setLogs(data || [])
  }, [logsEndpoint, toast])

  useEffect(() => { loadData() }, [loadData])
  useEffect(() => { if (tab === 'logs') loadLogs() }, [tab, loadLogs])

  async function handleCreateKey() {
    if (!newKeyName.trim()) return
    try {
      const { data, error } = await supabase.rpc('create_api_key', {
        p_name: newKeyName,
        p_permissions: newKeyPerms,
        p_rate_limit: newKeyLimit,
      })
      if (error) throw error
      setCreatedKey(data?.full_key || data)
      setNewKeyName('')
      setNewKeyPerms(['read'])
      setNewKeyLimit(100)
      await loadData()
      toast('success', 'Clé API créée', 'Copiez la clé maintenant, elle ne sera plus affichée.')
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleRevokeKey(id: string) {
    if (!confirmSync('Révoquer cette clé API ? Action irréversible.')) return
    try {
      const { error } = await supabase.from('api_keys').update({ active: false, revoked_at: new Date().toISOString() }).eq('id', id)
      if (error) throw error
      await loadData()
      toast('success', 'Clé révoquée', '')
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleDeleteKey(id: string) {
    if (!confirmSync('Supprimer définitivement cette clé ?')) return
    try {
      const { error } = await supabase.from('api_keys').delete().eq('id', id)
      if (error) throw error
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleCreateWebhook() {
    if (!whName.trim() || !whUrl.trim()) return
    // LOT5-05 : Validation SSRF côté client avant l'envoi
    if (!isAllowedWebhookUrl(whUrl)) {
      toast('error', 'URL non autorisée', 'L\'URL doit être en HTTPS et ne pas pointer vers un réseau privé (SSRF)')
      return
    }
    try {
      const tid = await getTenantId()
      if (!tid) throw new Error('Aucun tenant actif')
      const { error } = await supabase.from('webhook_endpoints').insert({
        name: whName,
        url: whUrl,
        active_events: whEvents,
        tenant_id: tid,
      })
      if (error) throw error
      setWhName('')
      setWhUrl('')
      setWhEvents(['*'])
      setShowWebhookModal(false)
      await loadData()
      toast('success', 'Webhook créé', '')
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleToggleWebhook(wh: WebhookEndpoint) {
    try {
      const { error } = await supabase.from('webhook_endpoints').update({ active: !wh.active }).eq('id', wh.id)
      if (error) throw error
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  async function handleDeleteWebhook(id: string) {
    if (!confirmSync('Supprimer ce webhook ?')) return
    try {
      const { error } = await supabase.from('webhook_endpoints').delete().eq('id', id)
      if (error) throw error
      await loadData()
    } catch (err: any) {
      toast('error', 'Erreur', err.message)
    }
  }

  function copyToClipboard(text: string) {
    navigator.clipboard.writeText(text)
    toast('success', 'Copié', '')
  }

  function toggleEvent(event: string) {
    setWhEvents(prev => prev.includes('*') ? [event] : prev.includes(event) ? prev.filter(e => e !== event) : [...prev, event])
  }

  return (
    <div className="space-y-6">
      <Breadcrumb items={[{ label: t('nav.settings'), href: '/settings' }, { label: 'API & Webhooks' }]} />
      <PageHeader title="API & Webhooks" description="Gérez vos clés API et webhooks sortants" />

      <div className="flex gap-2 border-b border-[var(--color-border)]">
        <button onClick={() => setTab('api-keys')} className={`px-4 py-2 text-sm font-medium border-b-2 ${tab === 'api-keys' ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)]'}`}>
          <Key className="w-4 h-4 inline mr-1" /> Clés API
        </button>
        <button onClick={() => setTab('webhooks')} className={`px-4 py-2 text-sm font-medium border-b-2 ${tab === 'webhooks' ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)]'}`}>
          <Webhook className="w-4 h-4 inline mr-1" /> Webhooks
        </button>
        <button onClick={() => setTab('logs')} className={`px-4 py-2 text-sm font-medium border-b-2 ${tab === 'logs' ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)]'}`}>
          <Activity className="w-4 h-4 inline mr-1" /> Logs de livraison
        </button>
      </div>

      {tab === 'api-keys' && (
        <div className="space-y-4">
          <div className="flex justify-end">
            <Button onClick={() => { setShowKeyModal(true); setCreatedKey(null) }}><Plus className="w-4 h-4 mr-1" /> Nouvelle clé</Button>
          </div>
          {loading ? <SkeletonTable rows={3} cols={6} /> : apiKeys.length === 0 ? (
            <EmptyState icon={<Key className="w-8 h-8" />} title="Aucune clé API" description="Créez une clé pour accéder à l'API publique." />
          ) : (
            <Table headers={['Nom', 'Préfixe', 'Permissions', 'Limite/min', 'Statut', 'Dernière utilisation', 'Actions']}>
              {apiKeys.map(k => (
                <TableRow key={k.id}>
                  <TableCell className="font-medium">{k.name}</TableCell>
                  <TableCell className="font-mono text-xs">{k.key_prefix}...</TableCell>
                  <TableCell><div className="flex gap-1 flex-wrap">{(k.permissions || []).map(p => <Badge key={p} variant="info">{p}</Badge>)}</div></TableCell>
                  <TableCell className="text-xs">{k.rate_limit_per_min}</TableCell>
                  <TableCell>{k.active ? <Badge variant="success">Active</Badge> : <Badge variant="danger">Révoquée</Badge>}</TableCell>
                  <TableCell className="text-xs text-[var(--color-text-secondary)]">{k.last_used_at ? new Date(k.last_used_at).toLocaleString('fr-FR') : 'Jamais'}</TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      {k.active && <button onClick={() => handleRevokeKey(k.id)} title="Révoquer" className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-warning)]"><X className="w-4 h-4" /></button>}
                      <button onClick={() => handleDeleteKey(k.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </div>
      )}

      {tab === 'webhooks' && (
        <div className="space-y-4">
          <div className="flex justify-end">
            <Button onClick={() => setShowWebhookModal(true)}><Plus className="w-4 h-4 mr-1" /> Nouveau webhook</Button>
          </div>
          {loading ? <SkeletonTable rows={3} cols={5} /> : webhooks.length === 0 ? (
            <EmptyState icon={<Webhook className="w-8 h-8" />} title="Aucun webhook" description="Configurez un endpoint pour recevoir des événements." />
          ) : (
            <Table headers={['Nom', 'URL', 'Événements', 'Statut', 'Actions']}>
              {webhooks.map(w => (
                <TableRow key={w.id}>
                  <TableCell className="font-medium">{w.name}</TableCell>
                  <TableCell className="font-mono text-xs max-w-xs truncate">{w.url}</TableCell>
                  <TableCell><div className="flex gap-1 flex-wrap">{(w.active_events || []).map(e => <Badge key={e} variant="info">{e}</Badge>)}</div></TableCell>
                  <TableCell>
                    <button onClick={() => handleToggleWebhook(w)}>{w.active ? <Badge variant="success">Actif</Badge> : <Badge variant="neutral">Inactif</Badge>}</button>
                  </TableCell>
                  <TableCell>
                    <button onClick={() => handleDeleteWebhook(w.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" aria-label={tCommon('actions.delete')} title={tCommon('actions.delete')}><Trash2 className="w-4 h-4" aria-hidden="true" /></button>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </div>
      )}

      {tab === 'logs' && (
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Select value={logsEndpoint} onChange={(e) => setLogsEndpoint(e.target.value)}>
              <option value="all">Tous les endpoints</option>
              {webhooks.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
            </Select>
            <Button variant="outline" onClick={loadLogs}><RefreshCw className="w-4 h-4 mr-1" /> Actualiser</Button>
          </div>
          {logs.length === 0 ? (
            <EmptyState icon={<Activity className="w-8 h-8" />} title="Aucun log" description="Les livraisons de webhooks apparaîtront ici." />
          ) : (
            <Table headers={['Date', 'Événement', 'URL', 'Statut', 'Code', 'Tentative', 'Erreur']}>
              {logs.map(l => (
                <TableRow key={l.id}>
                  <TableCell className="text-xs">{new Date(l.delivered_at).toLocaleString('fr-FR')}</TableCell>
                  <TableCell className="font-mono text-xs">{l.event}</TableCell>
                  <TableCell className="font-mono text-xs max-w-xs truncate">{l.url}</TableCell>
                  <TableCell>
                    {l.status === 'delivered' ? <Badge variant="success">Livré</Badge> : l.status === 'failed' ? <Badge variant="danger">Échec</Badge> : <Badge variant="warning">{l.status}</Badge>}
                  </TableCell>
                  <TableCell className="text-xs">{l.response_code || '—'}</TableCell>
                  <TableCell className="text-xs">{l.attempt}</TableCell>
                  <TableCell className="text-xs text-[var(--color-danger)] max-w-xs truncate">{l.error_message || '—'}</TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </div>
      )}

      {/* Modal création clé API */}
      {showKeyModal && (
        <Modal open={showKeyModal} onClose={() => setShowKeyModal(false)} title="Nouvelle clé API">
          {createdKey ? (
            <div className="space-y-4">
              <div className="p-4 bg-[var(--color-warning-50)] border border-[var(--color-warning)] rounded-lg flex gap-3">
                <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0" />
                <p className="text-sm">Copiez votre clé maintenant. Elle ne sera plus jamais affichée.</p>
              </div>
              <div className="flex items-center gap-2">
                <Input value={createdKey} readOnly className="font-mono text-xs" />
                <Button onClick={() => copyToClipboard(createdKey)} ariaLabel={tCommon('actions.copy')}><Copy className="w-4 h-4" aria-hidden="true" /></Button>
              </div>
              <Button onClick={() => setShowKeyModal(false)} className="w-full">Fermer</Button>
            </div>
          ) : (
            <div className="space-y-4">
              <div>
                <label className="text-sm font-medium">Nom de la clé</label>
                <Input value={newKeyName} onChange={(e) => setNewKeyName(e.target.value)} placeholder="ex: Intégration CRM" />
              </div>
              <div>
                <label className="text-sm font-medium">Permissions</label>
                <div className="flex gap-2 flex-wrap mt-1">
                  {['read', 'write', 'delete'].map(p => (
                    <button key={p} onClick={() => setNewKeyPerms(prev => prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p])}
                      className={`px-3 py-1 rounded text-xs border ${newKeyPerms.includes(p) ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]' : 'border-[var(--color-border)]'}`}>
                      {p}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className="text-sm font-medium">Limite de requêtes / minute</label>
                <Input type="number" value={newKeyLimit} onChange={(e) => setNewKeyLimit(Number(e.target.value))} />
              </div>
              <Button onClick={handleCreateKey} disabled={!newKeyName.trim()} className="w-full">Créer la clé</Button>
            </div>
          )}
        </Modal>
      )}

      {/* Modal création webhook */}
      {showWebhookModal && (
        <Modal open={showWebhookModal} onClose={() => setShowWebhookModal(false)} title="Nouveau webhook">
          <div className="space-y-4">
            <div>
              <label className="text-sm font-medium">Nom</label>
              <Input value={whName} onChange={(e) => setWhName(e.target.value)} placeholder="ex: Notification Slack" />
            </div>
            <div>
              <label className="text-sm font-medium">URL</label>
              <Input value={whUrl} onChange={(e) => setWhUrl(e.target.value)} placeholder="https://votre-endpoint.com/webhook" />
              {whUrl && !isAllowedWebhookUrl(whUrl) && (
                <p className="text-xs text-[var(--color-danger)] mt-1">⚠ HTTPS requis, réseaux privés bloqués (SSRF)</p>
              )}
            </div>
            <div>
              <label className="text-sm font-medium">Événements</label>
              <div className="flex gap-2 flex-wrap mt-1 max-h-40 overflow-y-auto">
                <button onClick={() => setWhEvents(['*'])} className={`px-3 py-1 rounded text-xs border ${whEvents.includes('*') ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]' : 'border-[var(--color-border)]'}`}>Tous (*)</button>
                {EVENT_TYPES.map(e => (
                  <button key={e} onClick={() => toggleEvent(e)} className={`px-3 py-1 rounded text-xs border ${whEvents.includes(e) ? 'bg-[var(--color-primary)] text-white border-[var(--color-primary)]' : 'border-[var(--color-border)]'}`}>{e}</button>
                ))}
              </div>
            </div>
            <Button onClick={handleCreateWebhook} disabled={!whName.trim() || !whUrl.trim()} className="w-full">Créer le webhook</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}
