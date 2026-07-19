import { useEffect, useState } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Input, Button } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getThirdPartyAccounts, getGrandLivreTiers } from '@/lib/queries'
import { BookOpen } from 'lucide-react'
import type { ThirdPartyAccount } from '@/types'

export function GrandLivreTiersPage() {
  const [tiers, setTiers] = useState<ThirdPartyAccount[]>([])
  const [selectedTiers, setSelectedTiers] = useState('')
  const [movements, setMovements] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [, setLoadingTiers] = useState(true)
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')

  useEffect(() => { loadTiers() }, [])

  async function loadTiers() {
    try {
      const data = await getThirdPartyAccounts()
      setTiers(data || [])
    } catch (err) {
      console.error('Error loading tiers:', err)
    } finally {
      setLoadingTiers(false)
    }
  }

  async function loadMovements() {
    if (!selectedTiers) return
    setLoading(true)
    try {
      const data = await getGrandLivreTiers(selectedTiers, dateFrom || undefined, dateTo || undefined)
      setMovements(data || [])
    } catch (err) {
      console.error('Error loading grand livre tiers:', err)
    } finally {
      setLoading(false)
    }
  }

  const totalDebit = movements.reduce((s, m) => s + Number(m.debit), 0)
  const totalCredit = movements.reduce((s, m) => s + Number(m.credit), 0)
  const solde = totalDebit - totalCredit
  const selectedTp = tiers.find((t) => t.code === selectedTiers)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'États' }, { label: 'Grand livre tiers' }]} />
      <PageHeader title="Grand livre tiers" subtitle="Mouvements détaillés par compte tiers" />

      <Card className="mb-4">
        <div className="p-4 grid grid-cols-4 gap-3 items-end">
          <div className="col-span-2">
            <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Compte tiers</label>
            <select className="input" value={selectedTiers} onChange={(e) => setSelectedTiers(e.target.value)}>
              <option value="">— Sélectionner —</option>
              {tiers.map((t) => <option key={t.id} value={t.code}>{t.code} — {t.name}</option>)}
            </select>
          </div>
          <Input label="Date du" type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
          <Input label="Date au" type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
        </div>
        <div className="px-4 pb-4">
          <Button onClick={loadMovements} disabled={loading || !selectedTiers}>
            {loading ? 'Chargement...' : 'Afficher'}
          </Button>
        </div>
      </Card>

      {!selectedTiers ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title="Sélectionnez un compte tiers"
          description="Choisissez un compte tiers pour voir ses mouvements."
        />
      ) : loading ? (
        <SkeletonTable rows={6} cols={6} />
      ) : movements.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="w-8 h-8" />}
          title="Aucun mouvement"
          description={`Le compte ${selectedTiers} — ${selectedTp?.name} n'a aucun mouvement.`}
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-3 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Total débit</p>
              <p className="text-lg font-bold font-mono text-[var(--color-success)]">{formatCurrency(totalDebit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Total crédit</p>
              <p className="text-lg font-bold font-mono text-[var(--color-danger)]">{formatCurrency(totalCredit)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Solde {solde >= 0 ? 'débiteur' : 'créditeur'}</p>
              <p className="text-lg font-bold font-mono">{formatCurrency(Math.abs(solde))}</p>
            </div>
          </div>

          <Card title={`${selectedTiers} — ${selectedTp?.name || ''}`}>
            <Table headers={['Date', 'N° pièce', 'Journal', 'Libellé', 'Débit', 'Crédit', 'Solde']}>
              {(() => {
                let runningBalance = 0
                return movements.map((m) => {
                  runningBalance += Number(m.debit) - Number(m.credit)
                  const je = m.journal_entries
                  return (
                    <TableRow key={m.id}>
                      <TableCell className="text-xs">{je?.date ? formatDate(je.date) : '—'}</TableCell>
                      <TableCell className="font-mono text-xs">{je?.piece_number || je?.number || '—'}</TableCell>
                      <TableCell className="font-mono text-xs">{je?.journal_code}</TableCell>
                      <TableCell className="max-w-xs truncate text-sm">{m.description || je?.description || ''}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{Number(m.debit) > 0 ? formatCurrency(Number(m.debit)) : ''}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{Number(m.credit) > 0 ? formatCurrency(Number(m.credit)) : ''}</TableCell>
                      <TableCell className="font-mono text-xs font-semibold text-right">{formatCurrency(runningBalance)}</TableCell>
                    </TableRow>
                  )
                })
              })()}
            </Table>
          </Card>
        </div>
      )}
    </div>
  )
}
