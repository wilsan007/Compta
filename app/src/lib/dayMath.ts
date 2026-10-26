// Dates « jour » (colonnes SQL `date`, texte `AAAA-MM-JJ`) manipulées en heure
// LOCALE, à minuit. `new Date('2026-05-10')` lit l'heure UNIVERSELLE et
// `toISOString()` la réécrit en UTC : à l'ouest de Greenwich, une tâche glissée
// d'un jour était enregistrée la veille. Ces fonctions ne passent jamais par UTC.

const DAY_MS = 24 * 60 * 60 * 1000

export function parseDay(value: string | null | undefined): Date | null {
  if (!value) return null
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value)
  if (!m) return null
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
}

export function formatDay(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function addDays(d: Date, n: number): Date {
  const r = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  r.setDate(r.getDate() + n)
  return r
}

// Nombre de jours de `a` à `b` (b − a), insensible aux changements d'heure.
export function diffDays(a: Date, b: Date): number {
  const ua = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())
  const ub = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate())
  return Math.round((ub - ua) / DAY_MS)
}

export function addDaysToDay(value: string, n: number): string {
  const d = parseDay(value)
  return d ? formatDay(addDays(d, n)) : value
}

export function minDay(...values: (string | null | undefined)[]): string | null {
  const v = values.filter((x): x is string => !!x).sort()
  return v.length ? v[0] : null
}

export function maxDay(...values: (string | null | undefined)[]): string | null {
  const v = values.filter((x): x is string => !!x).sort()
  return v.length ? v[v.length - 1] : null
}
