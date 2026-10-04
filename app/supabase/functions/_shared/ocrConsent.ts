// @ts-nocheck — Deno Edge Function
// ============================================================
// D-5 (migration 318) — le consentement à l'envoi de données à un tiers.
//
// CE QUE CE MODULE FERME. Des documents de la société partaient chez un
// prestataire d'OCR sans qu'aucun consentement ait été demandé — et il n'y avait
// nulle part où le donner. La société le donne depuis Paramètres → Société ; le
// consentement est DATÉ et SIGNÉ par la base (déclencheur `stamp_ocr_consent`),
// jamais par le client : un booléen qu'un client écrit ne prouve rien.
//
// LA PRATIQUE, POUR MÉMOIRE. Un sous-traitant suppose un contrat de
// sous-traitance (DPA) et une base légale ; les éditeurs du marché (Pennylane,
// Dext, Qonto, Sage AutoEntry, NetSuite) gardent l'OCR encadré par un DPA et un
// réglage PAR DOSSIER. Ce module est ce réglage, côté code.
//
// L'ÉCHEC EST FERMÉ : toute lecture impossible — erreur, ligne absente, société
// inconnue — vaut « pas de consentement ». Un doute ne fait pas partir les
// données.
// ============================================================

export interface VerdictConsentement {
  granted: boolean
  motif?: string
}

/** Le consentement OCR enregistré pour cette société. */
export async function ocrConsent(admin: any, tenantId: string | null | undefined): Promise<VerdictConsentement> {
  if (!tenantId) return { granted: false, motif: "société inconnue" }

  const { data, error } = await admin
    .from("company_settings")
    .select("ocr_consent")
    .eq("tenant_id", tenantId)
    .maybeSingle()

  if (error) {
    console.error("ocrConsent :", error)
    return { granted: false, motif: "consentement illisible" }
  }
  if (data?.ocr_consent !== true) return { granted: false, motif: "non consenti" }
  return { granted: true }
}

/**
 * La société dans laquelle l'appelant agit. L'application la transmet à CHAQUE
 * requête (`src/lib/supabase.ts` injecte `x-tenant-id` dans son `fetch`), donc
 * l'écran n'a rien à ajouter — et une requête sans en-tête est refusée plutôt
 * que devinée.
 */
export function tenantFromRequest(req: Request): string | null {
  const valeur = req.headers.get("x-tenant-id")
  return valeur && valeur.trim() !== "" ? valeur.trim() : null
}
