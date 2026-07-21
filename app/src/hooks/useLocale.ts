import { useCallback, useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import type { SupportedLanguage } from '../i18n'
import { useLegislation } from '../lib/legislation'

const LOCALE_MAP: Record<SupportedLanguage, string> = {
  fr: 'fr-FR',
  en: 'en-GB',
  ar: 'ar-MA',
}

export function useLocale() {
  const { i18n } = useTranslation()
  const { pack } = useLegislation()
  const lng = (i18n.language || 'fr').split('-')[0] as SupportedLanguage

  // Use the tenant's legislation pack locale when available, fall back to UI language locale
  const locale = pack?.locale || LOCALE_MAP[lng] || 'fr-FR'
  const currencyDecimals = pack?.currency_decimals ?? 2
  const tenantCurrency = pack?.currency || 'EUR'

  const formatCurrency = useCallback(
    (amount: number, currency?: string): string => {
      return new Intl.NumberFormat(locale, {
        style: 'currency',
        currency: currency || tenantCurrency,
        minimumFractionDigits: currencyDecimals,
        maximumFractionDigits: currencyDecimals,
      }).format(amount)
    },
    [locale, tenantCurrency, currencyDecimals],
  )

  const formatDate = useCallback(
    (date: string | Date): string => {
      const d = typeof date === 'string' ? new Date(date) : date
      return new Intl.DateTimeFormat(locale, {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      }).format(d)
    },
    [locale],
  )

  const formatDateTime = useCallback(
    (date: string | Date): string => {
      const d = typeof date === 'string' ? new Date(date) : date
      return new Intl.DateTimeFormat(locale, {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      }).format(d)
    },
    [locale],
  )

  const formatNumber = useCallback(
    (num: number): string => {
      return new Intl.NumberFormat(locale).format(num)
    },
    [locale],
  )

  const formatPercent = useCallback(
    (value: number, decimals = 1): string => {
      return new Intl.NumberFormat(locale, {
        style: 'percent',
        minimumFractionDigits: decimals,
        maximumFractionDigits: decimals,
      }).format(value / 100)
    },
    [locale],
  )

  const isRTL = useMemo(() => lng === 'ar', [lng])

  return {
    locale,
    language: lng,
    isRTL,
    currencyDecimals,
    tenantCurrency,
    formatCurrency,
    formatDate,
    formatDateTime,
    formatNumber,
    formatPercent,
  }
}
