import { supabase } from './supabase'

export interface ExchangeRate {
  id: string
  tenant_id: string | null
  base_currency: string
  quote_currency: string
  rate: number
  rate_date: string
  source: string
  created_at: string
}

export async function getRate(base: string, quote: string, date?: string): Promise<number | null> {
  const tid = await getTenantId()
  let q = supabase
    .from('exchange_rates')
    .select('rate')
    .eq('base_currency', base)
    .eq('quote_currency', quote)
    .order('rate_date', { ascending: false })
    .limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  if (date) q = q.eq('rate_date', date)
  const { data, error } = await q
  if (error || !data || data.length === 0) return null
  return Number(data[0].rate)
}

export async function getLatestRate(base: string, quote: string): Promise<{ rate: number; date: string } | null> {
  const tid = await getTenantId()
  let q = supabase
    .from('exchange_rates')
    .select('rate, rate_date')
    .eq('base_currency', base)
    .eq('quote_currency', quote)
    .order('rate_date', { ascending: false })
    .limit(1)
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error || !data || data.length === 0) return null
  return { rate: Number(data[0].rate), date: data[0].rate_date }
}

export async function getRateHistory(base: string, quote: string, days: number = 30): Promise<ExchangeRate[]> {
  const tid = await getTenantId()
  const startDate = new Date()
  startDate.setDate(startDate.getDate() - days)
  let q = supabase
    .from('exchange_rates')
    .select('*')
    .eq('base_currency', base)
    .eq('quote_currency', quote)
    .gte('rate_date', startDate.toISOString().split('T')[0])
    .order('rate_date', { ascending: true })
  if (tid) q = q.eq('tenant_id', tid)
  const { data, error } = await q
  if (error) throw error
  return (data || []) as ExchangeRate[]
}

export async function convertAmount(
  amount: number,
  fromCurrency: string,
  toCurrency: string,
  date?: string
): Promise<number> {
  if (fromCurrency === toCurrency) return amount
  const rate = await getRate(fromCurrency, toCurrency, date)
  if (rate === null) {
    const inverseRate = await getRate(toCurrency, fromCurrency, date)
    if (inverseRate !== null && inverseRate !== 0) return amount / inverseRate
    throw new Error(`No exchange rate found for ${fromCurrency}/${toCurrency}`)
  }
  return amount * rate
}

export async function saveRate(
  base: string,
  quote: string,
  rate: number,
  rateDate: string,
  source: string = 'manual'
): Promise<void> {
  const tid = await getTenantId()
  const { error } = await supabase
    .from('exchange_rates')
    .upsert(
      {
        tenant_id: tid,
        base_currency: base,
        quote_currency: quote,
        rate,
        rate_date: rateDate,
        source,
      },
      { onConflict: 'tenant_id,base_currency,quote_currency,rate_date' }
    )
  if (error) throw error
}

export async function fetchRatesFromECB(): Promise<{ currency: string; rate: number }[]> {
  const response = await fetch('https://api.frankfurter.app/latest')
  if (!response.ok) throw new Error('Failed to fetch ECB rates')
  const data = await response.json()
  const rates: { currency: string; rate: number }[] = []
  if (data.rates) {
    for (const [currency, rate] of Object.entries(data.rates)) {
      rates.push({ currency, rate: rate as number })
    }
  }
  return rates
}

export async function refreshRatesFromECB(baseCurrency: string = 'EUR'): Promise<number> {
  const rates = await fetchRatesFromECB()
  const today = new Date().toISOString().split('T')[0]
  let saved = 0
  for (const { currency, rate } of rates) {
    try {
      await saveRate(baseCurrency, currency, rate, today, 'ecb')
      saved++
    } catch (err) {
      console.error(`Failed to save rate for ${currency}:`, err)
    }
  }
  return saved
}

export function formatCurrencyWithCode(amount: number, currencyCode: string, locale: string = 'fr-FR'): string {
  try {
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency: currencyCode,
      minimumFractionDigits: 2,
    }).format(amount)
  } catch {
    return `${amount.toFixed(2)} ${currencyCode}`
  }
}

export function getRateAge(rateDate: string): 'fresh' | 'recent' | 'stale' {
  const days = Math.floor((Date.now() - new Date(rateDate).getTime()) / (1000 * 60 * 60 * 24))
  if (days <= 1) return 'fresh'
  if (days <= 7) return 'recent'
  return 'stale'
}

async function getTenantId(): Promise<string | null> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return null
  const { data } = await supabase
    .from('tenant_users')
    .select('tenant_id')
    .eq('auth_id', session.user.id)
    .eq('status', 'active')
    .maybeSingle()
  return data?.tenant_id || null
}
