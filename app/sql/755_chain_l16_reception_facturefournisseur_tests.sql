-- ═══════════════════════════════════════════════════════════════════════════
-- 755_chain_l16_reception_facturefournisseur_tests.sql — L16 · réception → facture fournisseur
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la réception rattache sa facture fournisseur ; la colonne
--        `purchase_invoices.goods_receipt_id` est posée ; le LIEN est posé ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : réception annulée, facture annulée, autre
--        fournisseur, facture déjà rattachée — quatre refus, quatre raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit la facture depuis la réception, et
--        la réception depuis la facture ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
--
-- Les factures sont saisies `pending` (aucune approbation requise par ce maillon :
-- on rapproche AVANT d'approuver).
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '755', false);
DELETE FROM _audit_results WHERE file = '755';

-- ── T01 — LE NOMINAL : la réception rattache sa facture ────────────────────
DO $$
DECLARE t uuid; s uuid; rcp uuid; f uuid; r jsonb; n int; v_gr uuid;
BEGIN
  t := _mk_tenant('T755A');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 755', 'F0755') RETURNING id INTO s;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-755-1', s, '2026-03-05', 'received') RETURNING id INTO rcp;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, due_date, status, total, amount_due, approval_status)
    VALUES (t, 'FF-755-1', s, '2026-04-05', 'sent', 1200, 1200, 'pending') RETURNING id INTO f;

  PERFORM _as_user();
  r := chain_l16_receipt_supplier_invoice(rcp, f);

  PERFORM _rec('T01a', 'la réception rattache sa facture fournisseur (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'invoice_id')::uuid = f, r::text);

  SELECT goods_receipt_id INTO v_gr FROM purchase_invoices WHERE id = f;
  PERFORM _rec('T01b', 'la facture porte désormais goods_receipt_id (la colonne lue par le rapport trois points)',
    v_gr = rcp, 'goods_receipt_id = ' || COALESCE(v_gr::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'goods_receipts' AND amont_id = rcp
     AND aval_type = 'purchase_invoices' AND aval_id = f
     AND effet = 'purchase.receipt.to_invoice' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; s uuid; rcp uuid; f uuid; n int;
BEGIN
  t := _mk_tenant('T755B');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 755 B', 'F0755B') RETURNING id INTO s;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-755-B', s, '2026-03-06', 'received') RETURNING id INTO rcp;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, due_date, status, total, amount_due, approval_status)
    VALUES (t, 'FF-755-B', s, '2026-04-05', 'sent', 600, 600, 'pending') RETURNING id INTO f;
  PERFORM _as_user();
  PERFORM chain_l16_receipt_supplier_invoice(rcp, f);
  BEGIN
    PERFORM chain_l16_receipt_supplier_invoice(rcp, f);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = rcp AND aval_id = f
     AND effet = 'purchase.receipt.to_invoice' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; s uuid; s2 uuid; rcp uuid; f uuid; rcp_cancel uuid; f_cancel uuid; f_other uuid; rcp2 uuid;
BEGIN
  t := _mk_tenant('T755C');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES
    (t, 'Fournisseur 755 C', 'F0755C'),
    (t, 'Fournisseur 755 C2', 'F0755C2');
  SELECT id INTO s  FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0755C';
  SELECT id INTO s2 FROM suppliers WHERE tenant_id = t AND account_tiers = 'F0755C2';
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-755-C', s, '2026-03-05', 'received') RETURNING id INTO rcp;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-755-Cc', s, '2026-03-05', 'cancelled') RETURNING id INTO rcp_cancel;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-755-C2', s, '2026-03-05', 'received') RETURNING id INTO rcp2;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, due_date, status, total, amount_due, approval_status)
    VALUES (t, 'FF-755-C', s, '2026-04-05', 'sent', 100, 100, 'pending') RETURNING id INTO f;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, due_date, status, total, amount_due, approval_status)
    VALUES (t, 'FF-755-Cx', s, '2026-04-05', 'cancelled', 100, 100, 'pending') RETURNING id INTO f_cancel;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, due_date, status, total, amount_due, approval_status)
    VALUES (t, 'FF-755-Co', s2, '2026-04-05', 'sent', 100, 100, 'pending') RETURNING id INTO f_other;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_receipt_supplier_invoice(rcp_cancel, f);
    PERFORM _rec('T03a', 'une réception ANNULÉE est refusée, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03a', 'une réception ANNULÉE est refusée, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_receipt_supplier_invoice(rcp, f_cancel);
    PERFORM _rec('T03b', 'une facture ANNULÉE est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'une facture ANNULÉE est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_receipt_supplier_invoice(rcp, f_other);
    PERFORM _rec('T03c', 'une facture d''un AUTRE fournisseur est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'une facture d''un AUTRE fournisseur est refusée', true, SQLERRM);
  END;
  PERFORM chain_l16_receipt_supplier_invoice(rcp, f);
  BEGIN
    PERFORM chain_l16_receipt_supplier_invoice(rcp2, f);
    PERFORM _rec('T03d', 'une facture DÉJÀ RATTACHÉE à une autre réception est refusée', false, 'accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T03d', 'une facture DÉJÀ RATTACHÉE à une autre réception est refusée', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; s uuid; rcp uuid; f uuid; n int;
BEGIN
  t := _mk_tenant('T755D');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (t, 'Fournisseur 755 D', 'F0755D') RETURNING id INTO s;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (t, 'BR-755-D', s, '2026-03-06', 'received') RETURNING id INTO rcp;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, due_date, status, total, amount_due, approval_status)
    VALUES (t, 'FF-755-D', s, '2026-04-05', 'sent', 240, 240, 'pending') RETURNING id INTO f;
  PERFORM _as_user();
  PERFORM chain_l16_receipt_supplier_invoice(rcp, f);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'goods_receipts', rcp, 'aval', 5, false)
   WHERE type = 'purchase_invoices' AND id = f;
  PERFORM _rec('T04a', 'depuis la RÉCEPTION, la frise voit la FACTURE', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'purchase_invoices', f, 'amont', 5, false)
   WHERE type = 'goods_receipts' AND id = rcp;
  PERFORM _rec('T04b', 'depuis la FACTURE, la frise voit la RÉCEPTION', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; sa uuid; ra uuid; fa uuid; n int;
BEGIN
  ta := _mk_tenant('T755E1');
  INSERT INTO suppliers (tenant_id, name, account_tiers)
    VALUES (ta, 'Fournisseur E1', 'FE1') RETURNING id INTO sa;
  INSERT INTO goods_receipts (tenant_id, number, supplier_id, receipt_date, status)
    VALUES (ta, 'BR-755-E1', sa, '2026-03-07', 'received') RETURNING id INTO ra;
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, due_date, status, total, amount_due, approval_status)
    VALUES (ta, 'FF-755-E1', sa, '2026-04-05', 'sent', 120, 120, 'pending') RETURNING id INTO fa;
  PERFORM _as_user();
  PERFORM chain_l16_receipt_supplier_invoice(ra, fa);

  RESET ROLE;
  tb := _mk_tenant('T755E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_receipt_supplier_invoice(ra, fa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la facture d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la facture d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'goods_receipts' AND amont_id = ra AND aval_type = 'purchase_invoices';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = ra AND aval_id = fa AND effet = 'purchase.receipt.to_invoice' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('755');
