-- ============================================================
-- 275_pay_run_totals_from_slips.sql — vague X3 / C5, C7
-- (audit fonctionnel exécuté du 28/09/2026)
--
-- LES DÉFAUTS, mesurés par le chemin de l'écran :
--   C5  le formulaire de lot envoyait `employer_contributions_total`, colonne
--       absente : aucun lot ne se créait (W06).
--   C7  les totaux affichés d'un lot (`gross_total`, `tax_total`, `net_total`,
--       `employee_count`) étaient CALCULÉS PAR L'ÉCRAN, avec un barème
--       marocain (CNSS, AMO, IR) — un troisième moteur de paie, étranger à la
--       paie de la société : 5 938,86 de net affiché pour 4 199,13 de nets aux
--       bulletins (H05). Rien en base ne tenait ces totaux.
--
-- LE CORRECTIF
--   1. Les totaux d'un lot sont un AGRÉGAT de ses bulletins non annulés, tenu
--      par la base : chaque insertion, modification ou suppression d'un
--      bulletin recalcule son lot (et l'ancien lot s'il change de lot).
--      `tax_total` = brut − net (toutes les retenues du salarié).
--   2. Personne d'autre ne les écrit : à la création ils partent de zéro, et un
--      UPDATE direct garde les valeurs agrégées.
--   3. Rattrapage : les lots existants sont recalculés (leurs totaux venaient
--      de l'écran — le journal et les virements, eux, lisent les bulletins).
--
--   4. M8 (masqué) : dès qu'un lot a pu être comptabilisé par l'écran, le
--      balayage du lecteur a trouvé `payroll_accounting_entries` (le pont paie →
--      grand livre) MODIFIABLE par un lecteur. Les 13 tables de paie qui portent
--      de l'argent ou alimentent le grand livre passent sous `can_perform`
--      (même mécanisme que 271/274 ; un `manager` n'y écrit plus — D-6).
--
-- L'écran crée désormais un lot VIDE (numéro, période, date de paie) ; le
-- calcul marocain est retiré, et `single-engine.test.ts` interdit son retour.
-- Suite : `275_pay_run_totals_from_slips_tests.sql`.
-- ============================================================

CREATE OR REPLACE FUNCTION public.pay_run_refresh_totals(p_tenant_id uuid, p_pay_run_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF p_pay_run_id IS NULL THEN
    RETURN;
  END IF;
  PERFORM set_config('app.pay_run_totals', 'on', true);
  UPDATE pay_runs r SET
    gross_total    = coalesce(a.brut, 0),
    net_total      = coalesce(a.net, 0),
    tax_total      = coalesce(a.brut, 0) - coalesce(a.net, 0),
    employee_count = coalesce(a.n, 0)
  FROM (
    -- `total_gross` (brut total, heures et primes comprises) vaut 0 par défaut : à défaut, le salaire de base
    SELECT sum(coalesce(nullif(s.total_gross, 0), s.gross_salary, 0)) AS brut,
           sum(coalesce(s.net_salary, 0))                  AS net,
           count(DISTINCT s.employee_id)                   AS n
    FROM pay_slips s
    WHERE s.tenant_id = p_tenant_id AND s.pay_run_id = p_pay_run_id AND s.status IS DISTINCT FROM 'cancelled'
  ) a
  WHERE r.tenant_id = p_tenant_id AND r.id = p_pay_run_id;
  PERFORM set_config('app.pay_run_totals', 'off', true);
END $$;
REVOKE EXECUTE ON FUNCTION public.pay_run_refresh_totals(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pay_slip_refresh_run_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM pay_run_refresh_totals(OLD.tenant_id, OLD.pay_run_id);
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') AND (TG_OP = 'INSERT' OR NEW.pay_run_id IS DISTINCT FROM OLD.pay_run_id) THEN
    PERFORM pay_run_refresh_totals(NEW.tenant_id, NEW.pay_run_id);
  END IF;
  RETURN NULL;
END $$;
REVOKE EXECUTE ON FUNCTION public.pay_slip_refresh_run_totals() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS pay_slip_refresh_run_totals ON public.pay_slips;
CREATE TRIGGER pay_slip_refresh_run_totals
  AFTER INSERT OR DELETE OR UPDATE OF pay_run_id, status, gross_salary, total_gross, net_salary, employee_id
  ON public.pay_slips
  FOR EACH ROW EXECUTE FUNCTION public.pay_slip_refresh_run_totals();

-- Les totaux ne s'écrivent que par l'agrégat
CREATE OR REPLACE FUNCTION public.pay_run_totals_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF current_setting('app.pay_run_totals', true) IS DISTINCT FROM 'on' THEN
    IF TG_OP = 'INSERT' THEN
      NEW.gross_total := 0; NEW.net_total := 0; NEW.tax_total := 0; NEW.employee_count := 0;
    ELSE
      NEW.gross_total := OLD.gross_total; NEW.net_total := OLD.net_total;
      NEW.tax_total := OLD.tax_total; NEW.employee_count := OLD.employee_count;
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.pay_run_totals_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS pay_run_totals_guard ON public.pay_runs;
CREATE TRIGGER pay_run_totals_guard
  BEFORE INSERT OR UPDATE OF gross_total, net_total, tax_total, employee_count ON public.pay_runs
  FOR EACH ROW EXECUTE FUNCTION public.pay_run_totals_guard();

COMMENT ON COLUMN public.pay_runs.net_total IS
  'X3/C7 (275) : somme des nets des bulletins non annulés du lot — tenue par la base (pay_run_refresh_totals).';

-- Rattrapage
DO $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT tenant_id, id FROM pay_runs LOOP
    PERFORM pay_run_refresh_totals(r.tenant_id, r.id);
    n := n + 1;
  END LOOP;
  RAISE NOTICE '[X3/C7] % lot(s) recalculé(s) depuis leurs bulletins', n;
END $$;

-- ── 4. Tables de paie sous le rôle (M8, masqué) ─────────────────────────────
-- Même mécanisme que 271 §2 et 274 §3, factorisé dans une fonction de session.
CREATE OR REPLACE FUNCTION pg_temp.guard_writes_with_can_perform(p_tables text[])
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE r record; v_action text; v_garde text; v_qual text; v_wc text; v_n int := 0;
BEGIN
  FOR r IN
    SELECT c.relname AS table_name, p.polname, p.polcmd,
           coalesce(pg_get_expr(p.polqual, p.polrelid), '') AS qual,
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') AS wc
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
    WHERE c.relname = ANY (p_tables) AND p.polpermissive AND p.polcmd IN ('a', 'w', 'd', '*')
    ORDER BY c.relname, p.polcmd
  LOOP
    IF r.qual LIKE '%can_perform%' OR r.wc LIKE '%can_perform%' THEN CONTINUE; END IF;
    IF r.polcmd = '*' THEN
      -- politique ALL scindée : les noms dérivent de l'ancienne (une table peut
      -- déjà porter un « <table>_select »)
      EXECUTE format('DROP POLICY %I ON public.%I', r.polname, r.table_name);
      -- une lecture existe déjà (politique SELECT propre) : ne pas la doubler (238)
      IF NOT EXISTS (SELECT 1 FROM pg_policy p2 WHERE p2.polrelid = ('public.' || quote_ident(r.table_name))::regclass
                     AND p2.polpermissive AND p2.polcmd = 'r') THEN
        EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT USING (%s)', r.polname || '_r', r.table_name, r.qual);
      END IF;
      EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT WITH CHECK ((%s) AND can_perform(%L, ''insert''))',
                     r.polname || '_a', r.table_name, coalesce(nullif(r.wc, ''), r.qual), r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE USING ((%s) AND can_perform(%L, ''update'')) WITH CHECK ((%s) AND can_perform(%L, ''update''))',
                     r.polname || '_w', r.table_name, r.qual, r.table_name, coalesce(nullif(r.wc, ''), r.qual), r.table_name);
      EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE USING ((%s) AND can_perform(%L, ''delete''))',
                     r.polname || '_d', r.table_name, r.qual, r.table_name);
      v_n := v_n + 4;
      CONTINUE;
    END IF;
    v_action := CASE r.polcmd WHEN 'a' THEN 'insert' WHEN 'w' THEN 'update' ELSE 'delete' END;
    v_garde := format('can_perform(%L, %L)', r.table_name, v_action);
    IF r.polcmd = 'a' THEN
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (%s)', r.polname, r.table_name, v_wc);
    ELSIF r.polcmd = 'd' THEN
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s)', r.polname, r.table_name, v_qual);
    ELSE
      v_qual := CASE WHEN r.qual = '' THEN v_garde ELSE format('(%s) AND %s', r.qual, v_garde) END;
      v_wc := CASE WHEN r.wc = '' THEN v_garde ELSE format('(%s) AND %s', r.wc, v_garde) END;
      EXECUTE format('ALTER POLICY %I ON public.%I USING (%s) WITH CHECK (%s)', r.polname, r.table_name, v_qual, v_wc);
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

DO $$
DECLARE v_n int;
BEGIN
  v_n := pg_temp.guard_writes_with_can_perform(ARRAY[
    'payroll_accounting_entries',   -- le pont paie → grand livre
    'payroll_account_mapping',      -- les comptes de la paie
    'payroll_components', 'payroll_component_rates', 'payroll_templates',
    'payroll_tax_grids', 'payroll_tax_grid_lines',
    'payroll_variable_elements',    -- primes, retenues, heures : entrent au bulletin
    'pay_recalls', 'salary_advances',
    'sepa_payment_orders',          -- le virement des salaires
    'dsn_declarations', 'payroll_archives']);
  RAISE NOTICE '[X3/M8] % politique(s) d''écriture de paie gardée(s) par can_perform', v_n;
END $$;
