-- ============================================================
-- 309_exchange_gain_loss_revaluation.sql — W7 (M-01, fin) :
-- l'écart de change au règlement, et la réévaluation de clôture
--
-- M01-03 🟠 « `ExchangeGainLossPage` lit `exchange_gain_loss_entries` ;
-- `CurrencyRevaluationPage` lit `currency_revaluations`. **Aucune fonction SQL
-- et aucun appel du front n'écrit dans ces deux tables** — `createExchangeGainLossEntry`
-- n'a aucun appelant. Les deux écrans sont vides à vie. L'écart de change au
-- règlement (666/766) et la réévaluation de clôture ne sont pas implémentés. »
--
-- La 306 a posé ce sans quoi rien de tout cela n'était possible : la **devise**,
-- le **montant en devise** (signé) et le **taux** sur chaque ligne d'écriture.
-- La 309 les utilise.
--
-- 1. L'ÉCART DE CHANGE AU RÈGLEMENT (666 / 766)
--    `post_exchange_gain_loss_on_payment` — déclencheur sur `customer_payments` :
--    quand un règlement est enregistré sur une facture en devise, la différence
--    entre ce que la pièce a valu au grand livre (montant en devise × taux de la
--    pièce) et ce qui a été réellement encaissé (montant en devise de tenue) est
--    constatée : **gain** (D client / C 766) si l'on encaisse plus que comptabilisé,
--    **perte** (D 666 / C client) sinon. La ligne est tracée dans
--    `exchange_gain_loss_entries` et le montant sur `customer_payments.exchange_gain_loss`.
--    Idempotent : un règlement déjà traité n'est pas retraité.
--
-- 2. LA RÉÉVALUATION DE CLÔTURE (`currency_revaluations`)
--    `revaluate_currency_balances(p_period_date)` — relevé, à la date de clôture,
--    des soldes **en devise** des comptes de tiers (41x / 40x), réévalués au taux
--    du jour (`exchange_rates`) : l'écart va dans `currency_revaluations` et dans
--    une écriture (411/401 contre 666/766). Idempotent par période : une période
--    déjà réévaluée est **refusée**, pas réécrite en silence.
--
-- LIMITES, DITES.
--   • Le règlement doit être **dans la devise de la pièce** : un règlement en
--     devise croisée (une facture USD réglée en GBP) n'a pas d'écart constaté —
--     il faudrait un taux de croisement, qui n'est pas saisi aujourd'hui.
--   • Les comptes utilisés sont ceux du plan : `666000` (pertes) et `766000`
--     (gains) — le plan standard les porte. Un plan sans eux est refusé par le
--     noyau au moment de valider l'écriture.
--   • La réévaluation ne **reprend pas** les écritures déjà réévaluées d'un mois
--     antérieur : elle constate, à chaque date, l'écart avec le taux du jour.
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_currency_reval_period_tenant
  ON public.currency_revaluations (tenant_id, period_date);

-- ------------------------------------------------------------
-- 1. L'écart de change au règlement (666 / 766)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.post_exchange_gain_loss_on_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_inv invoices%ROWTYPE;
  v_fonc text;
  v_dev text;
  v_taux numeric;
  v_montant_dev numeric;
  v_ecart numeric;
  v_collectif text;
  v_entry uuid;
  v_num text;
  v_taux_paiement numeric;
BEGIN
  -- Seulement à l'entrée dans les statuts qui comptent le règlement
  IF NOT (NEW.status IN ('recorded', 'reconciled')) THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  IF NEW.invoice_id IS NULL THEN RETURN NEW; END IF;
  -- Déjà traité : le montant d'écart est posé
  IF COALESCE(NEW.exchange_gain_loss, 0) <> 0 THEN RETURN NEW; END IF;

  SELECT * INTO v_inv FROM public.invoices
  WHERE id = NEW.invoice_id AND tenant_id = NEW.tenant_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_fonc := public.functional_currency(NEW.tenant_id);
  v_dev := COALESCE(NULLIF(v_inv.currency_code, ''), v_fonc);
  -- Une pièce en devise de tenue n'a pas d'écart de change
  IF v_dev = v_fonc THEN RETURN NEW; END IF;
  -- Règlement dans une autre devise que la pièce : hors périmètre (taux croisé)
  IF COALESCE(NULLIF(NEW.currency_code, ''), v_dev) <> v_dev THEN RETURN NEW; END IF;

  v_taux := COALESCE(NULLIF(v_inv.exchange_rate, 0), 1);
  v_montant_dev := COALESCE(NEW.amount_currency, NEW.amount);
  -- Ce qui a été encaissé, contre ce que la pièce a valu au grand livre :
  -- positif → on a encaissé **plus** que comptabilisé (gain), négatif → perte.
  v_ecart := round(COALESCE(NEW.amount, 0) - v_montant_dev * v_taux, 2);
  IF v_ecart = 0 THEN RETURN NEW; END IF;

  SELECT COALESCE(c.account_collectif, '411000') INTO v_collectif
  FROM public.customers c
  WHERE c.id = v_inv.customer_id AND c.tenant_id = NEW.tenant_id;
  v_collectif := COALESCE(v_collectif, '411000');

  v_num := 'ECART-' || COALESCE(NULLIF(NEW.number, ''), left(NEW.id::text, 8));
  INSERT INTO public.journal_entries (
    tenant_id, number, date, journal_code, status, description, reference, piece_number
  ) VALUES (
    NEW.tenant_id, v_num, COALESCE(NEW.payment_date, CURRENT_DATE), 'OD', 'draft',
    'Écart de change sur règlement ' || COALESCE(NEW.number, ''), v_num, v_num
  ) RETURNING id INTO v_entry;

  IF v_ecart > 0 THEN
    -- Encaissé plus que comptabilisé : gain
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      account_tiers, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, v_collectif, v_collectif, NULL, v_ecart, 0, 'Écart de change (gain) — ' || v_num, 0);
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, '766000', '766000', 0, v_ecart, 'Gain de change — ' || v_num, 1);
  ELSE
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, '666000', '666000', abs(v_ecart), 0, 'Perte de change — ' || v_num, 0);
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      account_tiers, debit, credit, description, line_order)
    VALUES (NEW.tenant_id, v_entry, v_collectif, v_collectif, NULL, 0, abs(v_ecart), 'Écart de change (perte) — ' || v_num, 1);
  END IF;

  UPDATE public.journal_entries SET status = 'posted'
  WHERE id = v_entry AND tenant_id = NEW.tenant_id;

  v_taux_paiement := CASE WHEN v_montant_dev <> 0
                          THEN round(COALESCE(NEW.amount, 0) / v_montant_dev, 6) ELSE v_taux END;

  INSERT INTO public.exchange_gain_loss_entries (
    tenant_id, payment_id, invoice_id, type, amount,
    exchange_rate_original, exchange_rate_payment,
    account_gain_code, account_loss_code, journal_entry_id
  ) VALUES (
    NEW.tenant_id, NEW.id, NEW.invoice_id, 'receivable', abs(v_ecart),
    v_taux, v_taux_paiement, '766000', '666000', v_entry
  );

  UPDATE public.customer_payments
  SET exchange_gain_loss = v_ecart
  WHERE id = NEW.id AND tenant_id = NEW.tenant_id;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.post_exchange_gain_loss_on_payment() FROM PUBLIC, anon;

DROP TRIGGER IF EXISTS post_exchange_gain_loss_on_payment ON public.customer_payments;
CREATE TRIGGER post_exchange_gain_loss_on_payment
  AFTER INSERT OR UPDATE OF status
  ON public.customer_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.post_exchange_gain_loss_on_payment();


-- ------------------------------------------------------------
-- 2. La réévaluation de clôture (`currency_revaluations` + 666/766)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revaluate_currency_balances(p_period_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fonc text;
  v_fiche uuid;
  v_nb int := 0;
  v_sans_taux int := 0;
  v_total numeric := 0;
  v_entry uuid;
  v_num text;
  v_ordre int := 0;
  r record;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;
  IF p_period_date IS NULL THEN
    RAISE EXCEPTION 'Date de réévaluation absente' USING ERRCODE = '22007';
  END IF;
  -- Idempotence : une période déjà réévaluée est refusée, pas réécrite en silence.
  IF EXISTS (SELECT 1 FROM public.currency_revaluations
             WHERE tenant_id = v_tid AND period_date = p_period_date AND status <> 'cancelled') THEN
    RAISE EXCEPTION 'La période du % a déjà été réévaluée', p_period_date USING ERRCODE = '23505';
  END IF;

  v_fonc := public.functional_currency(v_tid);
  SELECT id INTO v_fiche FROM public.fiscal_years
  WHERE tenant_id = v_tid AND p_period_date BETWEEN start_date AND end_date LIMIT 1;

  -- Les soldes **en devise** des comptes de tiers, au taux du jour.
  -- `exchange_rates` : `quote_currency` est la devise, `rate` sa valeur dans la
  -- devise de tenue.
  INSERT INTO public.currency_revaluations (
    tenant_id, fiscal_year_id, period_date, account_code, third_party_code, currency,
    original_rate, new_rate, original_amount, original_amount_eur, revalued_amount_eur,
    gain_loss, type, status
  )
  SELECT v_tid, v_fiche, p_period_date, x.compte, x.tiers, x.dev,
         CASE WHEN x.solde_devise <> 0 THEN round(x.histo / x.solde_devise, 6) ELSE 1 END,
         t.rate, x.solde_devise, x.histo, round(x.solde_devise * t.rate, 2),
         round(x.solde_devise * t.rate, 2) - x.histo,
         CASE WHEN left(x.compte, 2) = '41' THEN 'receivable' ELSE 'payable' END,
         'pending'
  FROM (
    SELECT COALESCE(l.account_general, l.account_code) AS compte,
           COALESCE(l.account_tiers, '') AS tiers,
           l.currency_code AS dev,
           round(sum(l.currency_amount), 2) AS solde_devise,
           round(sum(l.debit - l.credit), 2) AS histo
    FROM public.journal_lines l
    JOIN public.journal_entries e ON e.id = l.journal_id AND e.tenant_id = l.tenant_id
    WHERE l.tenant_id = v_tid
      AND e.status = 'posted'
      AND e.date <= p_period_date
      AND l.currency_code IS NOT NULL AND l.currency_code <> v_fonc
      AND COALESCE(l.account_general, l.account_code) ~ '^4[01]'
    GROUP BY 1, 2, 3
    HAVING round(sum(l.currency_amount), 2) <> 0
  ) x
  JOIN LATERAL (
    SELECT er.rate FROM public.exchange_rates er
    WHERE (er.tenant_id = v_tid OR er.tenant_id IS NULL)
      AND er.quote_currency = x.dev
      AND (er.base_currency IS NULL OR er.base_currency = v_fonc)
      AND er.rate_date <= p_period_date
    ORDER BY er.rate_date DESC LIMIT 1
  ) t ON true;
  GET DIAGNOSTICS v_nb = ROW_COUNT;


  -- Les soldes en devise **sans taux** ne sont pas réévalués : ils sont comptés
  -- et rendus, plutôt que réévalués à un taux inventé.
  SELECT count(*) INTO v_sans_taux
  FROM (
    SELECT COALESCE(l.account_general, l.account_code) AS compte,
           COALESCE(l.account_tiers, '') AS tiers, l.currency_code AS dev
    FROM public.journal_lines l
    JOIN public.journal_entries e ON e.id = l.journal_id AND e.tenant_id = l.tenant_id
    WHERE l.tenant_id = v_tid AND e.status = 'posted' AND e.date <= p_period_date
      AND l.currency_code IS NOT NULL AND l.currency_code <> v_fonc
      AND COALESCE(l.account_general, l.account_code) ~ '^4[01]'
    GROUP BY 1, 2, 3
    HAVING round(sum(l.currency_amount), 2) <> 0
      AND NOT EXISTS (SELECT 1 FROM public.exchange_rates er
                      WHERE (er.tenant_id = v_tid OR er.tenant_id IS NULL)
                        AND er.quote_currency = l.currency_code
                        AND er.rate_date <= p_period_date)
  ) s;

  IF v_nb = 0 THEN
    RETURN jsonb_build_object('period_date', p_period_date, 'lines', 0,
                              'gain_loss', 0, 'without_rate', v_sans_taux, 'entry_id', NULL);
  END IF;

  SELECT COALESCE(sum(gain_loss), 0) INTO v_total
  FROM public.currency_revaluations
  WHERE tenant_id = v_tid AND period_date = p_period_date AND status = 'pending';

  -- L'écriture de réévaluation : le solde de chaque tiers, contre 766 (gain) ou
  -- 666 (perte). Le total des ajustements équilibre la contrepartie.
  v_num := 'REVAL-' || to_char(p_period_date, 'YYYY-MM-DD');
  INSERT INTO public.journal_entries (
    tenant_id, number, date, journal_code, status, description, reference, piece_number
  ) VALUES (
    v_tid, v_num, p_period_date, 'OD', 'draft',
    'Réévaluation des créances et dettes en devises au ' || p_period_date, v_num, v_num
  ) RETURNING id INTO v_entry;

  FOR r IN
    SELECT * FROM public.currency_revaluations
    WHERE tenant_id = v_tid AND period_date = p_period_date AND status = 'pending'
      AND gain_loss <> 0
    ORDER BY account_code, third_party_code
  LOOP
    IF r.gain_loss > 0 THEN
      INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                        account_tiers, debit, credit, description, line_order)
      VALUES (v_tid, v_entry, r.account_code, r.account_code,
              NULLIF(r.third_party_code, ''), r.gain_loss, 0,
              'Réévaluation ' || r.currency || ' — ' || r.account_code, v_ordre);
    ELSE
      INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                        account_tiers, debit, credit, description, line_order)
      VALUES (v_tid, v_entry, r.account_code, r.account_code,
              NULLIF(r.third_party_code, ''), 0, abs(r.gain_loss),
              'Réévaluation ' || r.currency || ' — ' || r.account_code, v_ordre);
    END IF;
    v_ordre := v_ordre + 1;
  END LOOP;

  IF v_total > 0 THEN
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      debit, credit, description, line_order)
    VALUES (v_tid, v_entry, '766000', '766000', 0, v_total, 'Gain de change (réévaluation)', v_ordre);
  ELSIF v_total < 0 THEN
    INSERT INTO public.journal_lines (tenant_id, journal_id, account_code, account_general,
                                      debit, credit, description, line_order)
    VALUES (v_tid, v_entry, '666000', '666000', abs(v_total), 0, 'Perte de change (réévaluation)', v_ordre);
  END IF;

  UPDATE public.journal_entries SET status = 'posted' WHERE id = v_entry AND tenant_id = v_tid;
  UPDATE public.currency_revaluations
  SET status = 'posted', entry_id = v_entry, updated_at = now()
  WHERE tenant_id = v_tid AND period_date = p_period_date AND status = 'pending';

  RETURN jsonb_build_object('period_date', p_period_date, 'lines', v_nb,
                            'gain_loss', v_total, 'without_rate', v_sans_taux, 'entry_id', v_entry);
END;
$$;

COMMENT ON FUNCTION public.revaluate_currency_balances(date) IS
  'Réévaluation de clôture des créances et dettes en devise : soldes en devise au taux du jour, écart en 666/766, écriture et lignes dans currency_revaluations. Idempotente par période. 309 (W7).';

REVOKE EXECUTE ON FUNCTION public.revaluate_currency_balances(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revaluate_currency_balances(date) TO authenticated;

