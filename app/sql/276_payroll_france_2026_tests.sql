-- ============================================================
-- 276_payroll_france_2026_tests.sql — vague X3 / C6 : grille France 2026
--
-- MESURÉ AVANT (H06, chemin de l'écran) : 2 500 € brut non cadre → 1 615,05 € net.
--
-- BULLETINS D'OR — septembre 2026, entreprise de moins de 50 salariés, AT/MP
-- notifié 1,00 % (paramètre de la société du jeu d'essai). Chiffres établis par
-- un calcul INDÉPENDANT du moteur, à partir des seules sources citées dans la 276
-- (script `gold.py` joint à la preuve VAGUE-X3). Ils deviennent des tests de
-- non-régression à 0,01 € ; leur SIGNATURE par l'expert-comptable conditionne
-- la mise en production (D-G) — elle n'est pas dans ce dépôt.
--
--               brut     retenues sal.  CSG déd.  CSG non déd.  CRDS   net imposable  PAS         net payé   RGDU (coef)        patronal net
--   SMIC     1 867,02        211,16      124,74       44,02      9,17      1 531,12    0 % 0,00   1 477,93   743,26 (0,3981)       14,48
--   2 500 €  2 500,00        282,75      167,03       58,95     12,28      2 050,22  2,9 % 59,46  1 919,53   459,75 (0,1839)      554,90
--   4 500 €c 4 500,00        510,45      300,65      106,11     22,11      3 688,90 11,9 % 438,98 3 121,70   133,20 (0,0296)    1 703,80
--
--   T01–T03 les trois bulletins d'or, ligne à ligne sur les totaux ci-dessus
--   T04 un bulletin de janvier 2026 prend la grille janvier-avril (PAS 2025)
--       et le SMIC de janvier (RGDU sur 1 823,03)
--   T05 la grille 2024-2025 est close au 31/12/2025 et n'a pas changé ; un
--       bulletin de 2025 la lit encore
--   T06 chaque ligne et chaque paramètre France en vigueur en 2026 porte sa source
--
-- T01–T06 sont ROUGES avant la 276.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '276', false);
DELETE FROM _audit_results WHERE file = '276';

CREATE OR REPLACE FUNCTION _slip276(p_t uuid, p_name text, p_salary numeric, p_cadre boolean, p_period text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE e uuid; r jsonb;
BEGIN
  EXECUTE 'RESET ROLE';
  INSERT INTO employees (tenant_id, name, salary, status) VALUES (p_t, p_name, p_salary, 'active') RETURNING id INTO e;
  IF p_cadre THEN
    BEGIN EXECUTE 'UPDATE employees SET payroll_category = ''cadre'' WHERE id = $1' USING e;
    EXCEPTION WHEN undefined_column THEN NULL; END;
  END IF;
  PERFORM _as_user();
  r := calculate_payslip(e, p_period, NULL);
  EXECUTE 'RESET ROLE';
  RETURN r;
END $$;

-- d = résultat du moteur ; attendu = (brut, retenues, csgd, csgn, crds, net imposable, pas, net, rgdu, patronal)
CREATE OR REPLACE FUNCTION _gold276(p_id text, p_label text, d jsonb, a numeric[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE got numeric[];
BEGIN
  got := ARRAY[(d->>'total_gross')::numeric, (d->>'social_security_employee')::numeric, (d->>'csg_deductible')::numeric,
               (d->>'csg_non_deductible')::numeric, (d->>'crds')::numeric, (d->>'net_taxable')::numeric,
               (d->>'income_tax')::numeric, (d->>'net_salary')::numeric, (d->>'reduction_generale')::numeric,
               (d->>'employer_contributions')::numeric];
  PERFORM _rec(p_id, p_label, coalesce((d->>'success')::boolean, false) AND got = a,
    format('attendu %s | moteur %s %s', a, got, coalesce(d->>'error', '')));
END $$;

DO $$
DECLARE t uuid; d jsonb;
BEGIN
  t := _mk_tenant('X3C6');
  INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
  VALUES (t, 'FR', 'TAUX_ATMP', 1.00, '2026-01-01');
  d := _slip276(t, 'Salarié SMIC', 1867.02, false, '2026-09');
  PERFORM _gold276('T01', 'bulletin d''or SMIC (1 867,02 €, non cadre, sept. 2026)', d,
    ARRAY[1867.02, 211.16, 124.74, 44.02, 9.17, 1531.12, 0.00, 1477.93, 743.26, 14.48]);
  d := _slip276(t, 'Salarié 2 500', 2500, false, '2026-09');
  PERFORM _gold276('T02', 'bulletin d''or 2 500 € non cadre (sept. 2026)', d,
    ARRAY[2500, 282.75, 167.03, 58.95, 12.28, 2050.22, 59.46, 1919.53, 459.75, 554.90]);
  d := _slip276(t, 'Cadre 4 500', 4500, true, '2026-09');
  PERFORM _gold276('T03', 'bulletin d''or 4 500 € cadre au-dessus du PMSS (sept. 2026)', d,
    ARRAY[4500, 510.45, 300.65, 106.11, 22.11, 3688.90, 438.98, 3121.70, 133.20, 1703.80]);
END $$;

-- T04 — janvier 2026 : grille janvier-avril, SMIC 1 823,03
DO $$
DECLARE t uuid; d jsonb; grid text;
BEGIN
  t := _mk_tenant('X3C6J');
  d := _slip276(t, 'Salarié janvier', 2500, false, '2026-01');
  SELECT name INTO grid FROM payroll_tax_grids WHERE id::text = d->>'grid_version';
  -- PAS 2025 : net imposable 2 050,22 dans [2 042 ; 2 151[ → 3,5 % = 71,76 ;
  -- RGDU : coefficient sur 3 × 1 823,03, arrondi au dix-millième
  PERFORM _rec('T04', 'janvier 2026 : grille janvier-avril (PAS 2025, 3,5 %) et SMIC de janvier pour la RGDU',
    grid = 'Grille paie France 2026 (janvier-avril)' AND (d->>'income_tax')::numeric = 71.76
      AND (d->>'rgdu_coefficient')::numeric = round(0.02 + 0.3781 * power(0.5 * (3 * 1823.03 / 2500 - 1), 1.75), 4),
    format('grille=%s PAS=%s coef=%s', grid, d->>'income_tax', d->>'rgdu_coefficient'));
END $$;

-- T05 — la grille 2024-2025 close, inchangée, encore lue pour 2025
DO $$
DECLARE t uuid; d jsonb; g record; n int; grid text;
BEGIN
  SELECT * INTO g FROM payroll_tax_grids WHERE tenant_id IS NULL AND country_code = 'FR' AND name = 'Grille paie France 2024-2025';
  SELECT count(*) INTO n FROM payroll_tax_grid_lines WHERE grid_id = g.id;
  t := _mk_tenant('X3C6H');
  d := _slip276(t, 'Salarié 2025', 2500, false, '2025-11');
  SELECT name INTO grid FROM payroll_tax_grids WHERE id::text = d->>'grid_version';
  PERFORM _rec('T05', 'la grille 2024-2025 est close au 31/12/2025, garde ses 6 lignes, et un bulletin de 2025 la lit',
    g.effective_to = '2025-12-31' AND n = 6 AND grid = 'Grille paie France 2024-2025',
    format('fin=%s lignes=%s grille lue pour 2025=%s', g.effective_to, n, grid));
END $$;

-- T06 — les sources
DO $$
DECLARE n_lines int; n_params int; n_cols int;
BEGIN
  SELECT count(*) INTO n_cols FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'payroll_tax_grid_lines' AND column_name = 'source';
  IF n_cols = 0 THEN
    PERFORM _rec('T06', 'chaque ligne et chaque paramètre France 2026 porte sa source', false, 'colonne source absente');
    RETURN;
  END IF;
  EXECUTE $q$SELECT count(*) FROM payroll_tax_grid_lines l JOIN payroll_tax_grids g ON g.id = l.grid_id
           WHERE g.tenant_id IS NULL AND g.country_code = 'FR' AND g.effective_from >= '2026-01-01' AND coalesce(l.source, '') = ''$q$ INTO n_lines;
  EXECUTE $q$SELECT count(*) FROM payroll_legal_parameters
           WHERE tenant_id IS NULL AND country_code = 'FR' AND coalesce(valid_to, '9999-12-31') >= '2026-01-01'
             AND code NOT LIKE 'AMORT%' AND code NOT IN ('DIVISEUR_HORAIRE_MENSUEL', 'DIVISEUR_JOURS_MENSUEL', 'MAJORATION_HEURES_SUP',
                                                         'PLAFOND_TR2', 'TAUX_APPEL_T1', 'TAUX_APPEL_T2', 'TAUX_CEG', 'TAUX_CET')
             AND coalesce(source, '') = ''$q$ INTO n_params;
  PERFORM _rec('T06', 'chaque ligne et chaque paramètre de paie France en vigueur en 2026 porte sa source',
    n_lines = 0 AND n_params = 0, format('lignes sans source=%s paramètres sans source=%s', n_lines, n_params));
END $$;

SELECT _audit_assert('276');
