import { supabase } from '@/lib/supabase'

// ============================================================
// P1 — l'attestation d'intégrité technique, lue côté écran.
//
// La migration `770` pose `chain_certificat_integrite()` : un `jsonb` de FAITS
// (le dernier relevé des invariants, la liste des écarts, le rapport du banc,
// l'empreinte NF-525). Cette fonction ne rend AUCUNE prose — le vocabulaire
// (« attestation d'intégrité technique », la mention légale, « qui signe »)
// vit dans l'i18n de la page, pour qu'un traducteur puisse le corriger.
//
// DEUX RÈGLES TENUES ICI.
//
// 1. **On ne fabrique aucun `tenu`.** Un relevé absent vaut `non_mesure` (c'est
//    la fonction qui le décide, pas l'écran) ; `non_joue` reste visible.
// 2. **Un seul appel.** Le certificat est un instantané : on appelle la fonction
//    une fois, on rend ce qu'elle dit — jamais un recalcul local.

/** Un invariant en écart, tel que `chain_certificat_integrite` le nomme. */
export interface CertificatEcart {
  code: string
  libelle: string
  ecart: number | null
  lignes_en_ecart: number
  mesure_le: string | null
}

/** Le certificat d'intégrité technique d'une société — des faits, rien d'autre. */
export interface Certificat {
  emis_le: string
  version_migrations: string | null
  nb_migrations: number
  invariants: { tenu: number; rompu: number; non_mesure: number; total: number }
  ecarts: CertificatEcart[]
  banc: {
    tenues: number
    rompues: number
    non_jouees: number
    total: number
    maillons: number
    epreuves_par_maillon: number
  }
  nf525: {
    total_events?: number
    broken_links?: number
    chain_valid?: boolean
    sans_objet?: boolean
    verified_at?: string
  }
}

/**
 * L'attestation d'intégrité technique de la société courante. Le serveur n'atteste
 * que la société de l'appelant (garde `42501` côté fonction).
 */
export async function getCertificatIntegrite(): Promise<Certificat> {
  const { data, error } = await supabase.rpc('chain_certificat_integrite')
  if (error) throw error
  return data as unknown as Certificat
}
