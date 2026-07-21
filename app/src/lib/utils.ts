import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'
import i18n from '@/i18n'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

const LOCALE_MAP: Record<string, string> = {
  fr: 'fr-FR',
  en: 'en-US',
  ar: 'ar-MA',
}

function getCurrentLocale(): string {
  const lang = (i18n.language || 'fr').split('-')[0]
  return LOCALE_MAP[lang] || 'fr-FR'
}

export function formatCurrency(amount: number, currency = 'EUR'): string {
  return new Intl.NumberFormat(getCurrentLocale(), {
    style: 'currency',
    currency,
    minimumFractionDigits: 2,
  }).format(amount)
}

export function formatDate(date: string | Date): string {
  const d = typeof date === 'string' ? new Date(date) : date
  return new Intl.DateTimeFormat(getCurrentLocale(), {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(d)
}

export function formatNumber(num: number): string {
  return new Intl.NumberFormat(getCurrentLocale()).format(num)
}

export function getInitials(name: string): string {
  return name
    .split(' ')
    .map((n) => n[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
}

export function translateStatus(status: string): string {
  const key = `status.${status}`
  const translated = i18n.t(key, { ns: 'common' })
  return translated !== key ? translated : status
}

export function evaluateExpression(expr: string): number | null {
  const trimmed = expr.trim()
  if (!trimmed.startsWith('=')) return null
  const expression = trimmed.slice(1).trim()
  if (!expression) return null
  if (!/^[\d\s+\-*/().,%]+$/.test(expression)) return null
  try {
    const sanitized = expression.replace(/,/g, '.').replace(/(\d+(?:\.\d+)?)%/g, '($1/100)')
    const result = Function(`"use strict"; return (${sanitized})`)()
    if (typeof result === 'number' && isFinite(result)) {
      return Math.round(result * 100) / 100
    }
    return null
  } catch {
    return null
  }
}
