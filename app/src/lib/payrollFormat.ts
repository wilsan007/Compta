/**
 * Formatage d'un montant de bulletin.
 *
 * Ce module ne contient AUCUNE règle de paie — il ne fait qu'afficher à deux
 * décimales un nombre renvoyé par le moteur. Il survit à la suppression du
 * second moteur (`src/lib/payroll.ts`, 509 lignes) : c'était la seule chose,
 * dans ce fichier, qui n'était pas un barème.
 *
 * Le noyau de la paie est `payroll_compute_slip` (migrations 276 → 319 → 320).
 * Aucun écran ne recalcule : il appelle, puis formate.
 */
export function formatPayrollAmount(n: number): string {
  return n.toFixed(2)
}
