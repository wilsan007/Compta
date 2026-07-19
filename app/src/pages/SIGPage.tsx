import { useEffect, useState, useMemo } from 'react'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency } from '@/lib/utils'
import { getSIGData, getFiscalYears } from '@/lib/queries'
import { TrendingUp } from 'lucide-react'
import type { FiscalYear } from '@/types'

export function SIGPage() {
  const [data, setData] = useState<any[]>([])
  const [years, setYears] = useState<FiscalYear[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadYears()
  }, [])

  async function loadYears() {
    try {
      const fy = await getFiscalYears()
      setYears(fy || [])
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    }
  }

  useEffect(() => {
    loadSIG()
  }, [selectedYear])

  async function loadSIG() {
    setLoading(true)
    try {
      const res = await getSIGData(selectedYear || undefined)
      setData(res)
    } catch (err) {
      console.error('Error loading SIG:', err)
    } finally {
      setLoading(false)
    }
  }

  const sig = useMemo(() => {
    const getSolde = (prefix: string) =>
      data.filter((d) => d.code.startsWith(prefix)).reduce((s, d) => s + d.solde, 0)

    const ventes = getSolde('70')
    const productionStockee = -getSolde('71')
    const immobilisations = -getSolde('72')
    const autresProduits = getSolde('74') + getSolde('75') + getSolde('78') + getSolde('79')
    const achats = getSolde('60')
    const variationsStock = getSolde('603')
    const servicesExt = getSolde('61')
    const autresCharges = getSolde('62') + getSolde('63') + getSolde('65')
    const chargesFinancieres = getSolde('66')
    const chargesExceptionnelles = getSolde('67')
    const dotations = getSolde('68')
    const impots = getSolde('69')

    const margeCommerciale = ventes - achats
    const valeurAjoutee = margeCommerciale + productionStockee + immobilisations - variationsStock - servicesExt
    const ebe = valeurAjoutee + autresProduits - autresCharges - impots
    const resultatExploitation = ebe - dotations
    const resultatFinancier = -chargesFinancieres
    const resultatExceptionnel = -chargesExceptionnelles
    const resultatNet = resultatExploitation + resultatFinancier + resultatExceptionnel

    return [
      { label: 'Ventes de marchandises (70)', value: ventes, isTotal: false },
      { label: 'Marge commerciale', value: margeCommerciale, isTotal: true },
      { label: 'Production stockée (71)', value: productionStockee, isTotal: false },
      { label: 'Immobilisations (72)', value: immobilisations, isTotal: false },
      { label: 'Autres produits (74/75/78/79)', value: autresProduits, isTotal: false },
      { label: 'Valeur ajoutée', value: valeurAjoutee, isTotal: true },
      { label: 'Achats (60)', value: -achats, isTotal: false },
      { label: 'Variations de stock (603)', value: -variationsStock, isTotal: false },
      { label: 'Services extérieurs (61)', value: -servicesExt, isTotal: false },
      { label: 'Autres charges (62/63/65)', value: -autresCharges, isTotal: false },
      { label: 'Impôts et taxes (69)', value: -impots, isTotal: false },
      { label: 'Excédent Brut d\'Exploitation (EBE)', value: ebe, isTotal: true },
      { label: 'Dotations aux amortissements (68)', value: -dotations, isTotal: false },
      { label: 'Résultat d\'exploitation', value: resultatExploitation, isTotal: true },
      { label: 'Charges financières (66)', value: -chargesFinancieres, isTotal: false },
      { label: 'Résultat financier', value: resultatFinancier, isTotal: true },
      { label: 'Charges exceptionnelles (67)', value: -chargesExceptionnelles, isTotal: false },
      { label: 'Résultat exceptionnel', value: resultatExceptionnel, isTotal: true },
      { label: 'RÉSULTAT NET', value: resultatNet, isTotal: true, isFinal: true },
    ]
  }, [data])

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'États' }, { label: 'SIG' }]} />
      <PageHeader title="Soldes Intermédiaires de Gestion" subtitle="SIG — Compte de résultat en cascade" />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-56">
          <Select
            label="Exercice"
            value={selectedYear}
            onChange={(e) => setSelectedYear(e.target.value)}
            options={[{ value: '', label: 'Tous' }, ...years.map((y) => ({ value: y.id, label: y.code }))]}
          />
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={10} cols={2} />
      ) : data.length === 0 ? (
        <EmptyState
          icon={<TrendingUp className="w-8 h-8" />}
          title="Aucune donnée"
          description="Aucune écriture sur les comptes de classe 6 et 7 trouvée."
        />
      ) : (
        <Card>
          <Table headers={['Rubrique', 'Montant']}>
            {sig.map((row, i) => (
              <TableRow key={i}>
                <TableCell className={row.isFinal ? 'font-bold text-base' : row.isTotal ? 'font-semibold' : 'text-sm'}>
                  {row.label}
                </TableCell>
                <TableCell className={`font-mono text-right ${row.isFinal ? 'font-bold text-base' : row.isTotal ? 'font-semibold' : ''} ${row.value >= 0 ? 'text-[var(--color-success)]' : 'text-[var(--color-danger)]'}`}>
                  {formatCurrency(row.value)}
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
