// ============================================================
// A4 (migration 318) — le SIRET, contrôlé avant l'envoi
// ============================================================
//
// Un SIRET est un SIREN (8 chiffres) + un NIC (5 chiffres) = 14 chiffres, protégé
// par la clé de Luhn. C'est **la seule** vérification faite ici, et elle est
// faite au clavier : elle ne remplace pas la vérification à la source
// (`verify-siret`, qui interroge l'INSEE SIRENE quand une clé d'API est
// configurée), elle évite d'enregistrer un identifiant faux.
//
// Un SIRET vide est un SIRET non renseigné, pas un SIRET faux : la fiche reste
// saisissable, parce qu'un client particulier ou une donnée importée peuvent
// n'en pas porter.

/** La clé de Luhn est-elle correcte pour ces chiffres ? */
export function luhnValid(digits: string): boolean {
  const d = digits.replace(/\s+/g, '')
  if (!/^\d+$/.test(d)) return false
  let sum = 0
  let double = false
  for (let i = d.length - 1; i >= 0; i--) {
    let n = Number(d[i])
    if (double) {
      n *= 2
      if (n > 9) n -= 9
    }
    sum += n
    double = !double
  }
  return sum % 10 === 0
}

/** Un SIRET est valide s'il est vide, ou s'il porte 14 chiffres de clé correcte. */
export function isSiretValid(siret: string | null | undefined): boolean {
  const s = (siret || '').replace(/\s+/g, '')
  if (!s) return true
  return s.length === 14 && luhnValid(s)
}

/** Un SIRET est-il renseigné ? (pour distinguer « absent » de « faux ») */
export function hasSiret(siret: string | null | undefined): boolean {
  return (siret || '').trim().length > 0
}
