import { supabase } from '@/lib/supabase'

// ============================================================
// W6 — les vérifications externes et la signature électronique
//
// Ces cinq fonctions Edge étaient **déployées et sans appelant** : ni
// `verify-siret`, ni `verify-iban`, ni `validate-vat-vies`, ni
// `request-signature` n'avaient de porte d'entrée dans l'application ; leur
// travail était fait « à l'œil » par l'utilisateur (SIRET, IBAN, TVA saisis
// sans contrôle). Ce module est leur porte d'entrée, et il obéit à la doctrine
// de W6 : **rien n'est annoncé** que la fonction n'ait confirmé.
//
// Une nuance importante, portée telle quelle à l'écran : sans jeton d'API
// (SIRENE, VIES) la fonction ne vérifie que le **format et la clé de
// contrôle**, et le dit (`api_source: 'local_validation'`). L'écran ne doit
// donc jamais écrire « vérifié auprès de l'INSEE » quand le contrôle est local.
// ============================================================

export interface SiretCheck {
  valid: boolean
  siret?: string
  siren?: string
  nic?: string
  company_name?: string
  /** `INSEE SIRENE` = vérifié à la source ; `local_validation` = format et clé seulement */
  api_source?: string
  message?: string
  error?: string
}

export interface IbanCheck {
  valid: boolean
  iban?: string
  country?: string
  bank_code?: string
  branch_code?: string
  account_number?: string
  /** `local_validation` = format, longueur pays et clé ISO 13616 seulement */
  api_source?: string
  message?: string
  error?: string
}

export interface VatCheck {
  valid: boolean
  vat_number?: string
  country?: string
  company_name?: string | null
  address?: string | null
  /** `VIES` = vérifié à la source ; `local_validation` = format seulement */
  api_source?: string
  message?: string
  error?: string
}

/** Vérifie un SIRET : 14 chiffres, clé de Luhn, puis SIRENE si configuré. */
export async function verifySiret(siret: string): Promise<SiretCheck> {
  const { data, error } = await supabase.functions.invoke('verify-siret', { body: { siret } })
  if (error) throw error
  const res = (data || {}) as SiretCheck
  // Un SIRET dont la clé de contrôle est fausse revient en `valid: false` avec un
  // motif : ce n'est pas une erreur de transport, c'est un verdict.
  if (res.valid === false && res.error) return res
  return res
}

/** Vérifie un IBAN : format, longueur du pays, clé ISO 13616. */
export async function verifyIban(iban: string): Promise<IbanCheck> {
  const { data, error } = await supabase.functions.invoke('verify-iban', { body: { iban } })
  if (error) throw error
  return (data || {}) as IbanCheck
}

/** Vérifie un numéro de TVA intracommunautaire (VIES si configuré). */
export async function validateVatVies(vatNumber: string, requesterVat?: string): Promise<VatCheck> {
  const { data, error } = await supabase.functions.invoke('validate-vat-vies', {
    body: { vat_number: vatNumber, requester_vat: requesterVat },
  })
  if (error) throw error
  return (data || {}) as VatCheck
}

// ============================================================
// Signature électronique (Yousign)
// ============================================================

export interface SignatureSigner {
  first_name: string
  last_name: string
  email: string
  phone?: string
  level?: string
}

export interface SignatureRequestResult {
  success: boolean
  provider?: string
  signature_id?: string
  status?: string
  signers?: number
}

/**
 * Demande une signature électronique pour un document **déjà hébergé** (le
 * prestataire va chercher l'URL : elle doit être accessible et signée).
 *
 * W6 / EF-07 : la base garde désormais la trace de la demande
 * (`electronic_signatures` : prestataire, identifiant, statut, signataires,
 * date). Si l'enregistrement échoue, la fonction **lève** — demander une
 * signature sans trace, c'est la redemander demain.
 */
export async function requestSignature(params: {
  documentType: string
  documentId: string | null
  documentUrl: string
  signers: SignatureSigner[]
  tenantId: string | null
}): Promise<SignatureRequestResult> {
  const { data, error } = await supabase.functions.invoke('request-signature', {
    body: {
      document_type: params.documentType,
      document_id: params.documentId,
      document_url: params.documentUrl,
      signers: params.signers,
      provider: 'yousign',
      tenant_id: params.tenantId,
    },
  })
  if (error) throw error
  const res = (data || {}) as SignatureRequestResult & { code?: string; error?: string }
  if (!res.success) {
    throw new Error(res.error || 'Demande de signature non confirmée — aucune demande n\'a été transmise')
  }
  return res
}

// ============================================================
// PDF côté serveur (Gotenberg) — décision D-4
// ============================================================
//
// `generate-pdf` n'est **pas déployée** tant que la décision D-4 n'est pas
// tranchée : elle acceptait du HTML fourni par le client (SSRF prouvée,
// AUD-H03). Son code est durci (le HTML client est refusé, les valeurs sont
// échappées) et testé côté fonction Edge (`supabase/functions/__tests__/`).
//
// Aucun appelant n'est ajouté ici **exprès** : un export mort ferait monter le
// plafond de code mort (`npm run knip:ceiling`), et brancher un écran sur une
// fonction qui n'est pas déployée serait un placebo de plus. Le jour où la
// décision sera prise, l'appelant viendra avec elle.
