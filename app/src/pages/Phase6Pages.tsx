import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { useLocale } from '@/hooks/useLocale'
import { Plus, Trash2, Edit2, Play, Printer, Shield, CheckCircle, AlertTriangle, XCircle, Download, X } from 'lucide-react'
import {
  getAutoLabelRules, createAutoLabelRule, updateAutoLabelRule, deleteAutoLabelRule,
  getExtourneLogs, generateExtourne,
  getCarryForwardLogs, generateCarryForward,
  getLettrageDifferences, deleteLettrageDifference,
  getAccountingControlRuns, runAccountingControl,
  getCashControlSessions, createCashControlSession, updateCashControlSession, deleteCashControlSession,
  getFECAttestations, createFECAttestation, deleteFECAttestation,
  getTierRIBs, createTierRIB, updateTierRIB, deleteTierRIB,
  getIFRSAdjustments, createIFRSAdjustment, deleteIFRSAdjustment,
  getTaxPayments, createTaxPayment, updateTaxPayment, deleteTaxPayment,
  getCustomReportTemplates, createCustomReportTemplate, updateCustomReportTemplate, deleteCustomReportTemplate,
  getDeferredPrintingJobs, createDeferredPrintingJob, deleteDeferredPrintingJob,
  getJournalAccessRights, createJournalAccessRight, deleteJournalAccessRight,
  getVATOnCollections, createVATOnCollection, deleteVATOnCollection,
  getBatchEntrySessions, createBatchEntrySession, deleteBatchEntrySession,
  getJournalEntries, getFiscalYears, getJournals, getThirdPartyAccounts, getBankAccounts,
} from '@/lib/queries'
import type {
  AutoLabelRule, ExtourneLog, CarryForwardLog, LettrageDifference,
  AccountingControlRun, CashControlSession, FECAttestation, TierRIB,
  IFRSAdjustment, TaxPayment, CustomReportTemplate, DeferredPrintingJob,
  VATOnCollection, BatchEntrySession,
} from '@/types'

// ============ Batch Entry Page (Saisie par lot) ============
export function BatchEntryPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [sessions, setSessions] = useState<BatchEntrySession[]>([])
  const [journals, setJournals] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ session_name: '', journal_code: '', session_date: new Date().toISOString().slice(0, 10) })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [s, j] = await Promise.all([getBatchEntrySessions(), getJournals()])
      setSessions(s || [])
      setJournals(j || [])
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try {
      await createBatchEntrySession({ ...form, entry_count: 0, total_debit: 0, total_credit: 0, status: 'draft' } as any)
      toast('success', tCommon('common.success'), t('batchEntry.created'))
      setShowForm(false); setForm({ session_name: '', journal_code: '', session_date: new Date().toISOString().slice(0, 10) })
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteBatchEntrySession(id); toast('success', tCommon('common.success'), t('batchEntry.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('batchEntry.title') }]} />
      <PageHeader title={t('batchEntry.title')} subtitle={t('batchEntry.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('batchEntry.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <Input label={t('batchEntry.sessionName')} value={form.session_name} onChange={e => setForm({ ...form, session_name: e.target.value })} />
            <Select label={t('batchEntry.journal')} value={form.journal_code} onChange={e => setForm({ ...form, journal_code: e.target.value })}
              options={[{ value: '', label: tCommon('common.select') }, ...journals.map(j => ({ value: j.code, label: `${j.code} - ${j.name}` }))]} />
            <Input type="date" label={t('batchEntry.date')} value={form.session_date} onChange={e => setForm({ ...form, session_date: e.target.value })} />
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : sessions.length === 0 ? <EmptyState title={t('batchEntry.empty')} /> : (
        <Table headers={[t('batchEntry.colName'), t('batchEntry.colJournal'), t('batchEntry.colDate'), t('batchEntry.colEntries'), t('batchEntry.colDebit'), t('batchEntry.colCredit'), t('batchEntry.colStatus'), tCommon('table.actions')]}>
          {sessions.map(s => (
            <TableRow key={s.id}>
              <TableCell>{s.session_name}</TableCell>
              <TableCell>{s.journal_code}</TableCell>
              <TableCell>{formatDate(s.session_date)}</TableCell>
              <TableCell>{s.entry_count}</TableCell>
              <TableCell>{formatCurrency(s.total_debit)}</TableCell>
              <TableCell>{formatCurrency(s.total_credit)}</TableCell>
              <TableCell><Badge variant={s.status === 'validated' ? 'success' : 'warning'}>{t(`batchEntry.status.${s.status}`)}</Badge></TableCell>
              <TableCell><Button variant="danger" size="sm" onClick={() => handleDelete(s.id)}><Trash2 className="w-3 h-3" /></Button></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Auto Label Rules Page (Libellé automatique) ============
export function AutoLabelRulesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [rules, setRules] = useState<AutoLabelRule[]>([])
  const [journals, setJournals] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<AutoLabelRule | null>(null)
  const [form, setForm] = useState({ name: '', description: '', journal_code: '', account_code: '', account_prefix: '', label_pattern: '', priority: 100, active: true })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [r, j] = await Promise.all([getAutoLabelRules(), getJournals()])
      setRules(r || []); setJournals(j || [])
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  function openCreate() { setEditing(null); setForm({ name: '', description: '', journal_code: '', account_code: '', account_prefix: '', label_pattern: '', priority: 100, active: true }); setShowForm(true) }
  function openEdit(r: AutoLabelRule) { setEditing(r); setForm({ name: r.name, description: r.description || '', journal_code: r.journal_code || '', account_code: r.account_code || '', account_prefix: r.account_prefix || '', label_pattern: r.label_pattern, priority: r.priority, active: r.active }); setShowForm(true) }

  async function handleSave() {
    try {
      if (editing) { await updateAutoLabelRule(editing.id, form); toast('success', tCommon('common.success'), t('autoLabel.updated')) }
      else { await createAutoLabelRule(form as any); toast('success', tCommon('common.success'), t('autoLabel.created')) }
      setShowForm(false); await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteAutoLabelRule(id); toast('success', tCommon('common.success'), t('autoLabel.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('autoLabel.title') }]} />
      <PageHeader title={t('autoLabel.title')} subtitle={t('autoLabel.subtitle')} action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('autoLabel.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('autoLabel.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
            <Select label={t('autoLabel.journal')} value={form.journal_code} onChange={e => setForm({ ...form, journal_code: e.target.value })}
              options={[{ value: '', label: tCommon('common.all') }, ...journals.map(j => ({ value: j.code, label: `${j.code} - ${j.name}` }))]} />
            <Input label={t('autoLabel.accountCode')} value={form.account_code} onChange={e => setForm({ ...form, account_code: e.target.value })} />
            <Input label={t('autoLabel.accountPrefix')} value={form.account_prefix} onChange={e => setForm({ ...form, account_prefix: e.target.value })} />
            <Input label={t('autoLabel.pattern')} value={form.label_pattern} onChange={e => setForm({ ...form, label_pattern: e.target.value })} />
            <Input type="number" label={t('autoLabel.priority')} value={form.priority} onChange={e => setForm({ ...form, priority: parseInt(e.target.value) || 100 })} />
          </div>
          <div className="flex gap-2">
            <Button onClick={handleSave}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : rules.length === 0 ? <EmptyState title={t('autoLabel.empty')} /> : (
        <Table headers={[t('autoLabel.colName'), t('autoLabel.colJournal'), t('autoLabel.colAccount'), t('autoLabel.colPattern'), t('autoLabel.colPriority'), t('autoLabel.colActive'), tCommon('table.actions')]}>
          {rules.map(r => (
            <TableRow key={r.id}>
              <TableCell>{r.name}</TableCell>
              <TableCell>{r.journal_code || tCommon('common.all')}</TableCell>
              <TableCell>{r.account_code || r.account_prefix || '-'}</TableCell>
              <TableCell className="font-mono text-xs">{r.label_pattern}</TableCell>
              <TableCell>{r.priority}</TableCell>
              <TableCell>{r.active ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell>
              <TableCell><div className="flex gap-1"><Button variant="secondary" size="sm" onClick={() => openEdit(r)}><Edit2 className="w-3 h-3" /></Button><Button variant="danger" size="sm" onClick={() => handleDelete(r.id)}><Trash2 className="w-3 h-3" /></Button></div></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Extourne Page (Extourne automatique) ============
export function ExtournePage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [logs, setLogs] = useState<ExtourneLog[]>([])
  const [entries, setEntries] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [selectedEntry, setSelectedEntry] = useState('')
  const [reason, setReason] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [l, e] = await Promise.all([getExtourneLogs(), getJournalEntries()])
      setLogs(l || []); setEntries((e || []).filter((x: any) => x.status === 'posted'))
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleGenerate() {
    if (!selectedEntry) { toast('error', tCommon('common.error'), t('extourne.selectEntry')); return }
    try {
      await generateExtourne(selectedEntry, reason)
      toast('success', tCommon('common.success'), t('extourne.generated'))
      setShowForm(false); setSelectedEntry(''); setReason(''); await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('extourne.title') }]} />
      <PageHeader title={t('extourne.title')} subtitle={t('extourne.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('extourne.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <Select label={t('extourne.selectEntryLabel')} value={selectedEntry} onChange={e => setSelectedEntry(e.target.value)}
            options={[{ value: '', label: tCommon('common.select') }, ...entries.map((e: any) => ({ value: e.id, label: `${e.number} - ${e.description} (${e.date})` }))]} />
          <Input label={t('extourne.reason')} value={reason} onChange={e => setReason(e.target.value)} />
          <div className="flex gap-2">
            <Button onClick={handleGenerate}><Play className="w-4 h-4" /> {t('extourne.generate')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : logs.length === 0 ? <EmptyState title={t('extourne.empty')} /> : (
        <Table headers={[t('extourne.colDate'), t('extourne.colOriginal'), t('extourne.colExtourne'), t('extourne.colJournal'), t('extourne.colDebit'), t('extourne.colCredit'), t('extourne.colReason')]}>
          {logs.map(l => (
            <TableRow key={l.id}>
              <TableCell>{formatDate(l.extourne_date)}</TableCell>
              <TableCell className="font-mono text-xs">{l.original_entry_id.slice(0, 8)}</TableCell>
              <TableCell className="font-mono text-xs">{l.extourne_entry_id.slice(0, 8)}</TableCell>
              <TableCell>{l.journal_code || '-'}</TableCell>
              <TableCell>{formatCurrency(l.total_debit)}</TableCell>
              <TableCell>{formatCurrency(l.total_credit)}</TableCell>
              <TableCell>{l.reason || '-'}</TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Carry Forward Page (Reports à-nouveaux) ============
export function CarryForwardPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [logs, setLogs] = useState<CarryForwardLog[]>([])
  const [years, setYears] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [sourceYear, setSourceYear] = useState('')
  const [targetYear, setTargetYear] = useState('')

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [l, y] = await Promise.all([getCarryForwardLogs(), getFiscalYears()])
      setLogs(l || []); setYears(y || [])
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleGenerate() {
    if (!sourceYear || !targetYear) { toast('error', tCommon('common.error'), t('carryForward.selectYears')); return }
    try {
      const result = await generateCarryForward(sourceYear, targetYear)
      if (!result) { toast('info', tCommon('common.info'), t('carryForward.noData')) }
      else { toast('success', tCommon('common.success'), t('carryForward.generated')) }
      setShowForm(false); setSourceYear(''); setTargetYear(''); await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('carryForward.title') }]} />
      <PageHeader title={t('carryForward.title')} subtitle={t('carryForward.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('carryForward.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Select label={t('carryForward.sourceYear')} value={sourceYear} onChange={e => setSourceYear(e.target.value)}
              options={[{ value: '', label: tCommon('common.select') }, ...years.map(y => ({ value: y.id, label: y.code }))]} />
            <Select label={t('carryForward.targetYear')} value={targetYear} onChange={e => setTargetYear(e.target.value)}
              options={[{ value: '', label: tCommon('common.select') }, ...years.map(y => ({ value: y.id, label: y.code }))]} />
          </div>
          <div className="flex gap-2">
            <Button onClick={handleGenerate}><Play className="w-4 h-4" /> {t('carryForward.generate')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : logs.length === 0 ? <EmptyState title={t('carryForward.empty')} /> : (
        <Table headers={[t('carryForward.colDate'), t('carryForward.colEntries'), t('carryForward.colDebit'), t('carryForward.colCredit'), t('carryForward.colStatus')]}>
          {logs.map(l => (
            <TableRow key={l.id}>
              <TableCell>{formatDate(l.carry_forward_date)}</TableCell>
              <TableCell>{l.entry_count}</TableCell>
              <TableCell>{formatCurrency(l.total_debit)}</TableCell>
              <TableCell>{formatCurrency(l.total_credit)}</TableCell>
              <TableCell><Badge variant="success">{t(`carryForward.status.${l.status}`)}</Badge></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Lettrage Differences Page (Écarts de lettrage) ============
export function LettrageDifferencesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [diffs, setDiffs] = useState<LettrageDifference[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setDiffs(await getLettrageDifferences() || []) } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
    try { await deleteLettrageDifference(id); toast('success', tCommon('common.success'), t('lettrageDiff.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('lettrageDiff.title') }]} />
      <PageHeader title={t('lettrageDiff.title')} subtitle={t('lettrageDiff.subtitle')} />
      {loading ? <SkeletonTable /> : diffs.length === 0 ? <EmptyState title={t('lettrageDiff.empty')} /> : (
        <Table headers={[t('lettrageDiff.colThirdParty'), t('lettrageDiff.colCode'), t('lettrageDiff.colDebit'), t('lettrageDiff.colCredit'), t('lettrageDiff.colDifference'), t('lettrageDiff.colAccount'), t('lettrageDiff.colStatus'), tCommon('table.actions')]}>
          {diffs.map(d => (
            <TableRow key={d.id}>
              <TableCell>{d.third_party_code}</TableCell>
              <TableCell className="font-mono">{d.lettrage_code}</TableCell>
              <TableCell>{formatCurrency(d.debit_amount)}</TableCell>
              <TableCell>{formatCurrency(d.credit_amount)}</TableCell>
              <TableCell className={d.difference > 0 ? 'text-green-600 font-semibold' : 'text-red-600 font-semibold'}>{formatCurrency(d.difference)}</TableCell>
              <TableCell>{d.difference_account || '-'}</TableCell>
              <TableCell><Badge variant={d.status === 'resolved' ? 'success' : 'warning'}>{t(`lettrageDiff.status.${d.status}`)}</Badge></TableCell>
              <TableCell><Button variant="danger" size="sm" onClick={() => handleDelete(d.id)}><Trash2 className="w-3 h-3" /></Button></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Accounting Controls Page (Contrôles comptables) ============
export function AccountingControlsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatDate } = useLocale()
  const [runs, setRuns] = useState<AccountingControlRun[]>([])
  const [loading, setLoading] = useState(true)
  const [running, setRunning] = useState(false)
  const [selectedRun, setSelectedRun] = useState<AccountingControlRun | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setRuns(await getAccountingControlRuns() || []) } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleRun() {
    setRunning(true)
    try {
      const result = await runAccountingControl('full')
      toast('success', tCommon('common.success'), t('controls.runCompleted', { errors: result.errors_found, warnings: result.warnings_found }))
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
    finally { setRunning(false) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('controls.title') }]} />
      <PageHeader title={t('controls.title')} subtitle={t('controls.subtitle')} action={<Button onClick={handleRun} loading={running}><Shield className="w-4 h-4" /> {t('controls.run')}</Button>} />
      {loading ? <SkeletonTable /> : runs.length === 0 ? <EmptyState title={t('controls.empty')} /> : (
        <Table headers={[t('controls.colDate'), t('controls.colType'), t('controls.colChecks'), t('controls.colErrors'), t('controls.colWarnings'), t('controls.colStatus'), tCommon('table.actions')]}>
          {runs.map(r => (
            <TableRow key={r.id} onClick={() => setSelectedRun(r)}>
              <TableCell>{formatDate(r.run_date)}</TableCell>
              <TableCell>{t(`controls.types.${r.control_type}`)}</TableCell>
              <TableCell>{r.total_checks}</TableCell>
              <TableCell>{r.errors_found > 0 ? <span className="text-red-600 font-semibold">{r.errors_found}</span> : r.errors_found}</TableCell>
              <TableCell>{r.warnings_found > 0 ? <span className="text-orange-600 font-semibold">{r.warnings_found}</span> : r.warnings_found}</TableCell>
              <TableCell><Badge variant="success">{t(`controls.status.${r.status}`)}</Badge></TableCell>
              <TableCell><Button variant="secondary" size="sm" onClick={() => setSelectedRun(r)}>{tCommon('common.view')}</Button></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
      {selectedRun && (
        <Card className="p-4 mt-4" title={t('controls.detailsTitle')} action={<Button variant="secondary" size="sm" onClick={() => setSelectedRun(null)}><X className="w-4 h-4" /></Button>}>
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {selectedRun.details.map((d: any, i: number) => (
              <div key={i} className={`p-3 rounded border ${d.type === 'unbalanced' || d.type === 'duplicate_piece' || d.type === 'missing_account' ? 'border-red-300 bg-red-50' : 'border-orange-300 bg-orange-50'}`}>
                <div className="flex items-center gap-2">
                  {d.type === 'unbalanced' || d.type === 'duplicate_piece' || d.type === 'missing_account' ? <XCircle className="w-4 h-4 text-red-500" /> : <AlertTriangle className="w-4 h-4 text-orange-500" />}
                  <span className="font-medium">{t(`controls.detailTypes.${d.type}`)}</span>
                </div>
                <pre className="text-xs mt-1 overflow-x-auto">{JSON.stringify(d, null, 2)}</pre>
              </div>
            ))}
            {selectedRun.details.length === 0 && <div className="text-center py-4 text-green-600"><CheckCircle className="w-8 h-8 mx-auto mb-2" />{t('controls.noIssues')}</div>}
          </div>
        </Card>
      )}
    </div>
  )
}

// ============ Cash Control Page (Contrôle de caisse) ============
export function CashControlPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [sessions, setSessions] = useState<CashControlSession[]>([])
  const [journals, setJournals] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ session_number: '', journal_code: '', session_date: new Date().toISOString().slice(0, 10), theoretical_balance: 0, counted_balance: 0, notes: '' })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [s, j] = await Promise.all([getCashControlSessions(), getJournals()])
      setSessions(s || []); setJournals((j || []).filter(x => x.type === 'cash'))
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    const diff = form.counted_balance - form.theoretical_balance
    try {
      await createCashControlSession({ ...form, difference: diff, status: 'open', details: [] } as any)
      toast('success', tCommon('common.success'), t('cashControl.created'))
      setShowForm(false); setForm({ session_number: '', journal_code: '', session_date: new Date().toISOString().slice(0, 10), theoretical_balance: 0, counted_balance: 0, notes: '' })
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleValidate(id: string) {
    try { await updateCashControlSession(id, { status: 'validated', validated_at: new Date().toISOString() }); toast('success', tCommon('common.success'), t('cashControl.validated')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteCashControlSession(id); toast('success', tCommon('common.success'), t('cashControl.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('cashControl.title') }]} />
      <PageHeader title={t('cashControl.title')} subtitle={t('cashControl.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('cashControl.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <Input label={t('cashControl.sessionNumber')} value={form.session_number} onChange={e => setForm({ ...form, session_number: e.target.value })} />
            <Select label={t('cashControl.journal')} value={form.journal_code} onChange={e => setForm({ ...form, journal_code: e.target.value })}
              options={[{ value: '', label: tCommon('common.select') }, ...journals.map(j => ({ value: j.code, label: `${j.code} - ${j.name}` }))]} />
            <Input type="date" label={t('cashControl.date')} value={form.session_date} onChange={e => setForm({ ...form, session_date: e.target.value })} />
            <Input type="number" step="0.01" label={t('cashControl.theoretical')} value={form.theoretical_balance} onChange={e => setForm({ ...form, theoretical_balance: parseFloat(e.target.value) || 0 })} />
            <Input type="number" step="0.01" label={t('cashControl.counted')} value={form.counted_balance} onChange={e => setForm({ ...form, counted_balance: parseFloat(e.target.value) || 0 })} />
            <Input label={t('cashControl.notes')} value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} />
          </div>
          <div className="text-sm font-medium">
            {t('cashControl.difference')}: <span className={form.counted_balance - form.theoretical_balance < 0 ? 'text-red-600' : 'text-green-600'}>{formatCurrency(form.counted_balance - form.theoretical_balance)}</span>
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : sessions.length === 0 ? <EmptyState title={t('cashControl.empty')} /> : (
        <Table headers={[t('cashControl.colNumber'), t('cashControl.colJournal'), t('cashControl.colDate'), t('cashControl.colTheoretical'), t('cashControl.colCounted'), t('cashControl.colDifference'), t('cashControl.colStatus'), tCommon('table.actions')]}>
          {sessions.map(s => (
            <TableRow key={s.id}>
              <TableCell>{s.session_number}</TableCell>
              <TableCell>{s.journal_code}</TableCell>
              <TableCell>{formatDate(s.session_date)}</TableCell>
              <TableCell>{formatCurrency(s.theoretical_balance)}</TableCell>
              <TableCell>{formatCurrency(s.counted_balance)}</TableCell>
              <TableCell className={s.difference < 0 ? 'text-red-600 font-semibold' : s.difference > 0 ? 'text-green-600 font-semibold' : ''}>{formatCurrency(s.difference)}</TableCell>
              <TableCell><Badge variant={s.status === 'validated' ? 'success' : 'warning'}>{t(`cashControl.status.${s.status}`)}</Badge></TableCell>
              <TableCell><div className="flex gap-1">
                {s.status === 'open' && <Button variant="secondary" size="sm" onClick={() => handleValidate(s.id)}><CheckCircle className="w-3 h-3" /></Button>}
                <Button variant="danger" size="sm" onClick={() => handleDelete(s.id)}><Trash2 className="w-3 h-3" /></Button>
              </div></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ FEC Attestation Page (Attestation FEC) ============
export function FECAttestationPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [attestations, setAttestations] = useState<FECAttestation[]>([])
  const [years, setYears] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ fiscal_year_id: '', fec_type: 'definitive' })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [a, y] = await Promise.all([getFECAttestations(), getFiscalYears()])
      setAttestations(a || []); setYears(y || [])
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try {
      const year = years.find(y => y.id === form.fiscal_year_id)
      const attNumber = `FEC-ATT-${Date.now()}`
      await createFECAttestation({
        fiscal_year_id: form.fiscal_year_id,
        attestation_number: attNumber,
        attestation_date: new Date().toISOString().slice(0, 10),
        fec_type: form.fec_type,
        entry_count: 0,
        total_debit: 0,
        total_credit: 0,
        file_name: `${attNumber}.txt`,
        file_content: `ATTESTATION FEC\nExercice: ${year?.code}\nDate: ${new Date().toISOString().slice(0, 10)}\nType: ${form.fec_type}`,
        status: 'generated',
        generated_by: '',
      } as any)
      toast('success', tCommon('common.success'), t('fecAttest.created'))
      setShowForm(false); await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteFECAttestation(id); toast('success', tCommon('common.success'), t('fecAttest.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  function handleDownload(a: FECAttestation) {
    if (!a.file_content) return
    const blob = new Blob([a.file_content], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url; link.download = a.file_name || `attestation-${a.attestation_number}.txt`
    link.click(); URL.revokeObjectURL(url)
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('fecAttest.title') }]} />
      <PageHeader title={t('fecAttest.title')} subtitle={t('fecAttest.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('fecAttest.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Select label={t('fecAttest.fiscalYear')} value={form.fiscal_year_id} onChange={e => setForm({ ...form, fiscal_year_id: e.target.value })}
              options={[{ value: '', label: tCommon('common.select') }, ...years.map(y => ({ value: y.id, label: y.code }))]} />
            <Select label={t('fecAttest.type')} value={form.fec_type} onChange={e => setForm({ ...form, fec_type: e.target.value })}
              options={[{ value: 'definitive', label: t('fecAttest.types.definitive') }, { value: 'provisional', label: t('fecAttest.types.provisional') }]} />
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : attestations.length === 0 ? <EmptyState title={t('fecAttest.empty')} /> : (
        <Table headers={[t('fecAttest.colNumber'), t('fecAttest.colDate'), t('fecAttest.colType'), t('fecAttest.colEntries'), t('fecAttest.colDebit'), t('fecAttest.colCredit'), tCommon('table.actions')]}>
          {attestations.map(a => (
            <TableRow key={a.id}>
              <TableCell className="font-mono">{a.attestation_number}</TableCell>
              <TableCell>{formatDate(a.attestation_date)}</TableCell>
              <TableCell><Badge>{t(`fecAttest.types.${a.fec_type}`)}</Badge></TableCell>
              <TableCell>{a.entry_count}</TableCell>
              <TableCell>{formatCurrency(a.total_debit)}</TableCell>
              <TableCell>{formatCurrency(a.total_credit)}</TableCell>
              <TableCell><div className="flex gap-1">
                <Button variant="secondary" size="sm" onClick={() => handleDownload(a)}><Download className="w-3 h-3" /></Button>
                <Button variant="danger" size="sm" onClick={() => handleDelete(a.id)}><Trash2 className="w-3 h-3" /></Button>
              </div></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Tier RIBs Page (Multi-RIB par tiers) ============
export function TierRIBsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [ribs, setRibs] = useState<TierRIB[]>([])
  const [thirdParties, setThirdParties] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<TierRIB | null>(null)
  const [form, setForm] = useState({ third_party_account_id: '', rib_label: '', iban: '', bic: '', bank_name: '', is_default: false, active: true })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [r, tp] = await Promise.all([getTierRIBs(), getThirdPartyAccounts()])
      setRibs(r || []); setThirdParties(tp || [])
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  function openCreate() { setEditing(null); setForm({ third_party_account_id: '', rib_label: '', iban: '', bic: '', bank_name: '', is_default: false, active: true }); setShowForm(true) }
  function openEdit(r: TierRIB) { setEditing(r); setForm({ third_party_account_id: r.third_party_account_id, rib_label: r.rib_label, iban: r.iban, bic: r.bic || '', bank_name: r.bank_name || '', is_default: r.is_default, active: r.active }); setShowForm(true) }

  async function handleSave() {
    try {
      if (editing) { await updateTierRIB(editing.id, form); toast('success', tCommon('common.success'), t('tierRIB.updated')) }
      else { await createTierRIB(form as any); toast('success', tCommon('common.success'), t('tierRIB.created')) }
      setShowForm(false); await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteTierRIB(id); toast('success', tCommon('common.success'), t('tierRIB.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  const tpMap = new Map(thirdParties.map(tp => [tp.id, tp]))
  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('tierRIB.title') }]} />
      <PageHeader title={t('tierRIB.title')} subtitle={t('tierRIB.subtitle')} action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('tierRIB.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Select label={t('tierRIB.thirdParty')} value={form.third_party_account_id} onChange={e => setForm({ ...form, third_party_account_id: e.target.value })}
              options={[{ value: '', label: tCommon('common.select') }, ...thirdParties.map(tp => ({ value: tp.id, label: `${tp.account_code} - ${tp.name || tp.account_name || ''}` }))]} />
            <Input label={t('tierRIB.label')} value={form.rib_label} onChange={e => setForm({ ...form, rib_label: e.target.value })} />
            <Input label={t('tierRIB.iban')} value={form.iban} onChange={e => setForm({ ...form, iban: e.target.value })} />
            <Input label={t('tierRIB.bic')} value={form.bic} onChange={e => setForm({ ...form, bic: e.target.value })} />
            <Input label={t('tierRIB.bankName')} value={form.bank_name} onChange={e => setForm({ ...form, bank_name: e.target.value })} />
            <div className="flex items-center gap-4 pt-6">
              <label className="flex items-center gap-2"><input type="checkbox" checked={form.is_default} onChange={e => setForm({ ...form, is_default: e.target.checked })} /> {t('tierRIB.isDefault')}</label>
              <label className="flex items-center gap-2"><input type="checkbox" checked={form.active} onChange={e => setForm({ ...form, active: e.target.checked })} /> {t('tierRIB.active')}</label>
            </div>
          </div>
          <div className="flex gap-2">
            <Button onClick={handleSave}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : ribs.length === 0 ? <EmptyState title={t('tierRIB.empty')} /> : (
        <Table headers={[t('tierRIB.colThirdParty'), t('tierRIB.colLabel'), t('tierRIB.colIBAN'), t('tierRIB.colBIC'), t('tierRIB.colBank'), t('tierRIB.colDefault'), tCommon('table.actions')]}>
          {ribs.map(r => (
            <TableRow key={r.id}>
              <TableCell>{tpMap.get(r.third_party_account_id)?.account_code || r.third_party_account_id.slice(0, 8)}</TableCell>
              <TableCell>{r.rib_label}</TableCell>
              <TableCell className="font-mono text-xs">{r.iban}</TableCell>
              <TableCell className="font-mono text-xs">{r.bic || '-'}</TableCell>
              <TableCell>{r.bank_name || '-'}</TableCell>
              <TableCell>{r.is_default ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell>
              <TableCell><div className="flex gap-1"><Button variant="secondary" size="sm" onClick={() => openEdit(r)}><Edit2 className="w-3 h-3" /></Button><Button variant="danger" size="sm" onClick={() => handleDelete(r.id)}><Trash2 className="w-3 h-3" /></Button></div></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ IFRS Adjustments Page (IAS/IFRS) ============
export function IFRSAdjustmentsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [items, setItems] = useState<IFRSAdjustment[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ adjustment_type: 'provision', account_code: '', counter_account_code: '', description: '', amount: 0, adjustment_date: new Date().toISOString().slice(0, 10), ifrs_standard: '' })

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setItems(await getIFRSAdjustments() || []) } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try {
      await createIFRSAdjustment({ ...form, status: 'draft' } as any)
      toast('success', tCommon('common.success'), t('ifrsAdjustments.created'))
      setShowForm(false); setForm({ adjustment_type: 'provision', account_code: '', counter_account_code: '', description: '', amount: 0, adjustment_date: new Date().toISOString().slice(0, 10), ifrs_standard: '' })
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteIFRSAdjustment(id); toast('success', tCommon('common.success'), t('ifrsAdjustments.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('ifrsAdjustments.title') }]} />
      <PageHeader title={t('ifrsAdjustments.title')} subtitle={t('ifrsAdjustments.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('ifrsAdjustments.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Select label={t('ifrsAdjustments.type')} value={form.adjustment_type} onChange={e => setForm({ ...form, adjustment_type: e.target.value })}
              options={[{ value: 'provision', label: t('ifrsAdjustments.types.provision') }, { value: 'revaluation', label: t('ifrsAdjustments.types.revaluation') }, { value: 'impairment', label: t('ifrsAdjustments.types.impairment') }, { value: 'derecognition', label: t('ifrsAdjustments.types.derecognition') }, { value: 'fair_value', label: t('ifrsAdjustments.types.fair_value') }]} />
            <Input label={t('ifrsAdjustments.standard')} value={form.ifrs_standard} onChange={e => setForm({ ...form, ifrs_standard: e.target.value })} placeholder="IAS 36, IFRS 9..." />
            <Input label={t('ifrsAdjustments.account')} value={form.account_code} onChange={e => setForm({ ...form, account_code: e.target.value })} />
            <Input label={t('ifrsAdjustments.counterAccount')} value={form.counter_account_code} onChange={e => setForm({ ...form, counter_account_code: e.target.value })} />
            <Input type="number" step="0.01" label={t('ifrsAdjustments.amount')} value={form.amount} onChange={e => setForm({ ...form, amount: parseFloat(e.target.value) || 0 })} />
            <Input type="date" label={t('ifrsAdjustments.date')} value={form.adjustment_date} onChange={e => setForm({ ...form, adjustment_date: e.target.value })} />
            <div className="col-span-2"><Input label={t('ifrsAdjustments.description')} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></div>
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('ifrsAdjustments.empty')} /> : (
        <Table headers={[t('ifrsAdjustments.colDate'), t('ifrsAdjustments.colType'), t('ifrsAdjustments.colAccount'), t('ifrsAdjustments.colCounter'), t('ifrsAdjustments.colAmount'), t('ifrsAdjustments.colStandard'), t('ifrsAdjustments.colStatus'), tCommon('table.actions')]}>
          {items.map(i => (
            <TableRow key={i.id}>
              <TableCell>{formatDate(i.adjustment_date)}</TableCell>
              <TableCell>{t(`ifrsAdjustments.types.${i.adjustment_type}`)}</TableCell>
              <TableCell className="font-mono">{i.account_code}</TableCell>
              <TableCell className="font-mono">{i.counter_account_code}</TableCell>
              <TableCell>{formatCurrency(i.amount)}</TableCell>
              <TableCell>{i.ifrs_standard || '-'}</TableCell>
              <TableCell><Badge variant={i.status === 'posted' ? 'success' : 'warning'}>{t(`ifrsAdjustments.status.${i.status}`)}</Badge></TableCell>
              <TableCell><Button variant="danger" size="sm" onClick={() => handleDelete(i.id)}><Trash2 className="w-3 h-3" /></Button></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Tax Payments Page (Télépaiements) ============
export function TaxPaymentsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency, formatDate } = useLocale()
  const [items, setItems] = useState<TaxPayment[]>([])
  const [bankAccounts, setBankAccounts] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ payment_number: '', tax_type: 'TVA', period_label: '', period_start: '', period_end: '', amount: 0, payment_date: new Date().toISOString().slice(0, 10), payment_method: 'telepayment', bank_account_id: '' })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [p, b] = await Promise.all([getTaxPayments(), getBankAccounts()])
      setItems(p || []); setBankAccounts(b || [])
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try {
      await createTaxPayment({ ...form, bank_account_id: form.bank_account_id || null, status: 'draft', confirmation_number: null, journal_entry_id: null } as any)
      toast('success', tCommon('common.success'), t('taxPayment.created'))
      setShowForm(false); setForm({ payment_number: '', tax_type: 'TVA', period_label: '', period_start: '', period_end: '', amount: 0, payment_date: new Date().toISOString().slice(0, 10), payment_method: 'telepayment', bank_account_id: '' })
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleConfirm(id: string) {
    try {
      const conf = `CONF-${Date.now()}`
      await updateTaxPayment(id, { status: 'confirmed', confirmation_number: conf })
      toast('success', tCommon('common.success'), t('taxPayment.confirmed', { num: conf }))
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteTaxPayment(id); toast('success', tCommon('common.success'), t('taxPayment.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('taxPayment.title') }]} />
      <PageHeader title={t('taxPayment.title')} subtitle={t('taxPayment.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('taxPayment.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <Input label={t('taxPayment.number')} value={form.payment_number} onChange={e => setForm({ ...form, payment_number: e.target.value })} />
            <Select label={t('taxPayment.taxType')} value={form.tax_type} onChange={e => setForm({ ...form, tax_type: e.target.value })}
              options={[{ value: 'TVA', label: 'TVA' }, { value: 'IS', label: 'IS' }, { value: 'CFE', label: 'CFE' }, { value: 'CVAE', label: 'CVAE' }, { value: 'TVS', label: 'TVS' }]} />
            <Input label={t('taxPayment.periodLabel')} value={form.period_label} onChange={e => setForm({ ...form, period_label: e.target.value })} />
            <Input type="date" label={t('taxPayment.periodStart')} value={form.period_start} onChange={e => setForm({ ...form, period_start: e.target.value })} />
            <Input type="date" label={t('taxPayment.periodEnd')} value={form.period_end} onChange={e => setForm({ ...form, period_end: e.target.value })} />
            <Input type="number" step="0.01" label={t('taxPayment.amount')} value={form.amount} onChange={e => setForm({ ...form, amount: parseFloat(e.target.value) || 0 })} />
            <Input type="date" label={t('taxPayment.paymentDate')} value={form.payment_date} onChange={e => setForm({ ...form, payment_date: e.target.value })} />
            <Select label={t('taxPayment.method')} value={form.payment_method} onChange={e => setForm({ ...form, payment_method: e.target.value })}
              options={[{ value: 'telepayment', label: t('taxPayment.methods.telepayment') }, { value: 'bank_transfer', label: t('taxPayment.methods.bank_transfer') }, { value: 'check', label: t('taxPayment.methods.check') }]} />
            <Select label={t('taxPayment.bankAccount')} value={form.bank_account_id} onChange={e => setForm({ ...form, bank_account_id: e.target.value })}
              options={[{ value: '', label: tCommon('common.select') }, ...bankAccounts.map(b => ({ value: b.id, label: b.name }))]} />
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('taxPayment.empty')} /> : (
        <Table headers={[t('taxPayment.colNumber'), t('taxPayment.colType'), t('taxPayment.colPeriod'), t('taxPayment.colAmount'), t('taxPayment.colDate'), t('taxPayment.colMethod'), t('taxPayment.colStatus'), t('taxPayment.colConfirmation'), tCommon('table.actions')]}>
          {items.map(p => (
            <TableRow key={p.id}>
              <TableCell className="font-mono">{p.payment_number}</TableCell>
              <TableCell><Badge>{p.tax_type}</Badge></TableCell>
              <TableCell>{p.period_label}</TableCell>
              <TableCell>{formatCurrency(p.amount)}</TableCell>
              <TableCell>{formatDate(p.payment_date)}</TableCell>
              <TableCell>{t(`taxPayment.methods.${p.payment_method}`)}</TableCell>
              <TableCell><Badge variant={p.status === 'confirmed' ? 'success' : 'warning'}>{t(`taxPayment.status.${p.status}`)}</Badge></TableCell>
              <TableCell className="font-mono text-xs">{p.confirmation_number || '-'}</TableCell>
              <TableCell><div className="flex gap-1">
                {p.status === 'draft' && <Button variant="secondary" size="sm" onClick={() => handleConfirm(p.id)}><CheckCircle className="w-3 h-3" /></Button>}
                <Button variant="danger" size="sm" onClick={() => handleDelete(p.id)}><Trash2 className="w-3 h-3" /></Button>
              </div></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Custom Report Templates Page (Modèles d'édition personnalisés) ============
export function CustomReportTemplatesPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<CustomReportTemplate[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<CustomReportTemplate | null>(null)
  const [form, setForm] = useState({ name: '', description: '', report_type: 'trial_balance', category: 'accounting', page_orientation: 'portrait', page_size: 'A4', header_text: '', footer_text: '', show_logo: true, show_date: true, show_page_numbers: true, active: true })

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setItems(await getCustomReportTemplates() || []) } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  function openCreate() { setEditing(null); setForm({ name: '', description: '', report_type: 'trial_balance', category: 'accounting', page_orientation: 'portrait', page_size: 'A4', header_text: '', footer_text: '', show_logo: true, show_date: true, show_page_numbers: true, active: true }); setShowForm(true) }
  function openEdit(r: CustomReportTemplate) { setEditing(r); setForm({ name: r.name, description: r.description || '', report_type: r.report_type, category: r.category, page_orientation: r.page_orientation, page_size: r.page_size, header_text: r.header_text || '', footer_text: r.footer_text || '', show_logo: r.show_logo, show_date: r.show_date, show_page_numbers: r.show_page_numbers, active: r.active }); setShowForm(true) }

  async function handleSave() {
    try {
      const payload = { ...form, columns: [], filters: {}, group_by: null, sort_by: null, sort_order: 'asc' }
      if (editing) { await updateCustomReportTemplate(editing.id, payload); toast('success', tCommon('common.success'), t('customReport.updated')) }
      else { await createCustomReportTemplate(payload as any); toast('success', tCommon('common.success'), t('customReport.created')) }
      setShowForm(false); await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteCustomReportTemplate(id); toast('success', tCommon('common.success'), t('customReport.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('customReport.title') }]} />
      <PageHeader title={t('customReport.title')} subtitle={t('customReport.subtitle')} action={<Button onClick={openCreate}><Plus className="w-4 h-4" /> {t('customReport.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('customReport.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
            <Select label={t('customReport.type')} value={form.report_type} onChange={e => setForm({ ...form, report_type: e.target.value })}
              options={[{ value: 'trial_balance', label: t('customReport.types.trial_balance') }, { value: 'general_ledger', label: t('customReport.types.general_ledger') }, { value: 'balance_sheet', label: t('customReport.types.balance_sheet') }, { value: 'profit_loss', label: t('customReport.types.profit_loss') }, { value: 'aged_balance', label: t('customReport.types.aged_balance') }, { value: 'journals', label: t('customReport.types.journals') }]} />
            <Select label={t('customReport.orientation')} value={form.page_orientation} onChange={e => setForm({ ...form, page_orientation: e.target.value })}
              options={[{ value: 'portrait', label: t('customReport.orientations.portrait') }, { value: 'landscape', label: t('customReport.orientations.landscape') }]} />
            <Select label={t('customReport.pageSize')} value={form.page_size} onChange={e => setForm({ ...form, page_size: e.target.value })}
              options={[{ value: 'A4', label: 'A4' }, { value: 'A3', label: 'A3' }, { value: 'Letter', label: 'Letter' }]} />
            <Input label={t('customReport.header')} value={form.header_text} onChange={e => setForm({ ...form, header_text: e.target.value })} />
            <Input label={t('customReport.footer')} value={form.footer_text} onChange={e => setForm({ ...form, footer_text: e.target.value })} />
          </div>
          <div className="flex gap-4">
            <label className="flex items-center gap-2"><input type="checkbox" checked={form.show_logo} onChange={e => setForm({ ...form, show_logo: e.target.checked })} /> {t('customReport.showLogo')}</label>
            <label className="flex items-center gap-2"><input type="checkbox" checked={form.show_date} onChange={e => setForm({ ...form, show_date: e.target.checked })} /> {t('customReport.showDate')}</label>
            <label className="flex items-center gap-2"><input type="checkbox" checked={form.show_page_numbers} onChange={e => setForm({ ...form, show_page_numbers: e.target.checked })} /> {t('customReport.showPageNumbers')}</label>
          </div>
          <div className="flex gap-2">
            <Button onClick={handleSave}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('customReport.empty')} /> : (
        <Table headers={[t('customReport.colName'), t('customReport.colType'), t('customReport.colCategory'), t('customReport.colOrientation'), t('customReport.colPageSize'), t('customReport.colActive'), tCommon('table.actions')]}>
          {items.map(r => (
            <TableRow key={r.id}>
              <TableCell>{r.name}</TableCell>
              <TableCell>{t(`customReport.types.${r.report_type}`)}</TableCell>
              <TableCell>{r.category}</TableCell>
              <TableCell>{t(`customReport.orientations.${r.page_orientation}`)}</TableCell>
              <TableCell>{r.page_size}</TableCell>
              <TableCell>{r.active ? <Badge variant="success">{tCommon('common.yes')}</Badge> : <Badge>{tCommon('common.no')}</Badge>}</TableCell>
              <TableCell><div className="flex gap-1"><Button variant="secondary" size="sm" onClick={() => openEdit(r)}><Edit2 className="w-3 h-3" /></Button><Button variant="danger" size="sm" onClick={() => handleDelete(r.id)}><Trash2 className="w-3 h-3" /></Button></div></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Deferred Printing Page (Impressions différées) ============
export function DeferredPrintingPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatDate } = useLocale()
  const [items, setItems] = useState<DeferredPrintingJob[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ job_name: '', report_type: 'trial_balance', scheduled_date: '', output_format: 'pdf' })

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setItems(await getDeferredPrintingJobs() || []) } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try {
      await createDeferredPrintingJob({ ...form, parameters: {}, status: 'pending', output_data: null, generated_at: null, generated_by: null, error_message: null } as any)
      toast('success', tCommon('common.success'), t('deferredPrint.created'))
      setShowForm(false); setForm({ job_name: '', report_type: 'trial_balance', scheduled_date: '', output_format: 'pdf' })
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteDeferredPrintingJob(id); toast('success', tCommon('common.success'), t('deferredPrint.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('deferredPrint.title') }]} />
      <PageHeader title={t('deferredPrint.title')} subtitle={t('deferredPrint.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('deferredPrint.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('deferredPrint.jobName')} value={form.job_name} onChange={e => setForm({ ...form, job_name: e.target.value })} />
            <Select label={t('deferredPrint.reportType')} value={form.report_type} onChange={e => setForm({ ...form, report_type: e.target.value })}
              options={[{ value: 'trial_balance', label: t('customReport.types.trial_balance') }, { value: 'general_ledger', label: t('customReport.types.general_ledger') }, { value: 'balance_sheet', label: t('customReport.types.balance_sheet') }, { value: 'profit_loss', label: t('customReport.types.profit_loss') }, { value: 'aged_balance', label: t('customReport.types.aged_balance') }]} />
            <Input type="datetime-local" label={t('deferredPrint.scheduledDate')} value={form.scheduled_date} onChange={e => setForm({ ...form, scheduled_date: e.target.value })} />
            <Select label={t('deferredPrint.format')} value={form.output_format} onChange={e => setForm({ ...form, output_format: e.target.value })}
              options={[{ value: 'pdf', label: 'PDF' }, { value: 'csv', label: 'CSV' }, { value: 'xlsx', label: 'Excel' }]} />
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}><Printer className="w-4 h-4" /> {tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('deferredPrint.empty')} /> : (
        <Table headers={[t('deferredPrint.colName'), t('deferredPrint.colType'), t('deferredPrint.colScheduled'), t('deferredPrint.colFormat'), t('deferredPrint.colStatus'), t('deferredPrint.colGenerated'), tCommon('table.actions')]}>
          {items.map(j => (
            <TableRow key={j.id}>
              <TableCell>{j.job_name}</TableCell>
              <TableCell>{j.report_type}</TableCell>
              <TableCell>{formatDate(j.scheduled_date)}</TableCell>
              <TableCell><Badge>{j.output_format.toUpperCase()}</Badge></TableCell>
              <TableCell><Badge variant={j.status === 'completed' ? 'success' : j.status === 'error' ? 'danger' : 'warning'}>{t(`deferredPrint.status.${j.status}`)}</Badge></TableCell>
              <TableCell>{j.generated_at ? formatDate(j.generated_at) : '-'}</TableCell>
              <TableCell><Button variant="danger" size="sm" onClick={() => handleDelete(j.id)}><Trash2 className="w-3 h-3" /></Button></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ Journal Access Rights Page (Protection journaux par droits) ============
export function JournalAccessRightsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [items, setItems] = useState<any[]>([])
  const [journals, setJournals] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ user_id: '', journal_code: '', can_view: true, can_create: false, can_edit: false, can_delete: false, can_close: false })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [r, j] = await Promise.all([getJournalAccessRights(), getJournals()])
      setItems(r || []); setJournals(j || [])
    } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try {
      await createJournalAccessRight(form as any)
      toast('success', tCommon('common.success'), t('journalAccessRights.created'))
      setShowForm(false); setForm({ user_id: '', journal_code: '', can_view: true, can_create: false, can_edit: false, can_delete: false, can_close: false })
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteJournalAccessRight(id); toast('success', tCommon('common.success'), t('journalAccessRights.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('journalAccessRights.title') }]} />
      <PageHeader title={t('journalAccessRights.title')} subtitle={t('journalAccessRights.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('journalAccessRights.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Input label={t('journalAccessRights.userId')} value={form.user_id} onChange={e => setForm({ ...form, user_id: e.target.value })} placeholder="UUID" />
            <Select label={t('journalAccessRights.journal')} value={form.journal_code} onChange={e => setForm({ ...form, journal_code: e.target.value })}
              options={[{ value: '', label: tCommon('common.select') }, ...journals.map(j => ({ value: j.code, label: `${j.code} - ${j.name}` }))]} />
          </div>
          <div className="flex flex-wrap gap-4">
            <label className="flex items-center gap-2"><input type="checkbox" checked={form.can_view} onChange={e => setForm({ ...form, can_view: e.target.checked })} /> {t('journalAccessRights.canView')}</label>
            <label className="flex items-center gap-2"><input type="checkbox" checked={form.can_create} onChange={e => setForm({ ...form, can_create: e.target.checked })} /> {t('journalAccessRights.canCreate')}</label>
            <label className="flex items-center gap-2"><input type="checkbox" checked={form.can_edit} onChange={e => setForm({ ...form, can_edit: e.target.checked })} /> {t('journalAccessRights.canEdit')}</label>
            <label className="flex items-center gap-2"><input type="checkbox" checked={form.can_delete} onChange={e => setForm({ ...form, can_delete: e.target.checked })} /> {t('journalAccessRights.canDelete')}</label>
            <label className="flex items-center gap-2"><input type="checkbox" checked={form.can_close} onChange={e => setForm({ ...form, can_close: e.target.checked })} /> {t('journalAccessRights.canClose')}</label>
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('journalAccessRights.empty')} /> : (
        <Table headers={[t('journalAccessRights.colUser'), t('journalAccessRights.colJournal'), t('journalAccessRights.colView'), t('journalAccessRights.colCreate'), t('journalAccessRights.colEdit'), t('journalAccessRights.colDelete'), t('journalAccessRights.colClose'), tCommon('table.actions')]}>
          {items.map(r => (
            <TableRow key={r.id}>
              <TableCell className="font-mono text-xs">{r.tenant_users?.email || r.user_id.slice(0, 8)}</TableCell>
              <TableCell>{r.journal_code}</TableCell>
              <TableCell>{r.can_view ? '✓' : '✗'}</TableCell>
              <TableCell>{r.can_create ? '✓' : '✗'}</TableCell>
              <TableCell>{r.can_edit ? '✓' : '✗'}</TableCell>
              <TableCell>{r.can_delete ? '✓' : '✗'}</TableCell>
              <TableCell>{r.can_close ? '✓' : '✗'}</TableCell>
              <TableCell><Button variant="danger" size="sm" onClick={() => handleDelete(r.id)}><Trash2 className="w-3 h-3" /></Button></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}

// ============ VAT on Collections Page (TVA sur encaissements) ============
export function VATOnCollectionsPage() {
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<VATOnCollection[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ period_label: '', period_start: '', period_end: '', vat_base: 0, vat_rate: 20, vat_amount: 0, collected_amount: 0, uncollected_amount: 0, vat_collected: 0, vat_uncollected: 0 })

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setItems(await getVATOnCollections() || []) } catch (e) { console.error("loadData failed:", e) } finally { setLoading(false) }
  }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() {
    try {
      await createVATOnCollection({ ...form, status: 'draft', journal_entry_id: null } as any)
      toast('success', tCommon('common.success'), t('vatCollection.created'))
      setShowForm(false); setForm({ period_label: '', period_start: '', period_end: '', vat_base: 0, vat_rate: 20, vat_amount: 0, collected_amount: 0, uncollected_amount: 0, vat_collected: 0, vat_uncollected: 0 })
      await loadData()
    } catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  async function handleDelete(id: string) {
    try { await deleteVATOnCollection(id); toast('success', tCommon('common.success'), t('vatCollection.deleted')); await loadData() }
    catch (e: any) { toast('error', tCommon('common.error'), e.message) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('home.breadcrumb'), path: '/accounting' }, { label: t('vatCollection.title') }]} />
      <PageHeader title={t('vatCollection.title')} subtitle={t('vatCollection.subtitle')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('vatCollection.new')}</Button>} />
      {showForm && (
        <Card className="p-4 mb-4 space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <Input label={t('vatCollection.periodLabel')} value={form.period_label} onChange={e => setForm({ ...form, period_label: e.target.value })} />
            <Input type="date" label={t('vatCollection.periodStart')} value={form.period_start} onChange={e => setForm({ ...form, period_start: e.target.value })} />
            <Input type="date" label={t('vatCollection.periodEnd')} value={form.period_end} onChange={e => setForm({ ...form, period_end: e.target.value })} />
            <Input type="number" step="0.01" label={t('vatCollection.vatBase')} value={form.vat_base} onChange={e => setForm({ ...form, vat_base: parseFloat(e.target.value) || 0 })} />
            <Input type="number" step="0.01" label={t('vatCollection.vatRate')} value={form.vat_rate} onChange={e => setForm({ ...form, vat_rate: parseFloat(e.target.value) || 0 })} />
            <Input type="number" step="0.01" label={t('vatCollection.vatAmount')} value={form.vat_amount} onChange={e => setForm({ ...form, vat_amount: parseFloat(e.target.value) || 0 })} />
            <Input type="number" step="0.01" label={t('vatCollection.collected')} value={form.collected_amount} onChange={e => setForm({ ...form, collected_amount: parseFloat(e.target.value) || 0 })} />
            <Input type="number" step="0.01" label={t('vatCollection.uncollected')} value={form.uncollected_amount} onChange={e => setForm({ ...form, uncollected_amount: parseFloat(e.target.value) || 0 })} />
            <Input type="number" step="0.01" label={t('vatCollection.vatCollected')} value={form.vat_collected} onChange={e => setForm({ ...form, vat_collected: parseFloat(e.target.value) || 0 })} />
          </div>
          <div className="flex gap-2">
            <Button onClick={handleCreate}>{tCommon('actions.save')}</Button>
            <Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button>
          </div>
        </Card>
      )}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('vatCollection.empty')} /> : (
        <Table headers={[t('vatCollection.colPeriod'), t('vatCollection.colBase'), t('vatCollection.colRate'), t('vatCollection.colVATAmount'), t('vatCollection.colCollected'), t('vatCollection.colUncollected'), t('vatCollection.colStatus'), tCommon('table.actions')]}>
          {items.map(v => (
            <TableRow key={v.id}>
              <TableCell>{v.period_label}</TableCell>
              <TableCell>{formatCurrency(v.vat_base)}</TableCell>
              <TableCell>{v.vat_rate}%</TableCell>
              <TableCell>{formatCurrency(v.vat_amount)}</TableCell>
              <TableCell>{formatCurrency(v.vat_collected)}</TableCell>
              <TableCell>{formatCurrency(v.vat_uncollected)}</TableCell>
              <TableCell><Badge variant={v.status === 'filed' ? 'success' : 'warning'}>{t(`vatCollection.status.${v.status}`)}</Badge></TableCell>
              <TableCell><Button variant="danger" size="sm" onClick={() => handleDelete(v.id)}><Trash2 className="w-3 h-3" /></Button></TableCell>
            </TableRow>
          ))}
        </Table>
      )}
    </div>
  )
}
