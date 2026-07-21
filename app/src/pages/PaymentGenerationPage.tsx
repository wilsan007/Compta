import { useEffect, useState, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, AutoBreadcrumb, SkeletonTable, Input, Select } from '@/components/ui'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useToast } from '@/lib/toast'
import {
  getThirdPartyAccounts, getInvoices, getPurchaseInvoices, getBankAccounts,
  createCustomerPayment, createSupplierPayment, updateInvoice, updatePurchaseInvoice,
} from '@/lib/queries'
import { Wallet, CheckSquare, Square, Landmark } from 'lucide-react'
import type { ThirdPartyAccount, Invoice, PurchaseInvoice, BankAccount } from '@/types'

type TiersType = 'customer' | 'supplier'

interface SelectableInvoice {
  id: string
  number: string
  tiersLabel: string
  tiersId: string | null
  date: string
  dueDate: string
  amountDue: number
}

export function PaymentGenerationPage() {
  const { toast } = useToast()
  const { t } = useTranslation('accounting')
  const { t: tCommon } = useTranslation('common')
  const [tiersType, setTiersType] = useState<TiersType>('supplier')
  const [thirdParties, setThirdParties] = useState<ThirdPartyAccount[]>([])
  const [banks, setBanks] = useState<BankAccount[]>([])
  const [invoices, setInvoices] = useState<Invoice[]>([])
  const [purchaseInvoices, setPurchaseInvoices] = useState<PurchaseInvoice[]>([])
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)

  // Critères de sélection (comme la fenêtre Sage "Règlement tiers")
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [tiersFilter, setTiersFilter] = useState('')
  const [method, setMethod] = useState('transfer')
  const [bankAccountId, setBankAccountId] = useState('')
  const [paymentDate, setPaymentDate] = useState(new Date().toISOString().slice(0, 10))

  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [hasSearched, setHasSearched] = useState(false)

  useEffect(() => {
    loadRef()
  }, [])

  async function loadRef() {
    try {
      const [tp, ba] = await Promise.all([getThirdPartyAccounts(), getBankAccounts()])
      setThirdParties(tp || [])
      setBanks(ba || [])
    } catch (err) {
      console.error('Error loading reference data:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleSearch() {
    setLoading(true)
    setHasSearched(true)
    setSelected(new Set())
    try {
      if (tiersType === 'supplier') {
        const data = await getPurchaseInvoices()
        setPurchaseInvoices(data || [])
      } else {
        const data = await getInvoices()
        setInvoices(data || [])
      }
    } catch (err) {
      console.error('Error loading invoices:', err)
    } finally {
      setLoading(false)
    }
  }

  const tiersOptions = useMemo(
    () => thirdParties.filter((t) => t.type === tiersType),
    [thirdParties, tiersType],
  )

  const rows: SelectableInvoice[] = useMemo(() => {
    const source = tiersType === 'supplier'
      ? purchaseInvoices.map((p) => ({
          id: p.id,
          number: p.number,
          tiersLabel: p.supplier_name || '—',
          tiersId: p.supplier_id,
          date: p.date,
          dueDate: p.due_date,
          amountDue: Number(p.amount_due),
        }))
      : invoices.map((i) => ({
          id: i.id,
          number: i.number,
          tiersLabel: i.customer_name || '—',
          tiersId: i.customer_id,
          date: i.date,
          dueDate: i.due_date,
          amountDue: Number(i.amount_due),
        }))

    return source.filter((r) => {
      if (r.amountDue <= 0) return false
      if (dateFrom && r.date < dateFrom) return false
      if (dateTo && r.date > dateTo) return false
      if (tiersFilter) {
        const tp = tiersOptions.find((t) => t.id === tiersFilter)
        if (tp) {
          const matchesLinked = tiersType === 'supplier' ? tp.supplier_id === r.tiersId : tp.customer_id === r.tiersId
          if (!matchesLinked) return false
        }
      }
      return true
    })
  }, [purchaseInvoices, invoices, tiersType, dateFrom, dateTo, tiersFilter, tiersOptions])

  function toggleSelect(id: string) {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function toggleSelectAll() {
    if (selected.size === rows.length) {
      setSelected(new Set())
    } else {
      setSelected(new Set(rows.map((r) => r.id)))
    }
  }

  const selectedRows = rows.filter((r) => selected.has(r.id))
  const totalSelected = selectedRows.reduce((s, r) => s + r.amountDue, 0)

  async function handleGenerate() {
    if (selectedRows.length === 0) {
      toast('warning', t('paymentGeneration.selectionRequired'), t('paymentGeneration.selectAtLeastOne'))
      return
    }
    setGenerating(true)
    try {
      for (const row of selectedRows) {
        const number = `${tiersType === 'supplier' ? 'RSF' : 'RSC'}-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}-${row.id.slice(0, 4)}`
        if (tiersType === 'supplier') {
          await createSupplierPayment({
            number,
            supplier_id: row.tiersId,
            purchase_invoice_id: row.id,
            payment_date: paymentDate,
            amount: row.amountDue,
            method: method as any,
            bank_account_id: bankAccountId || null,
            reference: null,
            status: 'recorded',
          } as any)
          const pInv = purchaseInvoices.find((p) => p.id === row.id)
          await updatePurchaseInvoice(row.id, {
            amount_paid: Number(pInv?.amount_paid || 0) + row.amountDue,
            amount_due: 0,
            status: 'paid',
          } as any)
        } else {
          await createCustomerPayment({
            number,
            customer_id: row.tiersId,
            invoice_id: row.id,
            payment_date: paymentDate,
            amount: row.amountDue,
            method: method as any,
            bank_account_id: bankAccountId || null,
            reference: null,
            status: 'recorded',
          } as any)
          const cInv = invoices.find((i) => i.id === row.id)
          await updateInvoice(row.id, {
            amount_paid: Number(cInv?.amount_paid || 0) + row.amountDue,
            amount_due: 0,
            status: 'paid',
          } as any)
        }
      }
      toast('success', t('paymentGeneration.generated'), t('paymentGeneration.generatedDesc', { count: selectedRows.length }))
      await handleSearch()
    } catch (err: any) {
      toast('error', tCommon('error'), err.message || t('paymentGeneration.generateError'))
    } finally {
      setGenerating(false)
    }
  }

  return (
    <div>
      <AutoBreadcrumb />
      <PageHeader
        title={t('paymentGeneration.title')}
        subtitle={t('paymentGeneration.subtitle')}
      />

      <Card className="mb-4">
        <div className="p-4 space-y-4">
          <div className="grid grid-cols-4 gap-3">
            <Select
              label={t('paymentGeneration.tiersType')}
              value={tiersType}
              onChange={(e) => { setTiersType(e.target.value as TiersType); setTiersFilter(''); setHasSearched(false); setSelected(new Set()) }}
              options={[
                { value: 'supplier', label: t('paymentGeneration.suppliers') },
                { value: 'customer', label: t('paymentGeneration.customers') },
              ]}
            />
            <Input label={t('paymentGeneration.dateFrom')} type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
            <Input label={t('paymentGeneration.dateTo')} type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1.5">{t('paymentGeneration.thirdParty')}</label>
              <select className="input cursor-pointer" value={tiersFilter} onChange={(e) => setTiersFilter(e.target.value)}>
                <option value="">{t('paymentGeneration.all')}</option>
                {tiersOptions.map((t) => <option key={t.id} value={t.id}>{t.code} — {t.name}</option>)}
              </select>
            </div>
          </div>
          <div className="grid grid-cols-4 gap-3">
            <Select label={t('paymentGeneration.method')} value={method} onChange={(e) => setMethod(e.target.value)} options={[
              { value: 'transfer', label: t('paymentGeneration.methods.transfer') },
              { value: 'check', label: t('paymentGeneration.methods.check') },
              { value: 'cash', label: t('paymentGeneration.methods.cash') },
              { value: 'card', label: t('paymentGeneration.methods.card') },
              { value: 'direct_debit', label: t('paymentGeneration.methods.direct_debit') },
              { value: 'other', label: t('paymentGeneration.methods.other') },
            ]} />
            <div>
              <label className="block text-sm font-medium text-[var(--color-text-secondary)] mb-1.5">{t('paymentGeneration.bankAccount')}</label>
              <select className="input cursor-pointer" value={bankAccountId} onChange={(e) => setBankAccountId(e.target.value)}>
                <option value="">{t('paymentGeneration.selectPlaceholder')}</option>
                {banks.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
              </select>
            </div>
            <Input label={t('paymentGeneration.paymentDate')} type="date" value={paymentDate} onChange={(e) => setPaymentDate(e.target.value)} />
            <div className="flex items-end">
              <Button onClick={handleSearch} loading={loading} className="w-full">
                {t('paymentGeneration.search')}
              </Button>
            </div>
          </div>
        </div>
      </Card>

      {hasSearched && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <p className="text-sm text-[var(--color-text-secondary)]">
              {t('paymentGeneration.eligible', { count: rows.length, selected: selectedRows.length, total: formatCurrency(totalSelected) })}
            </p>
            <Button onClick={handleGenerate} loading={generating} disabled={selectedRows.length === 0}>
              <Wallet className="w-4 h-4" /> {t('paymentGeneration.generateN', { count: selectedRows.length || '' })}
            </Button>
          </div>

          {loading ? (
            <SkeletonTable rows={6} cols={6} />
          ) : rows.length === 0 ? (
            <EmptyState
              icon={<Landmark className="w-8 h-8" />}
              title={t('paymentGeneration.noInvoices')}
              description={t('paymentGeneration.noInvoicesDescription')}
            />
          ) : (
            <Card>
              <Table headers={['', t('paymentGeneration.invoiceNumber'), t('paymentGeneration.tiers'), t('paymentGeneration.date'), t('paymentGeneration.dueDate'), t('paymentGeneration.amountDue')]}>
                <TableRow onClick={toggleSelectAll}>
                  <TableCell className="w-8">
                    {selected.size === rows.length ? <CheckSquare className="w-4 h-4 text-[var(--color-primary)]" /> : <Square className="w-4 h-4 text-[var(--color-text-secondary)]" />}
                  </TableCell>
                  <TableCell colSpan={5} className="text-xs text-[var(--color-text-secondary)] uppercase">{t('paymentGeneration.selectAllLabel')}</TableCell>
                </TableRow>
                {rows.map((r) => (
                  <TableRow key={r.id} onClick={() => toggleSelect(r.id)}>
                    <TableCell className="w-8">
                      {selected.has(r.id) ? <CheckSquare className="w-4 h-4 text-[var(--color-primary)]" /> : <Square className="w-4 h-4 text-[var(--color-text-secondary)]" />}
                    </TableCell>
                    <TableCell className="font-mono text-xs">{r.number}</TableCell>
                    <TableCell className="text-sm">{r.tiersLabel}</TableCell>
                    <TableCell className="text-xs">{formatDate(r.date)}</TableCell>
                    <TableCell className="text-xs">
                      {formatDate(r.dueDate)}
                      {r.dueDate && r.dueDate < new Date().toISOString().slice(0, 10) && (
                        <Badge variant="danger">{t('paymentGeneration.overdue')}</Badge>
                      )}
                    </TableCell>
                    <TableCell className="font-mono text-sm text-right">{formatCurrency(r.amountDue)}</TableCell>
                  </TableRow>
                ))}
              </Table>
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
