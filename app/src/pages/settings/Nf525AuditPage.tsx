// @ts-nocheck
import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Select, Input } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { closeNf525Period, getNf525Attestation } from '@/lib/queries/businessFunctions'
import { useToast } from '@/lib/toast'
import { Shield, CheckCircle, AlertTriangle, RefreshCw, Lock, Download } from 'lucide-react'

interface Nf525Event {
  id: string
  event_type: string
  entity_type: string
  entity_id: string | null
  event_data: Record<string, any> | null
  sequence_number: number  // LOT1-06: maps to id (BIGSERIAL)
  previous_hash: string | null
  current_hash: string
  created_at: string
  user_id: string | null
}

const EVENT_TYPES = [
  'invoice.created', 'invoice.modified', 'invoice.cancelled',
  'payment.received', 'payment.sent',
  'journal_entry.created', 'journal_entry.modified',
  'fiscal_year.closed', 'vat_return.submitted',
  'stock.movement', 'purchase_invoice.received',
]

export function Nf525AuditPage() {
  const { t } = useTranslation('common')
  const { toast } = useToast()
  const [events, setEvents] = useState<Nf525Event[]>([])
  const [loading, setLoading] = useState(true)
  const [filterType, setFilterType] = useState<string>('all')
  const [integrityStatus, setIntegrityStatus] = useState<'idle' | 'verified' | 'corrupted' | 'checking'>('idle')
  const [integrityMessage, setIntegrityMessage] = useState<string>('')
  const [periodEnd, setPeriodEnd] = useState('')
  const [_periodStart, _setPeriodStart] = useState('')
  const [attestationStart, setAttestationStart] = useState('')
  const [attestationEnd, setAttestationEnd] = useState('')
  const [closingPeriod, setClosingPeriod] = useState(false)
  const [downloadingAttestation, setDownloadingAttestation] = useState(false)

  const loadEvents = useCallback(async () => {
    setLoading(true)
    try {
      let q = supabase
        .from('nf525_event_log')
        .select('*')
        .order('id', { ascending: false })
        .limit(200)
      if (filterType !== 'all') q = q.eq('event_type', filterType)
      const { data, error } = await q
      if (error) throw error
      setEvents((data || []) as Nf525Event[])
    } catch (err: any) {
      toast('error', t('error'), err.message)
    } finally {
      setLoading(false)
    }
  }, [filterType, toast, t])

  useEffect(() => { loadEvents() }, [loadEvents])

  async function handleVerifyIntegrity() {
    setIntegrityStatus('checking')
    setIntegrityMessage('')
    try {
      const { data, error } = await supabase.rpc('verify_nf525_chain')
      if (error) throw error
      const result = data as { valid?: boolean; verified?: boolean; message?: string; broken_at?: number }
      const isValid = result?.valid ?? result?.verified ?? false
      if (isValid) {
        setIntegrityStatus('verified')
        setIntegrityMessage(result?.message || t('nf525.chainValid'))
        toast('success', t('nf525.integrityVerified'), t('nf525.chainValid'))
      } else {
        setIntegrityStatus('corrupted')
        const msg = result?.message
          ? `${result.message}${result.broken_at ? ` (séquence #${result.broken_at})` : ''}`
          : t('nf525.chainCorrupted')
        setIntegrityMessage(msg)
        toast('error', t('nf525.integrityFailed'), msg)
      }
    } catch (err: any) {
      setIntegrityStatus('corrupted')
      setIntegrityMessage(err.message)
      toast('error', t('error'), err.message)
    }
  }

  function formatHash(hash: string | null): string {
    if (!hash) return '—'
    return hash.length > 16 ? `${hash.slice(0, 8)}…${hash.slice(-8)}` : hash
  }

  async function handleClosePeriod() {
    if (!periodEnd) { toast('warning', t('error'), 'Veuillez saisir la date de fin de période'); return }
    setClosingPeriod(true)
    try {
      const result = await closeNf525Period(periodEnd)
      toast('success', 'Période clôturée', result?.message || 'La période NF525 a été clôturée')
      setPeriodEnd('')
      await loadEvents()
    } catch (err: any) {
      toast('error', t('error'), err.message)
    } finally { setClosingPeriod(false) }
  }

  async function handleDownloadAttestation() {
    if (!attestationStart || !attestationEnd) { toast('warning', t('error'), 'Veuillez saisir la plage de dates'); return }
    setDownloadingAttestation(true)
    try {
      const result = await getNf525Attestation(attestationStart, attestationEnd)
      const content = typeof result === 'string' ? result : JSON.stringify(result, null, 2)
      const blob = new Blob([content], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `attestation-nf525-${attestationStart}_${attestationEnd}.json`
      a.click()
      URL.revokeObjectURL(url)
      toast('success', 'Attestation générée', 'Téléchargement de l\'attestation NF525')
    } catch (err: any) {
      toast('error', t('error'), err.message)
    } finally { setDownloadingAttestation(false) }
  }

  return (
    <div className="space-y-6">
      <Breadcrumb items={[{ label: t('settings'), href: '/settings' }, { label: 'NF525 Anti-fraude' }]} />
      <PageHeader
        title="NF525 Anti-fraude"
        description={t('nf525.pageDescription') || 'Journal d\'événements NF525 et vérification de l\'intégrité de la chaîne'}
      />

      {/* Integrity check card */}
      <Card className="p-6">
        <div className="flex items-center justify-between gap-4 flex-wrap">
          <div className="flex items-center gap-3">
            <Shield className="w-6 h-6 text-[var(--color-primary)]" />
            <div>
              <h3 className="font-semibold text-[var(--color-text)]">{t('nf525.integrityCheck') || 'Vérification de l\'intégrité'}</h3>
              <p className="text-sm text-[var(--color-text-secondary)]">
                {t('nf525.integrityCheckDescription') || 'Vérifie que la chaîne de hachage NF525 n\'a pas été altérée.'}
              </p>
            </div>
          </div>
          <Button onClick={handleVerifyIntegrity} disabled={integrityStatus === 'checking'}>
            <RefreshCw className={`w-4 h-4 mr-1 ${integrityStatus === 'checking' ? 'animate-spin' : ''}`} />
            {t('nf525.verifyIntegrity') || 'Vérifier l\'intégrité'}
          </Button>
        </div>

        {integrityStatus === 'verified' && (
          <div className="mt-4 p-4 bg-[var(--color-success-50)] border border-[var(--color-success)] rounded-lg flex items-start gap-3">
            <CheckCircle className="w-5 h-5 text-[var(--color-success)] flex-shrink-0 mt-0.5" />
            <div>
              <p className="font-medium text-[var(--color-success)]">{t('nf525.integrityVerified') || 'Intégrité vérifiée'}</p>
              <p className="text-sm text-[var(--color-text-secondary)]">{integrityMessage}</p>
            </div>
          </div>
        )}

        {integrityStatus === 'corrupted' && (
          <div className="mt-4 p-4 bg-[var(--color-danger-50)] border border-[var(--color-danger)] rounded-lg flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 text-[var(--color-danger)] flex-shrink-0 mt-0.5" />
            <div>
              <p className="font-medium text-[var(--color-danger)]">{t('nf525.integrityFailed') || 'Intégrité compromise'}</p>
              <p className="text-sm text-[var(--color-text-secondary)]">{integrityMessage}</p>
            </div>
          </div>
        )}
      </Card>

      {/* Period close & attestation card */}
      <Card className="p-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <div className="flex items-center gap-3 mb-3">
              <Lock className="w-5 h-5 text-[var(--color-primary)]" />
              <div>
                <h3 className="font-semibold text-[var(--color-text)]">Clôturer la période</h3>
                <p className="text-sm text-[var(--color-text-secondary)]">Fige la chaîne NF525 jusqu'à la date sélectionnée.</p>
              </div>
            </div>
            <Input type="date" value={periodEnd} onChange={(e) => setPeriodEnd(e.target.value)} placeholder="Date de fin de période" />
            <Button onClick={handleClosePeriod} disabled={closingPeriod || !periodEnd} className="mt-3">
              <Lock className="w-4 h-4" /> {closingPeriod ? 'Clôture en cours…' : 'Clôturer la période'}
            </Button>
          </div>
          <div>
            <div className="flex items-center gap-3 mb-3">
              <Download className="w-5 h-5 text-[var(--color-primary)]" />
              <div>
                <h3 className="font-semibold text-[var(--color-text)]">Télécharger l'attestation</h3>
                <p className="text-sm text-[var(--color-text-secondary)]">Génère l'attestation NF525 pour la plage de dates.</p>
              </div>
            </div>
            <div className="flex gap-2">
              <Input type="date" value={attestationStart} onChange={(e) => setAttestationStart(e.target.value)} placeholder="Début" />
              <Input type="date" value={attestationEnd} onChange={(e) => setAttestationEnd(e.target.value)} placeholder="Fin" />
            </div>
            <Button onClick={handleDownloadAttestation} disabled={downloadingAttestation || !attestationStart || !attestationEnd} className="mt-3">
              <Download className="w-4 h-4" /> {downloadingAttestation ? 'Génération…' : 'Télécharger l\'attestation'}
            </Button>
          </div>
        </div>
      </Card>

      {/* Events table */}
      <div className="space-y-4">
        <div className="flex items-center justify-between gap-3 flex-wrap">
          <div className="flex items-center gap-3">
            <Select value={filterType} onChange={(e) => setFilterType(e.target.value)}>
              <option value="all">{t('nf525.allEvents') || 'Tous les événements'}</option>
              {EVENT_TYPES.map(et => (
                <option key={et} value={et}>{et}</option>
              ))}
            </Select>
            <Button variant="outline" onClick={loadEvents} disabled={loading}>
              <RefreshCw className={`w-4 h-4 mr-1 ${loading ? 'animate-spin' : ''}`} />
              {t('refresh') || 'Actualiser'}
            </Button>
          </div>
          <Badge variant="info">
            {events.length} {t('nf525.events') || 'événements'}
          </Badge>
        </div>

        {loading ? (
          <SkeletonTable rows={6} cols={6} />
        ) : events.length === 0 ? (
          <EmptyState
            icon={<Shield className="w-8 h-8" />}
            title={t('nf525.noEvents') || 'Aucun événement NF525'}
            description={t('nf525.noEventsDescription') || 'Les événements de journalisation NF525 apparaîtront ici.'}
          />
        ) : (
          <Table headers={['#', t('nf525.eventType') || 'Type', t('nf525.entity') || 'Entité', 'Hash', t('nf525.date') || 'Date']}>
            {events.map(ev => (
              <TableRow key={ev.id}>
                <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]">{ev.id}</TableCell>
                <TableCell><Badge variant="info">{ev.event_type}</Badge></TableCell>
                <TableCell className="text-xs">
                  <span className="font-medium">{ev.entity_type}</span>
                  {ev.entity_id && <span className="text-[var(--color-text-secondary)] ml-1 font-mono">#{ev.entity_id.slice(0, 8)}</span>}
                </TableCell>
                <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]" title={ev.current_hash}>
                  {formatHash(ev.current_hash)}
                </TableCell>
                <TableCell className="text-xs text-[var(--color-text-secondary)]">
                  {new Date(ev.created_at).toLocaleString('fr-FR')}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </div>
    </div>
  )
}
