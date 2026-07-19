import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getGescomTransferData, transferGescomToAccounting } from '@/lib/queries'
import { ArrowRightLeft, CheckCircle2, AlertCircle } from 'lucide-react'
import { useToast } from '@/lib/toast'

export function GescomTransferPage() {
  const { toast } = useToast()
const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [transferring, setTransferring] = useState(false)
  const [results, setResults] = useState<Array<{ success: boolean; number: string; error?: string }> | null>(null)

  const loadData = useCallback(async () => {
    try { setData(await getGescomTransferData()) }
    catch (err) { console.error('Error:', err) }
    finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  function toggleSelect(key: string) {
    const next = new Set(selected)
    if (next.has(key)) next.delete(key)
    else next.add(key)
    setSelected(next)
  }

  function selectAllPending() {
    const next = new Set<string>()
    for (const inv of data?.invoices || []) { if (!inv.transferred) next.add(`sales-${inv.id}`) }
    for (const pur of data?.purchaseInvoices || []) { if (!pur.transferred) next.add(`purchase-${pur.id}`) }
    setSelected(next)
  }

  async function handleTransfer() {
    if (selected.size === 0) return
    setTransferring(true)
    try {
      const items: any[] = []
      for (const key of selected) {
        const [type, id] = key.split('-')
        if (type === 'sales') {
          const inv = data.invoices.find((i: any) => i.id === id)
          if (inv) items.push({ type: 'sales', id, number: inv.number, amount: Number(inv.total), date: inv.date })
        } else {
          const pur = data.purchaseInvoices.find((p: any) => p.id === id)
          if (pur) items.push({ type: 'purchase', id, number: pur.number, amount: Number(pur.total), date: pur.date })
        }
      }
      const res = await transferGescomToAccounting(items)
      setResults(res)
      setSelected(new Set())
      await loadData()
    } catch (err: any) { toast('error', 'Erreur', err.message || 'échec') }
    finally { setTransferring(false) }
  }

  const pendingItems = [
    ...(data?.invoices || []).filter((i: any) => !i.transferred).map((i: any) => ({ key: `sales-${i.id}`, label: i.number, type: 'Vente', amount: Number(i.total), date: i.date, transferred: false })),
    ...(data?.purchaseInvoices || []).filter((p: any) => !p.transferred).map((p: any) => ({ key: `purchase-${p.id}`, label: p.number, type: 'Achat', amount: Number(p.total), date: p.date, transferred: false })),
  ]

  return (
    <div>
      <Breadcrumb items={[{ label: 'Stock' }, { label: 'Transfert comptable' }]} />
      <PageHeader title="Transfert GesCom → Compta" subtitle={`${data?.pendingCount || 0} document(s) en attente`}
        action={<div className="flex gap-2"><Button variant="secondary" onClick={selectAllPending}>Tout sélectionner</Button><Button onClick={handleTransfer} disabled={selected.size === 0 || transferring}><ArrowRightLeft className="w-4 h-4" /> {transferring ? '...' : `Transférer (${selected.size})`}</Button></div>} />

      {results && (
        <Card className="mb-4">
          <div className="p-4">
            <h3 className="text-sm font-semibold mb-2">Résultats du transfert</h3>
            <div className="space-y-1">
              {results.map((r) => (
                <div key={r.number} className="flex items-center gap-2 text-xs">
                  {r.success ? <CheckCircle2 className="w-4 h-4 text-[var(--color-success)]" /> : <AlertCircle className="w-4 h-4 text-[var(--color-danger)]" />}
                  <span className="font-mono">{r.number}</span>
                  {r.success ? <span className="text-[var(--color-success)]">Transféré</span> : <span className="text-[var(--color-danger)]">{r.error}</span>}
                </div>
              ))}
            </div>
            <Button variant="secondary" className="mt-3" onClick={() => setResults(null)}>Fermer</Button>
          </div>
        </Card>
      )}

      {loading ? <SkeletonTable rows={6} cols={5} /> : pendingItems.length === 0 ? (
        <EmptyState icon={<CheckCircle2 className="w-8 h-8" />} title="Tout est transféré" description="Aucun document en attente de transfert." />
      ) : (
        <Card>
          <Table headers={['', 'N°', 'Type', 'Date', 'Montant', 'Statut']}>
            {pendingItems.map((item) => (
              <TableRow key={item.key}>
                <TableCell>
                  <input type="checkbox" checked={selected.has(item.key)} onChange={() => toggleSelect(item.key)} className="rounded" />
                </TableCell>
                <TableCell className="font-mono text-xs">{item.label}</TableCell>
                <TableCell className="text-xs">{item.type}</TableCell>
                <TableCell className="text-xs">{formatDate(item.date)}</TableCell>
                <TableCell className="font-mono text-xs text-right">{formatCurrency(item.amount)}</TableCell>
                <TableCell><Badge variant="warning">En attente</Badge></TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {!loading && data && (
        <div className="mt-6 grid grid-cols-2 gap-6">
          <Card title="Factures déjà transférées">
            <Table headers={['N°', 'Date', 'Montant', 'Statut']}>
              {(data.invoices || []).filter((i: any) => i.transferred).slice(0, 10).map((inv: any) => (
                <TableRow key={inv.id}>
                  <TableCell className="font-mono text-xs">{inv.number}</TableCell>
                  <TableCell className="text-xs">{formatDate(inv.date)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(inv.total))}</TableCell>
                  <TableCell><Badge variant="success">Transféré</Badge></TableCell>
                </TableRow>
              ))}
            </Table>
          </Card>
          <Card title="Factures d'achat transférées">
            <Table headers={['N°', 'Date', 'Montant', 'Statut']}>
              {(data.purchaseInvoices || []).filter((p: any) => p.transferred).slice(0, 10).map((pur: any) => (
                <TableRow key={pur.id}>
                  <TableCell className="font-mono text-xs">{pur.number}</TableCell>
                  <TableCell className="text-xs">{formatDate(pur.date)}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(pur.total))}</TableCell>
                  <TableCell><Badge variant="success">Transféré</Badge></TableCell>
                </TableRow>
              ))}
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
