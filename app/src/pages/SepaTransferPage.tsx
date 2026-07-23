import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, AutoBreadcrumb, Input } from '@/components/ui'
import { getPaymentOrders, getCompanySettings } from '@/lib/queries'
import { generateSEPAXML, downloadSEPAXML, type SEPAPaymentInfo, type SEPAInitiator } from '@/lib/sepa'
import { useToast } from '@/lib/toast'
import { formatCurrency, formatDate } from '@/lib/utils'
import { FileCode, Download, CheckSquare, Square, CheckCircle2 } from 'lucide-react'
import type { PaymentOrder, CompanySettings } from '@/types'

export function SepaTransferPage() {
  const { t } = useTranslation('features')
  const { toast } = useToast()
  const [payments, setPayments] = useState<PaymentOrder[]>([])
  const [company, setCompany] = useState<CompanySettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [generated, setGenerated] = useState(false)
  const [preview, setPreview] = useState('')
  const [executionDate, setExecutionDate] = useState(new Date().toISOString().split('T')[0])

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    try {
      const [pays, comp] = await Promise.all([
        getPaymentOrders(),
        getCompanySettings().catch(() => null),
      ])
      setPayments((pays || []).filter((p) => p.type === 'sepa_transfer' && p.status !== 'cancelled' && p.status !== 'draft'))
      setCompany(comp)
    } catch (err) {
      console.error('Error loading SEPA data:', err)
    } finally {
      setLoading(false)
    }
  }

  function toggleSelect(id: string) {
    const next = new Set(selected)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    setSelected(next)
    setGenerated(false)
  }

  function selectAll() {
    setSelected(new Set(payments.map((p) => p.id)))
    setGenerated(false)
  }

  function deselectAll() {
    setSelected(new Set())
    setGenerated(false)
  }

  function handleGenerate() {
    if (!company) {
      toast('error', t('sepa.companyIbanMissing'))
      return
    }
    const initiator: SEPAInitiator = {
      name: company.legal_name || company.name,
      iban: (company as any).iban || '',
      bic: (company as any).bic || '',
      siret: company.siret,
    }
    if (!initiator.iban) {
      toast('error', t('sepa.companyIbanMissing'))
      return
    }
    if (!initiator.bic) {
      toast('error', t('sepa.companyBicMissing'))
      return
    }

    const selectedPayments = payments.filter((p) => selected.has(p.id))
    const sepaPayments: SEPAPaymentInfo[] = selectedPayments.map((p) => ({
      name: p.third_party_name || '',
      iban: p.third_party_iban || '',
      bic: '',
      amount: Number(p.amount),
      reference: p.reference || p.number,
      description: p.description || p.reference || p.number,
    }))

    const xml = generateSEPAXML(initiator, sepaPayments, executionDate)
    setPreview(xml)
    setGenerated(true)
    const total = sepaPayments.reduce((s, p) => s + p.amount, 0)
    toast('success', t('sepa.generated'), t('sepa.generatedDesc', { count: sepaPayments.length, total: total.toFixed(2) }))
  }

  function handleDownload() {
    const selectedPayments = payments.filter((p) => selected.has(p.id))
    const initiator: SEPAInitiator = {
      name: company?.legal_name || company?.name || '',
      iban: (company as any)?.iban || '',
      bic: (company as any)?.bic || '',
      siret: company?.siret,
    }
    const sepaPayments: SEPAPaymentInfo[] = selectedPayments.map((p) => ({
      name: p.third_party_name || '',
      iban: p.third_party_iban || '',
      bic: '',
      amount: Number(p.amount),
      reference: p.reference || p.number,
      description: p.description || p.reference || p.number,
    }))
    const xml = generateSEPAXML(initiator, sepaPayments, executionDate)
    const filename = `sepa_${executionDate}.xml`
    downloadSEPAXML(xml, filename)
    toast('info', t('sepa.downloaded'), t('sepa.downloadedDesc', { filename }))
  }

  const selectedPayments = payments.filter((p) => selected.has(p.id))
  const totalAmount = selectedPayments.reduce((s, p) => s + Number(p.amount), 0)

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader title={t('sepa.title')} subtitle={t('sepa.subtitle')} />

      <Card className="mb-4">
        <div className="p-4">
          <p className="text-sm text-[var(--color-text-secondary)] mb-4">{t('sepa.intro')}</p>
          <div className="flex flex-wrap gap-3 items-end">
            <div className="w-48">
              <Input
                label={t('sepa.executionDate')}
                type="date"
                value={executionDate}
                onChange={(e) => setExecutionDate(e.target.value)}
              />
            </div>
            <Button variant="secondary" onClick={selectAll} disabled={payments.length === 0}>
              <CheckSquare className="w-4 h-4" /> {t('sepa.selectAll')}
            </Button>
            <Button variant="secondary" onClick={deselectAll} disabled={selected.size === 0}>
              <Square className="w-4 h-4" /> {t('sepa.deselectAll')}
            </Button>
            <Button onClick={handleGenerate} disabled={selected.size === 0 || loading}>
              <FileCode className="w-4 h-4" /> {t('sepa.generate')}
            </Button>
            {generated && (
              <Button variant="secondary" onClick={handleDownload}>
                <Download className="w-4 h-4" /> {t('sepa.download')}
              </Button>
            )}
          </div>
        </div>
      </Card>

      {loading ? (
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">...</div></Card>
      ) : payments.length === 0 ? (
        <EmptyState
          icon={<FileCode className="w-8 h-8" />}
          title={t('sepa.noPayments')}
          description={t('sepa.noPaymentsDesc')}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sepa.count')}</p>
              <p className="text-lg font-bold">{selected.size}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('sepa.total')}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalAmount)}</p>
            </div>
          </div>

          {generated && (
            <div className="p-3 rounded-lg bg-[var(--color-success)]/10 border border-[var(--color-success)]/30 text-sm text-[var(--color-success)] flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4" /> {t('sepa.generated')}
            </div>
          )}

          <Card>
            <div className="p-4">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-[var(--color-border)]">
                      <th className="p-2 w-8"></th>
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sepa.number')}</th>
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sepa.beneficiary')}</th>
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sepa.iban')}</th>
                      <th className="text-right p-2 text-[var(--color-text-secondary)] font-medium">{t('sepa.amount')}</th>
                      <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('sepa.date')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {payments.map((p) => (
                      <tr
                        key={p.id}
                        className={`border-b border-[var(--color-border)] last:border-0 cursor-pointer hover:bg-[var(--color-neutral-50)] ${selected.has(p.id) ? 'bg-[var(--color-primary)]/5' : ''}`}
                        onClick={() => toggleSelect(p.id)}
                      >
                        <td className="p-2">
                          {selected.has(p.id) ? (
                            <CheckSquare className="w-4 h-4 text-[var(--color-primary)]" />
                          ) : (
                            <Square className="w-4 h-4 text-[var(--color-text-secondary)]" />
                          )}
                        </td>
                        <td className="p-2 font-mono">{p.number}</td>
                        <td className="p-2">{p.third_party_name || '—'}</td>
                        <td className="p-2 font-mono text-xs">{p.third_party_iban || '—'}</td>
                        <td className="p-2 text-right font-mono">{formatCurrency(Number(p.amount))}</td>
                        <td className="p-2">{formatDate(p.payment_date)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </Card>

          {generated && preview && (
            <Card>
              <div className="p-4">
                <h3 className="text-sm font-semibold mb-2">{t('sepa.xmlPreview')}</h3>
                <pre className="text-xs font-mono overflow-x-auto bg-[var(--color-neutral-50)] p-3 rounded-lg max-h-96 overflow-y-auto">
                  {preview}
                </pre>
              </div>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
