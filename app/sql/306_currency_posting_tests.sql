-- ============================================================
-- 306_currency_posting_tests.sql — W7 (M-01) : le taux de change est appliqué
--
--   M01-01 🔴 Une facture en devise est comptabilisée **au montant en devise**.
--             Scénario du constat (`scenarios/M01_facture_en_devise.sql`) :
--             facture de 1 000 USD au taux 0,90 → l'écriture porte 1 000 EUR,
--             le client et le chiffre d'affaires sont faux de tout l'écart.
--   M01-02 🔴 `journal_lines` n'a **aucune** colonne de devise, de montant en
--             devise ni de taux : même corrigé, le déclencheur ne pourrait pas
--             conserver le montant d'origine.
--
-- Les scénarios mesurent la devise de tenue (EUR) sur l'écriture, la devise
-- d'origine sur la ligne, le refus d'une facture en devise sans taux, et la
-- non-régression d'une facture en euros. T06 mesure l'arrondi : trois lignes de
-- 100,00 USD au taux 0,333333 ne doivent pas laisser une écriture déséquilibrée.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '306', false);
DELETE FROM _audit_results WHERE file = '306';

DROP FUNCTION IF EXISTS _dev306_vente(uuid, uuid, text, numeric, numeric, jsonb);
CREATE OR REPLACE FUNCTION _dev306_vente(p_t uuid, p_c uuid, p_devise text,
  p_taux numeric, p_total numeric, p_lignes jsonb)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date,
                        status, subtotal, vat_total, total, amount_paid, amount_due,
                        currency_code, exchange_rate, amount_total_currency)
  VALUES (p_t, 'FAC-' || left(uuid_generate_v4()::text, 8), p_c, 'Client', CURRENT_DATE,
          CURRENT_DATE + 30, 'draft', p_total, 0, p_total, 0, p_total,
          p_devise, p_taux, p_total)
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price,
                             vat_rate, vat_code, total, vat_amount, line_order)
  SELECT p_t, inv, 'Ligne ' || o, 1, (x->>'p')::numeric, 0, 'FR0',
         (x->>'p')::numeric, 0, o
  FROM jsonb_array_elements(p_lignes) WITH ORDINALITY AS a(x, o);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  RETURN inv;
END $$;

DROP FUNCTION IF EXISTS _dev306_achat(uuid, uuid, text, numeric, numeric);
CREATE OR REPLACE FUNCTION _dev306_achat(p_t uuid, p_s uuid, p_devise text,
  p_taux numeric, p_total numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE pi uuid;
BEGIN
  INSERT INTO purchase_invoices (tenant_id, number, supplier_id, supplier_name, date, due_date,
                                 status, subtotal, vat_total, total, amount_paid, amount_due,
                                 approval_status, currency_code, exchange_rate)
  VALUES (p_t, 'FRN-' || left(uuid_generate_v4()::text, 8), p_s, 'Fournisseur', CURRENT_DATE,
          CURRENT_DATE + 30, 'draft', p_total, 0, p_total, 0, p_total, 'pending',
          p_devise, p_taux)
  RETURNING id INTO pi;
  INSERT INTO purchase_invoice_lines (tenant_id, purchase_invoice_id, description, quantity,
                                      unit_price, vat_rate, vat_code, total, vat_amount, line_order)
  VALUES (p_t, pi, 'Achat', 1, p_total, 0, 'FR0', p_total, 0, 1);
  UPDATE purchase_invoices SET approval_status = 'approved' WHERE id = pi;
  RETURN pi;
END $$;

-- T01/T02 — M01-01/M01-02 : une facture de 1 000 USD au taux 0,90 entre au
-- grand livre pour 900 EUR, et la ligne garde la devise et le taux d'origine.
DO $$
DECLARE t uuid; c uuid; d numeric; cr numeric; dev text; taux numeric;
        montant_dev numeric; dev_ecriture text;
BEGIN
  t := _mk_tenant('DEV01');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client US') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    PERFORM _dev306_vente(t, c, 'USD', 0.90, 1000, '[{"p":1000}]');
    PERFORM set_config('role', 'postgres', true);
    SELECT COALESCE(sum(l.debit), 0), COALESCE(sum(l.credit), 0) INTO d, cr
    FROM journal_lines l JOIN journal_entries e ON e.id = l.journal_id
    WHERE l.tenant_id = t AND e.invoice_ref = (SELECT number FROM invoices WHERE tenant_id = t LIMIT 1);

    SELECT l.currency_code, l.currency_amount, l.exchange_rate
      INTO dev, montant_dev, taux FROM journal_lines l
    JOIN journal_entries e ON e.id = l.journal_id
    WHERE l.tenant_id = t AND l.account_code = '707000';
    SELECT currency_code INTO dev_ecriture FROM journal_entries
    WHERE tenant_id = t ORDER BY created_at DESC LIMIT 1;

    PERFORM _rec('T01', 'une facture de 1 000 USD au taux 0,90 entre au grand livre pour 900 EUR',
      d = 900 AND cr = 900,
      format('débit=%s crédit=%s (900 attendus en devise de tenue)', d, cr));
    PERFORM _rec('T02', 'la ligne garde la devise (USD), le montant en devise (−1 000) et le taux (0,90)',
      dev = 'USD' AND montant_dev = -1000 AND taux = 0.90 AND dev_ecriture = 'USD',
      format('ligne : devise=%s montant devise=%s taux=%s ; écriture : devise=%s', dev, montant_dev, taux, dev_ecriture));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T01', 'une facture de 1 000 USD au taux 0,90 entre au grand livre pour 900 EUR', false, SQLERRM);
    PERFORM _rec('T02', 'la ligne garde la devise (USD), le montant en devise (−1 000) et le taux (0,90)', false, SQLERRM);
  END;
END $$;

-- T03 — une facture en devise **sans taux** est refusée : on ne devine pas
-- (le taux par défaut à 1 transformait 1 000 USD en 1 000 EUR en silence).
DO $$
DECLARE t uuid; c uuid; refuse boolean := false; err text := '—';
BEGIN
  t := _mk_tenant('DEV02');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client sans taux') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    PERFORM _dev306_vente(t, c, 'USD', 0, 1000, '[{"p":1000}]');
  EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
  END;
  PERFORM set_config('role', 'postgres', true);
  PERFORM _rec('T03', 'une facture en devise sans taux est refusée (jamais comptabilisée au montant en devise)',
    refuse, format('refus=%s | %s', refuse, left(err, 90)));
END $$;


-- T04 — non-régression : une facture en euros (taux 1) ne bouge pas.
DO $$
DECLARE t uuid; c uuid; d numeric; dev_txt text; montant_dev numeric;
BEGIN
  t := _mk_tenant('DEV03');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client EUR') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    PERFORM _dev306_vente(t, c, 'EUR', 1, 1200, '[{"p":1200}]');
    PERFORM set_config('role', 'postgres', true);
    SELECT COALESCE(sum(debit), 0) INTO d FROM journal_lines
    WHERE tenant_id = t AND account_code = '411000';
    SELECT currency_code, currency_amount INTO dev_txt, montant_dev FROM journal_lines
    WHERE tenant_id = t AND account_code = '707000';
    PERFORM _rec('T04', 'non-régression : une facture en euros reste à 1 200, sans devise étrangère',
      d = 1200 AND (dev_txt IS NULL OR dev_txt = 'EUR') AND COALESCE(montant_dev, 0) = -1200,
      format('débit 411=%s ; ligne 707 : devise=%s montant devise=%s', d, dev_txt, montant_dev));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T04', 'non-régression : une facture en euros reste à 1 200, sans devise étrangère', false, SQLERRM);
  END;
END $$;

-- T05 — même règle à l'achat : 500 USD au taux 0,90 → 450 EUR de charge.
DO $$
DECLARE t uuid; s uuid; d numeric;
BEGIN
  t := _mk_tenant('DEV04');
  INSERT INTO suppliers (tenant_id, name, account_tiers) VALUES (t, 'Fournisseur US', 'F0001') RETURNING id INTO s;
  PERFORM _as_user();
  BEGIN
    PERFORM _dev306_achat(t, s, 'USD', 0.90, 500);
    PERFORM set_config('role', 'postgres', true);
    SELECT COALESCE(sum(debit), 0) INTO d FROM journal_lines
    WHERE tenant_id = t AND account_code = '607000';
    PERFORM _rec('T05', 'un achat de 500 USD au taux 0,90 entre pour 450 EUR de charge',
      d = 450, format('débit 607=%s (450 attendu)', d));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T05', 'un achat de 500 USD au taux 0,90 entre pour 450 EUR de charge', false, SQLERRM);
  END;
END $$;

-- T06 — arrondi : trois lignes de 100,00 USD au taux 0,333333. Chaque ligne
-- arrondie donne 33,33 ; sans correction l'écriture est déséquilibrée d'un
-- centime et le noyau la refuse. Elle doit passer, équilibrée.
DO $$
DECLARE t uuid; c uuid; d numeric; cr numeric; dev numeric; ok boolean := false; err text := '—';
BEGIN
  t := _mk_tenant('DEV05');
  INSERT INTO customers (tenant_id, name) VALUES (t, 'Client arrondi') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    PERFORM _dev306_vente(t, c, 'USD', 0.333333, 300, '[{"p":100},{"p":100},{"p":100}]');
    SELECT COALESCE(sum(currency_amount), 0) INTO dev FROM journal_lines WHERE tenant_id = t;
    ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := false;
  END;
  PERFORM set_config('role', 'postgres', true);
  SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0) INTO d, cr
  FROM journal_lines WHERE tenant_id = t;
  PERFORM _rec('T06', 'l''arrondi de conversion est absorbé : l''écriture reste équilibrée, le montant en devise exact',
    ok AND d = cr AND d > 0 AND dev = 0,
    format('acceptée=%s débit=%s crédit=%s montant devise net=%s | %s', ok, d, cr, dev, left(err, 70)));
END $$;

DROP FUNCTION _dev306_achat(uuid, uuid, text, numeric, numeric);
DROP FUNCTION _dev306_vente(uuid, uuid, text, numeric, numeric, jsonb);
SELECT _audit_assert('306');

