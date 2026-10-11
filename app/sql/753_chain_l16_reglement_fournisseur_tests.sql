-- ═══════════════════════════════════════════════════════════════════════════
-- 753_chain_l16_reglement_fournisseur_tests.sql — L16 · facture fournisseur → règlement
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la facture fournisseur rattache son règlement ; la colonne
--        `supplier_payments.purchase_invoice_id` est posée ; le LIEN est posé ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : facture annulée, règlement annulé, autre fournisseur,
--        règlement déjà affecté — quatre refus, quatre raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit le règlement depuis la facture, et
--        la facture depuis le règlement ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
--
-- D2 (concurrence), D3 (panne partielle), D5 (réouverture) restent hors de
-- portée d'une suite SQL d'un seul processus ; D6 tenu par construction ; D7
-- sans objet sur une chaîne de deux pièces.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql

-- Une facture fournisseur APPROUVEE (l'approbation exige une ligne, 192 ; le
-- reglement exige une facture approuvee, 354).
CREATE OR REPLACE FUNCTION _mk_approved_pi(p_t uuid, p_sup uuid, p_total numeric) RETURNS uuid LANGUAGE plpgsql AS $x$
DECLARE v uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, supplier_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (p_t, p_sup, '2026-03-01', '2026-04-01', 'sent', p_total, 0, p_total) RETURNING id INTO v;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity, unit_price, total, vat_amount)
    VALUES (p_t, v, 'Ligne', 1, p_total, p_total, 0);
  UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = v;
  RETURN v;
END $x$;
SELECT set_config('audit.file', '753', false);
DELETE FROM _audit_results WHERE file = '753';

-- ── T01 — LE NOMINAL : la facture rattache son règlement ───────────────────
DO $$
DECLARE t uuid; s uuid; f uuid; p uuid; r jsonb; n int; v_inv uuid;
BEGIN
  t := _mk_tenant('T753A');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 753', 'F0753') RETURNING id INTO s;
  f := _mk_approved_pi(t, s, 1200);
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-753-1', s, '2026-03-10', 1200, 'transfer', 'recorded') RETURNING id INTO p;

  PERFORM _as_user();
  r := chain_l16_supplier_invoice_payment(f, p);

  PERFORM _rec('T01a', 'la facture fournisseur rattache son règlement (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'payment_id')::uuid = p, r::text);

  SELECT purchase_invoice_id INTO v_inv FROM supplier_payments WHERE id = p;
  PERFORM _rec('T01b', 'le règlement porte désormais purchase_invoice_id (la colonne que personne n''écrivait)',
    v_inv = f, 'purchase_invoice_id = ' || COALESCE(v_inv::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'purchase_invoices' AND amont_id = f
     AND aval_type = 'supplier_payments' AND aval_id = p
     AND effet = 'purchase.invoice.to_payment' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; s uuid; f uuid; p uuid; n int;
BEGIN
  t := _mk_tenant('T753B');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 753 B', 'F0753B') RETURNING id INTO s;
  f := _mk_approved_pi(t, s, 600);
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-753-B', s, '2026-03-11', 600, 'transfer', 'recorded') RETURNING id INTO p;
  PERFORM _as_user();
  PERFORM chain_l16_supplier_invoice_payment(f, p);
  BEGIN
    PERFORM chain_l16_supplier_invoice_payment(f, p);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = f AND aval_id = p
     AND effet = 'purchase.invoice.to_payment' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; s uuid; s2 uuid; f uuid; p uuid; f_cancel uuid; p_cancel uuid; p_other uuid; f2 uuid;
BEGIN
  t := _mk_tenant('T753C');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES
    (t, 'Fournisseur 753 C', 'F0753C'),
    (t, 'Fournisseur 753 C2', 'F0753C2');
  SELECT id INTO s  FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0753C';
  SELECT id INTO s2 FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0753C2';
  f := _mk_approved_pi(t, s, 100);
  f2 := _mk_approved_pi(t, s, 100);
  f_cancel := _mk_approved_pi(t, s, 100);
  UPDATE purchase_invoices SET status = 'cancelled' WHERE id = f_cancel;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-753-C', s, '2026-03-10', 100, 'transfer', 'recorded') RETURNING id INTO p;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-753-Cc', s, '2026-03-10', 100, 'transfer', 'cancelled') RETURNING id INTO p_cancel;
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-753-Co', s2, '2026-03-10', 100, 'transfer', 'recorded') RETURNING id INTO p_other;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_supplier_invoice_payment(f_cancel, p);
    PERFORM _rec('T03a', 'une facture ANNULÉE est refusée, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03a', 'une facture ANNULÉE est refusée, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_supplier_invoice_payment(f, p_cancel);
    PERFORM _rec('T03b', 'un règlement ANNULÉ est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un règlement ANNULÉ est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_supplier_invoice_payment(f, p_other);
    PERFORM _rec('T03c', 'un règlement d''un AUTRE fournisseur est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un règlement d''un AUTRE fournisseur est refusé', true, SQLERRM);
  END;
  PERFORM chain_l16_supplier_invoice_payment(f, p);
  BEGIN
    PERFORM chain_l16_supplier_invoice_payment(f2, p);
    PERFORM _rec('T03d', 'un règlement DÉJÀ AFFECTÉ à une autre facture est refusé', false, 'accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T03d', 'un règlement DÉJÀ AFFECTÉ à une autre facture est refusé', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; s uuid; f uuid; p uuid; n int;
BEGIN
  t := _mk_tenant('T753D');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 753 D', 'F0753D') RETURNING id INTO s;
  f := _mk_approved_pi(t, s, 240);
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (t, 'RF-753-D', s, '2026-03-12', 240, 'transfer', 'recorded') RETURNING id INTO p;
  PERFORM _as_user();
  PERFORM chain_l16_supplier_invoice_payment(f, p);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'purchase_invoices', f, 'aval', 5, false)
   WHERE type = 'supplier_payments' AND id = p;
  PERFORM _rec('T04a', 'depuis la FACTURE, la frise voit le RÈGLEMENT', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'supplier_payments', p, 'amont', 5, false)
   WHERE type = 'purchase_invoices' AND id = f;
  PERFORM _rec('T04b', 'depuis le RÈGLEMENT, la frise voit la FACTURE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; sa uuid; fa uuid; pa uuid; n int;
BEGIN
  ta := _mk_tenant('T753E1');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (ta, 'Fournisseur E1', 'FE1') RETURNING id INTO sa;
  fa := _mk_approved_pi(ta, sa, 120);
  INSERT INTO supplier_payments (tenant_id, number, supplier_id, payment_date, amount, method, status)
    VALUES (ta, 'RF-753-E1', sa, '2026-03-13', 120, 'transfer', 'recorded') RETURNING id INTO pa;
  PERFORM _as_user();
  PERFORM chain_l16_supplier_invoice_payment(fa, pa);

  RESET ROLE;
  tb := _mk_tenant('T753E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_supplier_invoice_payment(fa, pa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher le règlement d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher le règlement d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'purchase_invoices' AND amont_id = fa AND aval_type = 'supplier_payments';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = fa AND aval_id = pa AND effet = 'purchase.invoice.to_payment' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('753');
