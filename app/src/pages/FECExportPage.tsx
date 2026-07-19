import { useEffect, useState } from 'react'
import { Card, PageHeader, Button, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { getFiscalYears, getFECData } from '@/lib/queries'
import { Download, FileText } from 'lucide-react'
import type { FiscalYear } from '@/types'

function escapeFECField(value: any): string {
  if (value === null || value === undefined) return ''
  return String(value).replace(/"/g, '""')
}

function generateFECText(entries: any[]): string {
  const lines: string[] = []
  const header = [
    'JournalCode', 'JournalLib', 'EcritureNum', 'EcritureDate', 'CompteNum',
    'CompteLib', 'CompAuxNum', 'CompAuxLib', 'PieceRef', 'PieceDate',
    'EcritureLib', 'Debit', 'Credit', 'EcritureLet', 'DateLet',
    'ValidDate', 'Montantdevise', 'Idevise',
  ]
  lines.push(header.join('|'))

  for (const entry of entries) {
    const je = entry
    for (const line of je.journal_lines || []) {
      const row = [
        escapeFECField(je.journal_code),
        escapeFECField('Journal'),
        escapeFECField(je.number),
        escapeFECField(je.date?.replace(/-/g, '')),
        escapeFECField(line.account_general || line.account_code),
        escapeFECField(line.account_name || ''),
        escapeFECField(line.account_tiers || ''),
        escapeFECField(''),
        escapeFECField(je.piece_number || je.number),
        escapeFECField(je.date?.replace(/-/g, '')),
        escapeFECField(line.description || je.description),
        escapeFECField(Number(line.debit).toFixed(2)),
        escapeFECField(Number(line.credit).toFixed(2)),
        escapeFECField(line.lettrage_code || ''),
        escapeFECField(''),
        escapeFECField(je.date?.replace(/-/g, '')),
        '',
        '',
      ]
      lines.push(row.join('|'))
    }
  }

  return lines.join('\n')
}

export function FECExportPage() {
  const [years, setYears] = useState<FiscalYear[]>([])
  const [selectedYear, setSelectedYear] = useState('')
  const [loading, setLoading] = useState(false)
  const [entries, setEntries] = useState<any[]>([])
  const [exported, setExported] = useState(false)

  useEffect(() => { loadYears() }, [])

  async function loadYears() {
    try {
      const data = await getFiscalYears()
      setYears(data || [])
    } catch (err) {
      console.error('Error loading fiscal years:', err)
    }
  }

  async function loadFEC() {
    if (!selectedYear) return
    setLoading(true)
    setExported(false)
    try {
      const data = await getFECData(selectedYear)
      setEntries(data || [])
    } catch (err) {
      console.error('Error loading FEC data:', err)
    } finally {
      setLoading(false)
    }
  }

  function handleExport() {
    const year = years.find((y) => y.id === selectedYear)
    const fecText = generateFECText(entries)
    const blob = new Blob([fecText], { type: 'text/plain;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `FEC_${year?.code || 'exercice'}.txt`
    a.click()
    URL.revokeObjectURL(url)
    setExported(true)
  }

  const totalLines = entries.reduce((s, e) => s + (e.journal_lines?.length || 0), 0)
  const totalDebit = entries.reduce((s, e) =>
    s + (e.journal_lines?.reduce((ls: number, l: any) => ls + Number(l.debit), 0) || 0), 0)
  const totalCredit = entries.reduce((s, e) =>
    s + (e.journal_lines?.reduce((ls: number, l: any) => ls + Number(l.credit), 0) || 0), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: 'Comptabilité' }, { label: 'États' }, { label: 'Export FEC' }]} />
      <PageHeader title="Export FEC" subtitle="Fichier des Écritures Comptables (DGFIP)" />

      <Card className="mb-4">
        <div className="p-4 flex gap-3 items-end">
          <div className="w-56">
            <Select
              label="Exercice"
              value={selectedYear}
              onChange={(e) => setSelectedYear(e.target.value)}
              options={years.map((y) => ({ value: y.id, label: y.code }))}
            />
          </div>
          <Button onClick={loadFEC} disabled={loading || !selectedYear}>
            <FileText className="w-4 h-4" /> {loading ? 'Chargement...' : 'Générer'}
          </Button>
          {entries.length > 0 && (
            <Button variant="secondary" onClick={handleExport}>
              <Download className="w-4 h-4" /> Exporter FEC.txt
            </Button>
          )}
        </div>
      </Card>

      {loading ? (
        <SkeletonTable rows={4} cols={4} />
      ) : entries.length === 0 ? (
        <EmptyState
          icon={<FileText className="w-8 h-8" />}
          title="Aucune donnée FEC"
          description="Sélectionnez un exercice et cliquez sur Générer."
        />
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-4 gap-4">
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Écritures</p>
              <p className="text-lg font-bold">{entries.length}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Lignes</p>
              <p className="text-lg font-bold">{totalLines}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Total débit</p>
              <p className="text-lg font-bold font-mono">{totalDebit.toFixed(2)}</p>
            </div>
            <div className="card p-4">
              <p className="text-xs text-[var(--color-text-secondary)] mb-1">Total crédit</p>
              <p className="text-lg font-bold font-mono">{totalCredit.toFixed(2)}</p>
            </div>
          </div>
          {exported && (
            <div className="p-3 rounded-lg bg-[var(--color-success)]/10 border border-[var(--color-success)]/30 text-sm text-[var(--color-success)]">
              Fichier FEC exporté avec succès.
            </div>
          )}
          <Card>
            <div className="p-4">
              <h3 className="text-sm font-semibold mb-2">Aperçu (5 premières écritures)</h3>
              <pre className="text-xs font-mono overflow-x-auto bg-[var(--color-neutral-50)] p-3 rounded-lg max-h-96">
                {generateFECText(entries.slice(0, 5))}
              </pre>
            </div>
          </Card>
        </div>
      )}
    </div>
  )
}
