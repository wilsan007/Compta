-- ═══════════════════════════════════════════════════════════════════════════
-- 754_chain_l16_facture_avoir_tests.sql — L16 · facture → avoir
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la facture rattache son avoir ; le LIEN est posé
--        (effet `sale.invoice.to_credit_note`) ; l'avoir porte `invoice_id` ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : avoir introuvable, avoir en brouillon, autre client,
--        avoir qui annule déjà une autre facture — quatre refus, quatre raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit l'avoir depuis la facture, et la
--        facture depuis l'avoir ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
--
-- HARNAIS : les gardes `190` (une facture se valide avec au moins une ligne) et
-- `213` (un avoir se crée en brouillon PUIS se valide, contre une facture validée)
-- imposent de MONTER les documents — deux helpers ci-dessous. C'est le harnais
-- qui manquait au premier essai (numéro `498` rendu).
--
-- D2 (concurrence), D3 (panne partielle), D5 (réouverture) restent hors de
-- portée d'une suite SQL d'un seul processus ; D6 tenu par construction ; D7
-- sans objet sur une chaîne de deux pièces.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql

-- Une facture CLIENT validée (190 exige une ligne : « Facture sans ligne : rien à valider »).
CREATE OR REPLACE FUNCTION _mk_validated_invoice(p_t uuid, p_c uuid, p_total numeric) RETURNS uuid LANGUAGE plpgsql AS $x$
DECLARE v uuid;
BEGIN
  INSERT INTO invoices (tenant_id, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (p_t, p_c, '2026-03-01', '2026-04-01', 'draft', p_total, 0, p_total) RETURNING id INTO v;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, total, vat_total)
    VALUES (p_t, v, 'Ligne', 1, p_total, p_total, 0);
  UPDATE invoices SET validation_status = 'validated', status = 'sent' WHERE id = v;
  RETURN v;
END $x$;

-- Un avoir CLIENT validé, rattaché à sa facture (213 : brouillon PUIS validé).
CREATE OR REPLACE FUNCTION _mk_validated_credit_note(p_t uuid, p_c uuid, p_inv uuid, p_total numeric) RETURNS uuid LANGUAGE plpgsql AS $x$
DECLARE v uuid;
BEGIN
  INSERT INTO credit_notes (tenant_id, customer_id, date, status, subtotal, vat_total, total, reason, source_invoice_id, invoice_id)
    VALUES (p_t, p_c, '2026-03-02', 'draft', p_total, 0, p_total, 'Retour', p_inv, p_inv) RETURNING id INTO v;
  INSERT INTO credit_note_lines (tenant_id, credit_note_id, description, quantity, unit_price, total, vat_amount)
    VALUES (p_t, v, 'Ligne', 1, p_total, p_total, 0);
  UPDATE credit_notes SET status = 'validated' WHERE id = v;
  RETURN v;
END $x$;

SELECT set_config('audit.file', '754', false);
DELETE FROM _audit_results WHERE file = '754';

-- ── T01 — LE NOMINAL : la facture rattache son avoir ───────────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; a uuid; r jsonb; n int; v_inv uuid;
BEGIN
  t := _mk_tenant('T754A');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 754', 'C0754') RETURNING id INTO c;
  f := _mk_validated_invoice(t, c, 1200);
  a := _mk_validated_credit_note(t, c, f, 1200);

  PERFORM _as_user();
  r := chain_l16_invoice_credit_note(f, a);

  PERFORM _rec('T01a', 'la facture rattache son avoir (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'credit_note_id')::uuid = a, r::text);

  SELECT invoice_id INTO v_inv FROM credit_notes WHERE id = a;
  PERFORM _rec('T01b', 'l''avoir porte son invoice_id (posée par le trigger 213)', v_inv = f,
    'invoice_id = ' || COALESCE(v_inv::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'invoices' AND amont_id = f
     AND aval_type = 'credit_notes' AND aval_id = a
     AND effet = 'sale.invoice.to_credit_note' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; a uuid; n int;
BEGIN
  t := _mk_tenant('T754B');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 754 B', 'C0754B') RETURNING id INTO c;
  f := _mk_validated_invoice(t, c, 600);
  a := _mk_validated_credit_note(t, c, f, 600);
  PERFORM _as_user();
  PERFORM chain_l16_invoice_credit_note(f, a);
  BEGIN
    PERFORM chain_l16_invoice_credit_note(f, a);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = f AND aval_id = a
     AND effet = 'sale.invoice.to_credit_note' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; c uuid; c2 uuid; f uuid; a uuid; f_cancel uuid; a_draft uuid; f2 uuid; f3 uuid;
BEGIN
  t := _mk_tenant('T754C');
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES
    (t, 'Client 754 C', 'C0754C'),
    (t, 'Client 754 C2', 'C0754C2');
  SELECT id INTO c  FROM customers WHERE tenant_id = t AND account_tiers = 'C0754C';
  SELECT id INTO c2 FROM customers WHERE tenant_id = t AND account_tiers = 'C0754C2';
  f := _mk_validated_invoice(t, c, 100);
  a := _mk_validated_credit_note(t, c, f, 100);
  -- avoir en BROUILLON (jamais validé)
  INSERT INTO credit_notes (tenant_id, customer_id, date, status, subtotal, vat_total, total, reason)
    VALUES (t, c, '2026-03-02', 'draft', 100, 0, 100, 'Brouillon') RETURNING id INTO a_draft;
  -- facture d'un AUTRE client, validée, avec son propre avoir
  f2 := _mk_validated_invoice(t, c2, 100);
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_invoice_credit_note(f, '00000000-0000-0000-0000-000000000001'::uuid);
    PERFORM _rec('T03a', 'un avoir INTROUVABLE est refusé (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'un avoir INTROUVABLE est refusé (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_invoice_credit_note(f, a_draft);
    PERFORM _rec('T03b', 'un avoir en BROUILLON est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un avoir en BROUILLON est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_invoice_credit_note(f2, a);
    PERFORM _rec('T03c', 'un avoir d''un AUTRE client est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un avoir d''un AUTRE client est refusé', true, SQLERRM);
  END;
  -- avoir déjà rattaché à `f` : le rattacher à une autre facture du même client est refusé
  f3 := _mk_validated_invoice(t, c, 100);
  BEGIN
    PERFORM chain_l16_invoice_credit_note(f3, a);
    PERFORM _rec('T03d', 'un avoir qui annule DÉJÀ une autre facture est refusé', false, 'accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T03d', 'un avoir qui annule DÉJÀ une autre facture est refusé', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; a uuid; n int;
BEGIN
  t := _mk_tenant('T754D');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 754 D', 'C0754D') RETURNING id INTO c;
  f := _mk_validated_invoice(t, c, 240);
  a := _mk_validated_credit_note(t, c, f, 240);
  PERFORM _as_user();
  PERFORM chain_l16_invoice_credit_note(f, a);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'invoices', f, 'aval', 5, false)
   WHERE type = 'credit_notes' AND id = a;
  PERFORM _rec('T04a', 'depuis la FACTURE, la frise voit l''AVOIR', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'credit_notes', a, 'amont', 5, false)
   WHERE type = 'invoices' AND id = f;
  PERFORM _rec('T04b', 'depuis l''AVOIR, la frise voit la FACTURE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; ca uuid; fa uuid; aa uuid; n int;
BEGIN
  ta := _mk_tenant('T754E1');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (ta, 'Client E1', 'CE1') RETURNING id INTO ca;
  fa := _mk_validated_invoice(ta, ca, 120);
  aa := _mk_validated_credit_note(ta, ca, fa, 120);
  PERFORM _as_user();
  PERFORM chain_l16_invoice_credit_note(fa, aa);

  RESET ROLE;
  tb := _mk_tenant('T754E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_invoice_credit_note(fa, aa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher l''avoir d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher l''avoir d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'invoices' AND amont_id = fa AND aval_type = 'credit_notes';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = fa AND aval_id = aa AND effet = 'sale.invoice.to_credit_note' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('754');
