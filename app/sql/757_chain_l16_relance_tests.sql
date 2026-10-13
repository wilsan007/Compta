-- ═══════════════════════════════════════════════════════════════════════════
-- 757_chain_l16_relance_tests.sql — L16 · facture → relance
-- ═══════════════════════════════════════════════════════════════════════════
--   T01  NOMINAL : la facture rattache sa relance ; la colonne
--        `collection_reminders.invoice_id` est posée ; le LIEN est posé ;
--   T02  IDEMPOTENCE (D1) : le rejeu est REFUSÉ (unique_violation) ;
--   T03  REFUS EXPLICITES : relance introuvable, brouillon, annulée, autre
--        client, relance d'une autre facture — cinq refus, cinq raisons ;
--   T04  LA FRISE RÉPOND (I-01) : la frise voit la relance depuis la facture, et
--        la facture depuis la relance ;
--   T05  ISOLATION (D8) : le voisin ne rattache pas, et ne voit aucun lien.
-- ═══════════════════════════════════════════════════════════════════════════
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '757', false);
DELETE FROM _audit_results WHERE file = '757';

-- ── T01 — LE NOMINAL : la facture rattache sa relance ──────────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; rel uuid; r jsonb; n int; v_inv uuid;
BEGIN
  t := _mk_tenant('T757A');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 757', 'C0757') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-757-1', c, '2026-03-01', '2026-04-01', 'sent', 100, 0, 100) RETURNING id INTO f;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-757-1', c, 1, '2026-03-05', 100, 'sent') RETURNING id INTO rel;

  PERFORM _as_user();
  r := chain_l16_invoice_reminder(f, rel);

  PERFORM _rec('T01a', 'la facture rattache sa relance (jsonb de succès)',
    COALESCE((r->>'success')::boolean, false) AND (r->>'reminder_id')::uuid = rel, r::text);

  SELECT invoice_id INTO v_inv FROM collection_reminders WHERE id = rel;
  PERFORM _rec('T01b', 'la relance porte désormais invoice_id (la colonne que personne n''écrivait)', v_inv = f,
    'invoice_id = ' || COALESCE(v_inv::text, 'NULL'));

  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_type = 'invoices' AND amont_id = f
     AND aval_type = 'collection_reminders' AND aval_id = rel
     AND effet = 'sale.invoice.to_reminder' AND etat = 'actif';
  PERFORM _rec('T01c', 'le LIEN amont→aval est posé, actif, avec son effet (I-01)', n = 1, 'liens actifs = ' || n);
END $$;

-- ── T02 — IDEMPOTENCE (D1) : le rejeu est REFUSÉ ───────────────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; rel uuid; n int;
BEGIN
  t := _mk_tenant('T757B');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 757 B', 'C0757B') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-757-B', c, '2026-03-01', '2026-04-01', 'sent', 50, 0, 50) RETURNING id INTO f;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-757-B', c, 1, '2026-03-05', 50, 'sent') RETURNING id INTO rel;
  PERFORM _as_user();
  PERFORM chain_l16_invoice_reminder(f, rel);
  BEGIN
    PERFORM chain_l16_invoice_reminder(f, rel);
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', false, 'second appel accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T02a', 'le rejeu est REFUSÉ (unique_violation) — D1 tenu', true, SQLERRM);
  END;
  SELECT count(*) INTO n FROM document_links
   WHERE tenant_id = t AND amont_id = f AND aval_id = rel
     AND effet = 'sale.invoice.to_reminder' AND etat = 'actif';
  PERFORM _rec('T02b', 'un SEUL lien — le rejeu n''a rien ajouté', n = 1, 'liens = ' || n);
END $$;

-- ── T03 — REFUS EXPLICITES : cinq refus, cinq raisons ──────────────────────
DO $$
DECLARE t uuid; c uuid; c2 uuid; f uuid; f2 uuid;
        rel uuid; rel_draft uuid; rel_cancel uuid; rel_other uuid; rel_tied uuid;
BEGIN
  t := _mk_tenant('T757C');
  INSERT INTO customers (tenant_id, name, account_tiers) VALUES
    (t, 'Client 757 C', 'C0757C'),
    (t, 'Client 757 C2', 'C0757C2');
  SELECT id INTO c  FROM customers WHERE tenant_id = t AND account_tiers = 'C0757C';
  SELECT id INTO c2 FROM customers WHERE tenant_id = t AND account_tiers = 'C0757C2';
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-757-C', c, '2026-03-01', '2026-04-01', 'sent', 100, 0, 100) RETURNING id INTO f;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-757-C2', c, '2026-03-01', '2026-04-01', 'sent', 100, 0, 100) RETURNING id INTO f2;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-757-C', c, 1, '2026-03-05', 100, 'sent') RETURNING id INTO rel;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-757-Cd', c, 1, '2026-03-05', 100, 'draft') RETURNING id INTO rel_draft;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-757-Cc', c, 1, '2026-03-05', 100, 'cancelled') RETURNING id INTO rel_cancel;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-757-Co', c2, 1, '2026-03-05', 100, 'sent') RETURNING id INTO rel_other;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, invoice_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-757-Ct', c, f, 1, '2026-03-05', 100, 'sent') RETURNING id INTO rel_tied;
  PERFORM _as_user();

  BEGIN
    PERFORM chain_l16_invoice_reminder(f, '00000000-0000-0000-0000-000000000001'::uuid);
    PERFORM _rec('T03a', 'une relance INTROUVABLE est refusée (no_data_found)', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T03a', 'une relance INTROUVABLE est refusée (no_data_found)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_invoice_reminder(f, rel_draft);
    PERFORM _rec('T03b', 'une relance en BROUILLON est refusée (elle n''est pas partie)', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03b', 'une relance en BROUILLON est refusée (elle n''est pas partie)', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_invoice_reminder(f, rel_cancel);
    PERFORM _rec('T03c', 'une relance ANNULÉE est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03c', 'une relance ANNULÉE est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_invoice_reminder(f, rel_other);
    PERFORM _rec('T03d', 'une relance d''un AUTRE client est refusée', false, 'accepté !');
  EXCEPTION WHEN check_violation THEN
    PERFORM _rec('T03d', 'une relance d''un AUTRE client est refusée', true, SQLERRM);
  END;
  BEGIN
    PERFORM chain_l16_invoice_reminder(f2, rel_tied);
    PERFORM _rec('T03e', 'une relance DÉJÀ portée par une autre facture est refusée', false, 'accepté !');
  EXCEPTION WHEN unique_violation THEN
    PERFORM _rec('T03e', 'une relance DÉJÀ portée par une autre facture est refusée', true, SQLERRM);
  END;
END $$;

-- ── T04 — LA FRISE RÉPOND (I-01) ───────────────────────────────────────────
DO $$
DECLARE t uuid; c uuid; f uuid; rel uuid; n int;
BEGIN
  t := _mk_tenant('T757D');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (t, 'Client 757 D', 'C0757D') RETURNING id INTO c;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (t, 'FA-757-D', c, '2026-03-01', '2026-04-01', 'sent', 240, 0, 240) RETURNING id INTO f;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (t, 'REL-757-D', c, 2, '2026-03-10', 240, 'sent') RETURNING id INTO rel;
  PERFORM _as_user();
  PERFORM chain_l16_invoice_reminder(f, rel);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'invoices', f, 'aval', 5, false)
   WHERE type = 'collection_reminders' AND id = rel;
  PERFORM _rec('T04a', 'depuis la FACTURE, la frise voit la RELANCE', n = 1, 'nœuds aval = ' || n);

  SELECT count(*) INTO n FROM chain_document_arborescence(t, 'collection_reminders', rel, 'amont', 5, false)
   WHERE type = 'invoices' AND id = f;
  PERFORM _rec('T04b', 'depuis la RELANCE, la frise voit la FACTURE', n = 1, 'nœuds amont = ' || n);
END $$;

-- ── T05 — ISOLATION (D8) : le voisin ne rattache pas, et ne voit rien ───────
DO $$
DECLARE ta uuid; tb uuid; ca uuid; fa uuid; rela uuid; n int;
BEGIN
  ta := _mk_tenant('T757E1');
  INSERT INTO customers (tenant_id, name, account_tiers)
    VALUES (ta, 'Client E1', 'CE1') RETURNING id INTO ca;
  INSERT INTO invoices (tenant_id, number, customer_id, date, due_date, status, subtotal, vat_total, total)
    VALUES (ta, 'FA-757-E1', ca, '2026-03-01', '2026-04-01', 'sent', 120, 0, 120) RETURNING id INTO fa;
  INSERT INTO collection_reminders (tenant_id, number, customer_id, reminder_level, reminder_date, amount, status)
    VALUES (ta, 'REL-757-E1', ca, 1, '2026-03-05', 120, 'sent') RETURNING id INTO rela;
  PERFORM _as_user();
  PERFORM chain_l16_invoice_reminder(fa, rela);

  RESET ROLE;
  tb := _mk_tenant('T757E2');
  PERFORM _as_user();
  BEGIN
    PERFORM chain_l16_invoice_reminder(fa, rela);
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la relance d''autrui', false, 'accepté !');
  EXCEPTION WHEN no_data_found THEN
    PERFORM _rec('T05a', 'le VOISIN ne peut pas rattacher la relance d''autrui (no_data_found)', true, SQLERRM);
  END;

  SELECT count(*) INTO n FROM document_links
   WHERE amont_type = 'invoices' AND amont_id = fa AND aval_type = 'collection_reminders';
  PERFORM _rec('T05b', 'le voisin ne voit AUCUN lien de la société A', n = 0, 'liens visibles = ' || n);

  RESET ROLE;
  SELECT count(*) INTO n FROM document_links
   WHERE amont_id = fa AND aval_id = rela AND effet = 'sale.invoice.to_reminder' AND tenant_id = ta;
  PERFORM _rec('T05c', 'le lien de A existe toujours, un seul, et reste à A', n = 1, 'liens de A = ' || n);
END $$;

-- ── Le VERDICT (G5 : toute suite rend un verdict) ─────────────────────────
SELECT _audit_assert('757');
