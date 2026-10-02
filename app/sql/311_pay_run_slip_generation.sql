-- ============================================================
-- 311_pay_run_slip_generation.sql — recette /qa du 29/09/2026 (rh-006)
--
-- LES DÉFAUTS, mesurés à l'écran sur la base de recette du 29/09 :
--   rh-006 🔴 « Générer les bulletins » ne génère AUCUN bulletin. L'écran crée
--          le lot (POST pay_runs) puis s'arrête : `pay_slips` reste à 0, le lot
--          affiche 0 salarié, 0,00 € de brut et 0,00 € de net. Aucun écran ne
--          produisait de bulletin — toute la paie était intestable.
--   rh-006 🔴 « Valider la préparation » n'émettait AUCUNE requête : un `toast`
--          de succès, sans effet. Un lot VIDE s'approuvait donc, et le statut
--          `approved` fait foi pour l'écriture de paie (post_payroll_journal).
--
-- CE QUE FAIT CETTE MIGRATION
--   1. `generate_pay_run_slips(p_pay_run_id)` : UNE fonction de lot, gardée par
--      la société, qui appelle le moteur unique (`calculate_payslip`, 276) pour
--      chaque salarié ACTIF de la période et rend un VERDICT PAR SALARIÉ
--      (calculé / refusé, et pourquoi). Modèle : `generate_depreciation_entries`
--      (W5). L'écran n'a plus de boucle à porter — il affiche le verdict, y
--      compris les échecs nommés.
--   2. Un lot vide ne s'approuve plus : le passage à `approved` exige au moins
--      un bulletin non annulé. L'approbation est le feu vert de la
--      comptabilisation ; la donner sur un lot sans bulletin produisait une paie
--      à zéro, silencieusement.
--
-- CE QUE CETTE MIGRATION NE FAIT PAS
--   * aucun montant n'est calculé ici : `calculate_payslip` reste le SEUL moteur
--     (doctrine W5, « un seul moteur par grandeur »). Cette fonction l'appelle
--     et rapporte ; elle ne recalcule rien et ne contourne aucune grille.
--   * la grille France 2026 (276) reste soumise à la signature de l'expert
--     (décision D-G) — inchangé.
--   * un lot de paie n'est PAS généré en boucle sur plusieurs périodes : un lot,
--     une période (celle de ses bornes).
--
-- Preuve : `311_pay_run_slip_generation_tests.sql` (T01 à T05 ; T01, T02, T04
-- vus rouges avant).
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_pay_run_slips(p_pay_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_run pay_runs%ROWTYPE;
  v_period text;
  v_total int := 0;
  v_ok int := 0;
  v_bulletins jsonb := '[]'::jsonb;
  v_echecs jsonb := '[]'::jsonb;
  v_res jsonb;
  r record;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Paie : aucune société active' USING ERRCODE = 'insufficient_privilege';
  END IF;
  -- Le droit se dit en tête : sans lui, la boucle rendrait N échecs identiques
  -- au lieu d'un refus nommé (calculate_payslip, lui, garde chaque bulletin).
  IF NOT can_perform('pay_slips', 'update') THEN
    RAISE EXCEPTION 'Permission refusée : génération des bulletins de paie' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Le lot est désigné ET gardé par la société : le lot d'une autre société ne
  -- se génère pas (même garde que la 236, règle 2 du contrôle tenant_guard).
  SELECT * INTO v_run FROM pay_runs WHERE id = p_pay_run_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot de paie introuvable : %', p_pay_run_id USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF v_run.status NOT IN ('draft', 'processing') THEN
    RAISE EXCEPTION 'Lot % : statut % — les bulletins ne se génèrent que sur un lot en préparation',
      v_run.number, v_run.status USING ERRCODE = 'check_violation';
  END IF;

  v_period := to_char(v_run.period_start, 'YYYY-MM');

  FOR r IN
    SELECT id, COALESCE(NULLIF(btrim(name), ''), '—') AS nom,
           COALESCE(COALESCE(base_salary, salary), 0) AS salaire
    FROM employees
    WHERE tenant_id = v_tid AND status = 'active'
    ORDER BY employee_number NULLS LAST, created_at, id
  LOOP
    v_total := v_total + 1;
    -- DÉFAUT TROUVÉ PAR LE BANC ÉCRAN (X0), pas par relecture : l'inscription
    -- réelle crée un salarié « Admin » SANS salaire dans chaque société. Sans
    -- cette règle, « Générer les bulletins » produisait un bulletin à 0,00 € pour
    -- ce compte technique — mesuré : 3 bulletins au lieu de 2 sur le scénario de
    -- paie, et un bulletin d'or pris sur la mauvaise ligne. Un salarié sans
    -- salaire configuré ne « touche 0 » pas : il n'a rien à calculer, et le
    -- refus est NOMMÉ.
    IF r.salaire <= 0 THEN
      v_echecs := v_echecs || jsonb_build_object(
        'employee_id', r.id::text, 'employee', r.nom,
        'message', 'salaire non renseigné — aucun bulletin');
      CONTINUE;
    END IF;
    BEGIN
      v_res := calculate_payslip(r.id, v_period, p_pay_run_id);
      IF COALESCE((v_res ->> 'success')::boolean, false) THEN
        v_ok := v_ok + 1;
        v_bulletins := v_bulletins || jsonb_build_object(
          'employee_id', r.id::text,
          'employee', r.nom,
          'pay_slip_id', v_res ->> 'pay_slip_id',
          'total_gross', v_res -> 'total_gross',
          'net_salary', v_res -> 'net_salary');
      ELSE
        -- Le moteur a rendu un refus NOMMÉ : il est rapporté tel quel.
        v_echecs := v_echecs || jsonb_build_object(
          'employee_id', r.id::text, 'employee', r.nom,
          'message', COALESCE(v_res ->> 'error', 'calcul en échec'));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Sous-transaction annulée : aucun bulletin partiel ne survit, et l'échec
      -- est nommé au lieu d'être avalé (doctrine des échecs nommés, W5).
      v_echecs := v_echecs || jsonb_build_object(
        'employee_id', r.id::text, 'employee', r.nom, 'message', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'pay_run_id', p_pay_run_id::text,
    'number', v_run.number,
    'period', v_period,
    'total', v_total,
    'generes', v_ok,
    'echecs', v_echecs,
    'bulletins', v_bulletins);
END $$;
REVOKE EXECUTE ON FUNCTION public.generate_pay_run_slips(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_pay_run_slips(uuid) TO authenticated;

-- ── 2. Un lot vide ne s'approuve pas ────────────────────────────────────────
-- L'approbation est le feu vert de l'écriture de paie. Elle exige au moins un
-- bulletin NON ANNULÉ : c'est la même grandeur que les totaux du lot (275, qui
-- agrège les bulletins non annulés), donc un lot « approuvé » et vide est
-- exactement l'état que ni l'écran ni le grand livre ne peuvent expliquer.
CREATE OR REPLACE FUNCTION public.pay_run_require_slips_before_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_n int;
BEGIN
  IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
    SELECT count(*) INTO v_n
    FROM pay_slips
    WHERE tenant_id = NEW.tenant_id
      AND pay_run_id = NEW.id
      AND status IS DISTINCT FROM 'cancelled';
    IF v_n = 0 THEN
      RAISE EXCEPTION 'Lot % : aucun bulletin — générez les bulletins avant d''approuver la paie',
        NEW.number USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.pay_run_require_slips_before_approval() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS pay_run_require_slips_before_approval ON public.pay_runs;
CREATE TRIGGER pay_run_require_slips_before_approval
  BEFORE UPDATE ON public.pay_runs
  FOR EACH ROW
  EXECUTE FUNCTION public.pay_run_require_slips_before_approval();

