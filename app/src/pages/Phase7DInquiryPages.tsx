import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { useLocale } from '@/hooks/useLocale'
import { getReimputationLogs, createReimputationLog } from '@/lib/queries/misc'
import { getJournalEntries, getChartAccounts, getAnalyticSections, getAnalyticLedgerLines } from '@/lib/queries/accounting'
import { Plus, Search } from 'lucide-react'
import type { ReimputationLog } from '@/types'

// ============ Analytic OD Entry Page (Saisie OD analytiques) ============
export function AnalyticODEntryPage() {
  const { t } = useTranslation('accounting')
  const { toast } = useToast()
  const [sections, setSections] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getAnalyticSections()
      setSections(data || [])
    } catch (err) {
      console.error('Error loading analytic sections:', err)
      toast('error', t('analyticODEntry.title'), t('analyticODEntry.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  const filtered = sections.filter(s =>
    !search || s.code?.toLowerCase().includes(search.toLowerCase()) || s.name?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('analyticODEntry.title') }]} />
      <PageHeader title={t('analyticODEntry.title')} subtitle={t('analyticODEntry.subtitle')} />
      <Card className="p-4 mb-4">
        <div className="flex items-center gap-2">
          <Search className="w-4 h-4 text-[var(--color-text-secondary)]" />
          <Input placeholder={t('analyticODEntry.searchPlaceholder')} value={search} onChange={e => setSearch(e.target.value)} />
        </div>
      </Card>
      {loading ? <SkeletonTable /> : filtered.length === 0 ? <EmptyState title={t('analyticODEntry.empty')} /> : (
        <Table headers={[t('analyticODEntry.code'), t('analyticODEntry.name'), t('analyticODEntry.type'), t('analyticODEntry.parent')]}>
          {filtered.map(s => (
            <TableRow key={s.id}>
              <TableCell className="font-mono text-xs">{s.code}</TableCell>
              <TableCell>{s.name}</TableCell>
              <TableCell><Badge variant="primary">{s.type || 'section'}</Badge></TableCell>
              <TableCell className="font-mono text-xs">{s.parent_id ? sections.find(p => p.id === s.parent_id)?.code : '-'}</TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Third Party Inquiry Page (Interrogation tiers) ============
export function ThirdPartyInquiryPage() {
  const { t } = useTranslation('accounting')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [entries, setEntries] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [accountFilter, setAccountFilter] = useState('')

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const data = await getJournalEntries()
      setEntries(data || [])
    } catch (err) {
      console.error('Error loading entries:', err)
      toast('error', t('thirdPartyInquiry.title'), t('thirdPartyInquiry.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  const filtered = entries.filter(e =>
    (!search || e.description?.toLowerCase().includes(search.toLowerCase()) || e.number?.toLowerCase().includes(search.toLowerCase())) &&
    (!accountFilter || e.third_party_account?.includes(accountFilter))
  )

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('thirdPartyInquiry.title') }]} />
      <PageHeader title={t('thirdPartyInquiry.title')} subtitle={t('thirdPartyInquiry.subtitle')} />
      <Card className="p-4 mb-4 space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <Input placeholder={t('thirdPartyInquiry.searchPlaceholder')} value={search} onChange={e => setSearch(e.target.value)} />
          <Input placeholder={t('thirdPartyInquiry.accountFilter')} value={accountFilter} onChange={e => setAccountFilter(e.target.value)} />
        </div>
      </Card>
      {loading ? <SkeletonTable /> : filtered.length === 0 ? <EmptyState title={t('thirdPartyInquiry.empty')} /> : (
        <Table headers={[t('thirdPartyInquiry.date'), t('thirdPartyInquiry.number'), t('thirdPartyInquiry.description'), t('thirdPartyInquiry.thirdParty'), t('thirdPartyInquiry.debit'), t('thirdPartyInquiry.credit')]}>
          {filtered.slice(0, 100).map(e => (
            <TableRow key={e.id}>
              <TableCell>{formatDate(e.date)}</TableCell>
              <TableCell className="font-mono text-xs">{e.number}</TableCell>
              <TableCell>{e.description}</TableCell>
              <TableCell className="font-mono text-xs">{e.third_party_account || '-'}</TableCell>
              <TableCell className="text-right">{formatCurrency(e.total_debit || 0)}</TableCell>
              <TableCell className="text-right">{formatCurrency(e.total_credit || 0)}</TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Analytic Inquiry Page (Interrogation analytique) ============
export function AnalyticInquiryPage() {
  const { t } = useTranslation('accounting')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [lines, setLines] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')

  const load = useCallback(async () => {
    try {
      setLoading(true)
      // ACC-04 : lignes imputées analytiquement, requête bornée dédiée
      const data = await getAnalyticLedgerLines()
      setLines(data || [])
    } catch (err) {
      console.error('Error loading analytic lines:', err)
      toast('error', t('analyticInquiry.title'), t('analyticInquiry.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  const filtered = lines.filter(l =>
    !search || l.account_code?.toLowerCase().includes(search.toLowerCase()) || l.description?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('analyticInquiry.title') }]} />
      <PageHeader title={t('analyticInquiry.title')} subtitle={t('analyticInquiry.subtitle')} />
      <Card className="p-4 mb-4">
        <div className="flex items-center gap-2">
          <Search className="w-4 h-4 text-[var(--color-text-secondary)]" />
          <Input placeholder={t('analyticInquiry.searchPlaceholder')} value={search} onChange={e => setSearch(e.target.value)} />
        </div>
      </Card>
      {loading ? <SkeletonTable /> : filtered.length === 0 ? <EmptyState title={t('analyticInquiry.empty')} /> : (
        <Table headers={[t('analyticInquiry.date'), t('analyticInquiry.account'), t('analyticInquiry.description'), t('analyticInquiry.section'), t('analyticInquiry.amount')]}>
          {filtered.slice(0, 100).map(l => (
            <TableRow key={l.id}>
              <TableCell>{formatDate(l.date)}</TableCell>
              <TableCell className="font-mono text-xs">{l.account_code}</TableCell>
              <TableCell>{l.description}</TableCell>
              <TableCell className="font-mono text-xs">{l.analytic_section_id?.slice(0, 8) || '-'}</TableCell>
              <TableCell className="text-right">{formatCurrency(l.analytic_amount || l.debit || l.credit || 0)}</TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Reimputation Page (Réimputation) ============
export function ReimputationPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [logs, setLogs] = useState<ReimputationLog[]>([])
  const [entries, setEntries] = useState<any[]>([])
  const [accounts, setAccounts] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ original_entry_id: '', from_account: '', to_account: '', amount: 0, reason: '' })

  const load = useCallback(async () => {
    try {
      setLoading(true)
      const [l, e, a] = await Promise.all([getReimputationLogs(), getJournalEntries(), getChartAccounts()])
      setLogs(l || [])
      setEntries((e || []).filter((x: any) => x.status === 'posted'))
      setAccounts(a || [])
    } catch (err) {
      console.error('Error loading reimputation logs:', err)
      toast('error', t('reimputation.title'), t('reimputation.loadError'))
    } finally {
      setLoading(false)
    }
  }, [toast, t])

  useEffect(() => { load() }, [load])

  function resetForm() {
    setForm({ original_entry_id: '', from_account: '', to_account: '', amount: 0, reason: '' })
    setShowForm(false)
  }

  async function handleSubmit() {
    try {
      await createReimputationLog({ ...form, original_line_id: null, reimputed_entry_id: null, reimputed_line_id: null, status: 'completed' } as any)
      toast('success', tCommon('common.success'), tCommon('toast.created'))
      resetForm()
      await load()
    } catch (err: any) {
      toast('error', tCommon('common.error'), err.message)
    }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('reimputation.title') }]} />
      <PageHeader title={t('reimputation.title')} subtitle={t('reimputation.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('reimputation.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <Select label={t('reimputation.selectEntry')} value={form.original_entry_id} onChange={e => setForm({ ...form, original_entry_id: e.target.value })}
            options={[{ value: '', label: tCommon('actions.select') }, ...entries.map((e: any) => ({ value: e.id, label: `${e.number} - ${e.description} (${e.date})` }))]} />
          <div className="grid grid-cols-2 gap-3">
            <Select label={t('reimputation.fromAccount')} value={form.from_account} onChange={e => setForm({ ...form, from_account: e.target.value })}
              options={[{ value: '', label: tCommon('actions.select') }, ...accounts.map(a => ({ value: a.code, label: `${a.code} - ${a.name}` }))]} />
            <Select label={t('reimputation.toAccount')} value={form.to_account} onChange={e => setForm({ ...form, to_account: e.target.value })}
              options={[{ value: '', label: tCommon('actions.select') }, ...accounts.map(a => ({ value: a.code, label: `${a.code} - ${a.name}` }))]} />
          </div>
          <Input label={t('reimputation.amount')} type="number" value={String(form.amount)} onChange={e => setForm({ ...form, amount: Number(e.target.value) })} />
          <Input label={t('reimputation.reason')} value={form.reason} onChange={e => setForm({ ...form, reason: e.target.value })} />
          <div className="flex gap-2">
            <Button onClick={handleSubmit}>{t('reimputation.create')}</Button>
            <Button variant="secondary" onClick={resetForm}>{tCommon('actions.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : logs.length === 0 ? <EmptyState title={t('reimputation.empty')} /> : (
        <Table headers={[t('reimputation.date'), t('reimputation.fromAccount'), t('reimputation.toAccount'), t('reimputation.amount'), t('reimputation.reason'), t('reimputation.status')]}>
          {logs.map(l => (
            <TableRow key={l.id}>
              <TableCell>{formatDate(l.created_at)}</TableCell>
              <TableCell className="font-mono text-xs">{l.from_account}</TableCell>
              <TableCell className="font-mono text-xs">{l.to_account}</TableCell>
              <TableCell className="text-right">{formatCurrency(l.amount)}</TableCell>
              <TableCell>{l.reason || '-'}</TableCell>
              <TableCell><Badge variant={l.status === 'completed' ? 'success' : 'neutral'}>{l.status}</Badge></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}
