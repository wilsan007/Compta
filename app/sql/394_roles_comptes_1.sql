-- ═══════════════════════════════════════════════════════════════════════════
-- 394 — roles_comptes_1 : les comptes en dur, tranche 1 (LOC1-10)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CE QUE C'EST. Le garde-fou E01 (`scripts/check-country-neutral.mjs`) compte
-- les comptes écrits en clair dans les définitions de fonctions. Cette tranche
-- traite les SIX plus simples — correspondances EXACTES (le pack PCG rend le
-- même numéro), donc AUCUNE écriture ne change :
--
--   treasury_for_payment               530000 → CAISSE, 512000 → BANQUE
--                                      (+ les journaux CA / BQ → rôles)
--   letter_advance_invoice             419100 → CLIENTS_AVANCES_RECUES
--   sync_customer_third_party_account  411000 → CLIENTS
--   sync_supplier_third_party_account  401000 → FOURNISSEURS
--   backfill_third_party_accounts      411000 / 401000 / 421000 → CLIENTS /
--                                      FOURNISSEURS / PERSONNEL_REMUNERATIONS_DUES
--   sync_commitments_on_purchase_order 607000 → ACHATS_MARCHANDISES
--
-- ⚠ RESTENT MESURÉES, PARCE QUE LES RÉÉCRIRE CHANGERAIT LES ÉCRITURES — c'est
-- un arbitrage, pas une correction : `generate_depreciation_entry` (681200 là où
-- le pack porte DOTATIONS_AMORTISSEMENTS = 681100, et 281000 quand AMORTISSEMENTS
-- n'est pas mappé) et `ensure_pos_payment_methods` (511200 quand
-- MOYENS_PAIEMENT_A_ENCAISSER vaut 511000). Le compteur E01 descend donc de
-- **24 à 21** — pas à 18 : ce qui reste est NOMMÉ, pas oublié.
--
-- `treasury_for_payment` portait aussi les journaux `CA` / `BQ` en clair : ils
-- passent par le rôle. La fonction est STABLE, elle ne peut donc pas les SEMER
-- (`ensure_standard_journals` est VOLATILE) — ses appelants le font déjà.
--
-- Numéro pris le 2026-10-11T09:16:26.839Z par migration-numero.mjs
-- (ligne « plan6 C (lot K, Djibouti) », branche plan6/c-localisation).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. Trésorerie d'un règlement : caisse ou banque, journal compris
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.treasury_for_payment(p_tenant uuid, p_bank_account uuid, p_method text, OUT account_code text, OUT journal_code text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF p_bank_account IS NOT NULL THEN
    SELECT b.account_code, b.journal_code INTO account_code, journal_code
    FROM bank_accounts b WHERE b.id = p_bank_account AND b.tenant_id = p_tenant;
  END IF;
  IF account_code IS NULL THEN
    -- LOC1-10 : la caisse et la banque viennent du RÔLE (PCG : CAISSE = 530000,
    -- BANQUE = 512000) — et leur journal aussi (CAISSE = CA, BANQUE = BQ).
    IF p_method = 'cash' THEN
      account_code := resolve_account(p_tenant, 'CAISSE');
      journal_code := resolve_journal(p_tenant, 'JOURNAL_CAISSE');
    ELSE
      account_code := resolve_account(p_tenant, 'BANQUE');
      journal_code := resolve_journal(p_tenant, 'JOURNAL_BANQUE');
    END IF;
  END IF;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 2. Lettrage d'un acompte : le compte d'avance reçu
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.letter_advance_invoice(p_tenant uuid, p_advance uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_lines uuid[]; v_d numeric; v_c numeric; v_open int; v_code text; v_avance text;
BEGIN
  -- LOC1-10 : CLIENTS_AVANCES_RECUES = 419100 en PCG.
  v_avance := resolve_account(p_tenant, 'CLIENTS_AVANCES_RECUES');
  SELECT array_agg(id), COALESCE(sum(debit), 0), COALESCE(sum(credit), 0), count(*) FILTER (WHERE lettrage_code IS NULL)
    INTO v_lines, v_d, v_c, v_open
  FROM journal_lines
  WHERE tenant_id = p_tenant AND account_code = v_avance AND reference = 'ACOMPTE:' || p_advance;
  IF v_open = COALESCE(array_length(v_lines, 1), 0) AND v_open > 1 AND v_d = v_c THEN
    v_code := next_lettrage_code_for(p_tenant);
    UPDATE journal_lines SET lettrage_code = v_code, lettrage_date = CURRENT_DATE
    WHERE id = ANY(v_lines);
  END IF;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 3. Compte de tiers du client : le collectif par défaut
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_customer_third_party_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public.upsert_third_party_account(
    NEW.tenant_id,
    'customer',
    NULLIF(btrim(COALESCE(NEW.account_tiers, '')), ''),
    NEW.name,
    -- LOC1-10 : à défaut de collectif saisi, le RÔLE CLIENTS (PCG : 411000).
    COALESCE(NULLIF(btrim(COALESCE(NEW.account_collectif, '')), ''),
             resolve_account(NEW.tenant_id, 'CLIENTS')),
    COALESCE(NEW.credit_limit, 0),
    COALESCE(NEW.active, true),
    NEW.id,
    NULL);
  RETURN NULL;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 4. Compte de tiers du fournisseur : le collectif par défaut
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_supplier_third_party_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  PERFORM public.upsert_third_party_account(
    NEW.tenant_id,
    'supplier',
    NULLIF(btrim(COALESCE(NEW.account_tiers, '')), ''),
    NEW.name,
    -- LOC1-10 : à défaut de collectif saisi, le RÔLE FOURNISSEURS (PCG : 401000).
    COALESCE(NULLIF(btrim(COALESCE(NEW.account_collectif, '')), ''),
             resolve_account(NEW.tenant_id, 'FOURNISSEURS')),
    0,
    COALESCE(NEW.active, true),
    NULL,
    NEW.id);
  RETURN NULL;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 5. Rattrapage des comptes de tiers : les trois collectifs
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.backfill_third_party_accounts(p_tenant_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_n int := 0;
  v_step int := 0;
  -- LOC1-10 : les trois collectifs viennent des RÔLES, résolus UNE fois
  -- (PCG : CLIENTS = 411000, FOURNISSEURS = 401000, PERSONNEL_REMUNERATIONS_DUES
  -- = 421000). Résolus en tête : un pack qui ne les mappe pas doit échouer ici,
  -- AVANT d'écrire des dizaines de lignes de tiers.
  v_clients text;
  v_fournisseurs text;
  v_personnel text;
BEGIN
  IF p_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Rattrapage des comptes de tiers : la société est obligatoire' USING ERRCODE = 'null_value_not_allowed';
  END IF;

  v_clients := resolve_account(p_tenant_id, 'CLIENTS');
  v_fournisseurs := resolve_account(p_tenant_id, 'FOURNISSEURS');
  v_personnel := resolve_account(p_tenant_id, 'PERSONNEL_REMUNERATIONS_DUES');

  INSERT INTO third_party_accounts
    (tenant_id, code, type, name, account_general_code, credit_limit, active, customer_id)
  SELECT c.tenant_id, c.account_tiers, 'customer', c.name,
         COALESCE(NULLIF(btrim(COALESCE(c.account_collectif, '')), ''), v_clients),
         COALESCE(c.credit_limit, 0), COALESCE(c.active, true), c.id
  FROM customers c
  WHERE c.tenant_id = p_tenant_id
    AND NULLIF(btrim(COALESCE(c.account_tiers, '')), '') IS NOT NULL
  ORDER BY c.created_at, c.id
  ON CONFLICT (tenant_id, code) DO NOTHING;
  GET DIAGNOSTICS v_step = ROW_COUNT;
  v_n := v_n + v_step;

  INSERT INTO third_party_accounts
    (tenant_id, code, type, name, account_general_code, credit_limit, active, supplier_id)
  SELECT s.tenant_id, s.account_tiers, 'supplier', s.name,
         COALESCE(NULLIF(btrim(COALESCE(s.account_collectif, '')), ''), v_fournisseurs),
         0, COALESCE(s.active, true), s.id
  FROM suppliers s
  WHERE s.tenant_id = p_tenant_id
    AND NULLIF(btrim(COALESCE(s.account_tiers, '')), '') IS NOT NULL
  ORDER BY s.created_at, s.id
  ON CONFLICT (tenant_id, code) DO NOTHING;
  GET DIAGNOSTICS v_step = ROW_COUNT;
  v_n := v_n + v_step;

  -- Les salariés : le grand livre de la paie porte le matricule comme compte
  -- auxiliaire du 421 (mesuré : `421000 / M430080`), donc un salarié sans compte
  -- de tiers est un libellé manquant dans le FEC et dans le lettrage.
  INSERT INTO third_party_accounts
    (tenant_id, code, type, name, account_general_code, credit_limit, active)
  SELECT e.tenant_id, e.employee_number, 'employee', e.name, v_personnel,
         0, COALESCE(e.status, 'active') <> 'inactive'
  FROM employees e
  WHERE e.tenant_id = p_tenant_id
    AND NULLIF(btrim(COALESCE(e.employee_number, '')), '') IS NOT NULL
  ORDER BY e.created_at, e.id
  ON CONFLICT (tenant_id, code) DO NOTHING;
  GET DIAGNOSTICS v_step = ROW_COUNT;
  v_n := v_n + v_step;

  RETURN v_n;
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 6. Engagement budgétaire d'une commande d'achat : le compte de charge
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_commitments_on_purchase_order()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fy uuid;
  v_ligne RECORD;
  v_nb int := 0;
BEGIN
  -- Annulation : l'engagement encore actif part avec elle.
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    UPDATE public.budget_commitments
    SET status = 'cancelled', updated_at = now()
    WHERE tenant_id = NEW.tenant_id AND source_type = 'purchase_order'
      AND source_id = NEW.id AND status = 'active';
    RETURN NEW;
  END IF;

  IF NOT (NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM 'confirmed') THEN
    RETURN NEW;
  END IF;

  -- L'exercice qui contient la date de la commande
  SELECT id INTO v_fy FROM public.fiscal_years
  WHERE tenant_id = NEW.tenant_id
    AND COALESCE(NEW.order_date, CURRENT_DATE) BETWEEN start_date AND end_date
  LIMIT 1;

  -- Un engagement par compte de charge (compte de l'article, sinon de sa
  -- catégorie, sinon le RÔLE ACHATS_MARCHANDISES — PCG : 607000) : c'est le
  -- compte que le budget suit. LOC1-10 : le repli est résolu ICI, quand il sert
  -- — une simple mise à jour de statut ne doit pas dépendre du mappage du pack.
  FOR v_ligne IN
    SELECT COALESCE(p.purchase_account_code, pc.purchase_account_code,
                    resolve_account(NEW.tenant_id, 'ACHATS_MARCHANDISES')) AS compte,
           COALESCE(SUM(pol.line_total), 0) AS montant
    FROM public.purchase_order_lines pol
    LEFT JOIN public.products p ON p.id = pol.product_id AND p.tenant_id = NEW.tenant_id
    LEFT JOIN public.product_categories pc ON pc.id = p.category_id AND pc.tenant_id = NEW.tenant_id
    WHERE pol.purchase_order_id = NEW.id AND pol.tenant_id = NEW.tenant_id
    GROUP BY 1
  LOOP
    v_nb := v_nb + 1;
    INSERT INTO public.budget_commitments (
      tenant_id, description, account_code, fiscal_year_id, amount, commitment_date,
      source_type, source_id, status, supplier_id
    ) VALUES (
      NEW.tenant_id, 'Commande ' || NEW.number, v_ligne.compte, v_fy, v_ligne.montant,
      COALESCE(NEW.order_date, CURRENT_DATE), 'purchase_order', NEW.id, 'active', NEW.supplier_id
    )
    ON CONFLICT (tenant_id, source_type, source_id, account_code) WHERE source_id IS NOT NULL
    DO NOTHING;
  END LOOP;

  -- Commande sans ligne : le total d'en-tête sur le compte de charge par défaut
  IF v_nb = 0 AND COALESCE(NEW.subtotal, 0) > 0 THEN
    INSERT INTO public.budget_commitments (
      tenant_id, description, account_code, fiscal_year_id, amount, commitment_date,
      source_type, source_id, status, supplier_id
    ) VALUES (
      NEW.tenant_id, 'Commande ' || NEW.number,
      resolve_account(NEW.tenant_id, 'ACHATS_MARCHANDISES'),
      v_fy, NEW.subtotal,
      COALESCE(NEW.order_date, CURRENT_DATE), 'purchase_order', NEW.id, 'active', NEW.supplier_id
    )
    ON CONFLICT (tenant_id, source_type, source_id, account_code) WHERE source_id IS NOT NULL
    DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

