-- ============================================================
-- 313_chain_effects_contract.sql — L7 : LES CONTRATS D'EFFET DÉCLARÉS
--
-- Source : doc/audit/PLAN-IMPLEMENTATION-CHAINAGES-2026-09-24.md, doctrine
-- **M-05** (« chaque type de document déclare son effet, y compris aucun ») et
-- lot **L7** (« contrats d'effet déclarés, 0 % → 100 % »). Le socle (252) a la
-- table et la règle ; la **porte G2** (`ci/check_effects_contract.sql`) a le
-- contrôle ; il manquait les **déclarations**.
--
-- CE QUE CE FICHIER CHANGE, ET C'EST MESURÉ. Avant lui, sur une base qui vient
-- de jouer la batterie : **1 132 traces `tolere` pour 1 117 `applique`** — c'est
-- le défaut que la VAGUE-L1 §4 avait annoncé : chaque exécution d'un effet non
-- déclaré écrit **deux** traces, `tolere` (le contrat manque) PUIS `applique`
-- (l'effet est produit quand même, le mode par défaut étant `observe`). Après
-- lui : une seule trace `applique` par exécution, et `chain_autorise` rend
-- **vrai** pour les 14 effets. La suite 313 le mesure effet par effet.
--
-- LES 14 CONTRATS, ET COMMENT CHAQUE DRAPEAU A ÉTÉ MESURÉ. Les couples
-- (document, événement, effet) ne sont pas choisis : ils sont **extraits du
-- code** (les appels à `chain_avant`, plus les trois effets des quatre maillons
-- réécrits par la 311 qui n'appellent que `link_documents` — leurs tables
-- document/e´vénement viennent de la 311 §6.1). Les drapeaux viennent de la
-- mesure des **écritures réelles** de chaque maillon métier (`pg_proc.prosrc`,
-- relevé des tables cibles des `INSERT` / `UPDATE` / `DELETE`) :
--
--   invoices/validated/sale.invoice.generated_entry       → create_journal_on_invoice_validate : journal_entries, journal_lines (code « VT » littéral)
--   credit_notes/validated/sale.credit_note.generated_entry → credit_note_guard : journal_entries, journal_lines (« VT »)
--   supplier_payments/recorded/purchase.payment.generated_entry → create_journal_on_supplier_payment : journal_entries, journal_lines (code calculé, non littéral)
--   customer_payments/recorded/sale.payment.generated_entry → create_journal_on_customer_payment : journal_entries, journal_lines (code calculé)
--   bank_accounts/created/treasury.bank_account.journal    → bank_account_ensure_journal : journals
--   bank_accounts/created/treasury.bank_account.account    → bank_account_ensure_journal : journals (+ le compte est un référentiel)
--   sales_orders/confirmed/sale.order.reserved             → reserve_stock_on_sales_order_confirm : stock_reservations, stock_quantities
--   delivery_notes/shipped/sale.delivery.stock_out         → create_stock_out_on_delivery : stock_movements
--   st_shipments/shipped/subcontracting.shipment.stock_out → st_shipment_stock_out : stock_movements, stock_quantities
--   st_receipts/received/subcontracting.receipt.stock_in   → st_receipt_stock_in : stock_movements, stock_quantities
--   pos_sessions/closed/pos.session.closure                → post_pos_session_on_close_multi : journal_entries, journal_lines, stock_movements
--   bank_transactions/reconciled/treasury.bank_transaction.reconciled → auto_reconcile_by_score : bank_transactions, customer_payments
--   manufacturing_orders/completed/production.order.generated_entry → create_stock_on_manufacturing_complete : journal_entries, journal_lines
--   manufacturing_orders/completed/production.order.stock_in       → même maillon : stock_movements
--
-- CE QUI AGIT, ET CE QUI DÉCLARE SEULEMENT — mesuré, et écrit pour que personne
-- ne s'y trompe : **seul `actif` change un comportement** (`chain_autorise` le
-- lit, et c'est lui qui fait disparaître les traces `tolere`). Les autres
-- drapeaux (`ecrit_comptable`, `journal_code`, `touche_stock`, `touche_paie`,
-- `reversible`, `obligatoire`) ne sont lus par **aucun** code aujourd'hui —
-- vérifié : aucune fonction de `public` ne les mentionne. Ils **déclarent** ce
-- que la porte G2 confronte au réel, et ce que les écrans du lot **L5**
-- publieront. Un drapeau sans lecteur ne protège rien : c'est dit, pas caché.
--
-- CE QUE CE FICHIER NE FAIT PAS
--   * il ne pose pas `chain_avant` sur les maillons qui ne l'ont pas encore
--     (les trois effets sans `chain_avant` sont ceux dont les maillons se
--     reproduisent : c'est le lot **L3**, et le cycle de vie de la **312** l'a
--     rendu possible) ;
--   * il ne règle pas le mode d'application : `observe` reste le défaut, et
--     c'est ce qui fait qu'un effet déclaré est appliqué sans bruit ;
--   * il ne touche à aucun maillon : **des lignes de données**, rien d'autre.
--
-- REJOUABLE. `ON CONFLICT` sur la clé de la 252 (l'index unique sur
-- `COALESCE(tenant_id, …)`, document, événement, effet) : un second passage
-- RÉALIGNE le contrat standard au lieu de le dupliquer. Une ligne de **société**
-- n'est jamais touchée — elle porte une autre clé, et c'est elle qui l'emporte
-- (mesuré par la 252, T06).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Les quatorze contrats standard (tenant_id NULL = livrés avec le produit)
--    Chaque ligne : document, événement, effet, et les drapeaux MESURÉS.
--    `reversible = false` n'est pas un aveu : c'est une déclaration, avec son
--    motif en note — le point 4 de la définition de « terminé » (§4.1 du plan)
--    demande exactement cela quand aucun `chain_*_reverse` n'existe.
-- ─────────────────────────────────────────────────────────────
INSERT INTO document_effects (tenant_id, document_type, evenement, effet,
                              ecrit_comptable, journal_code, touche_stock, touche_paie,
                              reversible, obligatoire, actif, note)
VALUES
  -- Ventes → comptabilité (310)
  (NULL, 'invoices', 'validated', 'sale.invoice.generated_entry',
   true, 'VT', false, false, true, true, true,
   'L7/310 : create_journal_on_invoice_validate écrit journal_entries + journal_lines (mesuré). Réversible par extourne ou avoir (M-01).'),
  (NULL, 'credit_notes', 'validated', 'sale.credit_note.generated_entry',
   true, 'VT', false, false, true, true, true,
   'L7/310 : credit_note_guard écrit journal_entries + journal_lines (mesuré).'),
  (NULL, 'supplier_payments', 'recorded', 'purchase.payment.generated_entry',
   true, NULL, false, false, true, true, true,
   'L7/310 : create_journal_on_supplier_payment écrit journal_entries + journal_lines (mesuré) ; le code du journal est calculé par le maillon, pas littéral.'),
  (NULL, 'customer_payments', 'recorded', 'sale.payment.generated_entry',
   true, NULL, false, false, true, true, true,
   'L7/310 : create_journal_on_customer_payment écrit journal_entries + journal_lines (mesuré) ; code de journal calculé.'),
  -- Trésorerie : le référentiel (310) — une création de référentiel ne s'extourne pas, elle se désactive
  (NULL, 'bank_accounts', 'created', 'treasury.bank_account.journal',
   false, NULL, false, false, false, false, true,
   'L7/310 : bank_account_ensure_journal écrit journals (mesuré) — configuration, pas une écriture. Non réversible : un journal se désactive, il ne s''extourne pas.'),
  (NULL, 'bank_accounts', 'created', 'treasury.bank_account.account',
   false, NULL, false, false, false, false, true,
   'L7/310 : même maillon ; le compte de trésorerie est un référentiel. Non réversible (désactivation).'),
  -- Ventes → stock (311, par ligne)
  (NULL, 'sales_orders', 'confirmed', 'sale.order.reserved',
   false, NULL, true, false, true, false, true,
   'L7/311 : reserve_stock_on_sales_order_confirm écrit stock_reservations + stock_quantities (mesuré). Réversible : l''annulation libère la réservation (mesuré par la 230 T04 et la 312 C12).'),
  (NULL, 'delivery_notes', 'shipped', 'sale.delivery.stock_out',
   false, NULL, true, false, true, false, true,
   'L7/311 : create_stock_out_on_delivery écrit stock_movements (mesuré). M-06 : réexpédition refusée sans contre-passation — la réversibilité passe par l''extourne du mouvement.'),
  -- Sous-traitance (311, par ligne)
  (NULL, 'st_shipments', 'shipped', 'subcontracting.shipment.stock_out',
   false, NULL, true, false, true, false, true,
   'L7/311 : st_shipment_stock_out écrit stock_movements + stock_quantities (mesuré).'),
  (NULL, 'st_receipts', 'received', 'subcontracting.receipt.stock_in',
   false, NULL, true, false, true, false, true,
   'L7/311 : st_receipt_stock_in écrit stock_movements + stock_quantities (mesuré).'),
  -- Caisse (311) — la caisse est inaltérable (W2/W3) : déclaré non réversible
  (NULL, 'pos_sessions', 'closed', 'pos.session.closure',
   true, NULL, true, false, false, true, true,
   'L7/311 : post_pos_session_on_close_multi écrit journal_entries + journal_lines + stock_movements (mesuré). Non réversible : la caisse est inaltérable (vagues W2/W3) — une clôture se corrige par une écriture de régularisation, elle ne se défait pas.'),
  -- Rapprochement bancaire (311)
  (NULL, 'bank_transactions', 'reconciled', 'treasury.bank_transaction.reconciled',
   false, NULL, false, false, true, false, true,
   'L7/311 : auto_reconcile_by_score écrit bank_transactions + customer_payments (mesuré). Réversible par dé-lettrage (M-03).'),
  -- Production (311)
  (NULL, 'manufacturing_orders', 'completed', 'production.order.generated_entry',
   true, NULL, false, false, true, true, true,
   'L7/311 : create_stock_on_manufacturing_complete écrit journal_entries + journal_lines (mesuré).'),
  (NULL, 'manufacturing_orders', 'completed', 'production.order.stock_in',
   false, NULL, true, false, true, false, true,
   'L7/311 : même maillon, écrit stock_movements (mesuré).')
ON CONFLICT (COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
             document_type, evenement, effet)
DO UPDATE SET
  ecrit_comptable = EXCLUDED.ecrit_comptable,
  journal_code    = EXCLUDED.journal_code,
  touche_stock    = EXCLUDED.touche_stock,
  touche_paie     = EXCLUDED.touche_paie,
  reversible      = EXCLUDED.reversible,
  obligatoire     = EXCLUDED.obligatoire,
  actif           = EXCLUDED.actif,
  note            = EXCLUDED.note;


-- ─────────────────────────────────────────────────────────────
-- 2. Ce que la migration constate (un compte, jamais un silence)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_standard int; v_societe int; v_ecrit int; v_stock int; v_non_reversible int;
BEGIN
  SELECT count(*) INTO v_standard FROM document_effects WHERE tenant_id IS NULL;
  SELECT count(*) INTO v_societe  FROM document_effects WHERE tenant_id IS NOT NULL;
  SELECT count(*) FILTER (WHERE ecrit_comptable), count(*) FILTER (WHERE touche_stock),
         count(*) FILTER (WHERE NOT reversible)
    INTO v_ecrit, v_stock, v_non_reversible
  FROM document_effects WHERE tenant_id IS NULL;

  RAISE NOTICE 'Contrats d''effet standard déclarés : % (dont % qui écrivent au grand livre, % qui touchent le stock, % déclarés non réversibles). Lignes de société héritées : %.',
    v_standard, v_ecrit, v_stock, v_non_reversible, v_societe;

  IF v_standard < 14 THEN
    RAISE EXCEPTION 'Contrats d''effet : % contrat(s) standard en base après la migration, 14 attendus — la porte G2 (ci/check_effects_contract.sql) mesurerait un écart.', v_standard;
  END IF;
END $$;

