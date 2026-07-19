import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { searchEntries, getJournals, getChartAccounts, getThirdPartyAccounts } from '@/lib/queries'
import { Search, ChevronDown, ChevronRight, Filter, X } from 'lucide-react'
import type { JournalEntry, Journal, ChartAccount, ThirdPartyAccount } from '@/types'

const statusDetailLabels: Record<string, string> = {
  open: 'Ouvert',
  printed: 'Imprimé',
  closed: 'Clôturé',
  draft: 'Brouillon',
  posted: 'Validé',
}

export function SearchEntriesPage() {
  const [journals, setJournals] = useState<Journal[]>([])
  const [accounts, setAccounts] = useState<ChartAccount[]>([])
  const [thirdParties, setThirdParties] = useState<ThirdPartyAccount[]>([])
  const [results, setResults] = useState<JournalEntry[]>([])
  const [loading, setLoading] = useState(false)
  const [hasSearched, setHasSearched] = useState(false)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [showFilters, setShowFilters] = useState(true)

  const [criteria, setCriteria] = useState({
    journalCode: '',
    dateFrom: '',
    dateTo: '',
    accountCode: '',
    accountTiers: '',
    amountMin: '',
    amountMax: '',
    description: '',
    pieceNumber: '',
  })

  useEffect(() => {
    loadRefData()
  }, [])

  async function loadRefData() {
    try {
      const [j, a, tp] = await Promise.all([
        getJournals(),
        getChartAccounts(),
        getThirdPartyAccounts(),
      ])
      setJournals(j || [])
      setAccounts(a || [])
      setThirdParties(tp || [])
    } catch (err) {
      console.error('Error loading ref data:', err)
    }
  }

  function updateCriteria(field: keyof typeof criteria, value: string) {
    setCriteria((prev) => ({ ...prev, [field]: value }))
  }

  async function handleSearch() {
    setLoading(true)
    setHasSearched(true)
    setExpanded(new Set())
    try {
      const res = await searchEntries({
        journalCode: criteria.journalCode || undefined,
        dateFrom: criteria.dateFrom || undefined,
        dateTo: criteria.dateTo || undefined,
        accountCode: criteria.accountCode || undefined,
        accountTiers: criteria.accountTiers || undefined,
        amountMin: criteria.amountMin ? Number(criteria.amountMin) : undefined,
        amountMax: criteria.amountMax ? Number(criteria.amountMax) : undefined,
        description: criteria.description || undefined,
        pieceNumber: criteria.pieceNumber || undefined,
      })
      setResults(res || [])
    } catch (err) {
      console.error('Error searching entries:', err)
      setResults([])
    } finally {
      setLoading(false)
    }
  }

  function resetSearch() {
    setCriteria({
      journalCode: '', dateFrom: '', dateTo: '', accountCode: '',
      accountTiers: '', amountMin: '', amountMax: '', description: '', pieceNumber: '',
    })
    setResults([])
    setHasSearched(false)
  }

  function toggleExpand(id: string) {
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const totalDebit = results.reduce((s, e) => s + Number(e.total_debit), 0)
  const totalCredit = results.reduce((s, e) => s + Number(e.total_credit), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Traitement' }, { label: 'Recherche d\'écritures' }]} />
      <PageHeader
        title="Recherche d'écritures"
        subtitle="Recherche multi-critères dans les écritures comptables"
        action={
          <Button variant="secondary" onClick={() => setShowFilters(!showFilters)}>
            <Filter className="w-4 h-4" /> {showFilters ? 'Masquer les filtres' : 'Afficher les filtres'}
          </Button>
        }
      />

      {showFilters && (
        <Card className="mb-4">
          <div className="p-4 space-y-4">
            <div className="grid grid-cols-4 gap-3">
              <Select
                label="Journal"
                value={criteria.journalCode}
                onChange={(e) => updateCriteria('journalCode', e.target.value)}
                options={[{ value: '', label: 'Tous' }, ...journals.map((j) => ({ value: j.code, label: `${j.code} — ${j.name}` }))]}
              />
              <Input label="Date du" type="date" value={criteria.dateFrom} onChange={(e) => updateCriteria('dateFrom', e.target.value)} />
              <Input label="Date au" type="date" value={criteria.dateTo} onChange={(e) => updateCriteria('dateTo', e.target.value)} />
              <Input label="N° pièce" value={criteria.pieceNumber} onChange={(e) => updateCriteria('pieceNumber', e.target.value)} placeholder="Ex: ACH-0001" />
            </div>
            <div className="grid grid-cols-4 gap-3">
              <div>
                <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Compte général</label>
                <select className="input" value={criteria.accountCode} onChange={(e) => updateCriteria('accountCode', e.target.value)}>
                  <option value="">Tous</option>
                  {accounts.map((a) => <option key={a.id} value={a.code}>{a.code} — {a.name}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Compte tiers</label>
                <select className="input" value={criteria.accountTiers} onChange={(e) => updateCriteria('accountTiers', e.target.value)}>
                  <option value="">Tous</option>
                  {thirdParties.map((t) => <option key={t.id} value={t.code}>{t.code} — {t.name}</option>)}
                </select>
              </div>
              <Input label="Montant min" type="number" step="0.01" value={criteria.amountMin} onChange={(e) => updateCriteria('amountMin', e.target.value)} placeholder="0.00" />
              <Input label="Montant max" type="number" step="0.01" value={criteria.amountMax} onChange={(e) => updateCriteria('amountMax', e.target.value)} placeholder="0.00" />
            </div>
            <div className="grid grid-cols-3 gap-3">
              <Input label="Description (contient)" value={criteria.description} onChange={(e) => updateCriteria('description', e.target.value)} placeholder="Mot-clé..." />
            </div>
            <div className="flex justify-end gap-3">
              <Button variant="secondary" onClick={resetSearch}><X className="w-4 h-4" /> Réinitialiser</Button>
              <Button onClick={handleSearch} disabled={loading}>
                <Search className="w-4 h-4" /> {loading ? 'Recherche...' : 'Rechercher'}
              </Button>
            </div>
          </div>
        </Card>
      )}

      {hasSearched && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <p className="text-sm text-[var(--color-text-secondary)]">
              {results.length} résultat(s) — Total débit: {formatCurrency(totalDebit)} | Total crédit: {formatCurrency(totalCredit)}
            </p>
          </div>
          {loading ? (
            <SkeletonTable rows={6} cols={7} />
          ) : results.length === 0 ? (
            <EmptyState
              icon={<Search className="w-8 h-8" />}
              title="Aucune écriture trouvée"
              description="Modifiez vos critères de recherche et réessayez."
            />
          ) : (
            <Card>
              <Table headers={['', 'N°', 'Date', 'Journal', 'Description', 'Statut', 'Débit', 'Crédit']}>
                {results.map((entry) => (
                  <div key={entry.id}>
                    <TableRow onClick={() => toggleExpand(entry.id)}>
                      <TableCell className="w-8">
                        {entry.journal_lines && entry.journal_lines.length > 0
                          ? (expanded.has(entry.id) ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />)
                          : <span className="w-4 inline-block" />}
                      </TableCell>
                      <TableCell className="font-mono text-xs">{entry.piece_number || entry.number}</TableCell>
                      <TableCell className="text-xs">{formatDate(entry.date)}</TableCell>
                      <TableCell className="font-mono text-xs">{entry.journal_code}</TableCell>
                      <TableCell className="max-w-xs truncate text-sm">{entry.description}</TableCell>
                      <TableCell>
                        <Badge variant="neutral">
                          {statusDetailLabels[entry.status_detail || entry.status] || entry.status}
                        </Badge>
                      </TableCell>
                      <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.total_debit))}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.total_credit))}</TableCell>
                    </TableRow>
                    {expanded.has(entry.id) && entry.journal_lines && entry.journal_lines.map((line) => (
                      <tr key={line.id} className="bg-[var(--color-neutral-50)]">
                        <TableCell />
                        <TableCell className="font-mono text-xs text-[var(--color-text-secondary)]">{line.account_general || line.account_code}</TableCell>
                        <TableCell />
                        <TableCell />
                        <TableCell colSpan={2} className="text-xs text-[var(--color-text-secondary)]">
                          {line.account_tiers && <span className="font-mono">[{line.account_tiers}] </span>}
                          {line.description || ''}
                        </TableCell>
                        <TableCell className="font-mono text-xs text-right">{Number(line.debit) > 0 ? formatCurrency(Number(line.debit)) : ''}</TableCell>
                        <TableCell className="font-mono text-xs text-right">{Number(line.credit) > 0 ? formatCurrency(Number(line.credit)) : ''}</TableCell>
                      </tr>
                    ))}
                  </div>
                ))}
              </Table>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
