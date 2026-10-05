/**
 * 2.13 (G1) — un brouillon de facture est-il modifiable depuis l'écran ?
 *
 * La base (`update_invoice_draft`, 353) refuse une facture validée et un brouillon
 * dont les lignes viennent d'un autre document. L'écran ajoute deux cas qu'il ne
 * sait pas rééditer fidèlement : la facture d'acompte (un formulaire à part) et le
 * brouillon qui déduit déjà un acompte (la déduction se recalcule, elle ne se rouvre pas).
 */
export interface DraftLike {
  validation_status?: string | null
  status?: string | null
  invoice_type?: string | null
  is_advance_invoice?: boolean | null
  invoice_lines?: {
    time_entry_id?: string | null
    delivery_note_line_id?: string | null
    sales_order_line_id?: string | null
    advance_invoice_id?: string | null
  }[] | null
}

export function isEditableDraft(inv: DraftLike | null | undefined): boolean {
  if (!inv || inv.validation_status === 'validated' || inv.status === 'cancelled') return false
  if (inv.is_advance_invoice || inv.invoice_type === 'advance') return false
  return !(inv.invoice_lines || []).some((l) =>
    l.time_entry_id || l.delivery_note_line_id || l.sales_order_line_id || l.advance_invoice_id)
}
