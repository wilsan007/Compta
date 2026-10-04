-- ============================================================
-- 309_exchange_gain_loss_tests.sql — W7 (M-01, fin) : l'écart de change vit
--
--   M01-03 🟠 `ExchangeGainLossPage` lit `exchange_gain_loss_entries` et
--             `CurrencyRevaluationPage` lit `currency_revaluations` : **aucune
--             fonction SQL et aucun appel du front n'écrit dans ces deux
--             tables**. Les écrans sont vides à vie ; l'écart de change au
--             règlement (666/766) et la réévaluation de clôture ne sont pas
--             implémentés.
--
-- Les scénarios mesurent : un **gain** au règlement (encaissé plus que
-- comptabilisé), une **perte**, l'absence d'écart en devise de tenue, la
-- **réévaluation** d'une période (et son refus si elle est relancée), et le
-- sort honnête d'un solde en devise **sans taux**.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '309', false);
DELETE FROM _audit_results WHERE file = '309';

DROP FUNCTION IF EXISTS _ec309_vente(uuid, uuid, numeric, numeric);
CREATE OR REPLACE FUNCTION _ec309_vente(p_t uuid, p_c uuid, p_taux numeric, p_montant numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE inv uuid;
BEGIN
  INSERT INTO invoices (tenant_id, number, customer_id, customer_name, date, due_date,
                        status, subtotal, vat_total, total, amount_paid, amount_due,
                        currency_code, exchange_rate, amount_total_currency)
  VALUES (p_t, 'FAC-' || left(uuid_generate_v4()::text, 8), p_c, 'Client US', '2026-03-10',
          '2026-04-10', 'draft', p_montant, 0, p_montant, 0, p_montant,
          CASE WHEN p_taux = 1 THEN 'EUR' ELSE 'USD' END, p_taux, p_montant)
  RETURNING id INTO inv;
  INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price,
                             vat_rate, vat_code, total, vat_amount, line_order)
  VALUES (p_t, inv, 'Prestation', 1, p_montant, 0, 'FR0', p_montant, 0, 1);
  UPDATE invoices SET validation_status = 'validated' WHERE id = inv;
  RETURN inv;
END $$;

DROP FUNCTION IF EXISTS _ec309_reglement(uuid, uuid, uuid, text, numeric, numeric, numeric);
CREATE OR REPLACE FUNCTION _ec309_reglement(p_t uuid, p_c uuid, p_inv uuid, p_devise text,
  p_taux_piece numeric, p_taux_paiement numeric, p_montant_devise numeric)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE p uuid;
BEGIN
  INSERT INTO customer_payments (tenant_id, number, customer_id, invoice_id, payment_date,
                                 amount, method, status, currency_code, exchange_rate, amount_currency)
  VALUES (p_t, 'REG-' || left(uuid_generate_v4()::text, 8), p_c, p_inv, '2026-04-05',
          round(p_montant_devise * p_taux_paiement, 2), 'transfer', 'recorded', p_devise,
          p_taux_paiement, p_montant_devise)
  RETURNING id INTO p;
  RETURN p;
END $$;

-- T01 — gain : facture 1 000 USD comptabilisée à 0,90 (900 EUR), encaissée à
-- 0,95 (950 EUR) → 50 EUR de gain, en 411 contre 766, et dans la table d'écarts.
DO $$
DECLARE t uuid; c uuid; inv uuid; pay uuid; n int; mnt_ecart numeric; net411 numeric; gain numeric; v record;
BEGIN
  t := _mk_tenant('EC01');
  INSERT INTO customers (tenant_id, name, account_collectif) VALUES (t, 'Client US', '411000') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _ec309_vente(t, c, 0.90, 1000);
    pay := _ec309_reglement(t, c, inv, 'USD', 0.90, 0.95, 1000);
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*), COALESCE(sum(amount), 0) INTO n, mnt_ecart
    FROM exchange_gain_loss_entries WHERE tenant_id = t;
    SELECT exchange_gain_loss INTO gain FROM customer_payments WHERE id = pay;
    SELECT COALESCE(sum(debit), 0) - COALESCE(sum(credit), 0) INTO net411
    FROM journal_lines WHERE tenant_id = t AND account_code = '411000';
    SELECT COALESCE(sum(credit), 0) AS gain766 INTO v FROM journal_lines WHERE tenant_id = t AND account_code = '766000';
    PERFORM _rec('T01', 'un règlement encaissé plus que comptabilisé constate un gain de change (766) de 50',
      n = 1 AND mnt_ecart = 50 AND gain = 50 AND COALESCE(v.gain766, 0) = 50 AND net411 = 0,
      format('écarts=%s montant=%s gain porté au règlement=%s ; créance 411 soldée (net=%s) ; crédit 766=%s',
             n, mnt_ecart, gain, net411, v.gain766));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T01', 'un règlement encaissé plus que comptabilisé constate un gain de change (766) de 50', false, SQLERRM);
  END;
END $$;

-- T02 — perte : la même facture encaissée à 0,85 (850 EUR) → 50 EUR de perte,
-- en 666 contre 411.
DO $$
DECLARE t uuid; c uuid; inv uuid; pay uuid; perte numeric; gain numeric;
BEGIN
  t := _mk_tenant('EC02');
  INSERT INTO customers (tenant_id, name, account_collectif) VALUES (t, 'Client US', '411000') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _ec309_vente(t, c, 0.90, 1000);
    pay := _ec309_reglement(t, c, inv, 'USD', 0.90, 0.85, 1000);
    PERFORM set_config('role', 'postgres', true);
    SELECT exchange_gain_loss INTO perte FROM customer_payments WHERE id = pay;
    SELECT COALESCE(sum(debit), 0) INTO gain FROM journal_lines WHERE tenant_id = t AND account_code = '666000';
    PERFORM _rec('T02', 'un règlement encaissé moins que comptabilisé constate une perte de change (666) de 50',
      perte = -50 AND gain = 50, format('écart porté au règlement=%s (attendu −50) ; débit 666=%s', perte, gain));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T02', 'un règlement encaissé moins que comptabilisé constate une perte de change (666) de 50', false, SQLERRM);
  END;
END $$;

-- T03 — non-régression : en devise de tenue, aucun écart n'est constaté.
DO $$
DECLARE t uuid; c uuid; inv uuid; n int; v_entry int;
BEGIN
  t := _mk_tenant('EC03');
  INSERT INTO customers (tenant_id, name, account_collectif) VALUES (t, 'Client EUR', '411000') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _ec309_vente(t, c, 1, 500);
    PERFORM _ec309_reglement(t, c, inv, 'EUR', 1, 1, 500);
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) INTO n FROM exchange_gain_loss_entries WHERE tenant_id = t;
    SELECT count(*) INTO v_entry FROM journal_entries WHERE tenant_id = t AND number LIKE 'ECART-%';
    PERFORM _rec('T03', 'une facture en euros ne constate aucun écart de change',
      n = 0 AND v_entry = 0, format('écarts=%s écritures d''écart=%s', n, v_entry));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T03', 'une facture en euros ne constate aucun écart de change', false, SQLERRM);
  END;
END $$;


-- T04 — réévaluation de clôture : la créance de 1 000 USD (comptabilisée à 0,90)
-- réévaluée au taux du 30/06 (0,95) → 50 EUR de gain, une ligne dans
-- `currency_revaluations`, une écriture, et un **refus** si on relance.
DO $$
DECLARE t uuid; c uuid; inv uuid; r jsonb; n int; gl numeric; st text; refuse boolean := false; err text := '—';
BEGIN
  t := _mk_tenant('EC04');
  INSERT INTO customers (tenant_id, name, account_collectif) VALUES (t, 'Client US', '411000') RETURNING id INTO c;
  INSERT INTO exchange_rates (tenant_id, base_currency, quote_currency, rate, rate_date)
  VALUES (t, 'EUR', 'USD', 0.95, '2026-06-30');
  PERFORM _as_user();
  BEGIN
    inv := _ec309_vente(t, c, 0.90, 1000);
    r := public.revaluate_currency_balances('2026-06-30');
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*), COALESCE(sum(gain_loss), 0), max(status) INTO n, gl, st
    FROM currency_revaluations WHERE tenant_id = t;
    BEGIN
      PERFORM _as_user();
      PERFORM public.revaluate_currency_balances('2026-06-30');
    EXCEPTION WHEN OTHERS THEN refuse := true; err := SQLERRM;
    END;
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T04', 'réévaluation au 30/06 : 50 EUR de gain portés, une ligne, une écriture, et un refus de relance',
      n = 1 AND gl = 50 AND st = 'posted' AND refuse
        AND err NOT LIKE '%does not exist%' AND err NOT LIKE '%n''existe pas%',
      format('lignes=%s écart=%s statut=%s relance refusée=%s (%s) | verdict=%s', n, gl, st, refuse, left(err, 60), r::text));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T04', 'réévaluation au 30/06 : 50 EUR de gain portés, une ligne, une écriture, et un refus de relance', false, SQLERRM);
  END;
END $$;

-- T05 — un solde en devise **sans taux** n'est pas réévalué à un taux inventé :
-- aucune ligne, et le verdict dit combien de soldes sont restés sans taux.
DO $$
DECLARE t uuid; c uuid; inv uuid; r jsonb;
BEGIN
  t := _mk_tenant('EC05');
  INSERT INTO customers (tenant_id, name, account_collectif) VALUES (t, 'Client US', '411000') RETURNING id INTO c;
  PERFORM _as_user();
  BEGIN
    inv := _ec309_vente(t, c, 0.90, 1000);
    r := public.revaluate_currency_balances('2026-06-30');
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T05', 'sans taux du jour, la réévaluation ne réévalue rien et le dit',
      COALESCE((r->>'lines')::int, -1) = 0 AND COALESCE((r->>'without_rate')::int, 0) = 1,
      format('verdict=%s', r::text));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', 'postgres', true);
    PERFORM _rec('T05', 'sans taux du jour, la réévaluation ne réévalue rien et le dit', false, SQLERRM);
  END;
END $$;

DROP FUNCTION _ec309_reglement(uuid, uuid, uuid, text, numeric, numeric, numeric);
DROP FUNCTION _ec309_vente(uuid, uuid, numeric, numeric);
SELECT _audit_assert('309');

