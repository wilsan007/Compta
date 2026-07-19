import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getTreasuryDashboard } from '@/lib/queries'
import { Wallet, TrendingUp, TrendingDown, Clock } from 'lucide-react'

export function TreasuryDashboardPage() {
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [])

  async function load() {
    try {
      const res = await getTreasuryDashboard()
      setData(res)
    } catch (err) {
      console.error('Error loading treasury dashboard:', err)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: 'Trésorerie' }, { label: 'Tableau de bord' }]} />
        <PageHeader title="Tableau de bord trésorerie" subtitle="Chargement..." />
        <SkeletonTable rows={4} cols={4} />
      </div>
    )
  }

  const { accounts, totalBalance, forecastBuckets, pendingPayments } = data || {}

  return (
    <div>
      <Breadcrumb items={[{ label: 'Trésorerie' }, { label: 'Tableau de bord' }]} />
      <PageHeader title="Tableau de bord trésorerie" subtitle="Vue d'ensemble des liquidités et prévisions" />

      <div className="grid grid-cols-4 gap-4 mb-6">
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <Wallet className="w-5 h-5 text-[var(--color-primary)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">Solde total</p>
            </div>
            <p className="text-2xl font-bold font-mono">{formatCurrency(totalBalance || 0)}</p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingUp className="w-5 h-5 text-[var(--color-success)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">Encaissements 90j</p>
            </div>
            <p className="text-2xl font-bold font-mono text-[var(--color-success)]">
              {formatCurrency(forecastBuckets?.reduce((s: number, b: any) => s + b.incoming, 0) || 0)}
            </p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <TrendingDown className="w-5 h-5 text-[var(--color-danger)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">Décaissements 90j</p>
            </div>
            <p className="text-2xl font-bold font-mono text-[var(--color-danger)]">
              {formatCurrency(forecastBuckets?.reduce((s: number, b: any) => s + b.outgoing, 0) || 0)}
            </p>
          </div>
        </Card>
        <Card>
          <div className="p-4">
            <div className="flex items-center gap-2 mb-2">
              <Clock className="w-5 h-5 text-[var(--color-warning)]" />
              <p className="text-sm text-[var(--color-text-secondary)]">Paiements en attente</p>
            </div>
            <p className="text-2xl font-bold font-mono">{pendingPayments?.length || 0}</p>
          </div>
        </Card>
      </div>

      <div className="grid grid-cols-2 gap-6 mb-6">
        <Card title="Comptes bancaires">
          <Table headers={['Banque', 'Type', 'Solde']}>
            {(accounts || []).map((acc: any) => (
              <TableRow key={acc.id}>
                <TableCell className="font-medium">{acc.name}</TableCell>
                <TableCell className="text-xs">{acc.type}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(acc.balance))}</TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>

        <Card title="Prévision 90 jours">
          <Table headers={['Période', 'Encaissements', 'Décaissements', 'Net']}>
            {(forecastBuckets || []).map((b: any) => (
              <TableRow key={b.label}>
                <TableCell className="font-medium">{b.label}</TableCell>
                <TableCell className="font-mono text-[var(--color-success)] text-right">{formatCurrency(b.incoming)}</TableCell>
                <TableCell className="font-mono text-[var(--color-danger)] text-right">{formatCurrency(b.outgoing)}</TableCell>
                <TableCell className={`font-mono font-bold text-right ${b.incoming - b.outgoing >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                  {formatCurrency(b.incoming - b.outgoing)}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      </div>

      <Card title="Paiements en attente">
        {(pendingPayments || []).length === 0 ? (
          <EmptyState icon={<Clock className="w-8 h-8" />} title="Aucun paiement en attente" description="Tous les paiements ont été exécutés." />
        ) : (
          <Table headers={['N°', 'Bénéficiaire', 'Montant', 'Date', 'Statut']}>
            {(pendingPayments || []).map((p: any) => (
              <TableRow key={p.id}>
                <TableCell className="font-mono text-xs">{p.number}</TableCell>
                <TableCell className="text-sm">{p.third_party_name || '—'}</TableCell>
                <TableCell className="font-mono text-right">{formatCurrency(Number(p.amount))}</TableCell>
                <TableCell className="text-xs">{formatDate(p.payment_date)}</TableCell>
                <TableCell>
                  <Badge variant={p.status === 'approved' ? 'warning' : 'neutral'}>
                    {p.status === 'approved' ? 'Approuvé' : 'Brouillon'}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        )}
      </Card>
    </div>
  )
}
