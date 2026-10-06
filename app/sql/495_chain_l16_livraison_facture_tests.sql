-- ═══════════════════════════════════════════════════════════════════════════
-- 495_chain_l16_livraison_facture_tests.sql — L16 · livraison → facture
-- ═══════════════════════════════════════════════════════════════════════════
-- Cette suite éprouve le maillon de la 495 sur les épreuves du banc qui ont un
-- sens ici :
--   T01  NOMINAL : le bon de livraison rattache sa facture ; la colonne
--        `invoices.delivery_note_id` est posée ; le LIEN est posé (effet
--        `sale.delivery.to_invoice`) ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) et n'ajoute
--        aucun lien ;
--   T03  REFUS EXPLICITES : bon annulé, bon retourné, facture annulée, facture
--        d'un autre client — quatre refus, quatre raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit la facture depuis le bon, et le
--        bon depuis la facture ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas la facture d'autrui, et ne
--        voit aucun lien.
--
-- Ce que cette suite NE joue PAS, et le dit : D2 (concurrence), D3 (panne
-- partielle), D5 (réouverture) restent hors de portée d'une suite SQL d'un seul
-- processus ; D6 (retour arrière) est tenu par construction, D7 (volume) n'a
-- pas de sens sur une chaîne de deux pièces.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '495', false);
DELETE FROM _audit_results WHERE file = '495';

-- ── T01 — LE NOMINAL : le bon rattache sa facture ──────────────────────────
DO $$
DECLARE t uuid; c uuid; d uuid; f uuid; r jsonb; n int; v_dn uuid;
BEGIN
  t := _mk_tenant('T495A');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 495', 'C0495') RETURNING id INTO c;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-495-1', c, '2026-03-05', 'shipped') RETURNING id INTO d;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-495-1', c, '2026-03-06', '2026-04-05', 'sent', 1000, 200, 1200) RETURNING id INTO f;

  PERFORM _as_user();
  r := chain_l16_delivery_invoice(d, f);

  PERFORM _rec('T01a', 'le bon de livraison rattache sa facture (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'invoice_id')::uuid = f, r::text);

  SELECT delivery_note_id INTO v_dn FROM invoices WHERE id = f;
  PERFORM _rec('T01b', 'la facture porte désormais delivery_note_id (la colonne que personne n''écrivait)',
    v_dn = d, 'delivery_note_id = ' || COALESCE(v_dn::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'delivery_notes' AND amont_id = d
     AND aval_type = 'invoices' AND aval_id = f
     AND effet = 'sale.delivery.to_invoice' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; c uuid; d uuid; f uuid; n int;
BEGIN
  t := _mk_tenant('T495B');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 495 B', 'C0495B') RETURNING id INTO c;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-495-B', c, '2026-03-06', 'shipped') RETURNING id INTO d;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-495-B', c, '2026-03-07', '2026-04-05', 'sent', 500, 100, 600) RETURNING id INTO f;
  PERFORM _as_user();
  PERFORM chain_l16_delivery_invoice(d, f);
  BEGIN
    PERFORM chain_l16_delivery_invoice(d, f);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = d AND aval_id = f
     AND effet = 'sale.delivery.to_invoice' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : quatre refus, quatre raisons ──────────────────
DO $$
DECLARE t uuid; c uuid; c2 uuid; d uuid; f uuid; d_cancel uuid; d_return uuid; f_cancel uuid; f_other uuid;
BEGIN
  t := _mk_tenant('T495C');
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES
    (t, 'Client 495 C', 'C0495C'),
    (t, 'Client 495 C2', 'C0495C2');
  SELECT id INTO c  FROM customers WHERE tenant_id = t AND account_tiers = 'C0495C';
  SELECT id INTO c2 FROM customers WHERE tenant_id = t AND account_tiers = 'C0495C2';
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-495-C', c, '2026-03-05', 'shipped') RETURNING id INTO d;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-495-Ca', c, '2026-03-05', 'cancelled') RETURNING id INTO d_cancel;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-495-Cr', c, '2026-03-05', 'returned') RETURNING id INTO d_return;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-495-C', c, '2026-03-06', '2026-04-05', 'sent', 100, 20, 120) RETURNING id INTO f;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-495-Ca', c, '2026-03-06', '2026-04-05', 'cancelled', 100, 20, 120) RETURNING id INTO f_cancel;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-495-Co', c2, '2026-03-06', '2026-04-05', 'sent', 100, 20, 120) RETURNING id INTO f_other;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_delivery_invoice(d_cancel, f);
    PERFORM _rec('T03a', 'un bon ANNULE est refusé, avec sa raison', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03a', 'un bon ANNULE est refusé, avec sa raison', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_delivery_invoice(d_return, f);
    PERFORM _rec('T03b', 'un bon RETOURNE est refusé', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'un bon RETOURNE est refusé', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_delivery_invoice(d, f_cancel);
    PERFORM _rec('T03c', 'une facture ANNULEE est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'une facture ANNULEE est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_delivery_invoice(d, f_other);
    PERFORM _rec('T03d', 'une facture d''un AUTRE client est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03d', 'une facture d''un AUTRE client est refusée', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; c uuid; d uuid; f uuid; n int;
BEGIN
  t := _mk_tenant('T495D');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 495 D', 'C0495D') RETURNING id INTO c;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (t, 'BL-495-D', c, '2026-03-06', 'shipped') RETURNING id INTO d;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-495-D', c, '2026-03-07', '2026-04-05', 'sent', 200, 40, 240) RETURNING id INTO f;
  PERFORM _as_user();
  PERFORM chain_l16_delivery_invoice(d, f);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'delivery_notes', d, 'aval', 5, false)
   WHERE type = 'invoices' AND id = f;
  PERFORM _rec('T04a', 'depuis le BON, la frise voit la FACTURE', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'invoices', f, 'amont', 5, false)
   WHERE type = 'delivery_notes' AND id = d;
  PERFORM _rec('T04b', 'depuis la FACTURE, la frise voit le BON', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; ca uuid; da uuid; fa uuid; n int;
BEGIN
  ta := _mk_tenant('T495E1');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (ta, 'Client E1', 'CE1') RETURNING id INTO ca;
  INSERT INTO delivery_notes (tenant_id, number, customer_id, delivery_date, status)
    VALUES (ta, 'BL-495-E1', ca, '2026-03-08', 'shipped') RETURNING id INTO da;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (ta, 'FA-495-E1', ca, '2026-03-09', '2026-04-05', 'sent', 100, 20, 120) RETURNING id INTO fa;
  PERFORM _as_user();
  PERFORM chain_l16_delivery_invoice(da, fa);

  RESET ROLE;
  tb := _mk_tenant('T495E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_delivery_invoice(da, fa);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la facture d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la facture d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'delivery_notes' AND amont_id = da AND aval_type = 'invoices';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = da AND aval_id = fa AND effet = 'sale.delivery.to_invoice' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('495');
