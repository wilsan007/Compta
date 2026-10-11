-- ═══════════════════════════════════════════════════════════════════════════
-- 756_chain_l16_avoir_fournisseur_tests.sql — L16 · facture fournisseur → avoir
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la facture fournisseur rattache son avoir ; le LIEN est posé ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : avoir introuvable, avoir en brouillon, autre
--        fournisseur, avoir qui annule déjà une autre facture — quatre refus ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit l'avoir depuis la facture, et la
--        facture depuis l'avoir ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
--
-- HARNAIS : les gardes `192` (facture fournisseur approuvée requise ; avoir saisi
-- en brouillon PUIS validé) imposent de MONTER les documents — deux helpers.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql

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

CREATE OR REPLACE FUNCTION _mk_validated_pcn(p_t uuid, p_sup uuid, p_inv uuid, p_total numeric) RETURNS uuid LANGUAGE plpgsql AS $x$
DECLARE v uuid;
BEGIN
  INSERT INTO purchase_credit_notes (tenant_id, supplier_id, date, status, subtotal, vat_total, total, reason, purchase_invoice_id)
    VALUES (p_t, p_sup, '2026-03-02', 'draft', p_total, 0, p_total, 'Retour', p_inv) RETURNING id INTO v;
  INSERT INTO purchase_credit_lines (tenant_id, purchase_credit_id, description, quantity, unit_price, total, vat_total, vat_amount)
    VALUES (p_t, v, 'Ligne', 1, p_total, p_total, 0, 0);
  UPDATE purchase_credit_notes SET status = 'validated' WHERE id = v;
  RETURN v;
END $x$;

SELECT set_config('audit.file', '756', false);
DELETE FROM _audit_results WHERE file = '756';

-- ── T01 — LE NOMINAL : la facture rattache son avoir ───────────────────────
DO $$
DECLARE t uuid; s uuid; f uuid; a uuid; r jsonb; n int; v_inv uuid;
BEGIN
  t := _mk_tenant('T756A');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 756', 'F0756') RETURNING id INTO s;
  f := _mk_approved_pi(t, s, 1200);
  a := _mk_validated_pcn(t, s, f, 1200);

  PERFORM _as_user();
  r := chain_l16_supplier_invoice_credit_note(f, a);

  PERFORM _rec('T01a', 'la facture fournisseur rattache son avoir (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'credit_note_id')::uuid = a, r::text);

  SELECT purchase_invoice_id INTO v_inv FROM purchase_credit_notes WHERE id = a;
  PERFORM _rec('T01b', 'l''avoir porte son purchase_invoice_id (posée par le trigger 192)', v_inv = f,
    'purchase_invoice_id = ' || COALESCE(v_inv::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'purchase_invoices' AND amont_id = f
     AND aval_type = 'purchase_credit_notes' AND aval_id = a
     AND effet = 'purchase.invoice.to_credit_note' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; s uuid; f uuid; a uuid; n int;
BEGIN
  t := _mk_tenant('T756B');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 756 B', 'F0756B') RETURNING id INTO s;
  f := _mk_approved_pi(t, s, 600);
  a := _mk_validated_pcn(t, s, f, 600);
  PERFORM _as_user();
  PERFORM chain_l16_supplier_invoice_credit_note(f, a);
  BEGIN
    PERFORM chain_l16_supplier_invoice_credit_note(f, a);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = f AND aval_id = a
     AND effet = 'purchase.invoice.to_credit_note' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; s uuid; s2 uuid; f uuid; a uuid; a_draft uuid; f2 uuid; f3 uuid;
BEGIN
  t := _mk_tenant('T756C');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES
    (t, 'Fournisseur 756 C', 'F0756C'),
    (t, 'Fournisseur 756 C2', 'F0756C2');
  SELECT id INTO s  FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0756C';
  SELECT id INTO s2 FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0756C2';
  f := _mk_approved_pi(t, s, 100);
  a := _mk_validated_pcn(t, s, f, 100);
  -- avoir en BROUILLON (jamais validé)
  INSERT INTO purchase_credit_notes (tenant_id, supplier_id, date, status, subtotal, vat_total, total, reason, purchase_invoice_id)
    VALUES (t, s, '2026-03-02', 'draft', 100, 0, 100, 'Brouillon', f) RETURNING id INTO a_draft;
  f2 := _mk_approved_pi(t, s2, 100);   -- facture d'un AUTRE fournisseur
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_supplier_invoice_credit_note(f, '00000000-0000-0000-0000-000000000001'::uuid);
    PERFORM _rec('T03a', 'un avoir INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'un avoir INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_supplier_invoice_credit_note(f, a_draft);
    PERFORM _rec('T03b', 'un avoir en BROUILLON est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un avoir en BROUILLON est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_supplier_invoice_credit_note(f2, a);
    PERFORM _rec('T03c', 'un avoir d''un AUTRE fournisseur est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un avoir d''un AUTRE fournisseur est refusé', true, SQLERRM);
  END;
  f3 := _mk_approved_pi(t, s, 100);
  BEGIN
    PERFORM chain_l16_supplier_invoice_credit_note(f3, a);
    PERFORM _rec('T03d', 'un avoir qui annule DÉJÀ une autre facture est refusé', false, 'accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T03d', 'un avoir qui annule DÉJÀ une autre facture est refusé', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; s uuid; f uuid; a uuid; n int;
BEGIN
  t := _mk_tenant('T756D');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 756 D', 'F0756D') RETURNING id INTO s;
  f := _mk_approved_pi(t, s, 240);
  a := _mk_validated_pcn(t, s, f, 240);
  PERFORM _as_user();
  PERFORM chain_l16_supplier_invoice_credit_note(f, a);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'purchase_invoices', f, 'aval', 5, false)
   WHERE type = 'purchase_credit_notes' AND id = a;
  PERFORM _rec('T04a', 'depuis la FACTURE, la frise voit l''AVOIR', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'purchase_credit_notes', a, 'amont', 5, false)
   WHERE type = 'purchase_invoices' AND id = f;
  PERFORM _rec('T04b', 'depuis l''AVOIR, la frise voit la FACTURE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; sa uuid; fa uuid; aa uuid; n int;
BEGIN
  ta := _mk_tenant('T756E1');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (ta, 'Fournisseur E1', 'FE1') RETURNING id INTO sa;
  fa := _mk_approved_pi(ta, sa, 120);
  aa := _mk_validated_pcn(ta, sa, fa, 120);
  PERFORM _as_user();
  PERFORM chain_l16_supplier_invoice_credit_note(fa, aa);

  RESET ROLE;
  tb := _mk_tenant('T756E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_supplier_invoice_credit_note(fa, aa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher l''avoir d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher l''avoir d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'purchase_invoices' AND amont_id = fa AND aval_type = 'purchase_credit_notes';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = fa AND aval_id = aa AND effet = 'purchase.invoice.to_credit_note' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('756');
