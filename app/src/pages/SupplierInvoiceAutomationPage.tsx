import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getPurchaseInvoices, getSuppliers, createPurchaseInvoice } from '@/lib/queries'
import { Upload, FileText, CheckCircle2, X, Sparkles, AlertCircle } from 'lucide-react'
import type { PurchaseInvoice, Supplier } from '@/types'
import { useToast } from '@/lib/toast'

export function SupplierInvoiceAutomationPage() {
const [invoices, setInvoices] = useState<PurchaseInvoice[]>([])
  const [suppliers, setSuppliers] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [ocrResult, setOcrResult] = useState<any>(null)
  const [processing, setProcessing] = useState(false)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const [inv, sup] = await Promise.all([getPurchaseInvoices(), getSuppliers()])
      setInvoices(inv || [])
      setSuppliers(sup || [])
    } catch (err) {
      console.error('Error loading data:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setProcessing(true)
    setOcrResult(null)

    setTimeout(() => {
      const simulated = {
        supplierName: '',
        invoiceNumber: `FACT-${String(Date.now()).slice(-6)}`,
        date: new Date().toISOString().split('T')[0],
        dueDate: new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0],
        total: 0,
        lines: [
          { description: 'Article 1', quantity: 1, unitPrice: 0, total: 0 },
        ],
        confidence: 0,
      }
      setOcrResult(simulated)
      setProcessing(false)
      setShowForm(true)
    }, 1500)
  }

  const recentInvoices = invoices.slice(0, 10)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Achats' }, { label: 'Automatisation factures' }]} />
      <PageHeader title="Automatisation factures fournisseurs" subtitle="Import et OCR de factures fournisseurs" />

      <Card className="mb-6">
        <div className="p-6">
          <div className="flex items-center gap-3 mb-4">
            <Sparkles className="w-5 h-5 text-[var(--color-primary)]" />
            <h3 className="text-sm font-semibold">Importer une facture (OCR simulé)</h3>
          </div>
          <div className="border-2 border-dashed border-[var(--color-border)] rounded-lg p-8 text-center">
            <Upload className="w-10 h-10 mx-auto text-[var(--color-text-secondary)] mb-3" />
            <p className="text-sm text-[var(--color-text-secondary)] mb-2">
              Glissez une facture PDF ou image, ou cliquez pour parcourir
            </p>
            <p className="text-xs text-[var(--color-text-secondary)] mb-4">PDF, PNG, JPG — 10 Mo max</p>
            <label className="btn-primary text-sm px-4 py-2 rounded-lg cursor-pointer inline-flex items-center gap-2">
              <Upload className="w-4 h-4" /> Parcourir
              <input type="file" accept=".pdf,.png,.jpg,.jpeg" className="hidden" onChange={handleFileUpload} />
            </label>
            {processing && (
              <div className="mt-4 flex items-center justify-center gap-2 text-sm text-[var(--color-primary)]">
                <div className="w-4 h-4 border-2 border-[var(--color-primary)] border-t-transparent rounded-full animate-spin" />
                Analyse OCR en cours...
              </div>
            )}
          </div>
        </div>
      </Card>

      <Card title="Factures récentes">
        {loading ? (
          <SkeletonTable rows={5} cols={5} />
        ) : recentInvoices.length === 0 ? (
          <EmptyState icon={<FileText className="w-8 h-8" />} title="Aucune facture" description="Importez votre première facture fournisseur." />
        ) : (
          <Table headers={['N°', 'Fournisseur', 'Date', 'Montant', 'Statut']}>
            {recentInvoices.map((inv) => (
              <TableRow key={inv.id}>
                <TableCell className="font-mono text-xs">{inv.number}</TableCell>
                <TableCell className="text-sm">{suppliers.find((s) => s.id === inv.supplier_id)?.name || '—'}</TableCell>
                <TableCell className="text-xs">{formatDate(inv.date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(inv.total))}</TableCell>
                <TableCell>
                  <Badge variant={inv.status === 'paid' ? 'success' : inv.status === 'overdue' ? 'danger' : 'warning'}>
                    {inv.status === 'paid' ? 'Payée' : inv.status === 'overdue' ? 'En retard' : 'Reçue'}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </Card>

      {showForm && ocrResult && (
        <OcrForm
          result={ocrResult}
          suppliers={suppliers}
          onClose={() => { setShowForm(false); setOcrResult(null) }}
          onSaved={() => { setShowForm(false); setOcrResult(null); load() }}
        />
      )}
    </div>
  )
}

function OcrForm({ result, suppliers, onClose, onSaved }: {
  result: any; suppliers: Supplier[]; onClose: () => void; onSaved: () => void
}) {
const [supplierId, setSupplierId] = useState('')
const { toast } = useToast()
  const [number, setNumber] = useState(result.invoiceNumber || '')
  const [date, setDate] = useState(result.date || '')
  const [dueDate, setDueDate] = useState(result.dueDate || '')
  const [total, setTotal] = useState(result.total || 0)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createPurchaseInvoice({
        number, supplier_id: supplierId || null,
        date, due_date: dueDate,
        subtotal: total, vat: 0, total,
        status: 'received',
      } as any)
      onSaved()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl overflow-hidden" style={{ width: '100%', maxWidth: '36rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <div className="flex items-center gap-2">
            <h2 className="text-lg font-semibold">Vérifier les données OCR</h2>
            <Badge variant={result.confidence > 80 ? 'success' : 'warning'}>
              <AlertCircle className="w-3 h-3 mr-1" /> {result.confidence}% confiance
            </Badge>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="p-3 rounded-lg bg-[var(--color-warning)]/10 border border-[var(--color-warning)]/30 text-xs text-[var(--color-text-secondary)] flex items-center gap-2">
            <AlertCircle className="w-4 h-4 text-[var(--color-warning)] flex-shrink-0" />
            Vérifiez et corrigez les données extraites avant validation.
          </div>
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Fournisseur</label>
            <select className="input" value={supplierId} onChange={(e) => setSupplierId(e.target.value)} required>
              <option value="">— Sélectionner —</option>
              {suppliers.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </div>
          <Input label="N° facture" required value={number} onChange={(e) => setNumber(e.target.value)} />
          <div className="grid grid-cols-2 gap-4">
            <Input label="Date" type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
            <Input label="Échéance" type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </div>
          <Input label="Montant total" type="number" step="0.01" required value={total} onChange={(e) => setTotal(Number(e.target.value))} />
          <div className="flex justify-end gap-3 pt-2">
            <Button variant="secondary" onClick={onClose}>Annuler</Button>
            <Button type="submit" disabled={saving}>
              <CheckCircle2 className="w-4 h-4" /> {saving ? '...' : 'Valider et créer'}
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}
