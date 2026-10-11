// ============================================================
// e2e/chiffres.ts — lire un CHIFFRE à l'écran
//
// D.5 (PLAN-6-PARTIES §7, repris de 4.4 / AUD-J02) : quatre parcours ne se
// contentent pas de NOMMER un écran, ils **lisent un montant** et vérifient
// qu'une relation tient, **au centime** (HT + TVA = TTC, net = brut − retenues,
// total de session = somme des tickets, plan comptable non vide).
//
// Ces fonctions sont volontairement robustes : elles lisent le **texte visible**
// et en extraient les montants **dans les deux écritures** (« 1 234,56 » la
// française, « €100.00 » celle que l'écran rend), plutôt que de dépendre d'un
// sélecteur de champ qui change à chaque refonte.
//
// Quand le corps de page est plein de nombres qui ne sont PAS des montants
// (quantités entières, numéros, dates), une lecture globale ne suffit plus :
// `celluleSousEnTete` lit alors **une case**, désignée par son en-tête de
// colonne et par un texte qui repère sa ligne.
// ============================================================
import { type Page } from '@playwright/test'

/**
 * Extrait les montants d'un texte, **dans les deux écritures** :
 *   - française : `1 234,56` / `1.234,56` (virgule décimale, point = milliers) ;
 *   - anglaise  : `1,234.56` / `€100.00` (point décimal, virgule = milliers).
 *
 * Un montant est reconnu **s'il porte deux décimales** : c'est ce qui distingue
 * une somme d'un code de compte (`401000`), d'un numéro ou d'une quantité — sans
 * cette règle, `401000` entrerait comme un montant de 401 000.
 */
export function extraireMontants(texte: string): number[] {
  const brut = texte.match(/-?\d[\d\u00a0\u202f ,.]*\d[.,]\d{2}(?!\d)/g) ?? []
  return brut.map(normaliserMontant).filter((n) => Number.isFinite(n))
}

/** « 1 234,56 » → 1234.56 ; « 1,234.56 » → 1234.56 ; « €100.00 » → 100. */
export function normaliserMontant(s: string): number {
  let t = s.replace(/[\s\u00a0\u202f]/g, '')
  const lastComma = t.lastIndexOf(',')
  const lastDot = t.lastIndexOf('.')
  if (lastComma > lastDot) {
    t = t.replace(/\./g, '').replace(',', '.') // virgule décimale (fr)
  } else if (lastDot > lastComma) {
    t = t.replace(/,/g, '') // point décimal (en)
  }
  return Number(t)
}
/**
 * « −2 » (moins typographique), « -2 », « 10 », « 8.00 », « 1 234,56 € » → un
 * nombre. À la différence d'`extraireMontants`, un **entier est accepté** : ici
 * on lit une case désignée explicitement, pas tout le corps de page.
 */
export function nombreLisible(texte: string): number | null {
  const t = texte.replace(/[\u2212\u2013\u2014]/g, '-').replace(/[€$\s\u00a0\u202f]/g, '')
  const m = t.match(/-?\d+(?:[.,]\d+)?/)
  return m ? normaliserMontant(m[0]) : null
}

/**
 * La valeur d'une **case**, désignée par son **en-tête de colonne** et par un
 * texte qui repère sa **ligne** (un SKU, une référence, un numéro).
 *
 * Le rang de la colonne est lu dans l'en-tête, jamais écrit en dur : ajouter une
 * colonne ne décale pas la mesure. Rend `null` si l'en-tête ou la ligne manque —
 * le test le dit alors explicitement, au lieu de comparer un chiffre inventé.
 */
export async function celluleSousEnTete(page: Page, ligneRepere: string, entete: string): Promise<number | null> {
  const entetes = await page.locator('table').first().locator('thead th').allInnerTexts()
  const rang = entetes.findIndex((h) => h.trim().toLowerCase().includes(entete.trim().toLowerCase()))
  if (rang < 0) return null
  const ligne = page.locator('table tbody tr').filter({ hasText: ligneRepere }).first()
  if (await ligne.count() === 0) return null
  const cellule = ligne.locator('td').nth(rang)
  if (await cellule.count() === 0) return null
  return nombreLisible(await cellule.innerText())
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
