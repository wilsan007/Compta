import { useEffect, useState, useCallback } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select, ConfirmDialog } from '@/components/ui'
import { BookCheck, Plus, Trash2, X, Printer, CheckCircle, Ban } from 'lucide-react'
import { useToast } from '@/lib/toast'
import { useLocale } from '@/hooks/useLocale'
import { getCheckBooks, createCheckBook, updateCheckBook, deleteCheckBook, getChecks, createCheck, updateCheck, deleteCheck } from '@/lib/queries/accounting'
import type { CheckBook, Check } from '@/types'

export function CheckBooksPage() {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const { formatCurrency } = useLocale()
  const [activeTab, setActiveTab] = useState<'checkBooks' | 'checks' | 'print'>('checkBooks')
  const [checkBooks, setCheckBooks] = useState<CheckBook[]>([])
  const [checks, setChecks] = useState<Check[]>([])
  const [loading, setLoading] = useState(true)
  const [showBookForm, setShowBookForm] = useState(false)
  const [showCheckForm, setShowCheckForm] = useState(false)
  const [deleteBookTarget, setDeleteBookTarget] = useState<CheckBook | null>(null)
  const [deleteCheckTarget, setDeleteCheckTarget] = useState<Check | null>(null)
  const [printCheck, setPrintCheck] = useState<Check | null>(null)

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [books, chks] = await Promise.all([getCheckBooks(), getChecks()])
      setCheckBooks(books || [])
      setChecks(chks || [])
    } catch (err: any) { console.error("catch:", err); toast('error', tCommon('toast.error'), err.message || tCommon('toast.loadError')) } finally { setLoading(false) }
  }, [tCommon, toast])

  useEffect(() => { loadData() }, [loadData])

  const statusBadge = (status: string) => {
    const variants: Record<string, 'success' | 'warning' | 'danger' | 'neutral' | 'primary'> = {
      active: 'success', exhausted: 'warning', cancelled: 'danger',
      draft: 'neutral', issued: 'primary', cashed: 'success', lost: 'danger',
    }
    return <Badge variant={variants[status] || 'neutral'}>{t(`checkBooks.statuses.${status}`)}</Badge>
  }

  return (
    <div className="p-6 space-y-6">
      <AutoBreadcrumb />
      <PageHeader title={t('checkBooks.title')} subtitle={t('checkBooks.subtitle')} />

      <div className="flex gap-2 border-b border-[var(--color-border)]">
        {(['checkBooks', 'checks', 'print'] as const).map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${activeTab === tab ? 'border-[var(--color-primary)] text-[var(--color-primary)]' : 'border-transparent text-[var(--color-text-secondary)] hover:text-[var(--color-text)]'}`}
          >
            {t(`checkBooks.tabs.${tab}`)}
          </button>
        ))}
      </div>

      {activeTab === 'checkBooks' && (
        <Card>
          <div className="flex items-center justify-between p-4 border-b border-[var(--color-border)]">
            <h3 className="font-semibold">{t('checkBooks.tabs.checkBooks')}</h3>
            <Button onClick={() => setShowBookForm(true)}><Plus className="w-4 h-4 mr-1" /> {t('checkBooks.checkBooks.new')}</Button>
          </div>
          {loading ? <SkeletonTable /> : checkBooks.length === 0 ? (
            <EmptyState icon={<BookCheck className="w-12 h-12" />} title={t('checkBooks.checkBooks.noCheckBooks')} description={t('checkBooks.checkBooks.noCheckBooksDesc')} />
          ) : (
            <Table headers={[t('checkBooks.checkBooks.name'), t('checkBooks.checkBooks.bankAccount'), t('checkBooks.checkBooks.firstCheck'), t('checkBooks.checkBooks.lastCheck'), t('checkBooks.checkBooks.nextCheck'), t('checkBooks.checkBooks.status'), t('checkBooks.checkBooks.issuedCount'), '']}>
              {checkBooks.map(book => (
                <TableRow key={book.id}>
                  <TableCell>{book.name}</TableCell>
                  <TableCell>{book.bank_account_id || '—'}</TableCell>
                  <TableCell>{book.first_check_number}</TableCell>
                  <TableCell>{book.last_check_number}</TableCell>
                  <TableCell>{book.next_check_number}</TableCell>
                  <TableCell>{statusBadge(book.status)}</TableCell>
                  <TableCell>{book.issued_count}</TableCell>
                  <TableCell><button onClick={() => setDeleteBookTarget(book)} className="p-1 text-red-500 hover:bg-red-50 rounded"><Trash2 className="w-4 h-4" /></button></TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>
      )}

      {activeTab === 'checks' && (
        <Card>
          <div className="flex items-center justify-between p-4 border-b border-[var(--color-border)]">
            <h3 className="font-semibold">{t('checkBooks.tabs.checks')}</h3>
            <Button onClick={() => setShowCheckForm(true)}><Plus className="w-4 h-4 mr-1" /> {t('checkBooks.checks.new')}</Button>
          </div>
          {loading ? <SkeletonTable /> : checks.length === 0 ? (
            <EmptyState icon={<BookCheck className="w-12 h-12" />} title={t('checkBooks.checks.noChecks')} description={t('checkBooks.checks.noChecksDesc')} />
          ) : (
            <Table headers={[t('checkBooks.checks.checkNumber'), t('checkBooks.checks.amount'), t('checkBooks.checks.payee'), t('checkBooks.checks.issueDate'), t('checkBooks.checks.status'), '']}>
              {checks.map(chk => (
                <TableRow key={chk.id}>
                  <TableCell>{chk.check_number}</TableCell>
                  <TableCell>{chk.amount.toFixed(2)}</TableCell>
                  <TableCell>{chk.payee}</TableCell>
                  <TableCell>{chk.issue_date}</TableCell>
                  <TableCell>{statusBadge(chk.status)}</TableCell>
                  <TableCell>
                    <div className="flex gap-1">
                      {chk.status === 'issued' && (
                        <button onClick={async () => { await updateCheck(chk.id, { status: 'cashed' }); toast('success', t('checkBooks.title'), t('checkBooks.checkCashed')); loadData() }} className="p-1 text-green-600 hover:bg-green-50 rounded" title={t('checkBooks.checks.markCashed')}><CheckCircle className="w-4 h-4" /></button>
                      )}
                      {chk.status !== 'cancelled' && chk.status !== 'cashed' && (
                        <button onClick={async () => { await updateCheck(chk.id, { status: 'cancelled' }); toast('success', t('checkBooks.title'), t('checkBooks.checkCancelled')); loadData() }} className="p-1 text-orange-600 hover:bg-orange-50 rounded" title={t('checkBooks.checks.markCancelled')}><Ban className="w-4 h-4" /></button>
                      )}
                      <button onClick={() => setPrintCheck(chk)} className="p-1 text-blue-600 hover:bg-blue-50 rounded" title={t('checkBooks.print.print')}><Printer className="w-4 h-4" /></button>
                      <button onClick={() => setDeleteCheckTarget(chk)} className="p-1 text-red-500 hover:bg-red-50 rounded"><Trash2 className="w-4 h-4" /></button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </Table>
          )}
        </Card>
      )}

      {activeTab === 'print' && (
        <Card>
          <div className="p-6">
            <h3 className="font-semibold mb-4">{t('checkBooks.print.title')}</h3>
            {printCheck ? (
              <div className="max-w-md mx-auto border border-[var(--color-border)] rounded-lg p-8 space-y-6">
                <div className="flex justify-between text-sm text-[var(--color-text-secondary)]">
                  <span>{t('checkBooks.print.number')}: {printCheck.check_number}</span>
                  <span>{t('checkBooks.print.date')}: {printCheck.issue_date}</span>
                </div>
                <div className="text-center py-8">
                  <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('checkBooks.print.amount')}</p>
                  <p className="text-2xl font-bold">{formatCurrency(printCheck.amount)}</p>
                </div>
                <div className="text-center">
                  <p className="text-xs text-[var(--color-text-secondary)] mb-1">{t('checkBooks.print.payee')}</p>
                  <p className="text-lg font-medium">{printCheck.payee}</p>
                </div>
                <Button variant="secondary" className="w-full" onClick={() => window.print()}><Printer className="w-4 h-4 mr-2" /> {t('checkBooks.print.print')}</Button>
              </div>
            ) : (
              <EmptyState icon={<Printer className="w-12 h-12" />} title={t('checkBooks.print.title')} description={t('checkBooks.checks.noChecks')} />
            )}
          </div>
        </Card>
      )}

      {showBookForm && <CheckBookForm onClose={() => setShowBookForm(false)} onSaved={() => { setShowBookForm(false); loadData() }} />}
      {showCheckForm && <CheckForm checkBooks={checkBooks} onClose={() => setShowCheckForm(false)} onSaved={() => { setShowCheckForm(false); loadData() }} />}
      {deleteBookTarget && (
        <ConfirmDialog
          open={!!deleteBookTarget}
          title={t('checkBooks.deleteConfirm')}
          message={deleteBookTarget.name}
          onConfirm={async () => { await deleteCheckBook(deleteBookTarget.id); toast('success', t('checkBooks.title'), t('checkBooks.deleted')); setDeleteBookTarget(null); loadData() }}
          onCancel={() => setDeleteBookTarget(null)}
        />
      )}
      {deleteCheckTarget && (
        <ConfirmDialog
          open={!!deleteCheckTarget}
          title={t('checkBooks.checkDeleteConfirm')}
          message={deleteCheckTarget.check_number}
          onConfirm={async () => { await deleteCheck(deleteCheckTarget.id); toast('success', t('checkBooks.title'), t('checkBooks.checkDeleted')); setDeleteCheckTarget(null); loadData() }}
          onCancel={() => setDeleteCheckTarget(null)}
        />
      )}
    </div>
  )
}

function CheckBookForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [bankAccountId, setBankAccountId] = useState('')
  const [firstCheck, setFirstCheck] = useState('')
  const [lastCheck, setLastCheck] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim() || !firstCheck.trim() || !lastCheck.trim()) return
    setSaving(true)
    try {
      await createCheckBook({
        name, bank_account_id: bankAccountId || null, journal_id: null,
        first_check_number: firstCheck, last_check_number: lastCheck,
        next_check_number: firstCheck, status: 'active',
      } as any)
      toast('success', t('checkBooks.title'), t('checkBooks.saved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('checkBooks.saveError'))
    } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('checkBooks.checkBooks.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label={t('checkBooks.checkBooks.name')} required value={name} onChange={(e) => setName(e.target.value)} />
          <Input label={t('checkBooks.checkBooks.bankAccount')} value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)} />
          <Input label={t('checkBooks.checkBooks.firstCheck')} required value={firstCheck} onChange={(e) => setFirstCheck(e.target.value)} />
          <Input label={t('checkBooks.checkBooks.lastCheck')} required value={lastCheck} onChange={(e) => setLastCheck(e.target.value)} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}

function CheckForm({ checkBooks, onClose, onSaved }: { checkBooks: CheckBook[]; onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('banking')
  const { t: tCommon } = useTranslation('common')
  const { toast } = useToast()
  const [checkBookId, setCheckBookId] = useState('')
  const [checkNumber, setCheckNumber] = useState('')
  const [amount, setAmount] = useState('')
  const [payee, setPayee] = useState('')
  const [issueDate, setIssueDate] = useState(new Date().toISOString().slice(0, 10))
  const [dueDate, setDueDate] = useState('')
  const [notes, setNotes] = useState('')
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!checkBookId || !amount || !payee) return
    setSaving(true)
    try {
      const book = checkBooks.find(b => b.id === checkBookId)
      const num = checkNumber || book?.next_check_number || ''
      await createCheck({
        check_book_id: checkBookId, check_number: num,
        amount: parseFloat(amount), payee, issue_date: issueDate,
        due_date: dueDate || null, status: 'issued', notes: notes || null,
        journal_entry_id: null, payment_id: null,
      } as any)
      if (book) {
        const nextNum = String(Number(num) + 1)
        await updateCheckBook(book.id, { next_check_number: nextNum, issued_count: book.issued_count + 1 })
      }
      toast('success', t('checkBooks.title'), t('checkBooks.checkSaved'))
      onSaved()
    } catch (err: any) {
      toast('error', tCommon('toast.error'), err.message || t('checkBooks.checkSaveError'))
    } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '32rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('checkBooks.checks.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]" aria-label={tCommon('actions.close')} title={tCommon('actions.close')}><X className="w-5 h-5" aria-hidden="true" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Select
            label={t('checkBooks.checks.selectCheckBook')}
            value={checkBookId}
            onChange={(e) => setCheckBookId(e.target.value)}
            required
            options={[
              { value: '', label: '—' },
              ...checkBooks.filter(b => b.status === 'active').map(b => ({ value: b.id, label: `${b.name} (${b.next_check_number})` })),
            ]}
          />
          <Input label={t('checkBooks.checks.checkNumber')} value={checkNumber} onChange={(e) => setCheckNumber(e.target.value)} placeholder={checkBooks.find(b => b.id === checkBookId)?.next_check_number || ''} />
          <Input label={t('checkBooks.checks.amount')} type="number" step="0.01" required value={amount} onChange={(e) => setAmount(e.target.value)} />
          <Input label={t('checkBooks.checks.payee')} required value={payee} onChange={(e) => setPayee(e.target.value)} />
          <Input label={t('checkBooks.checks.issueDate')} type="date" required value={issueDate} onChange={(e) => setIssueDate(e.target.value)} />
          <Input label={t('checkBooks.checks.dueDate')} type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          <Input label={t('checkBooks.checks.notes')} value={notes} onChange={(e) => setNotes(e.target.value)} />
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
            <Button type="submit" loading={saving}>{tCommon('actions.create')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
