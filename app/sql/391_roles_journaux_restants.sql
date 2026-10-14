-- ═══════════════════════════════════════════════════════════════════════════
-- 391 — roles_journaux_restants : les derniers journaux en dur (LOC1-09)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. LOC1-09 : plus AUCUN code de journal en dur dans les fonctions
-- effectives. Les 4 triggers de ventes/achats/règlements (`386`) et le stock/POS
-- (`387`/`388`) étaient déjà faits ; restent **9 fonctions**. Cette migration en
-- traite **3** (les plus courtes) ; les 6 autres suivent (même méthode).
--
-- ÉCRITURES IDENTIQUES. Le pack PCG rend exactement les codes d'aujourd'hui :
-- `JOURNAL_A_NOUVEAUX→AN`, `JOURNAL_OD→OD`, `JOURNAL_VENTES→VT`,
-- `JOURNAL_ACHATS→AC`. Aucune écriture ne change.
--
-- ⚠ CE QUI RESTE EN DUR ICI, ET POURQUOI. Le compte `890000` (« Bilan
-- d'ouverture ») reste un littéral : c'est un COMPTE, pas un journal — il relève
-- de LOC1-10/11 (comptes en dur), et le catalogue fermé ne le nomme pas encore.
-- De même, `411000`/`666000`/`766000` dans l'écart de change.
--
-- Numéro pris le 2026-10-11T05:33:09.236Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Solde d'ouverture d'un compte bancaire → journal AN
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.bank_account_post_opening_balance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fy fiscal_years%ROWTYPE;
  v_amount numeric := round(coalesce(NEW.balance, 0), 2);
  v_entry uuid;
  v_number text;
  v_journal text;
BEGIN
  IF v_amount = 0 THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = NEW.tenant_id AND current_date BETWEEN start_date AND end_date LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO v_fy FROM fiscal_years
    WHERE tenant_id = NEW.tenant_id AND status NOT IN ('closed', 'locked')
    ORDER BY start_date DESC LIMIT 1;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solde initial de % : aucun exercice ouvert pour le comptabiliser — créez l''exercice, ou créez le compte avec un solde nul',
      NEW.name USING ERRCODE = 'check_violation';
  END IF;

  -- LOC1-09 : le journal des à-nouveaux vient du RÔLE, et il est garanti
  PERFORM ensure_standard_journals(NEW.tenant_id);
  v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_A_NOUVEAUX');

  IF EXISTS (
    SELECT 1 FROM journal_entries je JOIN journal_lines jl ON jl.journal_id = je.id
    WHERE je.tenant_id = NEW.tenant_id AND je.journal_code = v_journal AND je.fiscal_year_id = v_fy.id
      AND coalesce(jl.account_general, jl.account_code) = NEW.account_code) THEN
    RAISE EXCEPTION 'L''exercice % porte déjà un à-nouveau sur le compte % : pas de double ouverture',
      v_fy.code, NEW.account_code USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO chart_accounts (tenant_id, code, name, type)
  VALUES (NEW.tenant_id, '890000', 'Bilan d''ouverture', 'equity')
  ON CONFLICT (tenant_id, code) DO NOTHING;

  v_number := get_next_piece_number(v_journal);
  INSERT INTO journal_entries (tenant_id, number, piece_number, date, journal_code, status, description, reference)
  VALUES (NEW.tenant_id, v_number, v_number, v_fy.start_date, v_journal, 'draft',
          'Solde d''ouverture — ' || coalesce(NEW.name, NEW.account_code), 'BANK-OPEN-' || NEW.id)
  RETURNING id INTO v_entry;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order)
  VALUES
    (NEW.tenant_id, v_entry, NEW.account_code, NEW.account_code, coalesce(NEW.name, 'Banque'),
     greatest(v_amount, 0), greatest(-v_amount, 0), 'Solde d''ouverture', 0),
    (NEW.tenant_id, v_entry, '890000', '890000', 'Bilan d''ouverture',
     greatest(-v_amount, 0), greatest(v_amount, 0), 'Solde d''ouverture', 1);
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;   -- le noyau valide (et rafraîchit le solde)
  RETURN NULL;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 2. Stock initial → journal AN, sur le rôle
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.stock_initial_post_opening_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fy fiscal_years%ROWTYPE;
  v_amount numeric := round(COALESCE(NEW.quantity, 0) * COALESCE(NEW.unit_cost, 0), 2);
  v_date date := COALESCE(NEW.movement_date, NEW.date, CURRENT_DATE);
  v_stock_account text;
  v_nom text;
  v_entry uuid;
  v_number text;
  v_journal text;
BEGIN
  IF NEW.movement_type IS DISTINCT FROM 'initial' OR v_amount <= 0 THEN
    RETURN NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM journal_entries je
              WHERE je.tenant_id = NEW.tenant_id AND je.reference = 'STOCK-OPEN-' || NEW.id) THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_fy FROM fiscal_years
  WHERE tenant_id = NEW.tenant_id AND v_date BETWEEN start_date AND end_date LIMIT 1;
  IF NOT FOUND THEN
    SELECT * INTO v_fy FROM fiscal_years
    WHERE tenant_id = NEW.tenant_id AND status NOT IN ('closed', 'locked')
    ORDER BY start_date DESC LIMIT 1;
  END IF;
  IF NOT FOUND THEN
    RAISE WARNING 'Stock initial (mouvement %) : aucun exercice pour porter l''écriture d''à-nouveau — le stock est enregistré, l''écriture reste à passer.', NEW.id;
    RETURN NULL;
  END IF;

  SELECT p.name INTO v_nom FROM products p WHERE p.id = NEW.product_id AND p.tenant_id = NEW.tenant_id;
  v_stock_account := resolve_stock_account(NEW.product_id);

  -- LOC1-09 : le journal des à-nouveaux vient du RÔLE (les journaux sont garantis)
  PERFORM ensure_standard_journals(NEW.tenant_id);
  v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_A_NOUVEAUX');

  INSERT INTO chart_accounts (tenant_id, code, name, type)
  VALUES (NEW.tenant_id, '890000', 'Bilan d''ouverture', 'equity')
  ON CONFLICT (tenant_id, code) DO NOTHING;
  INSERT INTO chart_accounts (tenant_id, code, name, type)
  VALUES (NEW.tenant_id, v_stock_account, 'Stocks', 'asset')
  ON CONFLICT (tenant_id, code) DO NOTHING;

  v_number := get_next_piece_number(v_journal);
  INSERT INTO journal_entries (tenant_id, number, piece_number, date, journal_code, status, description, reference)
  VALUES (NEW.tenant_id, v_number, v_number, v_fy.start_date, v_journal, 'draft',
          'Stock d''ouverture — ' || COALESCE(v_nom, 'article'), 'STOCK-OPEN-' || NEW.id)
  RETURNING id INTO v_entry;
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_name, debit, credit, description, line_order, product_id, quantity)
  VALUES
    (NEW.tenant_id, v_entry, v_stock_account, v_stock_account, 'Stocks',
     v_amount, 0, 'Stock d''ouverture — ' || COALESCE(v_nom, 'article'), 0, NEW.product_id, NEW.quantity),
    (NEW.tenant_id, v_entry, '890000', '890000', 'Bilan d''ouverture',
     0, v_amount, 'Stock d''ouverture — ' || COALESCE(v_nom, 'article'), 1, NULL, NULL);
  UPDATE journal_entries SET status = 'posted' WHERE id = v_entry;
  RETURN NULL;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 3. Écart de change sur règlement → journal OD
--    (les COMPTES 411000/666000/766000 restent : ce sont des comptes, LOC1-10/11)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.post_exchange_gain_loss_on_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_journal text;
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

  -- LOC1-09 : le journal vient du RÔLE
  v_journal := resolve_journal(NEW.tenant_id, 'JOURNAL_OD');

  v_num := 'ECART-' || COALESCE(NULLIF(NEW.number, ''), left(NEW.id::text, 8));
  INSERT INTO public.journal_entries (
    tenant_id, number, date, journal_code, status, description, reference, piece_number
  ) VALUES (
    NEW.tenant_id, v_num, COALESCE(NEW.payment_date, CURRENT_DATE), v_journal, 'draft',
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
$function$;
