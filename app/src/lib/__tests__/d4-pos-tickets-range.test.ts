// ============================================================
// d4-pos-tickets-range.test.ts — D4 (stk-013), le chemin de l'écran
//
// Les statistiques de caisse passent une période à `getPosTickets`, qui doit
// interroger `[gte(from), lt(to))`. La recette a mesuré la requête réellement
// émise — `date=gte.2026-09-28&date=lt.2026-09-28T23:59:59` — donc on vérifie
// ici les deux bornes telles qu'elles partent, pas seulement l'utilitaire.
// ============================================================
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { supabase } from '@/lib/supabase'
import { getPosTickets } from '@/lib/queries/posAdvanced'
import { localDayRange } from '@/lib/dateRange'

describe('getPosTickets : la période est interrogée en [from, to)', () => {
  beforeEach(() => vi.clearAllMocks())

  it('pose gte(from) et lt(to) — deux bornes distinctes, la fin exclue', async () => {
    const now = new Date(2026, 8, 29, 10, 20)
    const range = localDayRange('today', now)

    await getPosTickets(undefined, range)

    const chain = (supabase.from as any).mock.results.at(-1).value
    expect(chain.gte).toHaveBeenCalledWith('date', range.from)
    expect(chain.lt).toHaveBeenCalledWith('date', range.to)
    // La fin n'est plus le début + 'T23:59:59' (la forme d'avant, qui ne
    // pouvait rien contenir).
    expect(range.to).not.toContain('23:59:59')
    expect(new Date(range.to).getTime()).toBeGreaterThan(new Date(range.from).getTime())
  })

  it('sans période, aucune borne n’est posée (l’écran des sessions passe l’id)', async () => {
    await getPosTickets('session-1')

    const chain = (supabase.from as any).mock.results.at(-1).value
    expect(chain.gte).not.toHaveBeenCalled()
    expect(chain.lt).not.toHaveBeenCalled()
    expect(chain.eq).toHaveBeenCalledWith('session_id', 'session-1')
  })
})
