import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Button, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getBudgetTracking, getFiscalYears } from '@/lib/queries'
import { Download, TrendingDown, TrendingUp } from 'lucide-react'
import type { FiscalYear } from '@/types'

interface BudgetItem {
  id: string
  name: string
  account_code: string
  total: number
  realized: number
  committed: number
  available: number
  variance: number
  variance_pct: number
  chart_accounts?: { code: string; name: string }
}

export function BudgetTrackingPage() {
  const [items, setItems] = useState<BudgetItem[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [loading, setLoading] = useState(true)
  const [yearFilter, setYearFilter] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const [b, fy] = await Promise.all([getBudgetTracking(yearFilter || undefined), getFiscalYears()])
      setItems(b || [])
      setYears(fy || [])
    } catch (err) {
      console.error('Error loading budget tracking:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleFilterChange(v: string) {
    setYearFilter(v)
    setTimeout(load, 0)
  }

  function exportCSV() {
    const headers = ['Compte', 'Libellé', 'Budget', 'Réalisé', 'Engagé', 'Disponible', 'Écart', 'Écart %']
    const rows = items.map(i => [
      i.chart_accounts?.code || i.account_code || '',
      i.name,
      i.total.toFixed(2),
      i.realized.toFixed(2),
      (i.committed || 0).toFixed(2),
      (i.available || 0).toFixed(2),
      i.variance.toFixed(2),
      i.variance_pct.toFixed(1) + '%',
    ])
    const csv = [headers, ...rows].map(r => r.join(';')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'suivi-budgetaire.csv'
    a.click()
  }

  if (loading) return <SkeletonTable rows={6} />

  return (
    <div>
      <Breadcrumb items={[{ label: 'Reporting', path: '/reporting/budget' }, { label: 'Suivi budgétaire' }]} />
      <PageHeader title="Suivi budgétaire" subtitle="Réalisé vs budget — analyse des écarts" action={
        <div className="flex items-center gap-2">
          <Select value={yearFilter} onChange={(e) => handleFilterChange(e.target.value)} options={[
            { value: '', label: 'Tous les exercices' },
            ...years.map(y => ({ value: y.id, label: y.code })),
          ]} />
          <Button variant="secondary" onClick={exportCSV}><Download className="w-4 h-4 mr-2" /> Export CSV</Button>
        </div>
      } />

      {items.length === 0 ? (
        <EmptyState title="Aucun budget" description="Aucun budget n'a été défini pour cet exercice." />
      ) : (
        <Card>
          <Table headers={['Compte', 'Libellé', 'Budget', 'Réalisé', 'Engagé', 'Disponible', 'Écart', 'Écart %', 'Statut']}>
            <tbody>
              {items.map((item) => (
                <TableRow key={item.id}>
                  <TableCell className="font-mono">{item.chart_accounts?.code || item.account_code || '—'}</TableCell>
                  <TableCell>{item.name}</TableCell>
                  <TableCell className="text-right">{formatCurrency(item.total)}</TableCell>
                  <TableCell className="text-right">{formatCurrency(item.realized)}</TableCell>
                  <TableCell className="text-right text-orange-600">{formatCurrency(item.committed || 0)}</TableCell>
                  <TableCell className={`text-right font-medium ${(item.available || 0) >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                    {formatCurrency(item.available || 0)}
                  </TableCell>
                  <TableCell className={`text-right ${item.variance >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                    {formatCurrency(item.variance)}
                  </TableCell>
                  <TableCell className={`text-right ${item.variance_pct >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                    {item.variance_pct.toFixed(1)}%
                  </TableCell>
                  <TableCell>
                    {(item.available || 0) >= 0 ? (
                      <span className="inline-flex items-center gap-1 text-green-600 text-sm"><TrendingUp className="w-3 h-3" /> Dans le budget</span>
                    ) : (
                      <span className="inline-flex items-center gap-1 text-red-600 text-sm"><TrendingDown className="w-3 h-3" /> Dépassement</span>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </tbody>
          </Table>
        </Card>
      )}
    </div>
  )
}
