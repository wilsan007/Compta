// ============================================================
// e2e/chiffres.ts — lire un CHIFFRE à l'écran
//
// D.5 (PLAN-6-PARTIES §7, repris de 4.4 / AUD-J02) : quatre parcours ne se
// contentent pas de NOMMER un écran, ils **lisent un montant** et vérifient
// qu'une relation tient, **au centime** (HT + TVA = TTC, net = brut − retenues,
// total de session = somme des tickets, plan comptable non vide).
//
// Ces fonctions sont volontairement robustes : elles lisent le **texte visible**
// et en extraient les montants au format français (« 1 234,56 », « 1.234,56 »,
// « -12,30 »), plutôt que de dépendre d'un sélecteur de champ qui change à
// chaque refonte d'écran.
// ============================================================
import { type Page } from '@playwright/test'

/**
 * Extrait les montants d'un texte, au format français : séparateur de milliers
 * (espace, insécable `\u00a0`, fine insécable `\u202f`, point) et virgule
 * décimale. Un entier sans décimale n'est **pas** un montant (les quantités,
 * les numéros et les compteurs ne sont pas des sommes).
 */
export function extraireMontants(texte: string): number[] {
  const brut = texte.match(/-?\d[\d\u00a0\u202f .]*,\d{1,2}(?!\d)/g) ?? []
  return brut
    .map((s) => Number(s.replace(/[\s\u00a0\u202f.]/g, '').replace(',', '.')))
    .filter((n) => Number.isFinite(n))
}

/** Les montants visibles sur l'écran courant (le corps de la page). */
export async function montantsVisibles(page: Page): Promise<number[]> {
  return extraireMontants(await page.locator('body').innerText())
}

/** Égalité **au centime** — les montants lus sont à deux décimales. */
export function auCentime(a: number, b: number): boolean {
  return Math.abs(a - b) < 0.005
}

/**
 * Cherche, parmi les montants lus, une relation `a OP b = c` (p. ex. une somme
 * `a + b = c` ou un reste `a - b = c`). Rend le triplet trouvé, ou `null`.
 *
 * C'est le « chiffre » de la recette : on ne se contente pas qu'un montant soit
 * affiché, on vérifie que deux d'entre eux en **produisent** un troisième.
 */
export function chercherRelation(
  montants: number[],
  operateur: 'somme' | 'difference',
): [number, number, number] | null {
  const vus = montants.slice(0, 80) // une page bavarde ne doit pas coûter O(n³)
  for (const c of vus) {
    for (const a of vus) {
      if (a === c) continue
      const b = operateur === 'somme' ? c - a : a - c
      if (auCentime(b, 0)) continue
      if (vus.some((x) => x !== a && x !== c && auCentime(x, b))) return [a, b, c]
    }
  }
  return null
}
