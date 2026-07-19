import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, Breadcrumb, SkeletonTable, StatCard } from '@/components/ui'
import { getJournalEntries, getChartAccounts, getTrialBalance } from '@/lib/queries'
import { formatCurrency, formatDate } from '@/lib/utils'
import { CalendarDays, FileText, TrendingUp, AlertTriangle, Plus, BookOpen } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import type { JournalEntry, ChartAccount } from '@/types'

export function AccountingDashboardPage() {
  const navigate = useNavigate()
  const [entries, setEntries] = useState<JournalEntry[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [trialBalance, setTrialBalance] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadData()
  }, [])

  async function loadData() {
    try {
      const [je, accs, tb] = await Promise.all([
        getJournalEntries(),
        getChartAccounts(),
        getTrialBalance(),
      ])
      setEntries(je || [])
      setAccounts(accs || [])
      setTrialBalance(tb || [])
    } catch (err) {
      console.error('Error loading accounting dashboard:', err)
    } finally {
      setLoading(false)
    }
  }

  const draftEntries = entries.filter((e) => e.status === 'draft')
  const totalDebit = entries.reduce((s, e) => s + Number(e.total_debit), 0)

  const recentEntries = entries.slice(0, 5)

  const classCounts = accounts.reduce((acc, a) => {
    const cls = a.code.charAt(0)
    acc[cls] = (acc[cls] || 0) + 1
    return acc
  }, {} as Record<string, number>)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Gestion quotidienne' }]} />
      <PageHeader
        title="Gestion quotidienne"
        subtitle="Tableau de bord comptable — saisie, suivi et contrôle"
        action={<Button onClick={() => navigate('/accounting/journal-entries')}><Plus className="w-4 h-4" /> Nouvelle écriture</Button>}
      />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard
          label="Écritures totales"
          value={String(entries.length)}
          icon={<FileText className="w-5 h-5" />}
          color="primary"
        />
        <StatCard
          label="Brouillons en attente"
          value={String(draftEntries.length)}
          icon={<AlertTriangle className="w-5 h-5" />}
          color={draftEntries.length > 0 ? 'warning' : 'success'}
        />
        <StatCard
          label="Total débit"
          value={formatCurrency(totalDebit)}
          icon={<TrendingUp className="w-5 h-5" />}
          color="success"
        />
        <StatCard
          label="Comptes au plan"
          value={String(accounts.length)}
          icon={<BookOpen className="w-5 h-5" />}
          color="primary"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <Card title="Dernières écritures" action={<Button variant="ghost" size="sm" onClick={() => navigate('/accounting/journal-entries')}>Voir tout</Button>}>
            {loading ? (
              <SkeletonTable rows={4} cols={5} />
            ) : recentEntries.length === 0 ? (
              <p className="text-sm text-[var(--color-text-secondary)] py-8 text-center">Aucune écriture. Cliquez sur "Nouvelle écriture" pour commencer.</p>
            ) : (
              <Table headers={['Numéro', 'Date', 'Description', 'Statut', 'Montant']}>
                {recentEntries.map((entry) => (
                  <TableRow key={entry.id} onClick={() => navigate('/accounting/journal-entries')}>
                    <TableCell className="font-mono font-semibold">{entry.number}</TableCell>
                    <TableCell>{formatDate(entry.date)}</TableCell>
                    <TableCell className="max-w-xs truncate">{entry.description}</TableCell>
                    <TableCell>
                      <Badge variant={entry.status === 'posted' ? 'success' : 'warning'}>
                        {entry.status === 'posted' ? 'Validé' : 'Brouillon'}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-mono text-right">{formatCurrency(Number(entry.total_debit))}</TableCell>
                  </TableRow>
                ))}
              </Table>
            )}
          </Card>

          <Card title="Actions rapides">
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
              <button onClick={() => navigate('/accounting/journal-entries')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <FileText className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">Saisie d'écriture</p>
                <p className="text-xs text-[var(--color-text-secondary)]">Nouvelle écriture comptable</p>
              </button>
              <button onClick={() => navigate('/accounting/chart-accounts')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <BookOpen className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">Plan comptable</p>
                <p className="text-xs text-[var(--color-text-secondary)]">Gérer les comptes PCG</p>
              </button>
              <button onClick={() => navigate('/accounting/general-ledger')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <CalendarDays className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">Grand livre</p>
                <p className="text-xs text-[var(--color-text-secondary)]">Mouvements par compte</p>
              </button>
              <button onClick={() => navigate('/accounting/trial-balance')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <TrendingUp className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">Balance générale</p>
                <p className="text-xs text-[var(--color-text-secondary)]">Soldes de tous les comptes</p>
              </button>
              <button onClick={() => navigate('/reports/journals')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <FileText className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">Édition journaux</p>
                <p className="text-xs text-[var(--color-text-secondary)]">Consulter les journaux</p>
              </button>
              <button onClick={() => navigate('/reports/balance-sheet')} className="card p-4 text-left hover:border-[var(--color-primary)] transition-colors">
                <AlertTriangle className="w-6 h-6 text-[var(--color-primary)] mb-2" />
                <p className="text-sm font-semibold">Bilan</p>
                <p className="text-xs text-[var(--color-text-secondary)]">Situation patrimoniale</p>
              </button>
            </div>
          </Card>
        </div>

        <div className="space-y-6">
          <Card title="Répartition par classe">
            {loading ? (
              <SkeletonTable rows={7} cols={2} />
            ) : (
              <div className="space-y-2">
                {Object.entries(classCounts).sort(([a], [b]) => a.localeCompare(b)).map(([cls, count]) => (
                  <div key={cls} className="flex items-center justify-between py-2 border-b border-[var(--color-border)] last:border-0">
                    <span className="text-sm text-[var(--color-text)]">Classe {cls}</span>
                    <Badge variant="neutral">{count} compte{count > 1 ? 's' : ''}</Badge>
                  </div>
                ))}
              </div>
            )}
          </Card>

          <Card title="Alertes comptables">
            <div className="space-y-3">
              {draftEntries.length > 0 && (
                <div className="flex items-start gap-3 p-3 rounded-lg bg-[rgba(255,149,0,0.08)]">
                  <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] mt-0.5" />
                  <div>
                    <p className="text-sm font-medium">{draftEntries.length} brouillon(s) en attente</p>
                    <p className="text-xs text-[var(--color-text-secondary)]">À valider pour comptabilisation</p>
                  </div>
                </div>
              )}
              {trialBalance.length > 0 && (
                <div className="flex items-start gap-3 p-3 rounded-lg bg-[rgba(0,135,90,0.08)]">
                  <TrendingUp className="w-5 h-5 text-[var(--color-success)] mt-0.5" />
                  <div>
                    <p className="text-sm font-medium">Balance disponible</p>
                    <p className="text-xs text-[var(--color-text-secondary)]">{trialBalance.length} comptes avec mouvements</p>
                  </div>
                </div>
              )}
              {entries.length === 0 && (
                <div className="flex items-start gap-3 p-3 rounded-lg bg-[rgba(0,102,204,0.08)]">
                  <FileText className="w-5 h-5 text-[var(--color-primary)] mt-0.5" />
                  <div>
                    <p className="text-sm font-medium">Aucune écriture</p>
                    <p className="text-xs text-[var(--color-text-secondary)]">Commencez par saisir une écriture</p>
                  </div>
                </div>
              )}
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
