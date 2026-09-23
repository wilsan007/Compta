// Lignes de TVA de la saisie manuelle (migration 198).
// Les codes viennent du paramétrage (get_vat_codes : FR20, FR055, AUTOLIQ, UE…),
// les mêmes que ceux des factures : la ligne est déclarée dans la bonne case.

/** Code TVA du paramétrage, avec ses comptes (get_vat_codes) */
export interface VatCode {
  vat_code: string
  label: string
  rate: number
  reverse_charge: boolean
  collected_account: string | null
  deductible_account: string | null
  ca3_base_box: string | null
  ca3_tax_box: string | null
}

export interface VatLineSpec {
  account: string
  description: string
  debit: number
  credit: number
}

const round2 = (n: number) => Math.round(n * 100) / 100

/**
 * Lignes à ajouter sous une ligne HT saisie au débit (achat) ou au crédit (vente).
 * TVA ordinaire : une ligne sur le compte déductible (débit) ou collecté (crédit),
 * contrepartie TTC. Autoliquidation (AUTOLIQ, UE) : TVA déductible ET TVA due,
 * contrepartie HT (le fournisseur ne facture pas la TVA).
 * Renvoie null si le code n'a pas de taux ou pas de compte pour ce sens.
 */
export function buildVatLines(code: VatCode, amountHt: number, isDebit: boolean): {
  ht: number
  tva: number
  counterpart: number
  lines: VatLineSpec[]
} | null {
  if (!(code.rate > 0) || !(amountHt > 0)) return null
  const ht = round2(amountHt)
  const tva = round2(ht * code.rate / 100)
  const side = (onDebit: boolean) => (onDebit ? { debit: tva, credit: 0 } : { debit: 0, credit: tva })

  if (code.reverse_charge) {
    if (!code.deductible_account || !code.collected_account) return null
    return {
      ht, tva, counterpart: ht,
      lines: [
        { account: code.deductible_account, description: `TVA déductible — ${code.label}`, ...side(isDebit) },
        { account: code.collected_account, description: `TVA due — ${code.label}`, ...side(!isDebit) },
      ],
    }
  }

  const account = isDebit ? code.deductible_account : code.collected_account
  if (!account) return null
  return {
    ht, tva, counterpart: round2(ht + tva),
    lines: [{ account, description: code.label, ...side(isDebit) }],
  }
}
