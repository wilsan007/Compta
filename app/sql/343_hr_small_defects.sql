-- ════════════════════════════════════════════════════════════════════════════
-- 343 — Partie 2, tâche 2.4 : les constats de bas de paie (C5, C6)
-- ════════════════════════════════════════════════════════════════════════════
--
-- Quatre défauts de la recette du 29/09, chacun mesuré avant correction
-- (suite 343) :
--
--   rh-002  `contract_type` s'écrivait tantôt `cdi` (fiche salarié), tantôt
--           `CDI` (création rapide) : les libellés de l'écran lisent les
--           minuscules, donc `CDI` s'affichait en clé brute. Aucune contrainte.
--   rh-001  une date d'embauche en 2099 ou en 1900 était acceptée.
--   rh-003  deux colonnes de salaire : `salary` (celle de l'écran) et
--           `base_salary` (qu'aucun écran n'écrit), et le moteur de paie lit
--           `COALESCE(base_salary, salary)`. Une fiche dont `base_salary` est
--           resté à l'ancienne valeur est donc payée à l'ANCIEN salaire.
--   C5      « Calculer les droits acquis » rendait 25 jours pour tout le monde,
--           embauché en janvier ou en décembre.
--
-- CE QUE FAIT CE FICHIER.
--   1. `contract_type` : valeurs ramenées en minuscules, contrainte sur les six
--      valeurs de l'écran, et un déclencheur qui normalise à l'écriture.
--   2. Date d'embauche : bornée (01/01/1950 → aujourd'hui + 1 an), refus rédigé.
--   3. Salaire : `base_salary` suit `salary` — une seule valeur. Les fiches
--      divergentes sont alignées sur `salary`, la valeur que l'écran montre.
--   4. `calculate_leave_acquisition` : prorata des mois de présence dans
--      l'année, depuis l'embauche (25 jours ouvrés par an, soit 2,0833 par mois).
--
-- CE QU'IL NE FAIT PAS.
--   * L'arrêt maladie (carence, maintien de salaire, ancienneté) : à faire
--     valider par l'expert-comptable (D-G), rien n'est changé.
--   * Les droits à congés restent calculés sur l'ANNÉE CIVILE, pas sur la
--     période de référence du 1er juin au 31 mai ; le calcul n'écrit pas les
--     soldes (`leave_balances`), il les annonce.
--   * Le message français du salaire négatif (rh-001, seconde moitié) relève de
--     la traduction des erreurs, tâche 2.12.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. contract_type ──────────────────────────────────────────────────────
UPDATE public.employees
   SET contract_type = NULLIF(lower(btrim(contract_type)), '')
 WHERE contract_type IS DISTINCT FROM NULLIF(lower(btrim(contract_type)), '');

-- La valeur par défaut de la colonne était 'CDI', en majuscules : une fiche créée
-- sans type recevait donc la graphie que les libellés ne lisent pas (et que la
-- contrainte ci-dessous refuse — vu par la suite 105, qui alimente la table
-- déclencheurs coupés).
ALTER TABLE public.employees ALTER COLUMN contract_type SET DEFAULT 'cdi';

ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_contract_type_check;
ALTER TABLE public.employees ADD CONSTRAINT employees_contract_type_check
  CHECK (contract_type IS NULL OR contract_type IN ('cdi', 'cdd', 'apprentissage', 'stage', 'interim', 'freelance'))
  NOT VALID;

-- Les lignes anciennes sont validées si elles le peuvent ; sinon la contrainte
-- reste opposable aux écritures nouvelles, et les lignes à reprendre sont dites.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.employees
   WHERE contract_type IS NOT NULL
     AND contract_type NOT IN ('cdi', 'cdd', 'apprentissage', 'stage', 'interim', 'freelance');
  IF n = 0 THEN
    ALTER TABLE public.employees VALIDATE CONSTRAINT employees_contract_type_check;
  ELSE
    RAISE NOTICE '343 : % fiche(s) salarié portent un type de contrat hors liste — contrainte posée pour les écritures nouvelles, lignes anciennes à reprendre', n;
  END IF;
END $$;

-- ── 3 (données). base_salary aligné sur salary ────────────────────────────
UPDATE public.employees
   SET base_salary = salary
 WHERE base_salary IS NOT NULL AND COALESCE(salary, 0) > 0
   AND base_salary IS DISTINCT FROM salary;

-- ── 1, 2, 3. Un déclencheur de cohérence de la fiche ──────────────────────
CREATE OR REPLACE FUNCTION public.employees_coherence()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- rh-002 : une seule graphie.
  NEW.contract_type := NULLIF(lower(btrim(NEW.contract_type)), '');

  -- rh-001 : une date d'embauche plausible.
  IF NEW.hire_date IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.hire_date IS DISTINCT FROM OLD.hire_date)
     AND (NEW.hire_date < DATE '1950-01-01' OR NEW.hire_date > CURRENT_DATE + INTERVAL '1 year') THEN
    RAISE EXCEPTION 'Date d''embauche invalide (%) : elle doit être comprise entre le 01/01/1950 et un an après aujourd''hui.',
      to_char(NEW.hire_date, 'DD/MM/YYYY')
      USING ERRCODE = 'check_violation';
  END IF;

  -- rh-003 : le salaire de la fiche est LE salaire. Si `salary` change sans que
  -- `base_salary` soit fourni dans la même écriture, il suit.
  IF TG_OP = 'UPDATE'
     AND NEW.salary IS DISTINCT FROM OLD.salary
     AND NEW.base_salary IS NOT DISTINCT FROM OLD.base_salary
     AND OLD.base_salary IS NOT NULL THEN
    NEW.base_salary := NEW.salary;
  END IF;

  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS b_employees_coherence ON public.employees;
CREATE TRIGGER b_employees_coherence
  BEFORE INSERT OR UPDATE ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.employees_coherence();

REVOKE ALL ON FUNCTION public.employees_coherence() FROM PUBLIC, anon, authenticated;

-- ── 4. Les droits à congés acquis, au prorata ─────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_leave_acquisition(p_employee_id uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_employee RECORD;
  v_annual_days numeric := 25;   -- jours ouvrés par an (5 semaines)
  v_debut date;
  v_fin date;
  v_mois integer := 0;
  v_acquired numeric := 0;
  v_taken numeric := 0;
BEGIN
  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id AND tenant_id = current_tenant_id();
  IF NOT FOUND THEN RAISE EXCEPTION 'Employé non trouvé'; END IF;

  SELECT COALESCE(SUM(days), 0) INTO v_taken
  FROM leave_requests
  WHERE employee_id = p_employee_id
    AND tenant_id = current_tenant_id()
    AND EXTRACT(YEAR FROM start_date) = p_year
    AND status = 'approved';

  -- 343 : les mois ENTIERS de présence dans l'année — de l'embauche (ou du
  -- 1er janvier) à la fin de l'année, à aujourd'hui pour l'année en cours, ou à
  -- la fin du contrat si elle est plus tôt.
  v_debut := GREATEST(COALESCE(v_employee.hire_date, make_date(p_year, 1, 1)), make_date(p_year, 1, 1));
  v_fin := LEAST(make_date(p_year, 12, 31), CURRENT_DATE,
                 COALESCE(v_employee.contract_end_date, make_date(p_year, 12, 31)));
  IF v_fin >= v_debut THEN
    v_mois := (EXTRACT(YEAR FROM age(v_fin + 1, v_debut)) * 12
             + EXTRACT(MONTH FROM age(v_fin + 1, v_debut)))::integer;
    v_acquired := LEAST(round(v_mois * v_annual_days / 12, 2), v_annual_days);
  END IF;

  RETURN jsonb_build_object(
    'employee_id', p_employee_id, 'year', p_year,
    'annual_days', v_annual_days, 'months', v_mois, 'acquired', v_acquired,
    'taken', v_taken, 'remaining', v_acquired - v_taken
  );
END;
$function$;
