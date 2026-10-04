-- ============================================================
-- 210_advance_invoices_tests.sql — R-03 (décision D-9 du 22/09)
--
-- Facture d'acompte : D 411 TTC / C 4191 HT / C 4457 TVA (et non 707).
-- Facture finale : toutes les lignes, plus une ligne négative « déduction
-- de l'acompte » rattachée à la facture d'acompte (advance_invoice_id) :
-- D 411 net / D 4191 HT déduit / C 7xx / C 4457 net ; 4191 lettré quand
-- l'acompte est entièrement déduit. Charges utiles du front (misc.ts).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '210', false);
DELETE FROM _audit_results WHERE file = '210';

-- Facture d'acompte telle que createAdvanceInvoice la crée (misc.ts)
CREATE OR REPLACE FUNCTION _mk_advance(t uuid, c uuid, d date, ht numeric, rate numeric, validate boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status, subtotal, vat_total, total,
    amount_paid, amount_due, notes, recurring, is_advance_invoice, advance_amount, invoice_type)
  VALUES (t, c, 'Client', d, d + 30, 'draft', ht, ht * rate / 100, ht * (1 + rate / 100), 0, ht * (1 + rate / 100), '',
    false, true, ht, 'advance')
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, product_id, description, quantity, unit_price, vat_rate, total, vat_total, line_order)
  VALUES (t, inv, NULL, 'Acompte', 1, ht, rate, ht, ht * rate / 100, 0);
  IF validate THEN UPDATE invoices SET validation_status = 'validated' WHERE id = inv; END IF;
  RETURN inv;
END $$;

-- Facture finale : une ligne de vente, et la déduction d'un acompte (montant HT positif à déduire)
CREATE OR REPLACE FUNCTION _mk_final(t uuid, c uuid, d date, ht numeric, rate numeric, adv uuid, deduct numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, customer_id, customer_name, date, due_date, status)
  VALUES (t, c, 'Client', d, d + 30, 'draft') RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, line_order)
  VALUES (t, inv, 'Travaux', 1, ht, rate, 0);
  IF adv IS NOT NULL THEN
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, vat_rate, line_order, advance_invoice_id)
    VALUES (t, inv, 'Déduction acompte', 1, -deduct, rate, 1, adv);
  END IF;
  RETURN inv;
END $$;

-- AC01 — la facture d'acompte est comptabilisée en 4191, pas en ventes
DO $$
DECLARE t uuid := _mk_tenant('AC01'); c uuid; a uuid; e uuid; r record;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client A') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    a := _mk_advance(t, c, '2026-03-01', 1000, 20);
    SELECT transferred_entry_id INTO e FROM invoices WHERE id = a;
    SELECT sum(debit) FILTER (WHERE account_code LIKE '411%') AS d411,
           sum(credit) FILTER (WHERE account_code = '419100') AS c4191,
           sum(credit) FILTER (WHERE account_code LIKE '4457%') AS c4457,
           count(*) FILTER (WHERE account_code LIKE '7%') AS n7
      INTO r FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('AC01', 'acompte 1 000 HT : D 411 1 200 / C 4191 1 000 / C 4457 200, aucun 7xx',
      r.d411 = 1200 AND r.c4191 = 1000 AND r.c4457 = 200 AND r.n7 = 0,
      format('D411=%s C4191=%s C4457=%s lignes 7xx=%s', r.d411, r.c4191, r.c4457, r.n7));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('AC01', 'acompte 1 000 HT : D 411 1 200 / C 4191 1 000 / C 4457 200, aucun 7xx', false, SQLERRM); END;
END $$;

-- AC02, AC03 — facture finale 3 000 HT avec déduction de l'acompte de 1 000 HT
DO $$
DECLARE t uuid := _mk_tenant('AC02'); c uuid; a uuid; f uuid; e uuid; ea uuid; r record; inv record; n_open int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client F') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    a := _mk_advance(t, c, '2026-03-01', 1000, 20);
    f := _mk_final(t, c, '2026-04-01', 3000, 20, a, 1000);
    UPDATE invoices SET validation_status = 'validated' WHERE id = f;
    SELECT subtotal, vat_total, total, amount_due INTO inv FROM invoices WHERE id = f;
    SELECT transferred_entry_id INTO e FROM invoices WHERE id = f;
    SELECT sum(debit) FILTER (WHERE account_code LIKE '411%') AS d411,
           sum(debit) FILTER (WHERE account_code = '419100') AS d4191,
           sum(credit) FILTER (WHERE account_code LIKE '7%') AS c7,
           sum(credit) FILTER (WHERE account_code LIKE '4457%') AS c4457,
           sum(debit) AS d, sum(credit) AS cr
      INTO r FROM journal_lines WHERE journal_id = e;
    PERFORM _rec('AC02', 'finale 3 000 − acompte 1 000 : facture 2 000 / 400 / 2 400 ; D 411 2 400 + D 4191 1 000 = C 7xx 3 000 + C 4457 400',
      inv.subtotal = 2000 AND inv.vat_total = 400 AND inv.total = 2400 AND inv.amount_due = 2400
        AND r.d411 = 2400 AND r.d4191 = 1000 AND r.c7 = 3000 AND r.c4457 = 400 AND r.d = r.cr,
      format('facture %s/%s/%s reste %s ; D411=%s D4191=%s C7=%s C4457=%s D=%s C=%s',
        inv.subtotal, inv.vat_total, inv.total, inv.amount_due, r.d411, r.d4191, r.c7, r.c4457, r.d, r.cr));

    SELECT transferred_entry_id INTO ea FROM invoices WHERE id = a;
    SELECT count(*) FILTER (WHERE lettrage_code IS NULL) INTO n_open
    FROM journal_lines WHERE account_code = '419100' AND journal_id IN (e, ea);
    PERFORM _rec('AC03', 'acompte entièrement déduit : les deux lignes 4191 sont lettrées ensemble',
      n_open = 0 AND (SELECT count(DISTINCT lettrage_code) FROM journal_lines WHERE account_code = '419100' AND journal_id IN (e, ea)) = 1,
      format('lignes 4191 non lettrées=%s', n_open));
  EXCEPTION WHEN OTHERS THEN
    PERFORM _rec('AC02', 'finale 3 000 − acompte 1 000 : facture 2 000 / 400 / 2 400 ; D 411 2 400 + D 4191 1 000 = C 7xx 3 000 + C 4457 400', false, SQLERRM);
    PERFORM _rec('AC03', 'acompte entièrement déduit : les deux lignes 4191 sont lettrées ensemble', false, 'scénario interrompu');
  END;
END $$;

-- AC04 — déduction en deux fois ; la seconde qui dépasse le solde de l'acompte est refusée
DO $$
DECLARE t uuid := _mk_tenant('AC04'); c uuid; a uuid; f1 uuid; f2 uuid; f3 uuid; ok2 boolean := true; refused3 boolean := false; n_open int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client D') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    a := _mk_advance(t, c, '2026-03-01', 1000, 20);
    f1 := _mk_final(t, c, '2026-04-01', 2000, 20, a, 600);
    UPDATE invoices SET validation_status = 'validated' WHERE id = f1;
    f3 := _mk_final(t, c, '2026-04-02', 2000, 20, a, 500);
    BEGIN UPDATE invoices SET validation_status = 'validated' WHERE id = f3;
    EXCEPTION WHEN OTHERS THEN refused3 := SQLERRM LIKE '%reste 400%'; END;
    f2 := _mk_final(t, c, '2026-04-03', 2000, 20, a, 400);
    UPDATE invoices SET validation_status = 'validated' WHERE id = f2;
    SELECT count(*) FILTER (WHERE lettrage_code IS NULL) INTO n_open FROM journal_lines jl
    WHERE account_code = '419100' AND journal_id IN (SELECT transferred_entry_id FROM invoices WHERE id IN (a, f1, f2));
    PERFORM _rec('AC04', 'acompte 1 000 : 600 puis 500 refusé (solde 400), puis 400 accepté ; 4191 soldé et lettré',
      refused3 AND (SELECT validation_status FROM invoices WHERE id = f3) IS DISTINCT FROM 'validated'
        AND (SELECT validation_status FROM invoices WHERE id = f2) = 'validated' AND n_open = 0,
      format('500 refusé=%s ; lignes 4191 ouvertes=%s', refused3, n_open));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('AC04', 'acompte 1 000 : 600 puis 500 refusé (solde 400), puis 400 accepté ; 4191 soldé et lettré', false, SQLERRM); END;
END $$;

-- AC05 — on ne déduit qu'un acompte validé du même client
DO $$
DECLARE t uuid := _mk_tenant('AC05'); c uuid; c2 uuid; a_other uuid; a_draft uuid; f1 uuid; f2 uuid; r1 boolean := false; r2 boolean := false;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client X') RETURNING id INTO c;
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client Y') RETURNING id INTO c2;
  PERFORM _as_user();
  BEGIN
    a_other := _mk_advance(t, c2, '2026-03-01', 1000, 20);
    a_draft := _mk_advance(t, c, '2026-03-01', 1000, 20, false);
    f1 := _mk_final(t, c, '2026-04-01', 3000, 20, a_other, 1000);
    BEGIN UPDATE invoices SET validation_status = 'validated' WHERE id = f1; EXCEPTION WHEN OTHERS THEN r1 := SQLERRM LIKE '%autre client%'; END;
    f2 := _mk_final(t, c, '2026-04-01', 3000, 20, a_draft, 1000);
    BEGIN UPDATE invoices SET validation_status = 'validated' WHERE id = f2; EXCEPTION WHEN OTHERS THEN r2 := SQLERRM LIKE '%pas validé%'; END;
    PERFORM _rec('AC05', 'déduction d''un acompte d''un autre client, ou non validé : validation refusée', r1 AND r2,
      format('autre client refusé=%s ; brouillon refusé=%s', r1, r2));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('AC05', 'déduction d''un acompte d''un autre client, ou non validé : validation refusée', false, SQLERRM); END;
END $$;

-- AC06 — non-régression : une facture ordinaire reste en 707
DO $$
DECLARE t uuid := _mk_tenant('AC06'); c uuid; f uuid; n7 numeric; n4191 int;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client O') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    f := _mk_final(t, c, '2026-04-01', 500, 20, NULL, 0);
    UPDATE invoices SET validation_status = 'validated' WHERE id = f;
    SELECT sum(credit) FILTER (WHERE account_code = '707000'), count(*) FILTER (WHERE account_code = '419100') INTO n7, n4191
    FROM journal_lines WHERE journal_id = (SELECT transferred_entry_id FROM invoices WHERE id = f);
    PERFORM _rec('AC06', 'facture ordinaire 500 HT : C 707000 500, pas de 4191', n7 = 500 AND n4191 = 0, format('C707=%s lignes 4191=%s', n7, n4191));
  EXCEPTION WHEN OTHERS THEN PERFORM _rec('AC06', 'facture ordinaire 500 HT : C 707000 500, pas de 4191', false, SQLERRM); END;
END $$;

DROP FUNCTION _mk_advance(uuid, uuid, date, numeric, numeric, boolean);
DROP FUNCTION _mk_final(uuid, uuid, date, numeric, numeric, uuid, numeric);

SELECT _audit_assert('210');
