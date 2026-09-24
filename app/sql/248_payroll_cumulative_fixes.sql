-- ============================================================
-- 248_payroll_cumulative_fixes.sql — RH : les cumuls suivent les bulletins,
-- et un lot de paie annulé se voit au grand livre
--
-- Trois défauts trouvés en exécutant `sql/247_payroll_cumulative_tests.sql`
-- sur base neuve le 24/09/2026, tous vus rouges avant ce fichier.
--
--   C03  un bulletin supprimé laisse sa ligne de cumul annuel. Le cumul sert
--        d'assiette au mois suivant (plafond, régularisation progressive) :
--        mesuré, le bulletin de mars cumulait 9 000 alors que 6 000 seulement
--        restaient payés. L'erreur ne se rattrape pas : elle court jusqu'au
--        31 décembre et part en DSN.
--   C04  `upsert_payroll_cumulative` est exécutable par tout utilisateur
--        connecté alors qu'elle n'est qu'un rouage de `calculate_payslip`.
--        Mesuré : un appel direct a porté le cumul d'un salarié à 999 999
--        sans bulletin, sans droit de paie et sans trace.
--   C06  un lot de paie annulé après comptabilisation laissait le pont
--        `payroll_accounting_entries` à « transferred » et l'écriture au grand
--        livre. Le statut « cancelled » que la contrainte CHECK admet — et que
--        `payroll_post_run` lit comme clé d'idempotence — n'était écrit par
--        aucune ligne de code du dépôt.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Le cumul suit le bulletin (C03)
-- ─────────────────────────────────────────────────────────────
-- Le cumul d'un mois n'existe que tant qu'un bulletin vivant le porte.
-- Supprimé ou annulé le dernier bulletin du mois, la ligne de cumul part.
CREATE OR REPLACE FUNCTION public.payroll_cumulative_follow_slip()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_year int; v_month int; v_reste int;
BEGIN
  IF OLD.period_start IS NULL OR OLD.employee_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  v_year := EXTRACT(YEAR FROM OLD.period_start)::int;
  v_month := EXTRACT(MONTH FROM OLD.period_start)::int;

  SELECT count(*) INTO v_reste
  FROM pay_slips s
  WHERE s.tenant_id = OLD.tenant_id
    AND s.employee_id = OLD.employee_id
    AND EXTRACT(YEAR FROM s.period_start)::int = v_year
    AND EXTRACT(MONTH FROM s.period_start)::int = v_month
    AND COALESCE(s.status, 'draft') <> 'cancelled'
    AND (TG_OP <> 'DELETE' OR s.id <> OLD.id);

  IF v_reste = 0 THEN
    DELETE FROM payroll_cumulative
    WHERE tenant_id = OLD.tenant_id AND employee_id = OLD.employee_id
      AND year = v_year AND month = v_month;
  END IF;

  RETURN COALESCE(NEW, OLD);
END $function$;

DROP TRIGGER IF EXISTS payroll_cumulative_follow_slip_del ON pay_slips;
CREATE TRIGGER payroll_cumulative_follow_slip_del
  AFTER DELETE ON pay_slips
  FOR EACH ROW EXECUTE FUNCTION payroll_cumulative_follow_slip();

DROP TRIGGER IF EXISTS payroll_cumulative_follow_slip_cancel ON pay_slips;
CREATE TRIGGER payroll_cumulative_follow_slip_cancel
  AFTER UPDATE OF status ON pay_slips
  FOR EACH ROW
  WHEN (NEW.status = 'cancelled' AND COALESCE(OLD.status, 'draft') <> 'cancelled')
  EXECUTE FUNCTION payroll_cumulative_follow_slip();

-- Reprise : les cumuls orphelins déjà en base (aucun bulletin vivant sur le mois)
DELETE FROM payroll_cumulative c
WHERE NOT EXISTS (
  SELECT 1 FROM pay_slips s
  WHERE s.tenant_id = c.tenant_id AND s.employee_id = c.employee_id
    AND EXTRACT(YEAR FROM s.period_start)::int = c.year
    AND EXTRACT(MONTH FROM s.period_start)::int = c.month
    AND COALESCE(s.status, 'draft') <> 'cancelled');

-- ─────────────────────────────────────────────────────────────
-- 2. Le cumul ne s'écrit que par un bulletin (C04)
-- ─────────────────────────────────────────────────────────────
-- `calculate_payslip` est SECURITY DEFINER et propriété de postgres : elle
-- continue d'appeler la fonction. Personne d'autre ne le peut.
REVOKE EXECUTE ON FUNCTION public.upsert_payroll_cumulative(uuid, integer, integer, numeric, numeric,
  numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric)
  FROM authenticated, anon, PUBLIC;

-- ─────────────────────────────────────────────────────────────
-- 3. Annuler un lot comptabilisé contrepasse son écriture (C06)
-- ─────────────────────────────────────────────────────────────
-- L'écriture d'origine n'est pas touchée — le noyau de saisie l'interdit et la
-- valeur probante l'exige. Une écriture de contrepassation est portée au
-- journal de paie, et le pont passe à « cancelled », le statut que la
-- contrainte CHECK admettait sans que rien ne l'écrive jamais.
CREATE OR REPLACE FUNCTION public.payroll_reverse_posted_run()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_bridge record;
  v_src record;
  v_rev uuid;
BEGIN
  SELECT * INTO v_bridge FROM payroll_accounting_entries
  WHERE tenant_id = OLD.tenant_id AND pay_run_id = OLD.id AND status = 'transferred'
  LIMIT 1;
  IF NOT FOUND OR v_bridge.journal_entry_id IS NULL THEN
    RETURN NEW;  -- lot jamais comptabilisé : rien à contrepasser
  END IF;

  SELECT * INTO v_src FROM journal_entries WHERE id = v_bridge.journal_entry_id;
  IF NOT FOUND OR v_src.status <> 'posted' THEN
    UPDATE payroll_accounting_entries SET status = 'cancelled' WHERE id = v_bridge.id;
    RETURN NEW;
  END IF;

  -- déjà contrepassée : ne pas le faire deux fois
  IF EXISTS (SELECT 1 FROM journal_entries
             WHERE tenant_id = OLD.tenant_id AND reference = 'PAYROLL-REV-' || OLD.number) THEN
    UPDATE payroll_accounting_entries SET status = 'cancelled' WHERE id = v_bridge.id;
    RETURN NEW;
  END IF;

  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (OLD.tenant_id, 'JE-PAIE-ANN-' || OLD.number, COALESCE(OLD.period_end, OLD.pay_date, CURRENT_DATE),
          'PAIE', 'draft', 'Annulation paie ' || OLD.number, 'PAYROLL-REV-' || OLD.number, OLD.number)
  RETURNING id INTO v_rev;

  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_general, account_tiers,
    debit, credit, description, line_order)
  SELECT OLD.tenant_id, v_rev, l.account_code, l.account_general, l.account_tiers,
         l.credit, l.debit, 'Annulation paie ' || OLD.number, l.line_order
  FROM journal_lines l WHERE l.journal_id = v_src.id;

  UPDATE journal_entries SET status = 'posted' WHERE id = v_rev;

  UPDATE payroll_accounting_entries SET status = 'cancelled' WHERE id = v_bridge.id;
  UPDATE pay_slips SET journal_posted = false WHERE pay_run_id = OLD.id AND tenant_id = OLD.tenant_id;

  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS payroll_reverse_posted_run_trg ON pay_runs;
CREATE TRIGGER payroll_reverse_posted_run_trg
  AFTER UPDATE OF status ON pay_runs
  FOR EACH ROW
  WHEN (NEW.status = 'cancelled' AND COALESCE(OLD.status, 'draft') <> 'cancelled')
  EXECUTE FUNCTION payroll_reverse_posted_run();

COMMENT ON FUNCTION public.payroll_reverse_posted_run() IS
  '248 : annuler un lot de paie comptabilisé porte une contrepassation au journal PAIE et passe payroll_accounting_entries à « cancelled ». L''écriture d''origine reste intacte (valeur probante).';

-- ─────────────────────────────────────────────────────────────
-- 4. Les deux fonctions créées ici ne sont pas appelables sans connexion
-- ─────────────────────────────────────────────────────────────
-- `CREATE FUNCTION` accorde EXECUTE à PUBLIC par défaut, et la 228 a mesuré que
-- les privilèges par défaut du schéma ne retirent pas ce droit-là (proacl reste
-- NULL). Deux conséquences, toutes deux mesurées le 24/09 après ce fichier :
--   * `ci/check_anon_grants.sql` — le contrôle permanent — refuse ces deux
--     fonctions : « appelable sans connexion : payroll_reverse_posted_run()
--     [PUBLIC] », et la CI échoue ;
--   * la suite 228 (`T06`) les compte comme exposées, puisque leur `proacl` est
--     resté NULL.
-- Aucune des deux n'est une RPC : l'une est déclencheur de `pay_slips`, l'autre
-- déclencheur de `pay_runs`. Elles sont appelées comme déclencheurs, et un
-- déclencheur ne vérifie pas le droit EXECUTE de celui qui écrit la ligne.
REVOKE EXECUTE ON FUNCTION public.payroll_cumulative_follow_slip() FROM authenticated, anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.payroll_reverse_posted_run() FROM authenticated, anon, PUBLIC;

