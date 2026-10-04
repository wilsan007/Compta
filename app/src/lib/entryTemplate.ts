import { localDateString } from '@/lib/dateRange'

/** Ce qu'une ligne de modèle de saisie porte pour décider de ses montants. */
export interface TemplateLineAmountSource {
  amount_type?: string | null
  fixed_amount?: number | null
  debit_pct?: number | null
  credit_pct?: number | null
}

/**
 * Les montants PROPOSÉS par une ligne de modèle quand on l'applique à une saisie.
 *
 * F6 (cpt-007) : `debit_pct` / `credit_pct` sont des POURCENTAGES. Les deux écrans de
 * saisie les recopiaient tels quels dans les colonnes débit et crédit — un modèle
 * « 100 % au débit » préremplissait 100,00 €. Et un montant fixe était recopié des
 * DEUX côtés à la fois.
 *
 *  - montant fixe : posé du côté que désigne le pourcentage (débit si aucun n'est donné) ;
 *  - à saisir, pourcentage, solde, TVA calculée : vide. Aucun montant de base n'est
 *    saisi à ce stade, donc aucun pourcentage ne peut s'appliquer.
 */
export function templateLineAmounts(tl: TemplateLineAmountSource): { debit: string; credit: string } {
  if (tl.amount_type === 'fixed' && tl.fixed_amount != null && Number(tl.fixed_amount) !== 0) {
    const auCredit = Number(tl.credit_pct) > 0 && !(Number(tl.debit_pct) > 0)
    const montant = String(tl.fixed_amount)
    return auCredit ? { debit: '', credit: montant } : { debit: montant, credit: '' }
  }
  return { debit: '', credit: '' }
}

/**
 * La date proposée pour une écriture saisie dans une période.
 *
 * F7 (cpt-008) : la date du jour était proposée même quand elle tombait HORS de la
 * période choisie. Aujourd'hui si elle est dans la période, sinon le premier jour de
 * la période.
 */
export function defaultEntryDate(periodStart?: string | null, periodEnd?: string | null, today: string = localDateString()): string {
  if (!periodStart || !periodEnd) return today
  const debut = periodStart.slice(0, 10)
  const fin = periodEnd.slice(0, 10)
  return today >= debut && today <= fin ? today : debut
}
