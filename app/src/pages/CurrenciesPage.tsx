import { useEffect, useState, useCallback } from 'react'
import { Card, PageHeader, Button, Table, TableRow, TableCell, Badge, EmptyState, Breadcrumb, SkeletonTable, Input } from '@/components/ui'
import { getCurrencies, createCurrency, updateCurrency, deleteCurrency } from '@/lib/queries'
import { Plus, Trash2, X, Coins } from 'lucide-react'
import type { Currency } from '@/types'
import { useToast } from '@/lib/toast'
import { useTranslation } from 'react-i18next'

export function CurrenciesPage() {
  const { t } = useTranslation('settings')
  const { toast } = useToast()
const [currencies, setCurrencies] = useState<Currency[]>([])
  const [loading, setLoading] = useState(true)
  const [showForm, setShowForm] = useState(false)

  const loadData = useCallback(async () => {
    setLoading(true)
    try { setCurrencies(await getCurrencies()) } catch (err) { console.error(err); toast('error', t('currencies.loadError'), t('currencies.loadError')) } finally { setLoading(false) }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  async function handleDelete(id: string) {
  if (!window.confirm(t('currencies.deleteConfirm'))) return
    try { await deleteCurrency(id); await loadData() } catch (err: any) { toast('error', t('currencies.loadError'), err.message || t('currencies.loadError')) }
  }

  async function handleSetBase(id: string) {
    try {
      for (const c of currencies) {
        await updateCurrency(c.id, { is_base: c.id === id })
      }
      await loadData()
    } catch (err: any) { toast('error', t('currencies.loadError'), err.message || t('currencies.loadError')) }
  }

  return (
    <div>
      <Breadcrumb items={[{ label: t('currencies.breadcrumb') }, { label: t('currencies.breadcrumb2') }]} />
      <PageHeader
        title={t('currencies.title')}
        subtitle={t('currencies.subtitle2')}
        action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('currencies.new')}</Button>}
      />

      {loading ? (
        <SkeletonTable rows={4} cols={5} />
      ) : currencies.length === 0 ? (
        <EmptyState icon={<Coins className="w-8 h-8" />} title={t('currencies.noCurrencies')} description={t('currencies.noCurrenciesAdd')} action={<Button onClick={() => setShowForm(true)}><Plus className="w-4 h-4" /> {t('currencies.new')}</Button>} />
      ) : (
        <Card>
          <Table headers={[t('currencies.code'), t('currencies.name'), t('currencies.symbol'), t('currencies.rateLabel'), t('currencies.base'), t('currencies.actions')]}>
            {currencies.map((c) => (
              <TableRow key={c.id}>
                <TableCell className="font-mono font-bold">{c.code}</TableCell>
                <TableCell className="text-sm">{c.name}</TableCell>
                <TableCell className="text-sm">{c.symbol || '—'}</TableCell>
                <TableCell className="font-mono text-xs">{Number(c.exchange_rate).toFixed(4)}</TableCell>
                <TableCell>
                  {c.is_base ? (
                    <Badge variant="success">{t('currencies.base')}</Badge>
                  ) : (
                    <button onClick={() => handleSetBase(c.id)} className="text-xs text-[var(--color-primary)] hover:underline">{t('currencies.setBase')}</button>
                  )}
                </TableCell>
                <TableCell>
                  <button onClick={() => handleDelete(c.id)} className="p-1.5 rounded hover:bg-[var(--color-neutral-100)] text-[var(--color-danger)]"><Trash2 className="w-4 h-4" /></button>
                </TableCell>
              </TableRow>
            ))}
          </Table>
        </Card>
      )}

      {showForm && <CurrencyForm onClose={() => setShowForm(false)} onSaved={() => { setShowForm(false); loadData() }} />}
    </div>
  )
}

function CurrencyForm({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { t } = useTranslation('settings')
  const [code, setCode] = useState('')
  const { toast } = useToast()
  const [name, setName] = useState('')
  const [symbol, setSymbol] = useState('')
  const [exchangeRate, setExchangeRate] = useState(1)
  const [isBase, setIsBase] = useState(false)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    try {
      await createCurrency({ code: code.toUpperCase(), name, symbol, exchange_rate: exchangeRate, is_base: isBase } as any)
      onSaved()
    } catch (err: any) { toast('error', t('currencies.loadError'), err.message || t('currencies.loadError')) } finally { setSaving(false) }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-[9990] flex items-center justify-center p-4">
      <div className="card shadow-2xl" style={{ width: '100%', maxWidth: '28rem' }}>
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--color-border)]">
          <h2 className="text-lg font-semibold">{t('currencies.new')}</h2>
          <button onClick={onClose} className="p-1 rounded hover:bg-[var(--color-neutral-100)]"><X className="w-5 h-5" /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Input label={t('currencies.codeLabel')} required value={code} onChange={(e) => setCode(e.target.value)} placeholder={t('currencies.codePlaceholder')} />
            <Input label={t('currencies.symbolLabel')} value={symbol} onChange={(e) => setSymbol(e.target.value)} placeholder={t('currencies.symbolPlaceholder')} />
          </div>
          <Input label={t('currencies.nameLabel')} required value={name} onChange={(e) => setName(e.target.value)} placeholder={t('currencies.namePlaceholder')} />
          <Input label={t('currencies.rateLabel')} type="number" step="0.0001" required value={exchangeRate} onChange={(e) => setExchangeRate(Number(e.target.value))} />
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={isBase} onChange={(e) => setIsBase(e.target.checked)} />
            {t('currencies.isBase')}
          </label>
          <div className="flex justify-end gap-3 pt-4 border-t border-[var(--color-border)]">
            <Button type="button" variant="secondary" onClick={onClose}>{t('currencies.cancel')}</Button>
            <Button type="submit" disabled={saving}>{saving ? '...' : t('currencies.createBtn')}</Button>
          </div>
        </form>
      </div>
    </div>
  )
}
