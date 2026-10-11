-- ═══════════════════════════════════════════════════════════════════════════
-- 497_chain_l16_facture_reglement_tests.sql — L16 · facture → règlement
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la facture rattache son règlement ; la colonne
--        `customer_payments.invoice_id` est posée ; le LIEN est posé
--        (effet `sale.invoice.to_payment`) ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : facture annulée, règlement annulé, autre client,
--        règlement déjà affecté — quatre refus, quatre raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit le règlement depuis la facture,
--        et la facture depuis le règlement ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
--
-- D2 (concurrence), D3 (panne partielle), D5 (réouverture) restent hors de
-- portée d'une suite SQL d'un seul processus ; D6 tenu par construction ; D7
-- sans objet sur une chaîne de deux pièces.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '497', false);
DELETE FROM _audit_results WHERE file = '497';

-- ── T01 — LE NOMINAL : la facture rattache son règlement ───────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; p uuid; r jsonb; n int; v_inv uuid;
BEGIN
  t := _mk_tenant('T497A');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 497', 'C0497') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-497-1', c, '2026-03-06', '2026-04-05', 'sent', 1000, 200, 1200) RETURNING id INTO f;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'REG-497-1', c, '2026-03-10', 1200, 'transfer', 'recorded') RETURNING id INTO p;

  PERFORM _as_user();
  r := chain_l16_invoice_payment(f, p);

  PERFORM _rec('T01a', 'la facture rattache son règlement (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'payment_id')::uuid = p, r::text);

  SELECT invoice_id INTO v_inv FROM customer_payments WHERE id = p;
  PERFORM _rec('T01b', 'le règlement porte désormais invoice_id (la colonne que personne n''écrivait)',
    v_inv = f, 'invoice_id = ' || COALESCE(v_inv::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'invoices' AND amont_id = f
     AND aval_type = 'customer_payments' AND aval_id = p
     AND effet = 'sale.invoice.to_payment' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; p uuid; n int;
BEGIN
  t := _mk_tenant('T497B');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 497 B', 'C0497B') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-497-B', c, '2026-03-06', '2026-04-05', 'sent', 500, 100, 600) RETURNING id INTO f;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'REG-497-B', c, '2026-03-11', 600, 'transfer', 'recorded') RETURNING id INTO p;
  PERFORM _as_user();
  PERFORM chain_l16_invoice_payment(f, p);
  BEGIN
    PERFORM chain_l16_invoice_payment(f, p);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = f AND aval_id = p
     AND effet = 'sale.invoice.to_payment' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; c uuid; c2 uuid; f uuid; p uuid; f_cancel uuid; p_cancel uuid; p_other uuid; f2 uuid;
BEGIN
  t := _mk_tenant('T497C');
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES
    (t, 'Client 497 C', 'C0497C'),
    (t, 'Client 497 C2', 'C0497C2');
  SELECT id INTO c  FROM customers WHERE tenant_id = t AND account_tiers = 'C0497C';
  SELECT id INTO c2 FROM customers WHERE tenant_id = t AND account_tiers = 'C0497C2';
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-497-C', c, '2026-03-06', '2026-04-05', 'sent', 100, 20, 120) RETURNING id INTO f;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-497-C2', c, '2026-03-06', '2026-04-05', 'sent', 100, 20, 120) RETURNING id INTO f2;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-497-Cx', c, '2026-03-06', '2026-04-05', 'cancelled', 100, 20, 120) RETURNING id INTO f_cancel;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'REG-497-C', c, '2026-03-10', 120, 'transfer', 'recorded') RETURNING id INTO p;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'REG-497-Cc', c, '2026-03-10', 120, 'transfer', 'cancelled') RETURNING id INTO p_cancel;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'REG-497-Co', c2, '2026-03-10', 120, 'transfer', 'recorded') RETURNING id INTO p_other;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_invoice_payment(f_cancel, p);
    PERFORM _rec('T03a', 'une facture ANNULEE est refusée, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03a', 'une facture ANNULEE est refusée, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_invoice_payment(f, p_cancel);
    PERFORM _rec('T03b', 'un règlement ANNULE est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un règlement ANNULE est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_invoice_payment(f, p_other);
    PERFORM _rec('T03c', 'un règlement d''un AUTRE client est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'un règlement d''un AUTRE client est refusé', true, SQLERRM);
  END;
  -- règlement déjà affecté à FA-497-C : le rattacher à FA-497-C2 est refusé.
  PERFORM chain_l16_invoice_payment(f, p);
  BEGIN
    PERFORM chain_l16_invoice_payment(f2, p);
    PERFORM _rec('T03d', 'un règlement DÉJÀ AFFECTÉ à une autre facture est refusé', false, 'accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T03d', 'un règlement DÉJÀ AFFECTÉ à une autre facture est refusé', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; p uuid; n int;
BEGIN
  t := _mk_tenant('T497D');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 497 D', 'C0497D') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-497-D', c, '2026-03-06', '2026-04-05', 'sent', 200, 40, 240) RETURNING id INTO f;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (t, 'REG-497-D', c, '2026-03-12', 240, 'transfer', 'recorded') RETURNING id INTO p;
  PERFORM _as_user();
  PERFORM chain_l16_invoice_payment(f, p);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'invoices', f, 'aval', 5, false)
   WHERE type = 'customer_payments' AND id = p;
  PERFORM _rec('T04a', 'depuis la FACTURE, la frise voit le RÈGLEMENT', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'customer_payments', p, 'amont', 5, false)
   WHERE type = 'invoices' AND id = f;
  PERFORM _rec('T04b', 'depuis le RÈGLEMENT, la frise voit la FACTURE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; ca uuid; fa uuid; pa uuid; n int;
BEGIN
  ta := _mk_tenant('T497E1');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (ta, 'Client E1', 'CE1') RETURNING id INTO ca;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (ta, 'FA-497-E1', ca, '2026-03-06', '2026-04-05', 'sent', 100, 20, 120) RETURNING id INTO fa;
  INSERT INTO customer_payments (tenant_id, number, customer_id, payment_date, amount, method, status)
    VALUES (ta, 'REG-497-E1', ca, '2026-03-13', 120, 'transfer', 'recorded') RETURNING id INTO pa;
  PERFORM _as_user();
  PERFORM chain_l16_invoice_payment(fa, pa);

  RESET ROLE;
  tb := _mk_tenant('T497E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_invoice_payment(fa, pa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher le règlement d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher le règlement d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'invoices' AND amont_id = fa AND aval_type = 'customer_payments';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = fa AND aval_id = pa AND effet = 'sale.invoice.to_payment' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('497');
