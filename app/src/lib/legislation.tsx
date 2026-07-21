import { createContext, useContext, useEffect, useState, useCallback, type ReactNode } from 'react'
import { getActiveLegislationPack, getApplicableVatRates } from './queries'
import type { LegislationPack, TaxRate } from '@/types'

interface LegislationContextValue {
  pack: LegislationPack | null
  vatRates: TaxRate[]
  defaultVatRate: number
  loading: boolean
  refresh: () => void
}

const LegislationContext = createContext<LegislationContextValue | undefined>(undefined)

export function LegislationProvider({ children }: { children: ReactNode }) {
  const [pack, setPack] = useState<LegislationPack | null>(null)
  const [vatRates, setVatRates] = useState<TaxRate[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshKey, setRefreshKey] = useState(0)

  const refresh = useCallback(() => setRefreshKey(k => k + 1), [])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    getActiveLegislationPack()
      .then(async (p) => {
        if (cancelled || !p) { setPack(null); setVatRates([]); return }
        setPack(p)
        const rates = await getApplicableVatRates(p.code)
        if (cancelled) return
        setVatRates(rates)
      })
      .catch(() => {
        if (!cancelled) { setPack(null); setVatRates([]) }
      })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [refreshKey])

  const defaultVatRate = vatRates.find(r => r.is_default)?.rate
    ?? vatRates.find(r => r.category === 'standard')?.rate
    ?? 0

  return (
    <LegislationContext.Provider value={{ pack, vatRates, defaultVatRate, loading, refresh }}>
      {children}
    </LegislationContext.Provider>
  )
}

export function useLegislation() {
  const ctx = useContext(LegislationContext)
  if (!ctx) throw new Error('useLegislation must be used within LegislationProvider')
  return ctx
}
