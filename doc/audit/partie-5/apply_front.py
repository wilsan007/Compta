"""Partie 5, tâches 5.10 et 5.11 — les changements d'écran, appliqués à l'identique.

Usage : python3 apply_front.py <dossier app>
  1. scripts/check-unused-tables.mjs : chain_document_types déclarée « serveur seulement » ;
  2. src/lib/utils.ts : errorMessage() traduit le refus CHAIN_DELETE_REFUSED (453) ;
  3. src/lib/queries/stock.ts : releaseStockReservation() appelle release_stock_reservation (454) ;
  4. src/i18n/locales/{fr,en,ar}/errors.json : clés errors:chain.* (message + 27 types) ;
  5. src/lib/__tests__/chainDeleteRefusal.test.ts : le message est vérifié.
"""
import json
import sys

APP = sys.argv[1]


def remplacer(chemin, avant, apres):
    s = open(chemin, encoding='utf-8').read()
    if apres in s:
        print(f'{chemin} : déjà fait')
        return
    assert avant in s, f'{chemin} : ancre introuvable'
    open(chemin, 'w', encoding='utf-8').write(s.replace(avant, apres, 1))
    print(f'{chemin} : modifié')


# 1 ─ la porte des tables non lues
remplacer(f'{APP}/scripts/check-unused-tables.mjs',
          "  chain_traces_defaut: '252 (L0) — partition par défaut des traces : stockage, jamais lue en direct',\n",
          "  chain_traces_defaut: '252 (L0) — partition par défaut des traces : stockage, jamais lue en direct',\n"
          "  chain_document_types: '450 (Partie 5) — registre des types de document des chaînages : lu par link_documents(), la garde de suppression (453) et INV-19 (455) ; l\\'écran traduit les types par i18n (errors:chain.types)',\n")

# 2 ─ le message de refus
remplacer(f'{APP}/src/lib/utils.ts',
          "export function errorMessage(err: unknown): string {\n  if (err instanceof Error) return err.message\n",
          """/**
 * Partie 5 (migration 453) : la base refuse de supprimer un document qu'un lien
 * de chaînage ACTIF relie à un autre (message `CHAIN_DELETE_REFUSED`, code
 * 23503, détail JSON `{ type, mode, id, liens: [{ effet, vers, vers_id }] }`).
 * Rend la phrase traduite, ou `null` si l'erreur n'est pas ce refus.
 */
export function chainDeleteRefusalMessage(err: unknown): string | null {
  if (!err || typeof err !== 'object') return null
  const e = err as { message?: unknown; details?: unknown }
  if (e.message !== 'CHAIN_DELETE_REFUSED') return null
  let detail: { type?: string; liens?: { vers?: string }[] } = {}
  try {
    detail = typeof e.details === 'string' ? JSON.parse(e.details) : {}
  } catch {
    detail = {}
  }
  const libelle = (code?: string) =>
    code ? i18n.t(`errors:chain.types.${code}`, { defaultValue: code }) : ''
  const liens = Array.isArray(detail.liens) ? detail.liens : []
  const vers = Array.from(new Set(liens.map((l) => libelle(l.vers)))).join(', ')
  return i18n.t('errors:chain.deleteRefused', {
    document: libelle(detail.type),
    count: liens.length,
    vers,
  })
}

export function errorMessage(err: unknown): string {
  const refus = chainDeleteRefusalMessage(err)
  if (refus) return refus
  if (err instanceof Error) return err.message
""")

# 3 ─ la libération de réservation
remplacer(f'{APP}/src/lib/queries/stock.ts',
          """export async function releaseStockReservation(id: string) {
  const tid = await getTenantId()
  const { error } = await supabase.from('stock_reservations').delete().eq('id', id).eq('tenant_id', tid || '')
  if (error) throw error
}""",
          """// Partie 5 (454) : une réservation se LIBÈRE, elle ne se supprime pas. La
// fonction rend la quantité réservée au dépôt, passe la réservation à
// `released` et ferme le lien commande → réservation. L'ancien DELETE ne
// rendait pas `reserved_quantity` et laissait un lien actif vers rien.
export async function releaseStockReservation(id: string) {
  const { error } = await supabase.rpc('release_stock_reservation', { p_reservation_id: id })
  if (error) throw error
}""")

# 4 ─ les traductions
TYPES = {
    'bank_accounts': ('Compte bancaire', 'Bank account', 'حساب بنكي'),
    'bank_transactions': ('Opération bancaire', 'Bank transaction', 'عملية بنكية'),
    'chart_accounts': ('Compte comptable', 'Ledger account', 'حساب محاسبي'),
    'credit_notes': ('Avoir client', 'Credit note', 'إشعار دائن'),
    'customer_payments': ('Règlement client', 'Customer payment', 'دفعة عميل'),
    'delivery_notes': ('Bon de livraison', 'Delivery note', 'إذن تسليم'),
    'expense_reports': ('Note de frais', 'Expense report', 'تقرير مصاريف'),
    'goods_receipts': ('Réception de marchandise', 'Goods receipt', 'استلام بضاعة'),
    'invoice_lines': ('Ligne de facture', 'Invoice line', 'سطر فاتورة'),
    'invoices': ('Facture client', 'Customer invoice', 'فاتورة عميل'),
    'journal_entries': ('Écriture comptable', 'Journal entry', 'قيد محاسبي'),
    'journal_lines': ("Ligne d'écriture", 'Journal line', 'سطر قيد'),
    'journals': ('Journal comptable', 'Journal', 'دفتر يومية'),
    'manufacturing_orders': ('Ordre de fabrication', 'Manufacturing order', 'أمر تصنيع'),
    'payroll_variable_elements': ('Élément variable de paie', 'Variable payroll item', 'عنصر أجر متغير'),
    'pay_runs': ('Lot de paie', 'Pay run', 'دفعة رواتب'),
    'pos_payments': ('Paiement de caisse', 'POS payment', 'دفعة صندوق'),
    'pos_sessions': ('Session de caisse', 'POS session', 'جلسة صندوق'),
    'pos_tickets': ('Ticket de caisse', 'POS receipt', 'إيصال صندوق'),
    'project_time_entries': ('Temps passé sur projet', 'Project time entry', 'وقت مسجل على مشروع'),
    'purchase_invoices': ('Facture fournisseur', 'Supplier invoice', 'فاتورة مورد'),
    'sales_orders': ('Commande client', 'Sales order', 'طلب بيع'),
    'stock_movements': ('Mouvement de stock', 'Stock movement', 'حركة مخزون'),
    'stock_reservations': ('Réservation de stock', 'Stock reservation', 'حجز مخزون'),
    'st_receipts': ('Réception de sous-traitance', 'Subcontracting receipt', 'استلام مقاولة من الباطن'),
    'st_shipments': ('Expédition de sous-traitance', 'Subcontracting shipment', 'شحنة مقاولة من الباطن'),
    'supplier_payments': ('Règlement fournisseur', 'Supplier payment', 'دفعة مورد'),
}
MESSAGES = {
    'fr': 'Suppression refusée : ce document ({{document}}) est relié à {{count}} document(s) par la chaîne ({{vers}}). Annulez-le d’abord : l’annulation ferme ces liens.',
    'en': 'Deletion refused: this document ({{document}}) is linked to {{count}} document(s) in the chain ({{vers}}). Cancel it first: cancelling closes these links.',
    'ar': 'تم رفض الحذف: هذا المستند ({{document}}) مرتبط بـ {{count}} مستند(ات) في السلسلة ({{vers}}). قم بإلغائه أولاً: الإلغاء يغلق هذه الروابط.',
}
for i, langue in enumerate(['fr', 'en', 'ar']):
    chemin = f'{APP}/src/i18n/locales/{langue}/errors.json'
    d = json.load(open(chemin, encoding='utf-8'))
    d['chain'] = {
        'deleteRefused': MESSAGES[langue],
        'types': {code: libelles[i] for code, libelles in TYPES.items()},
    }
    open(chemin, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
    print(f'{chemin} : errors:chain ajouté ({len(TYPES)} types)')

# 5 ─ le test
TEST = """import { describe, it, expect, beforeAll } from 'vitest'
import i18n from 'i18next'
import fr from '@/i18n/locales/fr/errors.json'
import { chainDeleteRefusalMessage, errorMessage } from '@/lib/utils'

// Partie 5 (453) : le refus de suppression d'un document relié arrive de la base
// sous la forme { message: 'CHAIN_DELETE_REFUSED', details: '<json>' }. L'écran
// ne doit JAMAIS afficher ce code brut (défaut F4 de la recette : messages SQL bruts).
describe('Partie 5 — refus de suppression d’un document relié', () => {
  beforeAll(async () => {
    await i18n.init({ lng: 'fr', ns: ['errors'], resources: { fr: { errors: fr } } })
  })

  const refus = {
    message: 'CHAIN_DELETE_REFUSED',
    code: '23503',
    details: JSON.stringify({
      type: 'sales_orders', mode: 'document', id: 'x',
      liens: [{ effet: 'stock.reserve', vers: 'stock_reservations', vers_id: 'r1' },
              { effet: 'stock.reserve', vers: 'stock_reservations', vers_id: 'r2' }],
    }),
  }

  it('traduit le refus : nomme le document, compte les liens, nomme les types reliés', () => {
    const m = chainDeleteRefusalMessage(refus)
    expect(m).toContain('Commande client')
    expect(m).toContain('2 document(s)')
    expect(m).toContain('Réservation de stock')
    expect(m).not.toContain('CHAIN_DELETE_REFUSED')
  })

  it('errorMessage() passe par la traduction, y compris pour une instance d’Error', () => {
    const e = Object.assign(new Error('CHAIN_DELETE_REFUSED'), { details: refus.details })
    expect(errorMessage(e)).toContain('Commande client')
    expect(errorMessage(refus)).not.toBe('CHAIN_DELETE_REFUSED')
  })

  it('laisse les autres erreurs inchangées', () => {
    expect(chainDeleteRefusalMessage(new Error('autre'))).toBeNull()
    expect(errorMessage(new Error('autre'))).toBe('autre')
  })

  it('un détail illisible ne fait pas planter : le message reste traduit', () => {
    const m = chainDeleteRefusalMessage({ message: 'CHAIN_DELETE_REFUSED', details: 'pas du json' })
    expect(m).not.toBeNull()
    expect(m).not.toContain('CHAIN_DELETE_REFUSED')
  })
})
"""
open(f'{APP}/src/lib/__tests__/chainDeleteRefusal.test.ts', 'w', encoding='utf-8').write(TEST)
print('src/lib/__tests__/chainDeleteRefusal.test.ts : écrit')
