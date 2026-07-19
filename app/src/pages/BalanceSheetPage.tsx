import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, SkeletonTable, Breadcrumb, Table, TableRow, TableCell } from '@/components/ui'
import { getBalanceSheet } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'

export function BalanceSheetPage() {
  const [data, setData] = useState<{ assets: any[]; liabilities: any[]; equity: any[] } | null>(null)
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      setData(await getBalanceSheet())
    } catch (err) {
      console.error('Failed to load balance sheet:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const totalAssets = (data?.assets || []).reduce((s, a) => s + (a.debit - a.credit), 0)
  const totalLiabilities = (data?.liabilities || []).reduce((s, l) => s + (l.credit - l.debit), 0)
  const totalEquity = (data?.equity || []).reduce((s, e) => s + (e.credit - e.debit), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Rapports' }, { label: 'Bilan' }]} />
      <PageHeader title="Bilan" subtitle="Vue d'ensemble du patrimoine de l'entreprise" />

      {loading ? (
        <SkeletonTable rows={6} cols={3} />
      ) : (
        <div className="grid grid-cols-2 gap-6">
          <div>
            <h3 className="text-sm font-semibold mb-3">ACTIF</h3>
            <Card>
              <Table headers={['Code', 'Compte', 'Montant']}>
                {(data?.assets || []).map((a) => (
                  <TableRow key={a.code}>
                    <TableCell className="font-mono text-xs">{a.code}</TableCell>
                    <TableCell className="text-sm">{a.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(a.debit - a.credit)}</TableCell>
                  </TableRow>
                ))}
                <TableRow>
                  <TableCell /><TableCell className="font-bold">Total Actif</TableCell>
                  <TableCell className="font-mono text-right font-bold text-base">{formatCurrency(totalAssets)}</TableCell>
                </TableRow>
              </Table>
            </Card>
          </div>
          <div>
            <h3 className="text-sm font-semibold mb-3">PASSIF</h3>
            <Card>
              <Table headers={['Code', 'Compte', 'Montant']}>
                {(data?.liabilities || []).map((l) => (
                  <TableRow key={l.code}>
                    <TableCell className="font-mono text-xs">{l.code}</TableCell>
                    <TableCell className="text-sm">{l.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(l.credit - l.debit)}</TableCell>
                  </TableRow>
                ))}
                {(data?.equity || []).map((e) => (
                  <TableRow key={e.code}>
                    <TableCell className="font-mono text-xs">{e.code}</TableCell>
                    <TableCell className="text-sm">{e.name}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(e.credit - e.debit)}</TableCell>
                  </TableRow>
                ))}
                <TableRow>
                  <TableCell /><TableCell className="font-bold">Total Passif + Capitaux</TableCell>
                  <TableCell className="font-mono text-right font-bold text-base">{formatCurrency(totalLiabilities + totalEquity)}</TableCell>
                </TableRow>
              </Table>
            </Card>
          </div>
        </div>
      )}
    </div>
  )
}
