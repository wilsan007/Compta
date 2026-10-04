-- ============================================================
-- 267_nf525_closure_tests.sql — vague W10 : le contrat front ↔ base, et la clôture NF-525
--
-- MESURÉ AVANT, sur base neuve (235 migrations, 0 erreur) :
--
--   (a) le contrôle `scripts/check-rpc-contract.mjs` trouvait **14 contrats
--       rompus** sur 117 appels `.rpc()` littéraux du front et des Edge
--       Functions, dont quatre fonctions de DÉCLENCHEUR (`RETURNS trigger`)
--       appelées depuis des écrans vivants — que PostgREST n'expose jamais :
--         perform_three_way_match         (BEFORE UPDATE purchase_invoices)
--         check_customer_credit_limit     (BEFORE UPDATE sales_orders)
--         apply_bank_reconciliation_rules (BEFORE INSERT bank_transactions)
--         auto_reconcile_by_score         (AFTER INSERT bank_transactions)
--       … et deux appels au stock qui, s'ils avaient abouti, auraient compté
--       DEUX fois le même mouvement : `increment_stock` / `decrement_stock` avec
--       `p_id` / `qty`, alors que `update_stock_on_movement` fait déjà le travail.
--
--   (b) la clôture NF-525 était IMPOSSIBLE :
--         ERROR: NF525: Le journal d'événements est inaltérable. Modification interdite.
--       `close_nf525_period` faisait `UPDATE nf525_event_log SET closed = true` en
--       comptant sur `SECURITY DEFINER` pour « contourner » le déclencheur
--       `prevent_nf525_modification` — un déclencheur n'est pas contourné par
--       SECURITY DEFINER. Ce drapeau `closed` n'était LU PAR PERSONNE, et rien
--       n'insérait dans `nf525_period_closures`, la table que lit
--       `get_nf525_attestation` : l'attestation levait « Période non clôturée ».
--
-- Ce que ce fichier prouve, côté BASE :
--   T01 le déclencheur est le SEUL moteur du stock : un mouvement, une variation
--   T02 les anciens noms d'arguments sont REFUSÉS par la base (42883)
--   T03 les quatre fonctions de déclencheur ne sont pas des RPC, et les lecteurs
--       réels que le front doit appeler existent
--   T04 la clôture NF-525 aboutit, ÉCRIT la clôture (append-only) et refuse une
--       seconde clôture — ROUGE avant la 267, vert avec elle
--   T05 l'attestation du mois est rendue, et une DATE est refusée (format AAAA-MM)
--   T06 la paie IJSS se calcule sur l'ARRÊT, pas sur un couple (salarié, jours)
--
-- T01, T02, T03 et T06 sont des gardes : la base était déjà correcte, c'est le
-- FRONT qui ne l'appelait pas. T04 est le seul ROUGE d'avant (267).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '267', false);
DELETE FROM _audit_results WHERE file = '267';

-- Société, dépôt, article — les mouvements sont posés par les scénarios.
CREATE OR REPLACE FUNCTION _mk_contract267(p_nom text, OUT t uuid, OUT wh uuid, OUT p uuid)
LANGUAGE plpgsql AS $$
BEGIN
  -- p_fy = true : le mouvement de stock écrit une écriture au journal ST, et
  -- `journal_entry_guard` refuse une date sans exercice qui la couvre.
  t := _mk_tenant(p_nom);
  INSERT INTO warehouses (tenant_id, code, name) VALUES (t, 'W-' || p_nom, 'Dépôt ' || p_nom)
    RETURNING id INTO wh;
  INSERT INTO products (tenant_id, name, sku, type, cost_price)
    VALUES (t, 'Article ' || p_nom, 'A-' || p_nom, 'stock', 0) RETURNING id INTO p;
END $$;

-- Un mouvement, exactement comme l'écran et le déclencheur le posent.
CREATE OR REPLACE FUNCTION _mv267(p_t uuid, p_p uuid, p_wh uuid, p_type text, p_qte numeric)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO stock_movements (tenant_id, product_id, warehouse_id, movement_type, type,
    quantity, unit_cost, reference, movement_date, date)
  VALUES (p_t, p_p, p_wh, p_type, p_type, p_qte, 10,
          'MV267-' || p_type || '-' || p_qte, CURRENT_DATE, CURRENT_DATE);
END $$;

-- ── T01 — un mouvement, UNE variation de stock ─────────────────────────────
-- Le déclencheur `update_stock_on_movement` couvre l'entrée, la sortie,
-- l'ajustement et l'initialisation. Le front appelait EN PLUS
-- `increment_stock({ p_id, qty })` : si cet appel avait abouti, l'article serait
-- passé de 0 à 10 pour une entrée de 5 (compté deux fois).
DO $$
DECLARE
  t uuid; wh uuid; p uuid; q_in numeric; q_out numeric; q_adj numeric;
BEGIN
  SELECT * INTO t, wh, p FROM _mk_contract267('W10T01');
  PERFORM _as_user();
  PERFORM _mv267(t, p, wh, 'in', 5);
  SELECT stock_quantity INTO q_in FROM products WHERE id = p AND tenant_id = t;
  PERFORM _mv267(t, p, wh, 'out', 2);
  SELECT stock_quantity INTO q_out FROM products WHERE id = p AND tenant_id = t;
  PERFORM _mv267(t, p, wh, 'adjustment', 12);
  SELECT stock_quantity INTO q_adj FROM products WHERE id = p AND tenant_id = t;

  PERFORM _rec('T01',
    'le déclencheur est le SEUL moteur : 5 → 5 (pas 10), sortie de 2 → 3, ajustement → 12',
    q_in = 5 AND q_out = 3 AND q_adj = 12,
    format('entrée=%s (5 attendu) ; sortie=%s (3 attendu) ; ajustement=%s (12 attendu)', q_in, q_out, q_adj));
END $$;

-- ── T02 — les anciens noms d'arguments sont REFUSÉS ────────────────────────
-- La contre-épreuve du défaut : `increment_stock(p_id, qty)`,
-- `close_nf525_period(p_period_end)` et `increment_download_count(doc_id)` ne
-- correspondent à AUCUNE signature — PostgREST renvoyait 404 et l'écriture
-- silencieuse ne se voyait pas.
DO $$
DECLARE
  refus text := '';
  t uuid;
BEGIN
  t := _mk_tenant('W10T02', false);
  PERFORM _as_user();

  BEGIN
    PERFORM increment_stock(p_id := gen_random_uuid(), qty := 1);
    refus := refus || ' increment_stock';
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  BEGIN
    PERFORM decrement_stock(p_id := gen_random_uuid(), qty := 1);
    refus := refus || ' decrement_stock';
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  BEGIN
    PERFORM close_nf525_period(p_period_end := '2026-09-30');
    refus := refus || ' close_nf525_period';
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  BEGIN
    PERFORM increment_download_count(doc_id := gen_random_uuid());
    refus := refus || ' increment_download_count';
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  PERFORM _rec('T02',
    'les quatre anciens noms d''arguments sont refusés par la base (undefined_function)',
    refus = '',
    format('acceptés à tort :%s', COALESCE(NULLIF(refus, ''), ' aucun')));
END $$;


-- ── T03 — les fonctions de déclencheur ne sont pas des RPC ─────────────────
-- PostgREST n'expose que les fonctions qui rendent une valeur, jamais un
-- `trigger`. Les quatre appels du front ne pouvaient donc que renvoyer 404 — et
-- les quatre lecteurs réels qui les remplacent existent bien.
DO $$
DECLARE
  v_trigger text := '';
  v_manquant text := '';
  n int;
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO v_trigger
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname IN ('perform_three_way_match', 'check_customer_credit_limit',
                      'apply_bank_reconciliation_rules', 'auto_reconcile_by_score')
    AND pg_get_function_result(p.oid) = 'trigger';

  -- Les remplaçants : le front les appelle dans le même commit.
  -- `run_three_way_match` (lecture du rapprochement) ; `customer_credit_score`
  -- (lecture du risque client) ; `smart_bank_reconciliation` (rapprochement à la
  -- demande) ; `increment_download_count` (compteur de téléchargements).
  SELECT count(*) INTO n
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.proname IN ('run_three_way_match', 'customer_credit_score',
                      'smart_bank_reconciliation', 'increment_download_count')
    AND pg_get_function_result(p.oid) <> 'trigger';

  SELECT coalesce(string_agg(x.n, ', '), '') INTO v_manquant
  FROM (VALUES ('run_three_way_match'), ('customer_credit_score'),
               ('smart_bank_reconciliation'), ('increment_download_count')) AS x(n)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace AND p.proname = x.n
      AND pg_get_function_result(p.oid) <> 'trigger');

  PERFORM _rec('T03',
    'les 4 fonctions de déclencheur ne sont pas des RPC, et les 4 lecteurs réels existent',
    v_trigger = 'apply_bank_reconciliation_rules, auto_reconcile_by_score, check_customer_credit_limit, perform_three_way_match'
      AND n = 4 AND v_manquant = '',
    format('déclencheurs trouvés=[%s] (4 attendus) ; lecteurs réels=%s (4 attendus) ; manquants=[%s]',
      v_trigger, n, v_manquant));
END $$;

-- ── T04 — la clôture NF-525 aboutit et se CONSTATE ─────────────────────────
-- ROUGE AVANT la 267 : `close_nf525_period` tentait un UPDATE du journal
-- inaltérable (`ERROR: NF525: Le journal d'événements est inaltérable`). Avec la
-- 267, la clôture AJOUTE son événement (le journal ne se réécrit pas) et inscrit
-- la clôture dans `nf525_period_closures` — là où l'attestation la lit.
-- Une seconde clôture de la même période est refusée.
DO $$
DECLARE
  t uuid;
  mois text := to_char(CURRENT_DATE, 'YYYY-MM');
  ev int;
  closure_rows int;
  refus_cloture text := '—';
  refus_double text := '—';
  info jsonb;
BEGIN
  t := _mk_tenant('W10T04', false);
  PERFORM _as_user();
  PERFORM log_nf525_event('W10-probe', 'audit', NULL, '{}'::jsonb, NULL, mois);
  PERFORM log_nf525_event('W10-probe', 'audit', NULL, '{}'::jsonb, NULL, mois);

  BEGIN
    info := close_nf525_period(mois);
    ev := (info ->> 'event_count')::int;
  EXCEPTION WHEN OTHERS THEN
    refus_cloture := SQLERRM;
  END;

  SELECT count(*) INTO closure_rows
  FROM nf525_period_closures WHERE tenant_id = t AND period = mois;

  BEGIN
    PERFORM close_nf525_period(mois);
  EXCEPTION WHEN OTHERS THEN
    refus_double := SQLERRM;
  END;

  PERFORM _rec('T04',
    'la clôture aboutit (2 événements), écrit la clôture append-only, et une seconde clôture est refusée',
    refus_cloture = '—' AND ev = 2 AND closure_rows = 1 AND refus_double <> '—',
    format('clôture=%s ; événements=%s (2 attendus) ; lignes de clôture=%s (1 attendue) ; seconde clôture → %s',
      refus_cloture, ev, closure_rows, refus_double));
END $$;

-- ── T05 — l'attestation est rendue, et le format est AAAA-MM ───────────────
-- Les déclencheurs écrivent `to_char(now(), 'YYYY-MM')` et l'attestation relit
-- `(p_period || '-01')::timestamp`. L'écran envoyait « 2026-09-30 » : l'appel
-- levait « Période non clôturée ».
DO $$
DECLARE
  t uuid;
  mois text := to_char(CURRENT_DATE, 'YYYY-MM');
  att jsonb;
  refus_date text := '—';
  refus_att text := '—';
BEGIN
  t := _mk_tenant('W10T05', false);
  PERFORM _as_user();
  PERFORM log_nf525_event('W10-probe', 'audit', NULL, '{}'::jsonb, NULL, mois);
  PERFORM log_nf525_event('W10-probe', 'audit', NULL, '{}'::jsonb, NULL, mois);
  BEGIN
    PERFORM close_nf525_period(mois);
  EXCEPTION WHEN OTHERS THEN
    refus_att := SQLERRM;
  END;

  BEGIN
    att := get_nf525_attestation(mois);
  EXCEPTION WHEN OTHERS THEN
    refus_att := SQLERRM;
  END;

  BEGIN
    PERFORM get_nf525_attestation(mois || '-30');
  EXCEPTION WHEN OTHERS THEN
    refus_date := SQLERRM;
  END;

  PERFORM _rec('T05',
    'l''attestation du mois clôturé est rendue (2 événements), et une DATE est refusée (format AAAA-MM)',
    refus_att = '—' AND (att ->> 'period') = mois AND (att ->> 'event_count')::int = 2 AND refus_date <> '—',
    format('attestation=%s ; période=%s ; événements=%s ; date envoyée à la place du mois → %s',
      refus_att, COALESCE(att ->> 'period', '—'), COALESCE(att ->> 'event_count', '—'), refus_date));
END $$;

-- ── T06 — la paie IJSS se calcule sur l'ARRÊT ──────────────────────────────
-- `calculate_sick_leave_pay(p_sick_leave_id)` : le couple (salarié, jours) de
-- l'écran n'existe dans aucune signature. Ici l'arrêt est DÉCLARÉ, et la
-- fonction rend un verdict chiffré.
DO $$
DECLARE
  t uuid; e uuid; sl uuid;
  refus text := '—';
  nb int;
BEGIN
  t := _mk_tenant('W10T06', false);
  PERFORM _as_user();
  INSERT INTO employees (tenant_id, employee_number, first_name, last_name, hire_date, status, base_salary)
  VALUES (t, 'W10-01', 'Ali', 'Test', CURRENT_DATE - 400, 'active', 3000)
  RETURNING id INTO e;
  INSERT INTO sick_leaves (tenant_id, employee_id, leave_type, start_date, end_date, waiting_days, daily_ijss, status)
  VALUES (t, e, 'sickness', CURRENT_DATE - 10, CURRENT_DATE - 5, 3, 25, 'closed')
  RETURNING id INTO sl;

  SELECT count(*) INTO nb FROM calculate_sick_leave_pay(sl);

  BEGIN
    PERFORM calculate_sick_leave_pay(p_employee_id := e, p_days := 5);
    refus := 'accepté';
  EXCEPTION WHEN undefined_function THEN refus := '—';
  END;

  PERFORM _rec('T06',
    'les IJSS se calculent sur l''arrêt déclaré (1 ligne), et le couple (salarié, jours) est refusé',
    nb = 1 AND refus = '—',
    format('lignes rendues=%s (1 attendue) ; appel (salarié, jours) → %s', nb, refus));
END $$;

SELECT _audit_assert('267');
