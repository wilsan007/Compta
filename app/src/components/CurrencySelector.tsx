import { useEffect, useState } from 'react'
import { getCurrencies } from '@/lib/queries/accounting'
import type { Currency } from '@/types'

interface CurrencySelectorProps {
  value: string
  onChange: (code: string) => void
  className?: string
  showBase?: boolean
}

const CURRENCY_FLAGS: Record<string, string> = {
  EUR: '🇪🇺',
  USD: '🇺🇸',
  GBP: '🇬🇧',
  MAD: '🇲🇦',
  XOF: '🌍',
  CHF: '🇨🇭',
  CAD: '🇨🇦',
  JPY: '🇯🇵',
  CNY: '🇨🇳',
  AUD: '🇦🇺',
}

export function CurrencySelector({ value, onChange, className, showBase = true }: CurrencySelectorProps) {
  const [currencies, setCurrencies] = useState<Currency[]>([])

  useEffect(() => {
    void getCurrencies()
      .then((c) => setCurrencies(c || []))
      .catch(() => {})
  }, [])

  return (
    <select
      className={`input ${className || ''}`}
      value={value}
      onChange={(e) => onChange(e.target.value)}
    >
      <option value="EUR">🇪🇺 EUR — Euro</option>
      {currencies
        .filter((c) => showBase || !c.is_base)
        .map((c) => (
          <option key={c.id} value={c.code}>
            {CURRENCY_FLAGS[c.code] || '💱'} {c.code} — {c.name}
          </option>
        ))}
    </select>
  )
}
