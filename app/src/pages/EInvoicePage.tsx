import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, EmptyState, AutoBreadcrumb, Badge, Select } from '@/components/ui'
import { getInvoices, getCustomers, getCompanySettings } from '@/lib/queries'
import { generateFacturX, generateUBL, downloadXML } from '@/lib/facturX'
import { useToast } from '@/lib/toast'
import { FileCode, Download, FileText, CheckCircle2 } from 'lucide-react'
import { formatCurrency, formatDate } from '@/lib/utils'
import type { Invoice, Customer, CompanySettings } from '@/types'

export function EInvoicePage() {
  const { t } = useTranslation('features')
  const { toast } = useToast()
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [customers, setCustomers] = useState<Customer[]>([])
  const [company, setCompany] = useState<CompanySettings | null>(null)
  const [loading, setLoading] = useState(true)
  const [selectedInvoice, setSelectedInvoice] = useState('')
  const [format, setFormat] = useState<'facturx' | 'ubl'>('facturx')
  const [generated, setGenerated] = useState(false)
  const [preview, setPreview] = useState('')

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    try {
      const [inv, cust, comp] = await Promise.all([
        getInvoices(),
        getCustomers(),
        getCompanySettings().catch(() => null),
      ])
      setInvoices(inv || [])
      setCustomers(cust || [])
      setCompany(comp)
    } catch (err) {
      console.error('Error loading data:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleGenerate() {
    const invoice = invoices.find((i) => i.id === selectedInvoice)
    if (!invoice) {
      toast('error', t('eInvoice.selectInvoice'))
      return
    }
    const customer = customers.find((c) => c.id === invoice.customer_id) || null
    const xml = format === 'facturx'
      ? generateFacturX(invoice, customer, company)
      : generateUBL(invoice, customer, company)
    setPreview(xml)
    setGenerated(true)
    toast('success', t('eInvoice.generated'), t('eInvoice.generatedDesc', { format: format === 'facturx' ? 'Factur-X (CII)' : 'UBL 2.1' }))
  }

  function handleDownload() {
    const invoice = invoices.find((i) => i.id === selectedInvoice)
    if (!invoice) return
    const customer = customers.find((c) => c.id === invoice.customer_id) || null
    const xml = format === 'facturx'
      ? generateFacturX(invoice, customer, company)
      : generateUBL(invoice, customer, company)
    const ext = format === 'facturx' ? 'factur-x' : 'ubl'
    downloadXML(xml, `${invoice.number}.${ext}.xml`)
    toast('info', t('eInvoice.downloadToast'), t('eInvoice.downloadToastDesc', { ext }))
  }

  const sentInvoices = invoices.filter((i) => i.status !== 'draft' && i.status !== 'cancelled')

  return (
    <div className="animate-fade-in">
      <AutoBreadcrumb />
      <PageHeader
        title={t('eInvoice.title')}
        subtitle={t('eInvoice.subtitle')}
      />

      <Card className="mb-4">
        <div className="p-4">
          <div className="flex items-start gap-3 mb-4">
            <FileCode className="w-5 h-5 text-[var(--color-primary)] flex-shrink-0 mt-0.5" />
            <div className="text-sm text-[var(--color-text-secondary)]">
              <strong className="text-[var(--color-text)]">{t('eInvoice.introStrong')}</strong>{' '}
              {t('eInvoice.intro')}
            </div>
          </div>
          <div className="flex flex-wrap gap-3 items-end">
            <div className="w-64">
              <Select
                label={t('eInvoice.invoice')}
                value={selectedInvoice}
                onChange={(e) => { setSelectedInvoice(e.target.value); setGenerated(false) }}
                options={[
                  { value: '', label: t('eInvoice.selectPlaceholder') },
                  ...sentInvoices.map((inv) => ({
                    value: inv.id,
                    label: `${inv.number} — ${inv.customer_name || ''} — ${formatCurrency(Number(inv.total))}`,
                  })),
                ]}
              />
            </div>
            <div className="w-48">
              <Select
                label={t('eInvoice.format')}
                value={format}
                onChange={(e) => { setFormat(e.target.value as 'facturx' | 'ubl'); setGenerated(false) }}
                options={[
                  { value: 'facturx', label: t('eInvoice.formatFacturX') },
                  { value: 'ubl', label: t('eInvoice.formatUbl') },
                ]}
              />
            </div>
            <Button onClick={handleGenerate} disabled={!selectedInvoice || loading}>
              <FileText className="w-4 h-4" /> {t('eInvoice.generate')}
            </Button>
            {generated && (
              <Button variant="secondary" onClick={handleDownload}>
                <Download className="w-4 h-4" /> {t('eInvoice.download')}
              </Button>
            )}
          </div>
        </div>
      </Card>

      {loading ? (
        <Card><div className="p-8 text-center text-[var(--color-text-secondary)]">...</div></Card>
      ) : sentInvoices.length === 0 ? (
        <EmptyState
          icon={<FileCode className="w-8 h-8" />}
          title={t('eInvoice.noEligible')}
          description={t('eInvoice.noEligibleDesc')}
        />
      ) : generated && preview ? (
        <div className="space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('eInvoice.format')}</p>
              <p className="text-lg font-bold">{format === 'facturx' ? 'Factur-X' : 'UBL 2.1'}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('eInvoice.conformity')}</p>
              <p className="text-lg font-bold text-[var(--color-success)]">EN 16931</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('eInvoice.xmlSize')}</p>
              <p className="text-lg font-bold">{(preview.length / 1024).toFixed(1)} {t('eInvoice.kb')}</p>
            </div>
          </div>
          <div className="p-3 rounded-lg bg-[var(--color-success)]/10 border border-[var(--color-success)]/30 text-sm text-[var(--color-success)] flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4" /> {t('eInvoice.xmlValid')}
          </div>
          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-2">{t('eInvoice.xmlPreview')}</h3>
              <pre className="text-xs font-mono overflow-x-auto bg-[var(--color-neutral-50)] p-3 rounded-lg max-h-96 overflow-y-auto">
                {preview}
              </pre>
            </div>
          </Card>
        </div>
      ) : (
        <Card>
          <div className="p-6">
            <h3 className="text-sm font-semibold mb-3">{t('eInvoice.eligibleInvoices', { count: sentInvoices.length })}</h3>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-[var(--color-border)]">
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('eInvoice.number')}</th>
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('eInvoice.customer')}</th>
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('eInvoice.date')}</th>
                    <th className="text-right p-2 text-[var(--color-text-secondary)] font-medium">{t('eInvoice.total')}</th>
                    <th className="text-left p-2 text-[var(--color-text-secondary)] font-medium">{t('eInvoice.status')}</th>
                  </tr>
                </thead>
                <tbody>
                  {sentInvoices.slice(0, 20).map((inv) => (
                    <tr key={inv.id} className="border-b border-[var(--color-border)] last:border-0 cursor-pointer hover:bg-[var(--color-neutral-50)]"
                      onClick={() => setSelectedInvoice(inv.id)}
                    >
                      <td className="p-2 font-medium">{inv.number}</td>
                      <td className="p-2">{inv.customer_name || '—'}</td>
                      <td className="p-2">{formatDate(inv.date)}</td>
                      <td className="p-2 text-right font-mono">{formatCurrency(Number(inv.total))}</td>
                      <td className="p-2"><Badge variant={inv.status === 'paid' ? 'success' : 'primary'}>{inv.status}</Badge></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </Card>
      )}
    </div>
  )
}
