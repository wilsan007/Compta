import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Modal, Button, Input, Select } from '@/components/ui'
import { getBankAccounts } from '@/lib/queries/banking'
import { formatCurrency } from '@/lib/utils'
import type { BankAccount } from '@/types'

// R-08 (décision D-10) : « Marquer payée » enregistrait un virement sans date, sans
// mode ni compte bancaire — tout partait donc en 512000/BQ. Cette fenêtre, commune
// aux ventes, aux achats et à la paie, demande les quatre informations qui
// déterminent l'écriture de trésorerie.

export type PaymentMethod = 'transfer' | 'check' | 'card' | 'cash' | 'direct_debit' | 'other'

export interface PaymentValues {
  payment_date: string
  amount: number
  method: PaymentMethod
  bank_account_id: string | null
  reference: string | null
}

export function PaymentDialog({
  title, subtitle, defaultAmount, maxAmount, defaultReference, amountEditable = true, showAmount = true, submitLabel,
  onSubmit, onClose,
}: {
  title: string
  subtitle?: string
  defaultAmount: number
  /** Montant dû : au-delà, l'excédent part en avance (4191 / 4091) — signalé à l'écran */
  maxAmount?: number
  defaultReference?: string | null
  amountEditable?: boolean
  /** Paie : le montant est calculé par le serveur, périmètre par périmètre */
  showAmount?: boolean
  submitLabel?: string
  onSubmit: (values: PaymentValues) => Promise<void> | void
  onClose: () => void
}) {
  const { t } = useTranslation('sales')
  const { t: tCommon } = useTranslation('common')
  const [banks, setBanks] = useState<BankAccount[]>([])
  const [date, setDate] = useState(new Date().toISOString().split('T')[0])
  const [amount, setAmount] = useState(defaultAmount)
  const [method, setMethod] = useState<PaymentMethod>('transfer')
  const [bankId, setBankId] = useState('')
  const [reference, setReference] = useState(defaultReference || '')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let cancelled = false
    getBankAccounts()
      .then(list => {
        if (cancelled) return
        setBanks(list)
        if (list.length === 1) setBankId(list[0].id)
      })
      .catch(() => { if (!cancelled) setBanks([]) })
    return () => { cancelled = true }
  }, [])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (showAmount && amount <= 0) return
    setSaving(true)
    try {
      await onSubmit({
        payment_date: date,
        amount: Number(amount),
        method,
        bank_account_id: bankId || null,
        reference: reference.trim() || null,
      })
    } finally {
      setSaving(false)
    }
  }

  const overpaid = showAmount && maxAmount !== undefined && amount > maxAmount

  return (
    <Modal open onClose={onClose} title={title}>
      <form onSubmit={handleSubmit} className="p-4 space-y-4">
        {subtitle && <p className="text-xs text-[var(--color-text-secondary)]">{subtitle}</p>}
        <div className={showAmount ? 'grid grid-cols-2 gap-4' : ''}>
          <Input label={t('payments.date')} type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          {showAmount && (
            <Input label={t('payments.amount')} type="number" step="0.01" required value={amount}
              disabled={!amountEditable} onChange={(e) => setAmount(Number(e.target.value))} />
          )}
        </div>
        {overpaid && (
          <p className="text-xs text-[var(--color-warning-text)]">
            {t('payments.overpaidNotice', { amount: formatCurrency(amount - (maxAmount ?? 0)) })}
          </p>
        )}
        <div className="grid grid-cols-2 gap-4">
          <Select label={t('payments.method')} required value={method}
            onChange={(e) => setMethod(e.target.value as PaymentMethod)}
            options={(['transfer', 'check', 'card', 'cash', 'direct_debit', 'other'] as PaymentMethod[])
              .map(m => ({ value: m, label: t(`payments.methods.${m}`) }))} />
          <Select label={t('payments.bankAccount')} value={bankId}
            onChange={(e) => setBankId(e.target.value)}
            options={[{ value: '', label: t('payments.defaultBankAccount') },
              ...banks.map(b => ({ value: b.id, label: b.name + (b.bank_name ? ` — ${b.bank_name}` : '') }))]} />
        </div>
        {method !== 'cash' && !bankId && (
          <p className="text-xs text-[var(--color-text-secondary)]">{t('payments.defaultBankAccountHint')}</p>
        )}
        <Input label={t('payments.reference')} value={reference} onChange={(e) => setReference(e.target.value)} />
        <div className="flex justify-end gap-3 pt-2 border-t border-[var(--color-border)]">
          <Button variant="secondary" type="button" onClick={onClose}>{tCommon('actions.cancel')}</Button>
          <Button type="submit" loading={saving}>{submitLabel || t('payments.record')}</Button>
        </div>
      </form>
    </Modal>
  )
}
