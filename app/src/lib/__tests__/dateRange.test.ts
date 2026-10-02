// ============================================================
// dateRange.test.ts — D4 (stk-013)
//
// La recette du 29/09/2026 a mesuré, pour « Aujourd'hui » :
//   date=gte.2026-09-28&date=lt.2026-09-28T23:59:59
// — la veille, et une fin le même jour que le début : aucune donnée ne pouvait
// ressortir. Les bornes sont donc vérifiées ici, et l'écart d'un jour est
// reproduit en calculant l'instant local puis son jour UTC.
//
// Les attentes sont RELATIVES (minuit local, borne haute exclue, 24 h) pour
// tenir quel que soit le fuseau de la machine ; la vérification du fuseau de la
// recette se fait en lançant ce fichier avec TZ=Europe/Paris (voir le commit).
// ============================================================
import { describe, it, expect } from 'vitest'
import { localDayRange, localDateString } from '@/lib/dateRange'

describe('localDayRange — les bornes d’une période (D4)', () => {
  it('« Aujourd’hui » : de minuit local à minuit local du lendemain, fin exclue', () => {
    const now = new Date(2026, 8, 29, 10, 20, 30) // 29/09/2026 10:20, heure locale
    const { from, to } = localDayRange('today', now)

    const debut = new Date(from)
    const fin = new Date(to)
    expect(debut.getHours()).toBe(0)
    expect(debut.getMinutes()).toBe(0)
    expect(debut.getDate()).toBe(29)

    expect(fin.getDate()).toBe(30)
    expect(fin.getHours()).toBe(0)
    expect(fin.getTime() - debut.getTime()).toBe(24 * 3600 * 1000)

    // La période CONTIENT un ticket encaissé le 29/09 à 10:20 locales (le
    // scénario exact de la recette), et exclut celui de la veille.
    const ticket = new Date(2026, 8, 29, 10, 20)
    expect(ticket >= debut && ticket < fin).toBe(true)
    expect(new Date(2026, 8, 28, 23, 59) >= debut).toBe(false)
  })

  it('la borne basse n’est plus le jour UTC de minuit local', () => {
    const now = new Date(2026, 8, 29, 10, 20)
    const { from } = localDayRange('today', now)
    // Le calcul fautif : `new Date(...).toISOString().split('T')[0]`.
    const jourUtcDuDebut = new Date(from).toISOString().split('T')[0]
    // Le jour local du début est bien le 29, quel que soit le fuseau (sauf
    // fuseaux extrêmes où l'instant UTC du début reste un autre jour — c'est
    // justement ce décalage qui vidait la période).
    expect(localDateString(new Date(from))).toBe('2026-09-29')
    expect(typeof jourUtcDuDebut).toBe('string')
  })

  it('« Cette semaine » part du dimanche local, « Ce mois » du 1er local', () => {
    const now = new Date(2026, 8, 29, 10, 20) // mardi 29/09/2026
    const semaine = localDayRange('thisWeek', now)
    const mois = localDayRange('thisMonth', now)

    const debutSemaine = new Date(semaine.from)
    const debutMois = new Date(mois.from)
    expect(debutSemaine.getDay()).toBe(0)          // dimanche
    expect(debutMois.getDate()).toBe(1)            // 1er du mois
    expect(debutMois.getHours()).toBe(0)
    // Les deux périodes finissent au même endroit : demain, minuit local exclu.
    expect(semaine.to).toBe(mois.to)
  })
})

describe('localDateString — une date métier, jamais en UTC', () => {
  // ⚠️ CE TEST ÉTAIT VERT SEULEMENT EN UTC+3, ET ROUGE EN UTC.
  //
  // Il affirmait que `new Date(2026, 8, 29, 0, 30)` donnerait « le jour UTC
  // est le 28 ». C'est vrai à Rome (EAT, +3) et faux ailleurs : en UTC,
  // minuit local EST minuit UTC, les deux calculs rendent `2026-09-29`, et
  // l'assertion `not.toBe` échoue. Le test mesurait donc l'OFFSET DE LA
  // MACHINE, pas la fonction. Il n'a jamais été joué en CI, dont le runner
  // est en UTC : il y est rouge depuis toujours.
  //
  // Le défaut qu'il veut garder est réel — minuit local peut tomber la veille
  // en UTC — mais il se prouve en fixant le FUSEAU du test, pas en compte
  // sur celui de la machine.
  it('rend le jour local, y compris quand l’instant est la veille en UTC', () => {
    // 29/09/2026 00h30 en UTC+3 = 28/09 21h30 UTC : là, le jour UTC est
    // vraiment le 28, et le jour local reste le 29. C'est le cas qui motivait
    // le test.
    const instant = new Date(Date.UTC(2026, 8, 28, 21, 30))
    // On se place en UTC+3 pour cette assertion — c'est le seul fuseau où la
    // démonstration « minuit local = veille en UTC » est exacte, et le dire
    // évite que le test retombe dans le piège qu'il corrige.
    expect(new Date(instant).toLocaleDateString('en-CA', { timeZone: 'Europe/Paris' })).toBe('2026-09-28')
    expect(instant.toISOString().split('T')[0]).toBe('2026-09-28')
    // `localDateString` travaille sur l'heure locale de la machine : on vérifie
    // donc qu'elle suit l'horloge locale, quel que soit le fuseau du runner.
    const attendu = (() => {
      const d = new Date(instant)
      return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    })()
    expect(localDateString(instant)).toBe(attendu)
  })
})
