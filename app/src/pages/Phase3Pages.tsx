import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { useToast } from '@/lib/toast'
import { useLocale } from '@/hooks/useLocale'
import { Plus, Trash2 } from 'lucide-react'
import {
  getFutureAccountingMovements, createFutureAccountingMovement, updateFutureAccountingMovement, deleteFutureAccountingMovement,
  getTreasuryTransfers, createTreasuryTransfer, updateTreasuryTransfer, deleteTreasuryTransfer,
  getCreditLines, createCreditLine, deleteCreditLine,
  getInvestments, createInvestment, deleteInvestment,
  getValueDateTrackings,
  getTreasuryRecurring, createTreasuryRecurring, deleteTreasuryRecurring,
  getConsolidatedTreasury,
} from '@/lib/queries'

// ============ MCF Page ============
export function MCFPage() {
  const { t } = useTranslation('treasury')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ description: '', account_code: '', amount: 0, movement_type: 'debit' as const, expected_date: '', source_type: 'manual' as const })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getFutureAccountingMovements() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createFutureAccountingMovement(form as any); toast('success', tCommon('common.success'), t('mcf.created')); setShowForm(false); setForm({ description: '', account_code: '', amount: 0, movement_type: 'debit', expected_date: '', source_type: 'manual' }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleIncorporate(id: string) { try { await updateFutureAccountingMovement(id, { incorporated: true }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteFutureAccountingMovement(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('mcf.breadcrumb1'), path: '/treasury' }, { label: t('mcf.title') }]} />
      <PageHeader title={t('mcf.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('mcf.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('mcf.description')} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /><Input placeholder={t('mcf.accountCode')} value={form.account_code} onChange={e => setForm({ ...form, account_code: e.target.value })} /><Input type="number" placeholder={t('mcf.amount')} value={form.amount} onChange={e => setForm({ ...form, amount: parseFloat(e.target.value) || 0 })} /><select className="border rounded px-3 py-2" value={form.movement_type} onChange={e => setForm({ ...form, movement_type: e.target.value as any })}><option value="debit">{t('mcf.debit')}</option><option value="credit">{t('mcf.credit')}</option></select><Input type="date" value={form.expected_date} onChange={e => setForm({ ...form, expected_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('mcf.empty')} /> : (
        <Table headers={[t('mcf.description'), t('mcf.accountCode'), t('mcf.amount'), t('mcf.type'), t('mcf.expectedDate'), t('mcf.status'), tCommon('common.actions')]}>
          {items.map(m => (<TableRow key={m.id}><TableCell>{m.description}</TableCell><TableCell>{m.account_code}</TableCell><TableCell>{formatCurrency(m.amount)}</TableCell><TableCell><Badge>{t(`mcf.types.${m.movement_type}`)}</Badge></TableCell><TableCell>{m.expected_date}</TableCell><TableCell>{m.incorporated ? <Badge>{t('mcf.incorporated')}</Badge> : <Badge>{t('mcf.pending')}</Badge>}</TableCell><TableCell><div className="flex gap-1">{!m.incorporated && <Button size="sm" variant="secondary" onClick={() => handleIncorporate(m.id)}>{t('mcf.incorporate')}</Button>}<Button size="sm" variant="danger" onClick={() => handleDelete(m.id)}><Trash2 className="w-4 h-4" /></Button></div></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Treasury Transfers Page ============
export function TreasuryTransfersPage() {
  const { t } = useTranslation('treasury')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ number: '', from_account_id: '', to_account_id: '', amount: 0, transfer_date: '', value_date: '', notes: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getTreasuryTransfers() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createTreasuryTransfer(form as any); toast('success', tCommon('common.success'), t('transfers.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleExecute(id: string) { try { await updateTreasuryTransfer(id, { status: 'executed' }); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteTreasuryTransfer(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('transfers.breadcrumb1'), path: '/treasury' }, { label: t('transfers.title') }]} />
      <PageHeader title={t('transfers.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('transfers.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('transfers.number')} value={form.number} onChange={e => setForm({ ...form, number: e.target.value })} /><Input placeholder={t('transfers.fromAccount')} value={form.from_account_id} onChange={e => setForm({ ...form, from_account_id: e.target.value })} /><Input placeholder={t('transfers.toAccount')} value={form.to_account_id} onChange={e => setForm({ ...form, to_account_id: e.target.value })} /><Input type="number" placeholder={t('transfers.amount')} value={form.amount} onChange={e => setForm({ ...form, amount: parseFloat(e.target.value) || 0 })} /><Input type="date" value={form.transfer_date} onChange={e => setForm({ ...form, transfer_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('transfers.empty')} /> : (
        <Table headers={[t('transfers.number'), t('transfers.from'), t('transfers.to'), t('transfers.amount'), t('transfers.date'), t('transfers.status'), tCommon('common.actions')]}>
          {items.map(tr => (<TableRow key={tr.id}><TableCell>{tr.number}</TableCell><TableCell>{tr.ba1?.name || '-'}</TableCell><TableCell>{tr.ba2?.name || '-'}</TableCell><TableCell>{formatCurrency(tr.amount)}</TableCell><TableCell>{tr.transfer_date}</TableCell><TableCell><Badge>{t(`transfers.statuses.${tr.status}`)}</Badge></TableCell><TableCell><div className="flex gap-1">{tr.status === 'draft' && <Button size="sm" variant="secondary" onClick={() => handleExecute(tr.id)}>{t('transfers.execute')}</Button>}<Button size="sm" variant="danger" onClick={() => handleDelete(tr.id)}><Trash2 className="w-4 h-4" /></Button></div></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Credit Lines Page ============
export function CreditLinesPage() {
  const { t } = useTranslation('treasury')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', type: 'credit_line' as const, limit_amount: 0, used_amount: 0, interest_rate: 0, start_date: '', end_date: '', monthly_payment: 0, notes: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getCreditLines() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createCreditLine(form as any); toast('success', tCommon('common.success'), t('creditLines.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteCreditLine(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('creditLines.breadcrumb1'), path: '/treasury' }, { label: t('creditLines.title') }]} />
      <PageHeader title={t('creditLines.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('creditLines.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('creditLines.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /><select className="border rounded px-3 py-2" value={form.type} onChange={e => setForm({ ...form, type: e.target.value as any })}><option value="credit_line">{t('creditLines.types.credit_line')}</option><option value="loan">{t('creditLines.types.loan')}</option><option value="overdraft">{t('creditLines.types.overdraft')}</option></select><Input type="number" placeholder={t('creditLines.limit')} value={form.limit_amount} onChange={e => setForm({ ...form, limit_amount: parseFloat(e.target.value) || 0 })} /><Input type="number" placeholder={t('creditLines.rate')} value={form.interest_rate} onChange={e => setForm({ ...form, interest_rate: parseFloat(e.target.value) || 0 })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('creditLines.empty')} /> : (
        <Table headers={[t('creditLines.name'), t('creditLines.type'), t('creditLines.limit'), t('creditLines.used'), t('creditLines.rate'), t('creditLines.status'), tCommon('common.actions')]}>
          {items.map(c => (<TableRow key={c.id}><TableCell>{c.name}</TableCell><TableCell>{t(`creditLines.types.${c.type}`)}</TableCell><TableCell>{formatCurrency(c.limit_amount)}</TableCell><TableCell>{formatCurrency(c.used_amount)}</TableCell><TableCell>{c.interest_rate}%</TableCell><TableCell><Badge>{t(`creditLines.statuses.${c.status}`)}</Badge></TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(c.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Investments Page ============
export function InvestmentsPage() {
  const { t } = useTranslation('treasury')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', type: 'opcv' as const, institution: '', initial_amount: 0, current_value: 0, acquisition_date: '', maturity_date: '', interest_rate: 0, notes: '' })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getInvestments() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createInvestment(form as any); toast('success', tCommon('common.success'), t('investments.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteInvestment(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('investments.breadcrumb1'), path: '/treasury' }, { label: t('investments.title') }]} />
      <PageHeader title={t('investments.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('investments.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('investments.name')} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /><select className="border rounded px-3 py-2" value={form.type} onChange={e => setForm({ ...form, type: e.target.value as any })}><option value="opcv">{t('investments.types.opcv')}</option><option value="bond">{t('investments.types.bond')}</option><option value="stock">{t('investments.types.stock')}</option><option value="term_deposit">{t('investments.types.term_deposit')}</option></select><Input placeholder={t('investments.institution')} value={form.institution} onChange={e => setForm({ ...form, institution: e.target.value })} /><Input type="number" placeholder={t('investments.initialAmount')} value={form.initial_amount} onChange={e => setForm({ ...form, initial_amount: parseFloat(e.target.value) || 0 })} /><Input type="number" placeholder={t('investments.currentValue')} value={form.current_value} onChange={e => setForm({ ...form, current_value: parseFloat(e.target.value) || 0 })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('investments.empty')} /> : (
        <Table headers={[t('investments.name'), t('investments.type'), t('investments.initial'), t('investments.current'), t('investments.rate'), t('investments.status'), tCommon('common.actions')]}>
          {items.map(i => (<TableRow key={i.id}><TableCell>{i.name}</TableCell><TableCell>{t(`investments.types.${i.type}`)}</TableCell><TableCell>{formatCurrency(i.initial_amount)}</TableCell><TableCell>{formatCurrency(i.current_value)}</TableCell><TableCell>{i.interest_rate}%</TableCell><TableCell><Badge>{t(`investments.statuses.${i.status}`)}</Badge></TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(i.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Value Date Tracking Page ============
export function ValueDateTrackingPage() {
  const { t } = useTranslation('treasury')
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getValueDateTrackings() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: t('valueDates.breadcrumb1'), path: '/treasury' }, { label: t('valueDates.title') }]} />
      <PageHeader title={t('valueDates.title')} />
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('valueDates.empty')} /> : (
        <Table headers={[t('valueDates.account'), t('valueDates.operationDate'), t('valueDates.valueDate'), t('valueDates.amount'), t('valueDates.type')]}>
          {items.map(v => (<TableRow key={v.id}><TableCell>{v.bank_accounts?.name || '-'}</TableCell><TableCell>{v.operation_date}</TableCell><TableCell>{v.value_date}</TableCell><TableCell>{formatCurrency(v.amount)}</TableCell><TableCell>{v.transaction_type || '-'}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Treasury Recurring Page ============
export function TreasuryRecurringPage() {
  const { t } = useTranslation('treasury')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ description: '', bank_account_id: '', amount: 0, type: 'outgoing' as const, frequency: 'monthly' as const, next_date: '', end_date: '', active: true })

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getTreasuryRecurring() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  async function handleCreate() { try { await createTreasuryRecurring(form as any); toast('success', tCommon('common.success'), t('recurring.created')); setShowForm(false); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }
  async function handleDelete(id: string) { if (!window.confirm(tCommon('form.confirmDelete'))) return; try { await deleteTreasuryRecurring(id); await loadData() } catch (e: any) { toast('error', tCommon('common.error'), e.message) } }

  return (
    <div>
      <Breadcrumb items={[{ label: t('recurring.breadcrumb1'), path: '/treasury' }, { label: t('recurring.title') }]} />
      <PageHeader title={t('recurring.title')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('recurring.new')}</Button>} />
      {showForm && (<Card className="p-4 mb-4 space-y-3"><div className="grid grid-cols-2 gap-3"><Input placeholder={t('recurring.description')} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /><Input type="number" placeholder={t('recurring.amount')} value={form.amount} onChange={e => setForm({ ...form, amount: parseFloat(e.target.value) || 0 })} /><select className="border rounded px-3 py-2" value={form.type} onChange={e => setForm({ ...form, type: e.target.value as any })}><option value="incoming">{t('recurring.types.incoming')}</option><option value="outgoing">{t('recurring.types.outgoing')}</option></select><select className="border rounded px-3 py-2" value={form.frequency} onChange={e => setForm({ ...form, frequency: e.target.value as any })}><option value="weekly">{t('recurring.freq.weekly')}</option><option value="monthly">{t('recurring.freq.monthly')}</option><option value="quarterly">{t('recurring.freq.quarterly')}</option><option value="yearly">{t('recurring.freq.yearly')}</option></select><Input type="date" value={form.next_date} onChange={e => setForm({ ...form, next_date: e.target.value })} /></div><div className="flex gap-2"><Button onClick={handleCreate}>{tCommon('actions.save')}</Button><Button variant="secondary" onClick={() => setShowForm(false)}>{tCommon('common.cancel')}</Button></div></Card>)}
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('recurring.empty')} /> : (
        <Table headers={[t('recurring.description'), t('recurring.amount'), t('recurring.type'), t('recurring.frequency'), t('recurring.nextDate'), tCommon('common.actions')]}>
          {items.map(r => (<TableRow key={r.id}><TableCell>{r.description}</TableCell><TableCell>{formatCurrency(r.amount)}</TableCell><TableCell><Badge>{t(`recurring.types.${r.type}`)}</Badge></TableCell><TableCell>{t(`recurring.freq.${r.frequency}`)}</TableCell><TableCell>{r.next_date}</TableCell><TableCell><Button size="sm" variant="danger" onClick={() => handleDelete(r.id)}><Trash2 className="w-4 h-4" /></Button></TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}

// ============ Consolidated Treasury Page ============
export function ConsolidatedTreasuryPage() {
  const { t } = useTranslation('treasury')
  const { formatCurrency } = useLocale()
  const [items, setItems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  const loadData = useCallback(async () => { setLoading(true); try { setItems(await getConsolidatedTreasury() || []) } catch { } finally { setLoading(false) } }, [])
  useEffect(() => { loadData() }, [loadData])

  return (
    <div>
      <Breadcrumb items={[{ label: t('consolidated.breadcrumb1'), path: '/treasury' }, { label: t('consolidated.title') }]} />
      <PageHeader title={t('consolidated.title')} />
      {loading ? <SkeletonTable /> : items.length === 0 ? <EmptyState title={t('consolidated.empty')} /> : (
        <Table headers={[t('consolidated.date'), t('consolidated.assets'), t('consolidated.liabilities'), t('consolidated.netPosition')]}>
          {items.map(c => (<TableRow key={c.id}><TableCell>{c.consolidation_date}</TableCell><TableCell>{formatCurrency(c.total_assets)}</TableCell><TableCell>{formatCurrency(c.total_liabilities)}</TableCell><TableCell>{formatCurrency(c.net_position)}</TableCell></TableRow>))}
        </Table>
      )}
    </div>
  )
}
