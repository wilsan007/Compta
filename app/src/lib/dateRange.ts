// ============================================================
// dateRange.ts — les bornes d'une période, dans le fuseau de l'utilisateur
//
// D4 (stk-013, recette /qa du 29/09/2026) : l'écran des statistiques de caisse
// interrogeait `gte(date, '2026-09-28')` et `lt(date, '2026-09-28T23:59:59')`
// pour la période « Aujourd'hui » du 29/09 — les DEUX bornes étaient la veille,
// et la fin était le même jour que le début : aucune donnée ne pouvait
// ressortir. La cause : `new Date().toISOString().split('T')[0]` lit le jour
// **UTC** d'un instant local (minuit local à Djibouti = 21 h la veille en UTC).
//
// Ici, les bornes sont calculées en heure locale, puis rendues en ISO (UTC, `Z`)
// — l'instant est sans ambiguïté — et la fin est **exclusive** (le lendemain à
// minuit), pour que `[gte, lt)` couvre exactement la période.
// ============================================================

export type PeriodKey = 'today' | 'thisWeek' | 'thisMonth'

export interface DateRange {
  /** Début de période, inclus — ISO UTC (`…Z`). */
  from: string
  /** Fin de période, **exclue** — ISO UTC (`…Z`) : le lendemain de la borne haute, à minuit local. */
  to: string
}

/** Minuit local du jour de `d`, sans le modifier. */
function startOfLocalDay(d: Date): Date {
  const copie = new Date(d)
  copie.setHours(0, 0, 0, 0)
  return copie
}

/** Minuit local du lendemain — la borne haute exclusive. */
function startOfNextLocalDay(d: Date): Date {
  const copie = startOfLocalDay(d)
  copie.setDate(copie.getDate() + 1)
  return copie
}

/**
 * Bornes `[from, to)` d'une période, dans le fuseau de l'utilisateur.
 * `soon` n'est pas borné à demain : « cette semaine » et « ce mois » vont jusqu'à
 * la fin de la période en cours, pas seulement jusqu'à aujourd'hui.
 */
export function localDayRange(period: PeriodKey, now: Date = new Date()): DateRange {
  let debut: Date
  if (period === 'thisWeek') {
    debut = startOfLocalDay(now)
    // Semaine commençant le dimanche, comme le calendrier local de `Date.getDay()`.
    debut.setDate(debut.getDate() - debut.getDay())
  } else if (period === 'thisMonth') {
    debut = startOfLocalDay(now)
    debut.setDate(1)
  } else {
    debut = startOfLocalDay(now)
  }
  return { from: debut.toISOString(), to: startOfNextLocalDay(now).toISOString() }
}

/** Date métier au format `AAAA-MM-JJ` dans le fuseau de l'utilisateur (jamais en UTC). */
export function localDateString(d: Date = new Date()): string {
  const a = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const j = String(d.getDate()).padStart(2, '0')
  return `${a}-${m}-${j}`
}
