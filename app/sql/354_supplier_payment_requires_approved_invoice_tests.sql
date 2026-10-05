-- ============================================================
-- 354_supplier_payment_requires_approved_invoice_tests.sql — partie 2 (défauts métier)
--
-- Défaut mesuré le 05/10/2026 sur le chemin de l'écran : un règlement fournisseur
-- imputé à une facture d'achat NON approuvée (`BROUILLON-ACH-…`, `pending`) était
-- accepté. La facture passait à `paid`, reste dû 0, sans écriture d'achat ; le
-- règlement, lui, était comptabilisé (D 401 / C 512) : le 401 débité sans dette
-- constatée, et l'approbation (271, M9) contournée par le paiement.
--
--   T01  régler une facture non approuvée est refusé, et rien n'est écrit
--   T02  régler une facture rejetée est refusé
--   T03  imputer APRÈS COUP un règlement libre à une facture non approuvée est refusé
--   T04  non-régression : une facture approuvée se règle, 401 soldé et lettré
--   T05  non-régression : un règlement sans facture reste possible
--   T06  les lignes déjà dans cet état sont LISTÉES, aucune n'est supprimée
--   T07  les approuver les régularise : écriture d'achat, 401 soldé et lettré
--   T08  un règlement annulé peut rester rattaché à une facture non approuvée
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '354', false);
DELETE FROM _audit_results WHERE file = '354';

CREATE OR REPLACE FUNCTION _mk_purchase_354(p_t uuid, p_s uuid, p_approve boolean)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pi uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date, status, subtotal, vat_total, total, amount_paid, amount_due, approval_status)
  VALUES (p_t, 'FOURN-' || left(uuid_generate_v4()::text, 8), p_s, 'Fournisseur', '2026-03-01', '2026-03-31', 'draft', 1000, 200, 1200, 0, 1200, 'pending')
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  VALUES (p_t, pi, 'Achat', 1, 1000, 20, 'FR20', 1000, 200, 0);
  IF p_approve THEN UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi; END IF;
  RETURN pi;
END $$;

-- Solde et lettrage du 401 d'une société : (solde, lignes, lignes lettrées)
CREATE OR REPLACE FUNCTION _s401_354(p_t uuid, OUT solde numeric, OUT lignes int, OUT lettrees int)
LANGUAGE sql AS $$
  SELECT COALESCE(sum(jl.debit - jl.credit), 0), count(*)::int, count(jl.lettrage_code)::int
  FROM journal_lines jl JOIN journal_entries e ON e.id = jl.journal_id AND e.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = p_t AND e.status = 'posted' AND jl.account_code LIKE '401%'
$$;

-- T01 — le défaut lui-même
DO $$
DECLARE t uuid := _mk_tenant('T01'); s uuid; b uuid; pi uuid; refus text := NULL; r record; n_pay int; n_bq int; s401 record;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur T01') RETURNING id INTO s;
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque', 'chequing') RETURNING id INTO b;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase_354(t, s, false);
    BEGIN
      INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method, bank_account_id, status)
      VALUES (t, 'DEC-T01', s, pi, '2026-03-05', 1200, 'transfer', b, 'recorded');
    EXCEPTION WHEN check_violation THEN refus := SQLERRM; END;
    SELECT status, approval_status, amount_due, amount_paid INTO r FROM purchase_invoices WHERE id = pi;
    SELECT count(*) INTO n_pay FROM supplier_payments WHERE tenant_id = t;
    SELECT count(*) INTO n_bq FROM journal_entries WHERE tenant_id = t AND journal_code = 'BQ';
    s401 := _s401_354(t);
    PERFORM _rec('T01', 'régler une facture d''achat non approuvée est refusé (23514) : facture intacte, aucun règlement, aucune écriture, 401 à 0',
      refus IS NOT NULL AND r.status = 'draft' AND r.approval_status = 'pending' AND r.amount_due = 1200
        AND n_pay = 0 AND n_bq = 0 AND s401.solde = 0,
      format('refus=%s statut=%s approbation=%s reste=%s règlements=%s écritures BQ=%s solde 401=%s',
             COALESCE(refus, '∅'), r.status, r.approval_status, r.amount_due, n_pay, n_bq, s401.solde));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T01', 'régler une facture d''achat non approuvée est refusé', false, SQLERRM); END;
END $$;

-- T02 — une facture rejetée ne se règle pas davantage
DO $$
DECLARE t uuid := _mk_tenant('T02'); s uuid; b uuid; pi uuid; refus text := NULL; r record;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur T02') RETURNING id INTO s;
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque', 'chequing') RETURNING id INTO b;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase_354(t, s, false);
    UPDATE purchase_invoices SET approval_status = 'rejected' WHERE id = pi;
    BEGIN
      INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method, bank_account_id, status)
      VALUES (t, 'DEC-T02', s, pi, '2026-03-05', 600, 'transfer', b, 'recorded');
    EXCEPTION WHEN check_violation THEN refus := SQLERRM; END;
    SELECT status, approval_status, amount_due INTO r FROM purchase_invoices WHERE id = pi;
    PERFORM _rec('T02', 'régler (même en partie) une facture d''achat rejetée est refusé, la facture reste rejetée et due',
      refus IS NOT NULL AND r.approval_status = 'rejected' AND r.amount_due = 1200 AND r.status <> 'paid',
      format('refus=%s statut=%s approbation=%s reste=%s', COALESCE(refus, '∅'), r.status, r.approval_status, r.amount_due));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T02', 'régler une facture d''achat rejetée est refusé', false, SQLERRM); END;
END $$;

-- T03 — la porte de derrière : créer un règlement libre, puis l'imputer par UPDATE
DO $$
DECLARE t uuid := _mk_tenant('T03'); s uuid; b uuid; pi uuid; p uuid; refus text := NULL; r record; lie uuid;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur T03') RETURNING id INTO s;
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque', 'chequing') RETURNING id INTO b;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase_354(t, s, false);
    INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, bank_account_id, status)
    VALUES (t, 'DEC-T03', s, '2026-03-05', 1200, 'transfer', b, 'recorded') RETURNING id INTO p;
    BEGIN
      UPDATE supplier_payments SET purchase_invoice_id = pi WHERE id = p;
    EXCEPTION WHEN check_violation THEN refus := SQLERRM; END;
    SELECT status, amount_due INTO r FROM purchase_invoices WHERE id = pi;
    SELECT purchase_invoice_id INTO lie FROM supplier_payments WHERE id = p;
    PERFORM _rec('T03', 'imputer après coup un règlement libre à une facture non approuvée est refusé',
      refus IS NOT NULL AND lie IS NULL AND r.status = 'draft' AND r.amount_due = 1200,
      format('refus=%s règlement imputé=%s statut=%s reste=%s', COALESCE(refus, '∅'), lie IS NOT NULL, r.status, r.amount_due));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T03', 'imputer après coup un règlement libre à une facture non approuvée est refusé', false, SQLERRM); END;
END $$;

-- T04 — non-régression : le chemin normal
DO $$
DECLARE t uuid := _mk_tenant('T04'); s uuid; b uuid; pi uuid; r record; s401 record;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur T04') RETURNING id INTO s;
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque', 'chequing') RETURNING id INTO b;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase_354(t, s, true);
    INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method, bank_account_id, status)
    VALUES (t, 'DEC-T04', s, pi, '2026-03-05', 1200, 'transfer', b, 'recorded');
    SELECT status, amount_due, transferred_entry_id IS NOT NULL AS ecrite INTO r FROM purchase_invoices WHERE id = pi;
    s401 := _s401_354(t);
    PERFORM _rec('T04', 'non-régression : une facture approuvée se règle — payée, 401 soldé, ses 2 lignes lettrées',
      r.status = 'paid' AND r.amount_due = 0 AND r.ecrite AND s401.solde = 0 AND s401.lignes = 2 AND s401.lettrees = 2,
      format('statut=%s reste=%s écriture d''achat=%s 401 : solde=%s lignes=%s lettrées=%s', r.status, r.amount_due, r.ecrite, s401.solde, s401.lignes, s401.lettrees));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T04', 'non-régression : une facture approuvée se règle', false, SQLERRM); END;
END $$;

-- T05 — non-régression : un règlement sans facture (acompte, règlement à imputer)
DO $$
DECLARE t uuid := _mk_tenant('T05'); s uuid; b uuid; pi uuid; n int; r record;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur T05') RETURNING id INTO s;
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque', 'chequing') RETURNING id INTO b;
  PERFORM _as_user();
  BEGIN
    pi := _mk_purchase_354(t, s, false);
    INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, bank_account_id, status)
    VALUES (t, 'DEC-T05', s, '2026-03-05', 500, 'transfer', b, 'recorded');
    SELECT count(*) INTO n FROM journal_entries WHERE tenant_id = t AND journal_code = 'BQ' AND status = 'posted';
    SELECT status, amount_due INTO r FROM purchase_invoices WHERE id = pi;
    PERFORM _rec('T05', 'non-régression : un règlement sans facture reste accepté et comptabilisé, et ne touche à aucune facture',
      n = 1 AND r.status = 'draft' AND r.amount_due = 1200,
      format('écritures BQ=%s facture voisine : statut=%s reste=%s', n, r.status, r.amount_due));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T05', 'non-régression : un règlement sans facture reste accepté', false, SQLERRM); END;
END $$;

-- T06 / T07 — les lignes nées AVANT la garde. L'état est fabriqué comme il est né :
-- par le règlement lui-même, la garde éteinte le temps de l'insertion (propriétaire
-- de la table seulement ; avant la 354 il n'y a rien à éteindre).
DO $$
DECLARE t uuid := _mk_tenant('T06'); s uuid; b uuid; pi uuid; garde boolean;
        n_liste int := -1; n_pay int; r record; s401 record; v_err text := NULL;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur T06') RETURNING id INTO s;
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque', 'chequing') RETURNING id INTO b;
  pi := _mk_purchase_354(t, s, false);
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'supplier_payments'::regclass AND tgname = 'tg_supplier_payment_invoice_guard') INTO garde;
  IF garde THEN ALTER TABLE supplier_payments DISABLE TRIGGER tg_supplier_payment_invoice_guard; END IF;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method, bank_account_id, status)
  VALUES (t, 'DEC-T06', s, pi, '2026-03-05', 1200, 'transfer', b, 'recorded');
  IF garde THEN ALTER TABLE supplier_payments ENABLE TRIGGER tg_supplier_payment_invoice_guard; END IF;
  PERFORM _as_user();

  BEGIN
    EXECUTE 'SELECT count(*) FROM purchase_invoices_settled_unapproved() WHERE purchase_invoice_id = $1 AND amount_settled = 1200 AND payments = 1'
      INTO n_liste USING pi;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  SELECT count(*) INTO n_pay FROM supplier_payments WHERE tenant_id = t AND purchase_invoice_id = pi AND status = 'recorded';
  SELECT status, approval_status INTO r FROM purchase_invoices WHERE id = pi;
  PERFORM _rec('T06', 'une facture réglée sans approbation (née avant la garde) est listée par purchase_invoices_settled_unapproved(), et rien n''est supprimé',
    n_liste = 1 AND n_pay = 1 AND r.approval_status = 'pending',
    format('listée=%s règlements conservés=%s statut=%s approbation=%s%s', n_liste, n_pay, r.status, r.approval_status, COALESCE(' erreur=' || v_err, '')));

  BEGIN
    UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
    SELECT status, amount_due, transferred_entry_id IS NOT NULL AS ecrite INTO r FROM purchase_invoices WHERE id = pi;
    s401 := _s401_354(t);
    n_liste := -1;
    BEGIN
      EXECUTE 'SELECT count(*) FROM purchase_invoices_settled_unapproved() WHERE purchase_invoice_id = $1' INTO n_liste USING pi;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    PERFORM _rec('T07', 'l''approuver la régularise : écriture d''achat passée, 401 soldé et lettré, elle sort de la liste',
      r.status = 'paid' AND r.amount_due = 0 AND r.ecrite AND s401.solde = 0 AND s401.lettrees = 2 AND n_liste = 0,
      format('statut=%s reste=%s écriture d''achat=%s 401 : solde=%s lettrées=%s encore listée=%s', r.status, r.amount_due, r.ecrite, s401.solde, s401.lettrees, n_liste));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T07', 'l''approuver la régularise', false, SQLERRM); END;
END $$;

-- T08 — annuler un règlement hérité ne doit pas être bloqué par la garde
DO $$
DECLARE t uuid := _mk_tenant('T08'); s uuid; b uuid; pi uuid; p uuid; garde boolean; r record; st text;
BEGIN
  INSERT INTO suppliers (tenant_id, name) VALUES (t, 'Fournisseur T08') RETURNING id INTO s;
  INSERT INTO bank_accounts (tenant_id, name, type) VALUES (t, 'Banque', 'chequing') RETURNING id INTO b;
  pi := _mk_purchase_354(t, s, false);
  SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'supplier_payments'::regclass AND tgname = 'tg_supplier_payment_invoice_guard') INTO garde;
  IF garde THEN ALTER TABLE supplier_payments DISABLE TRIGGER tg_supplier_payment_invoice_guard; END IF;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, purchase_invoice_id, payment_date, amount, method, bank_account_id, status)
  VALUES (t, 'DEC-T08', s, pi, '2026-03-05', 1200, 'transfer', b, 'recorded') RETURNING id INTO p;
  IF garde THEN ALTER TABLE supplier_payments ENABLE TRIGGER tg_supplier_payment_invoice_guard; END IF;
  PERFORM _as_user();
  BEGIN
    UPDATE supplier_payments SET status = 'cancelled' WHERE id = p;
    SELECT status INTO st FROM supplier_payments WHERE id = p;
    SELECT status, amount_due, approval_status INTO r FROM purchase_invoices WHERE id = pi;
    PERFORM _rec('T08', 'un règlement hérité s''annule : la facture non approuvée redevient due, elle n''est plus « payée »',
      st = 'cancelled' AND r.amount_due = 1200 AND r.status <> 'paid' AND r.approval_status = 'pending',
      format('règlement=%s facture : statut=%s reste=%s approbation=%s', st, r.status, r.amount_due, r.approval_status));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('T08', 'un règlement hérité s''annule', false, SQLERRM); END;
END $$;

DROP FUNCTION _mk_purchase_354(uuid, uuid, boolean);
DROP FUNCTION _s401_354(uuid);

SELECT _audit_assert('354');
