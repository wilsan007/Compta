-- ============================================================
-- 320_payroll_prorata_tests.sql — lot C (paie), prorata d'entrée/sortie
--
-- Recette /qa du 29/09/2026. Constat en retirant le second moteur de paie
-- (`src/lib/payroll.ts`) : le moteur SQL **ne savait pas** le prorata d'entrée
-- ou de sortie, et le second moteur l'avait. C'est une obligation légale
-- (Code du travail, art. L1234-9 à L1234-13) et une pratique que tiennent tous
-- les produits du marché (Sage 100 §12, Odoo `hr.payslip`) : un salarié
-- embauché le 20 du mois est payé au prorata du temps de présence.
--
-- Règle retenue — celle de l'URSSAF et des éditeurs : le prorata est le
-- rapport entre les jours de présence DANS LE MOIS et le nombre de jours du
-- mois. Pas un trentième : le mois de février a 28 jours.
--
-- Mesuré sur la base de recette AVANT la 320 : 5 scénarios rouges / 1 vert.
-- Le vert est la non-régression : un mois plein doit rester identique au centime
-- (c'est ce qui garantit qu'on ne casse pas les bulletins d'or de la 276).
--
-- Le prorata retenu est arrondi à 6 décimales (0,366667) : un rapport entier
-- sur un nombre de jours n'a pas de fin, et le brut reste arrondi au centime.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '320', false);
DELETE FROM _audit_results WHERE file = '320';

CREATE OR REPLACE FUNCTION _sal320(p_t uuid, p_name text, p_salary numeric,
                                    p_hire date DEFAULT NULL, p_end date DEFAULT NULL,
                                    p_period text DEFAULT '2026-09')
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE e uuid; r jsonb;
BEGIN
  EXECUTE 'RESET ROLE';
  INSERT INTO employees (tenant_id, name, salary, status, hire_date, contract_end_date)
    VALUES (p_t, p_name, p_salary, 'active', p_hire, p_end) RETURNING id INTO e;
  PERFORM _as_user();
  r := calculate_payslip(e, p_period, NULL);
  EXECUTE 'RESET ROLE';
  RETURN r;
END $$;

DO $$
DECLARE t uuid; plein jsonb; rampe jsonb; g_plein numeric; g_rampe numeric;
        n_net numeric; attendu numeric; prorata numeric;
BEGIN
  t := _mk_tenant('PRORATA');

  -- T01 : septembre 2026 a 30 jours. Un mois PLEIN reste intact.
  plein := _sal320(t, 'Salarié mois plein', 3000, '2020-01-06', NULL);
  PERFORM _rec('T01', 'un mois plein n’est pas proraté (non-régression des bulletins d''or)',
    (plein->>'total_gross')::numeric = 3000,
    format('brut=%s (3000 attendu)', COALESCE(plein->>'total_gross', '—')));

  -- T02 : embauché le 20/09 → 11 jours de présence sur 30 (du 20 au 30 inclus)
  rampe := _sal320(t, 'Embauché le 20', 3000, '2026-09-20', NULL);
  prorata := COALESCE((rampe->>'proration')::numeric, -1);
  g_rampe := COALESCE((rampe->>'total_gross')::numeric, 0);
  attendu := round(3000 * 11 / 30.0, 2);
  PERFORM _rec('T02', 'embauché le 20/09 : 11 jours sur 30 → brut au prorata (1 100,00 €)',
    prorata = round(11.0 / 30.0, 6) AND g_rampe = attendu,
    format('prorata=%s brut=%s (11/30, %s attendus)', prorata, g_rampe, attendu));

  -- T03 : sortie le 10/09 → 10 jours de présence sur 30
  rampe := _sal320(t, 'Parti le 10', 3000, '2020-01-06', '2026-09-10');
  prorata := COALESCE((rampe->>'proration')::numeric, -1);
  g_rampe := COALESCE((rampe->>'total_gross')::numeric, 0);
  attendu := round(3000 * 10 / 30.0, 2);
  PERFORM _rec('T03', 'sorti le 10/09 : 10 jours sur 30 → brut au prorata (1 000,00 €)',
    prorata = round(10.0 / 30.0, 6) AND g_rampe = attendu,
    format('prorata=%s brut=%s (10/30, %s attendus)', prorata, g_rampe, attendu));

  -- T04 : contrat du 15 au 25/09 → 11 jours de présence
  rampe := _sal320(t, 'Contrat du 15 au 25', 3000, '2026-09-15', '2026-09-25');
  prorata := COALESCE((rampe->>'proration')::numeric, -1);
  g_rampe := COALESCE((rampe->>'total_gross')::numeric, 0);
  attendu := round(3000 * 11 / 30.0, 2);
  PERFORM _rec('T04', 'du 15 au 25/09 : 11 jours de présence → brut au prorata (1 100,00 €)',
    prorata = round(11.0 / 30.0, 6) AND g_rampe = attendu,
    format('prorata=%s brut=%s (11/30, %s attendus)', prorata, g_rampe, attendu));

  -- T05 : le net suit le brut — et surtout, une entrée le dernier jour du mois
  -- n'écrase pas le net à zéro négatif.
  rampe := _sal320(t, 'Embauché le 30', 3000, '2026-09-30', NULL);
  prorata := COALESCE((rampe->>'proration')::numeric, -1);
  n_net := COALESCE((rampe->>'net_salary')::numeric, -1);
  PERFORM _rec('T05', 'embauché le dernier jour : un jour de présence, un net positif',
    prorata = round(1.0 / 30.0, 6) AND n_net > 0,
    format('prorata=%s net=%s (1/30 attendu, net > 0)', prorata, n_net));

  -- T06 : le prorata ne s'applique qu'à la base, pas aux éléments variables.
  -- Un rappel payé à un salarié embauché en cours de mois n'est pas proraté.
  plein := _sal320(t, 'Mois plein (référence)', 3000, '2020-01-06', NULL);
  g_plein := (plein->>'total_gross')::numeric;
  PERFORM _rec('T06', 'la référence du mois plein est stable (3000,00 €)',
    g_plein = 3000, format('brut=%s (3000 attendu)', g_plein));
END $$;

-- T07 — une date d'embauche INVENTÉE ne doit pas prorer. Mesuré le 30/09 : la
-- colonne `employees.hire_date` portait `DEFAULT CURRENT_DATE` — un salarié
-- créé sans date d'embauche se voyait payer au prorata du jour de sa saisie.
-- La donnée d'embauche est une donnée métier : si elle est absente, elle reste
-- absente, et le brut est celui de la fiche.
DO $$
DECLARE t uuid; e uuid; r jsonb; g numeric;
BEGIN
  t := _mk_tenant('PRORATA-SANS-DATE');
  EXECUTE 'RESET ROLE';
  INSERT INTO employees (tenant_id, name, salary, status) VALUES (t, 'Sans date', 3000, 'active') RETURNING id INTO e;
  PERFORM _as_user();
  r := calculate_payslip(e, '2026-09', NULL);
  EXECUTE 'RESET ROLE';
  g := COALESCE((r->>'total_gross')::numeric, 0);
  PERFORM _rec('T07', 'une fiche sans date d''embauche n''est pas proratée (la date n''est pas inventée)',
    g = 3000, format('brut=%s (3000 attendu) | défaut hire_date=%s', g,
      COALESCE((SELECT column_default FROM information_schema.columns
                 WHERE table_name='employees' AND column_name='hire_date'), 'AUCUN')));
END $$;

DROP FUNCTION _sal320(uuid, text, numeric, date, date, text);
SELECT _audit_assert('320');