// ============================================================================
// misc — demat.ts
// Extrait de l'ancien misc.ts le 2026-10-01 ; imports recalcules ;
// aucun code metier modifie.
// ============================================================================

import { supabase } from '@/lib/supabase'

// ============ EDI-TVA Submission ============
// W6 / TVA-01 : cette fonction fabriquait un identifiant local
// (`EDI-${Date.now()}`) et écrivait `edi_status = 'submitted'` **sans rien
// transmettre** — l'écran affichait un succès et masquait toute panne réelle.
// Elle appelle maintenant la fonction Edge `submit-vat-return`, qui seule sait
// si la télédéclaration a été acceptée. La base refuse par ailleurs (259) cette
// écriture à un utilisateur connecté : un placebo ne peut plus repasser.
export async function submitEdiTva(vatReturnId: string) {
  const { data: result, error } = await supabase.functions.invoke('submit-vat-return', {
    body: { vat_return_id: vatReturnId },
  })
  if (error) throw error
  if (!(result as any)?.success) {
    throw new Error((result as any)?.error || 'Télédéclaration TVA non confirmée — aucune donnée n\'a été transmise')
  }
  return result
}


// ============ Facture électronique (W6 / EF-06) ============
// L'écran générait le XML et le téléchargeait : rien n'était soumis, et aucune
// trace n'était conservée (donc un second clic aurait retransmis la facture).
// L'envoi passe désormais par la fonction Edge, et seule une confirmation
// réelle est rendue à l'appelant.
export async function submitEInvoice(
  invoiceId: string,
  platform: 'chorus_pro' | 'peppol' = 'chorus_pro',
  format: 'factur-x' | 'ubl' = 'factur-x',
  xmlContent?: string
): Promise<{ success: boolean; already_submitted?: boolean; transaction_id?: string | null; platform?: string }> {
  const { data: result, error } = await supabase.functions.invoke('submit-e-invoice', {
    body: { invoice_id: invoiceId, platform, format, xml_content: xmlContent },
  })
  if (error) throw error
  if (!(result as any)?.success) {
    throw new Error(
      (result as any)?.error
      || 'Dépôt électronique non confirmé — la facture n\'a pas été transmise'
    )
  }
  return result as any
}
