// ============================================================
// A5 (ach-003) — l'IBAN, contrôlé avant l'enregistrement
// ============================================================
//
// Un IBAN est protégé par la clé **mod 97-10** (ISO 13616) : on déplace les
// quatre premiers caractères à la fin, on remplace chaque lettre par son numéro
// (A = 10 … Z = 35), et le nombre obtenu doit valoir 1 modulo 97.
//
// Deux questions distinctes, et c'est tout le correctif :
//   - « est-ce bien un IBAN ? » → la **forme** : deux lettres de pays puis deux
//     chiffres de contrôle ;
//   - « est-il exact ? » → la **clé**.
//
// La distinction compte parce que ce même formulaire sert les comptes
// **ordinaires** (les champs bank code / sort code / account key d'un compte
// américain) : un numéro de compte n'est pas un IBAN, ce n'est pas un IBAN
// faux, et il ne doit pas être bloqué.

/** Espaces retirés, majuscules : la forme canonique d'un IBAN. */
export function cleanIban(value: string): string {
  return value.replace(/\s+/g, '').toUpperCase()
}

/** Ce texte a-t-il la forme d'un IBAN (2 lettres de pays + 2 chiffres) ? */
export function looksLikeIBAN(value: string): boolean {
  return /^[A-Z]{2}[0-9]{2}/.test(cleanIban(value))
}

/** La clé de contrôle mod 97-10 de cet IBAN est-elle correcte ? */
export function validateIBAN(iban: string): boolean {
  const cleaned = cleanIban(iban)
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{1,30}$/.test(cleaned)) return false
  const rearranged = cleaned.slice(4) + cleaned.slice(0, 4)
  const converted = rearranged.replace(/[A-Z]/g, (ch) => String(ch.charCodeAt(0) - 55))
  let remainder: number
  let block = converted
  while (block.length > 9) {
    remainder = Number(block.slice(0, 9)) % 97
    block = remainder.toString() + block.slice(9)
  }
  return Number(block) % 97 === 1
}

/**
 * L'enregistrement doit-il être refusé ? — la décision unique, partagée par les
 * trois écritures d'un IBAN (compte bancaire du tiers, RIB du salarié, ordre de
 * paiement). Un IBAN dont la clé est fausse part ailleurs, jusqu'au virement ;
 * un numéro de compte ordinaire n'est pas un IBAN et n'est jamais bloqué.
 */
export function isIbanRejected(value: string): boolean {
  return looksLikeIBAN(value) && !validateIBAN(value)
}
