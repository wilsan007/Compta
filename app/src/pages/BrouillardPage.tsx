import { Fragment, useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Table, TableRow, TableCell, EmptyState, Breadcrumb, SkeletonTable, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { getBrouillard, updateEntryStatusDetail, deleteJournalEntry } from '@/lib/queries'
import { Printer, Trash2, FileEdit, ChevronDown, ChevronRight } from 'lucide-react'
import type { JournalEntry } from '@/types'
import { useToast } from '@/lib/toast'

export function BrouillardPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
const [entries, setEntries] = useState<JournalEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [journalFilter, setJournalFilter] = useState('')

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const data = await getBrouillard()
      setEntries(data || [])
    } catch (err) {
      console.error('Error loading brouillard:', err)
    } finally {
      setLoading(false)
    }
  }

  function toggle(id: string) {
  setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function handlePrint(id: string) {
    try {
      await updateEntryStatusDetail(id, 'printed')
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.updateError'))
    }
  }

  async function handleDelete(id: string) {
    if (!window.confirm(t('brouillard.deleteConfirm'))) return
    try {
      await deleteJournalEntry(id)
      await load()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || tCommon('toast.deleteError'))
    }
  }

  const filtered = journalFilter
    ? entries.filter((e) => e.journal_code === journalFilter)
    : entries

  const journals = [...new Set(entries.map((e) => e.journal_code).filter(Boolean))] as string[]

  const totalDebit = filtered.reduce((s, e) => s + Number(e.total_debit), 0)
  const totalCredit = filtered.reduce((s, e) => s + Number(e.total_credit), 0)

  return (
    <div>
      <Breadcrumb items={[{ label: t('title') }, { label: t('brouillard.breadcrumb') }, { label: t('brouillard.title') }]} />
      <PageHeader title={t('brouillard.title')} subtitle={t('brouillard.subtitle')} />

      <div className="flex gap-3 mb-4 items-end">
        <div className="w-56">
          <Select
            label={t('brouillard.journal')}
            value={journalFilter}
            onChange={(e) => setJournalFilter(e.target.value)}
            options={[{ value: '', label: tCommon('common.all') }, ...journals.map((j: string) => ({ value: j, label: j }))]}
          />
        </div>
        <div className="flex gap-4 ml-auto text-sm">
          <span className="text-[var(--color-text-secondary)]">{t('brouillard.totalDebit')}: <strong className="font-mono">{formatCurrency(totalDebit)}</strong></span>
          <span className="text-[var(--color-text-secondary)]">{t('brouillard.totalCredit')}: <strong className="font-mono">{formatCurrency(totalCredit)}</strong></span>
        </div>
      </div>

      {loading ? (
        <SkeletonTable rows={6} cols={7} />
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<FileEdit className="w-8 h-8" />}
          title={t('brouillard.noEntries')}
          description={t('brouillard.noEntriesDescription')}
        />
      ) : (
        <Card>
          <Table headers={['', t('brouillard.entryNumber'), tCommon('common.date'), t('brouillard.journal'), tCommon('common.description'), t('brouillard.debit'), t('brouillard.credit'), tCommon('table.actions')]}>
            {filtered.map((entry) => (
              <Fragment key={entry.id}>
                <TableRow onClick={() => toggle(entry.id)}>
                  <TableCell className="w-8">
                    {entry.journal_lines && entry.journal_lines.length > 0
                      ? (expanded.has(entry.id) ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />)
                      : <span className="w-4 inline-block" />}
                  </TableCell>
                  <TableCell className="font-mono text-xs">{entry.piece_number || entry.number}</TableCell>
                  <TableCell className="text-xs">{formatDate(entry.date)}</TableCell>
                  <TableCell className="font-mono text-xs">{entry.journal_code}</TableCell>
                  <TableCell className="max-w-xs truncate text-sm">{entry.description}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.total_debit))}</TableCell>
                  <TableCell className="font-mono text-xs text-right">{formatCurrency(Number(entry.total_credit))}</TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      <button onClick={(e) => { e.stopPropagation(); handlePrint(entry.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-primary)]" title={t('brouillard.print')}>
                        <Printer className="w-4 h-4" />
                      </button>
                      <button onClick={(e) => { e.stopPropagation(); handleDelete(entry.id) }} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]" title={tCommon('actions.delete')}>
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </TableCell>
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
                    <TableCell />
                  </tr>
                ))}
              </Fragment>
            ))}
          </Table>
        </Card>
      )}
    </div>
  )
}
