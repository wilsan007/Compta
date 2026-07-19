import { useEffect, useState, useMemo } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import {
  getThirdPartyAccounts, getUnletteredLines, getLetteredLines,
  applyLettrage, removeLettrage, getNextLettrageCode,
} from '@/lib/queries'
import { Link2, Unlink, Search, Wand2 } from 'lucide-react'
import type { ThirdPartyAccount } from '@/types'
import { useToast } from '@/lib/toast'

export function LettragePage() {
  const { toast } = useToast()
const [thirdParties, setThirdParties] = useState<ThirdPartyAccount[]>([])
  const [selectedTiers, setSelectedTiers] = useState('')
  const [unlettered, setUnlettered] = useState<any[]>([])
  const [lettered, setLettered] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [loadingLines, setLoadingLines] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [search, setSearch] = useState('')
  const [filterType, setFilterType] = useState('')

  useEffect(() => { loadThirdParties() }, [])

  async function loadThirdParties() {
    try {
      const tp = await getThirdPartyAccounts()
      setThirdParties(tp || [])
    } catch (err) {
      console.error('Error loading third parties:', err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (selectedTiers) { loadLines() }
    else { setUnlettered([]); setLettered([]) }
  }, [selectedTiers])

  async function loadLines() {
    setLoadingLines(true)
    setSelected(new Set())
    try {
      const [ul, l] = await Promise.all([
        getUnletteredLines(selectedTiers),
        getLetteredLines(selectedTiers),
      ])
      setUnlettered(ul || [])
      setLettered(l || [])
    } catch (err) {
      console.error('Error loading lines:', err)
    } finally {
      setLoadingLines(false)
    }
  }

  function toggleSelect(id: string) {
  setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function handleLettrer() {
    if (selected.size < 2) { toast('warning', 'Attention', 'Sélectionnez au moins 2 lignes à lettrer.'); return }
    const totalD = unlettered.filter((l) => selected.has(l.id)).reduce((s, l) => s + Number(l.debit), 0)
    const totalC = unlettered.filter((l) => selected.has(l.id)).reduce((s, l) => s + Number(l.credit), 0)
    if (Math.abs(totalD - totalC) > 0.01) {
      toast('error', 'Écritures non équilibrées', `Débit: ${formatCurrency(totalD)}, Crédit: ${formatCurrency(totalC)}`)
      return
    }
    try {
      const code = await getNextLettrageCode()
      await applyLettrage(Array.from(selected), code)
      await loadLines()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleDelettrer(lineIds: string[]) {
    if (!window.confirm('Délettrer ces lignes ?')) return
    try {
      await removeLettrage(lineIds)
      await loadLines()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    }
  }

  async function handleAutoLettrer() {
    const sorted = [...unlettered].sort((a, b) => {
      const da = new Date(a.journal_entries?.date || a.created_at).getTime()
      const db = new Date(b.journal_entries?.date || b.created_at).getTime()
      return da - db
    })
    let count = 0
    for (let i = 0; i < sorted.length; i++) {
      for (let j = i + 1; j < sorted.length; j++) {
        const d = Number(sorted[i].debit)
        const c = Number(sorted[i].credit)
        const d2 = Number(sorted[j].debit)
        const c2 = Number(sorted[j].credit)
        if (d > 0 && c2 > 0 && Math.abs(d - c2) < 0.01) {
          const code = await getNextLettrageCode()
          await applyLettrage([sorted[i].id, sorted[j].id], code)
          count++; sorted.splice(j, 1); sorted.splice(i, 1); i--; break
        }
        if (c > 0 && d2 > 0 && Math.abs(c - d2) < 0.01) {
          const code = await getNextLettrageCode()
          await applyLettrage([sorted[i].id, sorted[j].id], code)
          count++; sorted.splice(j, 1); sorted.splice(i, 1); i--; break
        }
      }
    }
    if (count > 0) await loadLines()
    toast(count > 0 ? 'success' : 'info', 'Lettrage automatique', count > 0 ? `${count} lettrage(s) automatique(s) effectué(s).` : 'Aucun lettrage automatique possible.')
  }

  const filteredThirdParties = useMemo(() => {
    return thirdParties.filter((t) => {
      const ms = !search || t.code.toLowerCase().includes(search.toLowerCase()) || t.name.toLowerCase().includes(search.toLowerCase())
      const mt = !filterType || t.type === filterType
      return ms && mt
    })
  }, [thirdParties, search, filterType])

  const selectedTiersObj = thirdParties.find((t) => t.code === selectedTiers)
  const unletteredBalance = unlettered.reduce((s, l) => s + Number(l.debit) - Number(l.credit), 0)

  const letteredGroups = useMemo(() => {
    const groups: Record<string, any[]> = {}
    for (const l of lettered) {
      const code = l.lettrage_code
      if (!groups[code]) groups[code] = []
      groups[code].push(l)
    }
    return groups
  }, [lettered])

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Traitement' }, { label: 'Lettrage' }]} />
        <PageHeader title="Lettrage" subtitle="Chargement..." />
        <SkeletonTable rows={6} cols={6} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Traitement' }, { label: 'Lettrage' }]} />
      <PageHeader title="Lettrage" subtitle="Interrogation & lettrage des comptes tiers" />

      <div className="grid grid-cols-3 gap-4">
        {/* Left: Third party selector */}
        <div className="col-span-1">
          <Card>
            <div className="p-4 space-y-3">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-secondary)]" />
                <input className="input pl-10" placeholder="Rechercher un tiers..." value={search} onChange={(e) => setSearch(e.target.value)} />
              </div>
              <select className="input cursor-pointer" value={filterType} onChange={(e) => setFilterType(e.target.value)}>
                <option value="">Tous les types</option>
                <option value="customer">Clients</option>
                <option value="supplier">Fournisseurs</option>
                <option value="employee">Employés</option>
                <option value="other">Autres</option>
              </select>
              <div className="max-h-[60vh] overflow-y-auto divide-y divide-[var(--color-border)]">
                {filteredThirdParties.length === 0 ? (
                  <p className="text-sm text-[var(--color-text-secondary)] text-center py-4">Aucun tiers trouvé</p>
                ) : (
                  filteredThirdParties.map((tp) => (
                    <button key={tp.id} onClick={() => setSelectedTiers(tp.code)}
                      className={`w-full text-left p-2 rounded hover:bg-[var(--color-neutral-50)] ${selectedTiers === tp.code ? 'bg-[var(--color-primary)]/5 border-l-2 border-[var(--color-primary)]' : ''}`}>
                      <div className="font-mono text-xs font-semibold">{tp.code}</div>
                      <div className="text-sm truncate">{tp.name}</div>
                      <div className="flex items-center gap-2 mt-1">
                        <Badge variant={tp.type === 'customer' ? 'success' : tp.type === 'supplier' ? 'warning' : 'neutral'}>
                          {tp.type === 'customer' ? 'Client' : tp.type === 'supplier' ? 'Fournisseur' : tp.type}
                        </Badge>
                      </div>
                    </button>
                  ))
                )}
              </div>
            </div>
          </Card>
        </div>

        {/* Right: Lines for selected third party */}
        <div className="col-span-2">
          {!selectedTiers ? (
            <EmptyState icon={<Link2 className="w-8 h-8" />} title="Sélectionnez un compte tiers"
              description="Choisissez un tiers dans la liste de gauche pour afficher ses écritures et procéder au lettrage." />
          ) : loadingLines ? (
            <SkeletonTable rows={6} cols={6} />
          ) : (
            <div className="space-y-4">
              {/* Unlettered lines */}
              <Card>
                <div className="p-4 border-b border-[var(--color-border)]">
                  <div className="flex items-center justify-between">
                    <div>
                      <h3 className="font-semibold text-sm">{selectedTiersObj?.code} — {selectedTiersObj?.name}</h3>
                      <p className="text-xs text-[var(--color-text-secondary)] mt-1">
                        {unlettered.length} ligne(s) non lettrée(s) — Solde: {formatCurrency(unletteredBalance)}
                      </p>
                    </div>
                    <div className="flex gap-2">
                      <Button size="sm" variant="secondary" onClick={handleAutoLettrer} disabled={unlettered.length < 2}>
                        <Wand2 className="w-3 h-3" /> Lettrage auto
                      </Button>
                      <Button size="sm" onClick={handleLettrer} disabled={selected.size < 2}>
                        <Link2 className="w-3 h-3" /> Lettrer ({selected.size})
                      </Button>
                    </div>
                  </div>
                </div>
                {unlettered.length === 0 ? (
                  <div className="p-8 text-center text-sm text-[var(--color-text-secondary)]">Aucune écriture non lettrée pour ce tiers.</div>
                ) : (
                  <Table headers={['✓', 'Date', 'N° pièce', 'Journal', 'Libellé', 'Débit', 'Crédit']}>
                    {unlettered.map((line) => (
                      <TableRow key={line.id}>
                        <TableCell className="w-8">
                          <input type="checkbox" checked={selected.has(line.id)} onChange={() => toggleSelect(line.id)} className="w-4 h-4 rounded cursor-pointer" />
                        </TableCell>
                        <TableCell className="text-xs">{formatDate(line.journal_entries?.date || line.line_date || '')}</TableCell>
                        <TableCell className="font-mono text-xs">{line.piece_number || line.journal_entries?.number}</TableCell>
                        <TableCell className="font-mono text-xs">{line.journal_entries?.journal_code}</TableCell>
                        <TableCell className="text-sm max-w-xs truncate">{line.description}</TableCell>
                        <TableCell className="font-mono text-xs text-right">{Number(line.debit) > 0 ? formatCurrency(Number(line.debit)) : ''}</TableCell>
                        <TableCell className="font-mono text-xs text-right">{Number(line.credit) > 0 ? formatCurrency(Number(line.credit)) : ''}</TableCell>
                      </TableRow>
                    ))}
                  </Table>
                )}
              </Card>

              {/* Lettered lines */}
              {Object.keys(letteredGroups).length > 0 && (
                <Card>
                  <div className="p-4 border-b border-[var(--color-border)]">
                    <h3 className="font-semibold text-sm">Écritures lettrées</h3>
                  </div>
                  <Table headers={['Code', 'Date', 'N° pièce', 'Journal', 'Libellé', 'Débit', 'Crédit', 'Actions']}>
                    {Object.entries(letteredGroups).map(([code, lines]) => (
                      <div key={code}>
                        {lines.map((line, idx) => (
                          <TableRow key={line.id}>
                            <TableCell className="font-mono text-xs font-semibold">{idx === 0 ? code : ''}</TableCell>
                            <TableCell className="text-xs">{formatDate(line.journal_entries?.date || line.line_date || '')}</TableCell>
                            <TableCell className="font-mono text-xs">{line.piece_number || line.journal_entries?.number}</TableCell>
                            <TableCell className="font-mono text-xs">{line.journal_entries?.journal_code}</TableCell>
                            <TableCell className="text-sm max-w-xs truncate">{line.description}</TableCell>
                            <TableCell className="font-mono text-xs text-right">{Number(line.debit) > 0 ? formatCurrency(Number(line.debit)) : ''}</TableCell>
                            <TableCell className="font-mono text-xs text-right">{Number(line.credit) > 0 ? formatCurrency(Number(line.credit)) : ''}</TableCell>
                            <TableCell>
                              {idx === 0 && (
                                <button onClick={() => handleDelettrer(lines.map((l) => l.id))}
                                  className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title="Délettrer">
                                  <Unlink className="w-3.5 h-3.5" />
                                </button>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </div>
                    ))}
                  </Table>
                </Card>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
