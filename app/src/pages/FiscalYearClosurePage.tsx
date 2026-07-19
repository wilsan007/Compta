import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable } from '@/components/ui'
import { getFiscalYears, closeFiscalYear } from '@/lib/queries'
import { Lock, AlertTriangle } from 'lucide-react'
import type { FiscalYear } from '@/types'
import { useToast } from '@/lib/toast'

export function FiscalYearClosurePage() {
  const { toast } = useToast()
const [years, setYears] = useState<FiscalYear[]>([])
  const [loading, setLoading] = useState(true)
  const [closing, setClosing] = useState(false)
  const [selectedYear, setSelectedYear] = useState('')
  const [targetYear, setTargetYear] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
  try {
      const data = await getFiscalYears()
      setYears(data || [])
      const openYears = (data || []).filter((y) => y.status === 'open')
      if (openYears.length > 0) setSelectedYear(openYears[0].id)
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleClose() {
    if (!selectedYear || !targetYear) {
      toast('warning', 'Attention', 'Sélectionnez l\'exercice à clôturer et le nouvel exercice')
      return
    }
    if (selectedYear === targetYear) {
      toast('warning', 'Attention', 'L\'exercice cible doit être différent')
      return
    }
    if (!window.confirm('Confirmer la clôture de l\'exercice ? Cette opération génère les écritures de report à nouveau et est irréversible.')) return
    setClosing(true)
    try {
      const result = await closeFiscalYear(selectedYear, targetYear)
      toast('success', 'Exercice clôturé', `${result?.openingLinesCount || 0} ligne(s) de report à nouveau générée(s).`)
      await load()
    } catch (err: any) {
      toast('error', 'Erreur', err.message || 'échec')
    } finally {
      setClosing(false)
    }
  }

  const openYears = years.filter((y) => y.status === 'open')
  const selectedYearObj = years.find((y) => y.id === selectedYear)

  if (loading) {
    return (
      <div>
        <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Traitement' }, { label: 'Clôture exercice' }]} />
        <PageHeader title="Clôture d'exercice" subtitle="Chargement..." />
        <SkeletonTable rows={4} cols={4} />
      </div>
    )
  }

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'Traitement' }, { label: 'Clôture exercice' }]} />
      <PageHeader title="Clôture d'exercice" subtitle="Clôture annuelle et report à nouveau" />

      {years.length === 0 ? (
        <EmptyState
          icon={<Lock className="w-8 h-8" />}
          title="Aucun exercice"
          description="Créez d'abord des exercices dans la section Structure."
        />
      ) : (
        <div className="space-y-4">
          <Card>
            <div className="p-4 space-y-4">
              <h3 className="text-sm font-semibold">Exercices disponibles</h3>
              <Table headers={['Code', 'Libellé', 'Statut', 'Actions']}>
                {years.map((y) => (
                  <TableRow key={y.id}>
                    <TableCell className="font-mono text-sm font-semibold">{y.code}</TableCell>
                    <TableCell className="text-sm">{y.code}</TableCell>
                    <TableCell>
                      <Badge variant={y.status === 'open' ? 'success' : 'danger'}>
                        {y.status === 'open' ? 'Ouvert' : 'Clôturé'}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      {y.status === 'open' && (
                        <Button variant="secondary" onClick={() => setSelectedYear(y.id)}>Sélectionner</Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </Table>
            </div>
          </Card>

          {selectedYearObj && (
            <Card>
              <div className="p-4 space-y-4">
                <h3 className="text-sm font-semibold">Clôturer l'exercice {selectedYearObj.code}</h3>
                <div className="flex items-center gap-3 p-3 rounded-lg bg-[var(--color-warning)]/10 border border-[var(--color-warning)]/30">
                  <AlertTriangle className="w-5 h-5 text-[var(--color-warning)] flex-shrink-0" />
                  <p className="text-sm text-[var(--color-text-secondary)]">
                    Cette opération va calculer les soldes de tous les comptes (hors classe 6/7),
                    générer les écritures de report à nouveau dans le nouvel exercice,
                    puis marquer l'exercice courant comme clôturé.
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Exercice à clôturer</label>
                    <select className="input" value={selectedYear} onChange={(e) => setSelectedYear(e.target.value)}>
                      {openYears.map((y) => <option key={y.id} value={y.id}>{y.code}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1">Nouvel exercice (cible)</label>
                    <select className="input" value={targetYear} onChange={(e) => setTargetYear(e.target.value)}>
                      <option value="">— Sélectionner —</option>
                      {years.map((y) => <option key={y.id} value={y.id}>{y.code}</option>)}
                    </select>
                  </div>
                </div>
                <div className="flex justify-end">
                  <Button onClick={handleClose} disabled={closing || !targetYear || selectedYear === targetYear}>
                    <Lock className="w-4 h-4" /> {closing ? 'Clôture en cours...' : 'Clôturer l\'exercice'}
                  </Button>
                </div>
              </div>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
