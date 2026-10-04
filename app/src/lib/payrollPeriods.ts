/**
 * W4 (RH-06, RH-09) — les bornes de période et l'intersection des congés.
 *
 * Le front interrogeait PostgREST avec `.lte('date', `${period}-31`)` : PostgreSQL
 * refuse « 2026-04-31 » (erreur 22008) et l'import des éléments variables
 * échouait cinq mois sur douze (février, avril, juin, septembre, novembre).
 * Et il filtrait les congés « contenus dans la période » : un congé à cheval sur
 * deux mois était omis ENTIÈREMENT.
 *
 * Ce module ne fait que deux choses, et il les fait sans base ni horloge :
 *   1. `periodBounds('2026-04')` rend le DERNIER JOUR RÉEL du mois, calculé ;
 *   2. `periodOverlapFilter(bounds)` rend le filtre PostgREST d'INTERSECTION
 *      (un congé compte dès qu'il touche la période, même partiellement) —
 *      le même motif que celui déjà utilisé par `checkStaffAvailability`.
 *
 * Pur : aucune dépendance, aucune horloge implicite, testé par Vitest.
 */

export interface PeriodBounds {
  /** Premier jour du mois, « AAAA-MM-01 ». */
  first: string
  /** Dernier jour RÉEL du mois, « AAAA-MM-JJ » (28, 29, 30 ou 31). */
  last: string
}

/** Bornes d'une période « AAAA-MM ». Refuse tout ce qui n'en est pas une. */
export function periodBounds(period: string): PeriodBounds {
  const m = /^(\d{4})-(\d{2})$/.exec(period)
  if (!m) {
    throw new Error(`Période invalide : « ${period} » (format attendu AAAA-MM)`)
  }
  const [, year, month] = m
  const monthNumber = Number(month)
  if (monthNumber < 1 || monthNumber > 12) {
    throw new Error(`Période invalide : « ${period} » (mois hors 01–12)`)
  }
  // `new Date(Date.UTC(y, m, 0))` = dernier jour du mois m (m base 1 → mois
  // suivant base 0). Le jour 0 du mois suivant est le dernier du mois voulu :
  // aucun littéral « 31 », donc aucun 31 avril.
  const lastDay = new Date(Date.UTC(Number(year), monthNumber, 0)).getUTCDate()
  return { first: `${year}-${month}-01`, last: `${year}-${month}-${String(lastDay).padStart(2, '0')}` }
}

/** Le mois d'une date « AAAA-MM-JJ » (ou d'un instant ISO). */
export function periodOf(date: string): string {
  const m = /^(\d{4})-(\d{2})/.exec(date)
  if (!m) {
    throw new Error(`Date invalide : « ${date} » (format attendu AAAA-MM-JJ)`)
  }
  return `${m[1]}-${m[2]}`
}

/**
 * Filtre PostgREST d'intersection de périodes : « commence avant la fin ET
 * finit après le début ». Un congé qui traverse deux mois apparaît donc dans
 * les deux — il n'est omis d'aucun bulletin.
 */
export function periodOverlapFilter(bounds: PeriodBounds, startColumn = 'start_date', endColumn = 'end_date'): string {
  return `${startColumn}.lte.${bounds.last},${endColumn}.gte.${bounds.first}`
}
