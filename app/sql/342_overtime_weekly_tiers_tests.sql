-- ============================================================
-- 342_overtime_weekly_tiers_tests.sql — tâche 2.3
--
-- Taux horaire du décor : 2 500 € / 151,6667 h = 16,4835 € ;
-- à 25 % : 20,6044 € ; à 50 % : 24,7253 €.
--
--   T01  une semaine de 5 × 10 h (15 h sup) : 8 h à 25 %, 7 h à 50 % → 337,91 €
--        (avant la 342 : 15 h à 25 % = 309,07 €)
--   T02  l'ORDRE d'approbation ne change rien : vendredi approuvé avant lundi
--   T03  la semaine suivante repart à la première tranche
--   T04  les tranches de la SOCIÉTÉ priment (4 h à 10 %, puis 30 %)
--   T05  les paramètres sont datés et sourcés
--   T06  bulletin : la réduction de cotisations salariales vaut 11,31 % des
--        heures sup, à brut égal avec une prime
--   T07  un seul moteur : `calculate_overtime_pay` n'existe plus
--   T08  non-régression : une feuille isolée de 12 h reste à 103,02 € (340 T02)
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '342', false);
DELETE FROM _audit_results WHERE file = '342';

CREATE OR REPLACE FUNCTION _l342_employe(p_t uuid, p_nom text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE e uuid;
BEGIN
  INSERT INTO employees (tenant_id, name, email, status, salary, weekly_hours)
  VALUES (p_t, p_nom, lower(replace(p_nom, ' ', '')) || '@audit.test', 'active', 2500, 35)
  RETURNING id INTO e;
  RETURN e;
END $$;

-- Une feuille de `p_heures` heures, approuvée ; rend son identifiant.
CREATE OR REPLACE FUNCTION _l342_jour(p_t uuid, p_e uuid, p_date date, p_heures numeric, p_approuver boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE ts uuid;
BEGIN
  INSERT INTO timesheets (tenant_id, employee_id, date, hours)
  VALUES (p_t, p_e, p_date, p_heures) RETURNING id INTO ts;
  IF p_approuver THEN
    UPDATE timesheets SET status = 'approved' WHERE id = ts AND tenant_id = p_t;
  END IF;
  RETURN ts;
END $$;

CREATE OR REPLACE FUNCTION _l342_montant(p_t uuid, p_ts uuid)
RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT COALESCE(sum(amount), 0) FROM payroll_variable_elements
  WHERE tenant_id = p_t AND source_id = p_ts AND element_type = 'overtime'
$$;

-- ── T01 — 8 h à 25 %, puis 50 % ──────────────────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2T3T01', false);
  e uuid; j uuid[]; i int; total numeric; m_lun numeric; m_mer numeric; m_jeu numeric;
BEGIN
  PERFORM _as_user();
  e := _l342_employe(t, 'Salarie T3T01');
  -- semaine civile du lundi 09/02/2026 au vendredi 13/02/2026
  FOR i IN 0..4 LOOP
    j := j || _l342_jour(t, e, DATE '2026-02-09' + i, 10);
  END LOOP;
  SELECT sum(amount) INTO total FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND element_type = 'overtime';
  m_lun := _l342_montant(t, j[1]); m_mer := _l342_montant(t, j[3]); m_jeu := _l342_montant(t, j[4]);
  PERFORM _rec('T01', '15 h sup dans la semaine : 8 h à 25 % puis 7 h à 50 % (337,91 €, et non 309,07 €)',
    total BETWEEN 337.89 AND 337.93
      AND m_lun BETWEEN 61.80 AND 61.82          -- 3 h à 25 %
      AND m_mer BETWEEN 65.92 AND 65.95          -- 2 h à 25 % + 1 h à 50 %
      AND m_jeu BETWEEN 74.16 AND 74.19,         -- 3 h à 50 %
    format('total=%s lundi=%s mercredi=%s jeudi=%s', total, m_lun, m_mer, m_jeu));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'T01 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T02 — l'ordre d'approbation ne compte pas ────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2T3T02', false);
  e uuid; j uuid[]; i int; total numeric; m_lun numeric; m_ven numeric;
BEGIN
  PERFORM _as_user();
  e := _l342_employe(t, 'Salarie T3T02');
  FOR i IN 0..4 LOOP
    j := j || _l342_jour(t, e, DATE '2026-02-09' + i, 10, false);
  END LOOP;
  -- on approuve à l'envers : vendredi d'abord, lundi en dernier
  FOR i IN REVERSE 5..1 LOOP
    UPDATE timesheets SET status = 'approved' WHERE id = j[i] AND tenant_id = t;
  END LOOP;
  SELECT sum(amount) INTO total FROM payroll_variable_elements
   WHERE tenant_id = t AND employee_id = e AND element_type = 'overtime';
  m_lun := _l342_montant(t, j[1]); m_ven := _l342_montant(t, j[5]);
  PERFORM _rec('T02', 'approuver le vendredi avant le lundi donne le même résultat : lundi à 25 %, vendredi à 50 %',
    total BETWEEN 337.89 AND 337.93 AND m_lun BETWEEN 61.80 AND 61.82 AND m_ven BETWEEN 74.16 AND 74.19,
    format('total=%s lundi=%s vendredi=%s', total, m_lun, m_ven));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'T02 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T03 — la semaine suivante repart à 25 % ──────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2T3T03', false);
  e uuid; i int; ts uuid; m numeric;
BEGIN
  PERFORM _as_user();
  e := _l342_employe(t, 'Salarie T3T03');
  FOR i IN 0..4 LOOP
    PERFORM _l342_jour(t, e, DATE '2026-02-09' + i, 10);
  END LOOP;
  ts := _l342_jour(t, e, DATE '2026-02-16', 10);     -- lundi suivant
  m := _l342_montant(t, ts);
  PERFORM _rec('T03', 'le lundi de la semaine suivante repart à la première tranche (3 h à 25 % = 61,81 €)',
    m BETWEEN 61.80 AND 61.82, format('montant=%s', m));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'T03 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T04 — les tranches de la société priment ─────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2T3T04', false);
  e uuid; a uuid; b uuid; ma numeric; mb numeric;
BEGIN
  PERFORM _as_user();
  e := _l342_employe(t, 'Salarie T3T04');
  -- convention : 4 premières heures sup à 10 %, les suivantes à 30 %
  INSERT INTO overtime_tiers (tenant_id, from_hour, to_hour, rate_multiplier, is_conventional)
  VALUES (t, 36, 39, 1.10, true), (t, 40, NULL, 1.30, true);
  a := _l342_jour(t, e, DATE '2026-02-09', 10);      -- 3 h : 3 à 10 %
  b := _l342_jour(t, e, DATE '2026-02-10', 10);      -- 3 h : 1 à 10 %, 2 à 30 %
  ma := _l342_montant(t, a); mb := _l342_montant(t, b);
  PERFORM _rec('T04', 'les tranches de la société priment : 3 h à 10 % (54,40 €), puis 1 h à 10 % et 2 h à 30 % (60,99 €)',
    ma BETWEEN 54.38 AND 54.41 AND mb BETWEEN 60.97 AND 61.01,
    format('lundi=%s (54,40) mardi=%s (60,99)', ma, mb));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'T04 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T05 — paramètres datés et sourcés ────────────────────────
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM payroll_legal_parameters
   WHERE tenant_id IS NULL AND country_code = 'FR' AND btrim(COALESCE(source, '')) <> ''
     AND ((code = 'HEURES_SUP_TRANCHE_1_HEURES' AND value = 8)
       OR (code = 'MAJORATION_HEURES_SUP_2' AND value = 1.50)
       OR (code = 'HEURES_SUP_REDUCTION_SALARIALE_PCT' AND value = 11.31)
       OR (code = 'MAJORATION_HEURES_SUP' AND value = 1.25));
  PERFORM _rec('T05', 'les quatre paramètres des heures sup sont en base et sourcés (8 h, 1,25, 1,50, 11,31 %)',
    n = 4, format('paramètres sourcés=%s (4 attendus)', n));
END $$;

-- ── T06 — la réduction de cotisations salariales ─────────────
DO $$
DECLARE
  t uuid; e1 uuid; e2 uuid; r uuid; d1 jsonb; d2 jsonb; ecart numeric;
BEGIN
  EXECUTE 'RESET ROLE';
  t := _mk_tenant('P2T3T06');
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
    VALUES (t, 'FR', 'TAUX_ATMP', 1.00, '2026-01-01');
  INSERT INTO employees (tenant_id, name, salary, status, hire_date)
    VALUES (t, 'Salarié heures sup', 2500, 'active', '2020-01-06') RETURNING id INTO e1;
  INSERT INTO employees (tenant_id, name, salary, status, hire_date)
    VALUES (t, 'Salarié prime', 2500, 'active', '2020-01-06') RETURNING id INTO e2;
  INSERT INTO pay_runs (tenant_id, number, period_start, period_end, pay_date, status)
    VALUES (t, 'PR-T3T06', '2026-09-01', '2026-09-30', '2026-09-30', 'draft') RETURNING id INTO r;
  INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period, element_type, description, quantity, unit_price, amount, source)
  VALUES (t, e1, r, '2026-09', 'overtime', 'heures sup', 5, 20.6044, 103.02, 'manuel'),
         (t, e2, r, '2026-09', 'bonus',    'prime',      NULL, NULL,  103.02, 'manuel');
  PERFORM _as_user();
  d1 := calculate_payslip(e1, '2026-09', r);
  d2 := calculate_payslip(e2, '2026-09', r);
  EXECUTE 'RESET ROLE';
  ecart := round((d2->>'social_security_employee')::numeric - (d1->>'social_security_employee')::numeric, 2);
  PERFORM _rec('T06', 'à brut égal (2 603,02 €), les heures sup portent 11,65 € de cotisations salariales de moins qu''une prime (11,31 % de 103,02 €)',
    (d1->>'total_gross')::numeric = 2603.02 AND (d2->>'total_gross')::numeric = 2603.02
      AND ecart = 11.65 AND (d1->>'overtimeContributionRelief')::numeric = 11.65
      AND (d2->>'overtimeContributionRelief')::numeric = 0,
    format('brut=%s / %s écart de cotisations=%s (11,65) réduction publiée=%s',
           d1->>'total_gross', d2->>'total_gross', ecart, d1->>'overtimeContributionRelief'));
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T06', 'T06 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

-- ── T07 — un seul moteur ─────────────────────────────────────
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public' AND p.proname = 'calculate_overtime_pay';
  PERFORM _rec('T07', 'un seul moteur : calculate_overtime_pay (sans appelant, plafond en dur) n''existe plus',
    n = 0, format('fonctions restantes=%s', n));
END $$;

-- ── T08 — non-régression d'une feuille isolée ────────────────
DO $$
DECLARE
  t uuid := _mk_tenant('P2T3T08', false);
  e uuid; ts uuid; m numeric;
BEGIN
  PERFORM _as_user();
  e := _l342_employe(t, 'Salarie T3T08');
  ts := _l342_jour(t, e, DATE '2026-02-10', 12);
  m := _l342_montant(t, ts);
  PERFORM _rec('T08', 'non-régression : une feuille isolée de 12 h (5 h sup) reste à 103,02 € — toutes dans la première tranche',
    m BETWEEN 103.01 AND 103.03, format('montant=%s', m));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'T08 — le scénario n''a pas pu s''exécuter', false, SQLERRM);
END $$;

DROP FUNCTION _l342_montant(uuid, uuid);
DROP FUNCTION _l342_jour(uuid, uuid, date, numeric, boolean);
DROP FUNCTION _l342_employe(uuid, text);
SELECT _audit_assert('342');
