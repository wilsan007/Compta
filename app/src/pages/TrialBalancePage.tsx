import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Button } from '@/components/ui'
import { getTrialBalanceFiltered, getChartAccounts, getJournals } from '@/lib/queries'
import { formatCurrency } from '@/lib/utils'
import { Scale } from 'lucide-react'
import type { ChartAccount, Journal } from '@/types'

const accountTypeLabels: Record<string, string> = {
  asset: 'Actif',
  liability: 'Passif',
  equity: 'Capitaux propres',
  income: 'Produits',
  expense: 'Charges',
}

export function TrialBalancePage() {
  const [balances, setBalances] = useState<any[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [journals, setJournals] = useState<Journal[]>([])
  const [loading, setLoading] = useState(true)
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [journalCode, setJournalCode] = useState('')

  useEffect(() => { loadRef() }, [])

  async function loadRef() {
    try {
      const [accs, jrnls] = await Promise.all([getChartAccounts(), getJournals()])
      setAccounts(accs || [])
      setJournals(jrnls || [])
    } catch (err) {
      console.error('Error loading ref data:', err)
    } finally {
      setLoading(false)
    }
  }

  async function loadBalance() {
    setLoading(true)
    try {
      const tb = await getTrialBalanceFiltered({
        dateFrom: dateFrom || undefined,
        dateTo: dateTo || undefined,
        journalCode: journalCode || undefined,
      })
      setBalances(tb)
    } catch (err) {
      console.error('Error loading trial balance:', err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { loadBalance() }, [])

  const accountMap = new Map(accounts.map((a) => [a.code, a]))

  const enriched = balances.map((b) => {
    const acc = accountMap.get(b.account_code)
    const solde = b.total_debit - b.total_credit
    return {
      ...b,
      type: acc?.type || 'expense',
      solde_debiteur: solde > 0 ? solde : 0,
      solde_crediteur: solde < 0 ? Math.abs(solde) : 0,
    }
  })

  const totalDebit = enriched.reduce((s, b) => s + b.total_debit, 0)
  const totalCredit = enriched.reduce((s, b) => s + b.total_credit, 0)
  const totalSoldeDeb = enriched.reduce((s, b) => s + b.solde_debiteur, 0)
  const totalSoldeCred = enriched.reduce((s, b) => s + b.solde_crediteur, 0)

  const classLabels: Record<string, string> = {
    '1': 'Classe 1 — Capitaux',
    '2': 'Classe 2 — Immobilisations',
    '3': 'Classe 3 — Stocks',
    '4': 'Classe 4 — Tiers',
    '5': 'Classe 5 — Financiers',
    '6': 'Classe 6 — Charges',
    '7': 'Classe 7 — Produits',
    '8': 'Classe 8 — Spéciaux',
  }

  const grouped = enriched.reduce((acc, b) => {
    const cls = b.account_code.charAt(0)
    if (!acc[cls]) acc[cls] = []
    acc[cls].push(b)
    return acc
  }, {} as Record<string, any[]>)

  const sortedClasses = Object.keys(grouped).sort()

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'États' }, { label: 'Balance générale' }]} />
      <PageHeader title="Balance générale" subtitle="Soldes de tous les comptes avec filtres" />

      <Card className="mb-4">
        <div className="p-4 flex gap-3 items-end">
          <Input label="Du" type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          <Input label="Au" type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
          <div>
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Journal</label>
            <select className="input" value={journalCode} onChange={(e) => setJournalCode(e.target.value)}>
              <option value="">Tous</option>
              {journals.map((j) => <option key={j.id} value={j.code}>{j.code} — {j.name}</option>)}
            </select>
          </div>
          <Button onClick={loadBalance} disabled={loading}>Actualiser</Button>
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={10} cols={7} />
      ) : balances.length === 0 ? (
        <EmptyState
          icon={<Scale className="w-8 h-8" />}
          title="Aucune donnée"
          description="Aucune écriture trouvée avec ces filtres."
        />
      ) : (
        <div className="space-y-6">
          <div className="grid grid-cols-4 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Total mouvements débit</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalDebit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Total mouvements crédit</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(totalCredit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Total soldes débiteurs</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalSoldeDeb)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Total soldes créditeurs</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalSoldeCred)}</p>
            </div>
          </div>

          {sortedClasses.map((cls) => (
            <Card key={cls} title={classLabels[cls] || `Classe ${cls}`}>
              <Table headers={['Code', 'Libellé', 'Type', 'Total débit', 'Total crédit', 'Solde débiteur', 'Solde créditeur']}>
                {grouped[cls].map((b: any) => (
                  <TableRow key={b.account_code}>
                    <TableCell className="font-mono font-semibold">{b.account_code}</TableCell>
                    <TableCell>{accountMap.get(b.account_code)?.name || '—'}</TableCell>
                    <TableCell>
                      <Badge variant="neutral">{accountTypeLabels[b.type] || b.type}</Badge>
                    </TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(b.total_debit)}</TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(b.total_credit)}</TableCell>
                    <TableCell className="font-mono text-[var(--color-success)] text-right">{b.solde_debiteur > 0 ? formatCurrency(b.solde_debiteur) : ''}</TableCell>
                    <TableCell className="font-mono text-[var(--color-danger)] text-right">{b.solde_crediteur > 0 ? formatCurrency(b.solde_crediteur) : ''}</TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          ))}

          <Card title="Totaux généraux">
            <Table headers={['', '', '', 'Total débit', 'Total crédit', 'Solde débiteur', 'Solde créditeur']}>
              <TableRow>
                <TableCell colSpan={3} className="font-bold">TOTAUX</TableCell>
                <TableCell className="font-mono font-bold text-right">{formatCurrency(totalDebit)}</TableCell>
                <TableCell className="font-mono font-bold text-right">{formatCurrency(totalCredit)}</TableCell>
                <TableCell className="font-mono font-bold text-[var(--color-success)] text-right">{formatCurrency(totalSoldeDeb)}</TableCell>
                <TableCell className="font-mono font-bold text-[var(--color-danger)] text-right">{formatCurrency(totalSoldeCred)}</TableCell>
              </TableRow>
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
