-- ============================================================
-- 227_tenant_guard.sql — trois fonctions de plus qui agissaient sur la
--                        société d'autrui, trouvées par ci/check_tenant_guard
--
-- Même moule que le défaut du versement de la paie (224) : une fonction
-- SECURITY DEFINER — donc hors RLS — exécutable par `authenticated`, qui reçoit
-- un identifiant du client, retrouve la ligne SANS filtre de société, puis
-- travaille avec le `tenant_id` de cette ligne. L'appelant n'a jamais à prouver
-- qu'il appartient à la société qu'il modifie.
--
--   * `cancel_import_batch(p_batch_id)` — le plus grave : il SUPPRIME les
--     clients, fournisseurs, articles ou salariés créés par le lot. Un uuid de
--     lot appartenant à une autre société effaçait ses enregistrements importés.
--     Appelée depuis l'écran (src/lib/queries/imports.ts).
--   * `validate_import_batch(p_batch_id)` — passe le lot d'autrui à « validé »
--     et renvoie ses compteurs. Appelée depuis le même écran.
--   * `run_three_way_match(p_invoice_id)` — remet la facture fournisseur
--     d'autrui en « à approuver » et renvoie son rapprochement (montants
--     commandés, reçus, facturés). Exposée en RPC.
--
-- Le correctif est le même partout : la ligne doit appartenir à la société
-- active, sinon elle est « introuvable » — un appelant d'une autre société
-- n'apprend rien de son existence.
--
-- `calculate_manufacturing_cost(p_mo_id, p_tenant_id)` filtre déjà tout par le
-- `p_tenant_id` qu'on lui passe, mais rien n'obligeait ce paramètre à être la
-- société de l'appelant. Aucun écran ne l'appelle : le droit d'exécution est
-- retiré à `authenticated` plutôt que d'inventer une garde pour un appelant qui
-- n'existe pas.
--
-- Scénarios : sql/227_tenant_guard_tests.sql (T01 à T04).
-- Contrôle permanent : sql/ci/check_tenant_guard.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Annulation d'un lot d'import (supprime des données)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_trgm', 'pg_temp'
AS $$
DECLARE
  v_batch record;
  v_tid uuid;
BEGIN
  -- 227 : le lot doit appartenir à la société active — sans ce filtre, un uuid
  -- d'une autre société faisait supprimer ses enregistrements importés
  SELECT * INTO v_batch FROM import_batches
  WHERE id = p_batch_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot d''import introuvable';
  END IF;

  v_tid := v_batch.tenant_id;

  -- Supprimer les enregistrements créés par ce lot
  -- (les enregistrements importés portent l'ID du lot dans metadata)
  IF v_batch.target_table = 'customers' THEN
    DELETE FROM customers WHERE tenant_id = v_tid AND import_batch_id = p_batch_id;
  ELSIF v_batch.target_table = 'suppliers' THEN
    DELETE FROM suppliers WHERE tenant_id = v_tid AND import_batch_id = p_batch_id;
  ELSIF v_batch.target_table = 'products' THEN
    DELETE FROM products WHERE tenant_id = v_tid AND import_batch_id = p_batch_id;
  ELSIF v_batch.target_table = 'employees' THEN
    DELETE FROM employees WHERE tenant_id = v_tid AND import_batch_id = p_batch_id;
  END IF;

  -- Marquer le lot comme annulé
  UPDATE import_batches SET status = 'cancelled', completed_at = now()
  WHERE id = p_batch_id AND tenant_id = v_tid;

  RETURN jsonb_build_object('success', true, 'batch_id', p_batch_id, 'status', 'cancelled');
END;
$$;

-- ------------------------------------------------------------
-- 2. Validation d'un lot d'import
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_import_batch(p_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_trgm', 'pg_temp'
AS $$
DECLARE
  v_batch record;
  v_tid uuid;
BEGIN
  SELECT * INTO v_batch FROM import_batches
  WHERE id = p_batch_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot d''import introuvable';
  END IF;

  v_tid := v_batch.tenant_id;

  UPDATE import_batches SET status = 'validated', validated_at = now()
  WHERE id = p_batch_id AND tenant_id = v_tid;

  RETURN jsonb_build_object(
    'batch_id', p_batch_id,
    'total_rows', v_batch.total_rows,
    'valid_rows', v_batch.valid_rows,
    'invalid_rows', v_batch.invalid_rows,
    'status', 'validated'
  );
END;
$$;

-- ------------------------------------------------------------
-- 3. Rapprochement à trois voies d'une facture fournisseur
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_three_way_match(p_invoice_id uuid)
RETURNS TABLE(match_status character varying, total_ordered numeric, total_received numeric,
              total_invoiced numeric, price_variance numeric, quantity_variance numeric,
              line_results jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_invoice RECORD;
  v_match RECORD;
BEGIN
  SELECT * INTO v_invoice FROM purchase_invoices pi
  WHERE pi.id = p_invoice_id AND pi.tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase invoice not found'; END IF;

  UPDATE purchase_invoices
    SET approval_status = 'pending'
  WHERE id = p_invoice_id AND tenant_id = v_invoice.tenant_id
    AND approval_status NOT IN ('pending');

  SELECT
    pi.match_status,
    (pi.match_details->>'total_ordered')::numeric AS total_ordered,
    (pi.match_details->>'total_received')::numeric AS total_received,
    (pi.match_details->>'total_invoiced')::numeric AS total_invoiced,
    (pi.match_details->>'price_variance')::numeric AS price_variance,
    (pi.match_details->>'quantity_variance')::numeric AS quantity_variance,
    pi.match_details->'line_results' AS line_results
  INTO v_match
  FROM purchase_invoices pi WHERE pi.id = p_invoice_id AND pi.tenant_id = v_invoice.tenant_id;

  RETURN QUERY SELECT v_match.match_status, v_match.total_ordered, v_match.total_received,
    v_match.total_invoiced, v_match.price_variance, v_match.quantity_variance, v_match.line_results;
END;
$$;

-- ------------------------------------------------------------
-- 4. Coût de revient : aucun appelant côté client, droit retiré
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.calculate_manufacturing_cost(uuid, uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.calculate_manufacturing_cost(uuid, uuid) IS
  'Coût de revient d''un ordre de fabrication. Tout est filtré par p_tenant_id, mais rien '
  'n''oblige ce paramètre à être la société de l''appelant : réservée aux appels internes (227).';

-- ------------------------------------------------------------
-- 5. Surcharges héritées qui prennent la société en paramètre
--
-- `fec_export` et `get_journal_entry_count` existent en deux versions : celle
-- qui déduit la société de l'appelant (`current_tenant_id()`) et une ancienne
-- qui la reçoit en paramètre. Les deux étaient exécutables par `authenticated` :
-- la seconde rendait le FEC — c'est-à-dire TOUTES les écritures comptables —
-- d'une société quelconque à qui en connaissait l'identifiant. Aucun appelant,
-- ni écran ni Edge Function, n'utilise ces surcharges : le droit leur est retiré,
-- la version sûre reste en place.
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fec_export(uuid, date, date, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_journal_entry_count(uuid, date, date) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.fec_export(uuid, date, date, integer, integer) IS
  'Surcharge héritée : la société est un paramètre, donc l''appelant ne prouve rien. '
  'Réservée aux appels internes — les écrans utilisent fec_export(date, date, int, int) (227).';

-- ------------------------------------------------------------
-- 6. La garde que l'appelant peut écraser n'est pas une garde
--
-- Quatre fonctions écrivaient `COALESCE(p_tenant_id, current_tenant_id())` :
-- la société reçue en paramètre l'emporte sur celle de l'appelant. Elles
-- mentionnent donc `current_tenant_id()` — elles en ont l'air — mais un client
-- qui passe l'identifiant d'une autre société travaille dans SES livres :
--
--   * `generate_recurring_entry(p_entry_id, p_tenant_id)` — INSÈRE une écriture
--     comptable et ses lignes dans la société passée en paramètre ;
--   * `run_mrp(p_tenant_id, p_horizon_days)` — écrit le calcul des besoins ;
--   * `calculate_stock_valuation(...)` et `calculate_stock_valuation_at_date(...)`
--     — rendent la valorisation du stock de cette société (lecture), et c'est
--     par cette dernière que `get_stock_valuation` était joignable.
--
-- L'intention d'origine est visible : laisser un appelant SANS société active
-- (service_role, pg_cron, Edge Function) désigner la société à traiter. Elle est
-- préservée en inversant simplement la priorité — `COALESCE(current_tenant_id(),
-- p_tenant_id)` : un utilisateur connecté travaille toujours dans SA société, et
-- le paramètre ne sert plus que lorsqu'il n'y a aucun contexte.
--
-- La réécriture est faite sur la définition en place plutôt que recopiée ici :
-- ces corps font jusqu'à 4 500 caractères et les dupliquer les ferait diverger.
-- Le compte attendu est vérifié — si le motif disparaît ou se multiplie, la
-- migration échoue au lieu de passer silencieusement.
-- ------------------------------------------------------------
DO $migration$
DECLARE
  v_oid oid;
  v_def text;
  v_n int := 0;
BEGIN
  FOR v_oid IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
          ~* 'COALESCE\s*\(\s*p_\w+\s*,\s*current_tenant_id\s*\(\s*\)'
    ORDER BY p.oid
  LOOP
    v_def := regexp_replace(pg_get_functiondef(v_oid),
      'COALESCE\s*\(\s*(p_\w+)\s*,\s*current_tenant_id\s*\(\s*\)\s*\)',
      'COALESCE(current_tenant_id(), \1)', 'gi');
    EXECUTE v_def;
    v_n := v_n + 1;
  END LOOP;

  IF v_n <> 4 THEN
    RAISE EXCEPTION '227 : % fonction(s) réécrites, 4 attendues (calculate_stock_valuation, calculate_stock_valuation_at_date, generate_recurring_entry, run_mrp) — vérifiez ce qui a changé avant de passer outre', v_n;
  END IF;
  RAISE NOTICE '227 : % fonction(s) ne laissent plus le paramètre écraser la société de l''appelant', v_n;
END
$migration$;
