/**
 * Défaut corrigé le 2026-10-01 — le filtre par plan de la balance analytique
 * VIDait l'écran au lieu de filtrer.
 *
 * `AnalyticBalancePage` a un sélecteur de plan (« Tous les plans » / un plan) et
 * filtrait avec :
 *   `d.planId === selectedPlan || d.plan_id === selectedPlan`
 * Or `getAnalyticBalance()` ne renvoyait NI `planId` NI `plan_id` : la condition
 * était toujours fausse, `filtered` devenait vide, et les trois totaux
 * affichaient 0 dès qu'un plan était choisi.
 *
 * `analytic_sections.plan_id` existe en base : l'agrégat le remonte désormais sous
 * `planId`. Le défaut a été trouvé en typant les états « tableau de any » depuis
 * de requête (tsc a refusé les deux propriétés).
 */
import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

const racine = path.resolve(__dirname, '../../..') // app/
const lire = (p: string) => fs.readFileSync(path.join(racine, p), 'utf8')

describe('balance analytique — le filtre par plan filtre', () => {
  it('getAnalyticBalance expose `planId` (le plan de signature de la section)', () => {
    const src = lire('src/lib/queries/accounting/etats.ts')
    // 2026-10-05 (2.13, 353) : l'agrégat a été extrait dans `aggregateAnalyticBalance`
    // (il lit désormais les parts ventilées) et son type nommé `AnalyticBalanceRow`.
    // L'assertion suit le code : elle porte sur le bloc qui va du type à la fin de
    // la fonction de requête — même propriété vérifiée, le plan remonte de la section.
    const debut = src.indexOf('export interface AnalyticBalanceRow')
    expect(debut).toBeGreaterThan(-1)
    const requete = src.indexOf('export async function getAnalyticBalance', debut)
    expect(requete).toBeGreaterThan(debut)
    const fin = src.indexOf('\nexport ', requete + 1)
    const corps = fin > 0 ? src.slice(debut, fin) : src.slice(debut)
    expect(corps).toMatch(/return aggregateAnalyticBalance\(lines, sections\)/)

    // L'agrégat porte le plan, lu sur la section.
    expect(corps).toMatch(/planId:\s*sec\?\.plan_id/)
    expect(corps).toMatch(/planId:\s*string \| null/)
  })

  it("l'écran ne filtre QUE sur `planId` — plus de `plan_id` fantôme", () => {
    const src = lire('src/pages/AnalyticBalancePage.tsx')
    const fautives = src
      .split('\n')
      .filter((l) => !l.trim().startsWith('//'))
      .filter((l) => /\bd\.plan_id\b/.test(l))
    expect(fautives).toEqual([])
    // Et le filtre existe bien, sur la bonne propriété.
    expect(src).toMatch(/data\.filter\(\(d\)\s*=>\s*d\.planId\s*===\s*selectedPlan\)/)
  })

  it('les états de la page sont nommés depuis leur fonction, plus un tableau de any', () => {
    const src = lire('src/pages/AnalyticBalancePage.tsx')
    expect(src).toContain('useState<Awaited<ReturnType<typeof getAnalyticBalance>>>')
    expect(src).toContain('useState<Awaited<ReturnType<typeof getAnalyticPlans>>>')
  })
})