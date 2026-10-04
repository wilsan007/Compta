-- ============================================================
-- 276_payroll_france_2026.sql — vague X3 / C6 : la grille de paie France 2026
-- (audit fonctionnel exécuté du 28/09/2026 ; décision D-G du plan)
--
-- LE DÉFAUT (H06, chemin de l'écran) : un bulletin de 2 500 € brut non cadre
-- sortait à 1 615,05 € de net pour ≈ 1 920 € attendus. La grille « France
-- 2024-2025 » portait des taux inventés (« sécurité sociale salariale 6,98 % »,
-- « retraite 11,40 % » sur tout le brut, CSG à 9,20 % sur le brut entier) ; le
-- moteur comptait la CSG/CRDS DEUX fois, retranchait la CSG non déductible du
-- net imposable, appliquait un « taux neutre » fixe de 10 %, ignorait les
-- planchers de tranche (T2) et retranchait la réduction générale une fois PAR
-- ligne éligible.
--
-- DÉCISION D-G : chaque taux, plafond et assiette est une ligne datée avec sa
-- SOURCE OFFICIELLE, relevée le 28/09/2026 (aucune valeur de mémoire) :
--   [URSSAF-TAUX] urssaf.fr — Taux de cotisations secteur privé, mis à jour le 01/01/2026
--   [URSSAF-2026] urssaf.fr — Ce qu'il faut savoir au 1er janvier 2026 (RGDU :
--                 LFSS 2025 art. 18, décret 2025-887 ; vieillesse déplafonnée 2,11 %)
--   [URSSAF-PSS]  urssaf.fr — Plafonds de la Sécurité sociale 2026 (4 005 € / mois)
--   [SMIC-01]     Décret n° 2025-1228 du 17/12/2025 : 12,02 €/h au 01/01/2026
--   [SMIC-06]     Arrêté du 22/05/2026 : 12,31 €/h au 01/06/2026
--   [AA-2026]     Agirc-Arrco, circulaire 2025-16 SG-DRJ du 30/10/2025
--   [PAS-2025]    BOFiP BOI-BAREME-000037-20250410 (grille au 01/05/2025)
--   [PAS-2026]    BOFiP BOI-BAREME-000037, version du 06/07/2026 (grille au 01/05/2026)
-- La grille 2024-2025 est CLOSE au 31/12/2025, jamais modifiée : les bulletins
-- déjà calculés restent explicables. La MISE EN PRODUCTION attend la signature
-- de l'expert-comptable sur les trois bulletins d'or (D-G).
--
-- CE QUI CHANGE
--   1. Schéma : `employees.payroll_category` (cadre / non_cadre : Apec) ; sur les
--      lignes de grille, `applies_to`, `company_size` (FNAL < / ≥ 50),
--      `min_gross_pmss` (CET : due seulement au-delà du plafond),
--      `rate_employer_param` (AT/MP : taux NOTIFIÉ à la société) et `source` ;
--      `source` sur les paramètres légaux.
--   2. Paramètres datés 2026 (PMSS, SMIC, RGDU) ; ceux qu'ils remplacent sont clos.
--   3. Deux grilles 2026 (janvier-avril, puis à partir de mai : la grille du taux
--      par défaut du PAS change au 1er mai), mêmes cotisations.
--   4. Moteur : conditions de ligne, planchers, CSG (abattement sur 4 PMSS
--      seulement, comptée une fois), net imposable, taux par défaut en GRILLE,
--      RGDU calculée une fois et plafonnée aux cotisations éligibles, détail
--      ligne à ligne dans `calc_inputs.contributions`.
--
-- LIMITES DITES (preuve VAGUE-X3) : calcul mensuel sans régularisation annuelle
-- de la RGDU ni proratisation temps partiel ; AT/MP imputé en totalité à la RGDU
-- (la limite à la part mutualisée n'est pas modélisée) ; mutuelle, prévoyance
-- (dont 1,50 % cadre conventionnel), formation, taxe d'apprentissage, versement
-- mobilité, dialogue social hors RGDU et Alsace-Moselle ne sont pas portés par la
-- grille ; `TAUX_ATMP` et `EFFECTIF_50_PLUS` sont des paramètres DE LA SOCIÉTÉ
-- (0 et « moins de 50 » à défaut).
--
-- Suite : `276_payroll_france_2026_tests.sql` (bulletins d'or recalculés à la main).
-- ============================================================

-- ── 1. Schéma ────────────────────────────────────────────────────────────────
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS payroll_category text NOT NULL DEFAULT 'non_cadre';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'employees_payroll_category_check') THEN
    ALTER TABLE public.employees ADD CONSTRAINT employees_payroll_category_check CHECK (payroll_category IN ('non_cadre', 'cadre'));
  END IF;
END $$;
COMMENT ON COLUMN public.employees.payroll_category IS
  'X3/C6 (276) : catégorie de paie — cadre (cotisation Apec) ou non_cadre. Lue par calculate_payslip.';

ALTER TABLE public.payroll_tax_grid_lines
  ADD COLUMN IF NOT EXISTS applies_to text NOT NULL DEFAULT 'all',
  ADD COLUMN IF NOT EXISTS company_size text,
  ADD COLUMN IF NOT EXISTS min_gross_pmss numeric,
  ADD COLUMN IF NOT EXISTS rate_employer_param text,
  ADD COLUMN IF NOT EXISTS source text;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payroll_tax_grid_lines_applies_to_check') THEN
    ALTER TABLE public.payroll_tax_grid_lines ADD CONSTRAINT payroll_tax_grid_lines_applies_to_check
      CHECK (applies_to IN ('all', 'cadre', 'non_cadre'));
    ALTER TABLE public.payroll_tax_grid_lines ADD CONSTRAINT payroll_tax_grid_lines_company_size_check
      CHECK (company_size IS NULL OR company_size IN ('lt50', 'ge50'));
  END IF;
END $$;
ALTER TABLE public.payroll_legal_parameters ADD COLUMN IF NOT EXISTS source text;

-- ── 2. Paramètres légaux datés ───────────────────────────────────────────────
-- Les paramètres remplacés sont CLOS (valid_to), jamais réécrits.
UPDATE public.payroll_legal_parameters SET valid_to = '2025-12-31'
WHERE tenant_id IS NULL AND country_code = 'FR' AND valid_to IS NULL AND valid_from < '2026-01-01'
  AND code IN ('PMSS', 'SMIC_H', 'SMIC_M', 'REDUCTION_GEN_T', 'REDUCTION_GEN_T_MAX');

CREATE TEMP TABLE t276_params (code text, value numeric, valid_from date, valid_to date, source text);
INSERT INTO t276_params VALUES
  ('PMSS',               4005,    '2026-01-01', NULL,         '[URSSAF-PSS] Plafonds de la Sécurité sociale, mis à jour le 01/01/2026 : 4 005 € / mois, 48 060 € / an'),
  ('SMIC_H',             12.02,   '2026-01-01', '2026-05-31', '[SMIC-01] Décret n° 2025-1228 du 17/12/2025 : 12,02 €/h au 01/01/2026'),
  ('SMIC_M',             1823.03, '2026-01-01', '2026-05-31', '[SMIC-01] 12,02 € × 151,67 h (35 h × 52 / 12)'),
  ('SMIC_H',             12.31,   '2026-06-01', NULL,         '[SMIC-06] Arrêté du 22/05/2026 : 12,31 €/h au 01/06/2026'),
  ('SMIC_M',             1867.02, '2026-06-01', NULL,         '[SMIC-06] 12,31 € × 151,67 h (35 h × 52 / 12)'),
  ('RGDU_TMIN',          0.0200,  '2026-01-01', NULL,         '[URSSAF-2026] RGDU : T min = 0,0200'),
  ('RGDU_TDELTA_LT50',   0.3781,  '2026-01-01', NULL,         '[URSSAF-2026] RGDU : T delta = 0,3781 (moins de 50 salariés)'),
  ('RGDU_TDELTA_GE50',   0.3821,  '2026-01-01', NULL,         '[URSSAF-2026] RGDU : T delta = 0,3821 (50 salariés et plus)'),
  ('RGDU_P',             1.75,    '2026-01-01', NULL,         '[URSSAF-2026] RGDU : exposant P = 1,75'),
  ('RGDU_SMIC_MULTIPLE', 3,       '2026-01-01', NULL,         '[URSSAF-2026] RGDU : rémunérations inférieures à 3 Smic'),
  ('EFFECTIF_50_PLUS',   0,       '2026-01-01', NULL,         'Défaut : moins de 50 salariés — la société déclare son effectif (FNAL, RGDU)');

INSERT INTO public.payroll_legal_parameters (tenant_id, country_code, code, value, valid_from, valid_to, source)
SELECT NULL, 'FR', p.code, p.value, p.valid_from, p.valid_to, p.source
FROM t276_params p
WHERE NOT EXISTS (SELECT 1 FROM payroll_legal_parameters x
                  WHERE x.tenant_id IS NULL AND x.country_code = 'FR' AND x.code = p.code AND x.valid_from = p.valid_from);

-- les paramètres 2025 toujours en vigueur en 2026 reçoivent leur source
UPDATE public.payroll_legal_parameters SET source = CASE code
    WHEN 'CSG_DEDUCTIBLE'     THEN '[URSSAF-TAUX] CSG non imposable 6,80 % sur 98,25 % du brut dans la limite de 4 PMSS'
    WHEN 'CSG_NON_DEDUCTIBLE' THEN '[URSSAF-TAUX] CSG imposable 2,40 % sur 98,25 % du brut dans la limite de 4 PMSS'
    WHEN 'CRDS'               THEN '[URSSAF-TAUX] CRDS 0,50 % sur 98,25 % du brut dans la limite de 4 PMSS'
    WHEN 'CSG_CRDS_BASE'      THEN '[URSSAF-TAUX] assiette 98,25 % du brut dans la limite de 4 PMSS (192 240 € en 2026)'
    WHEN 'CGSS_BASE_MULTIPLE' THEN '[URSSAF-TAUX] limite de l''abattement : 4 PMSS'
    WHEN 'TAUX_NEUTRE'        THEN 'Repli du moteur si aucune grille de taux par défaut ne couvre la période (non légal)'
  END
WHERE tenant_id IS NULL AND country_code = 'FR' AND source IS NULL AND valid_to IS NULL
  AND code IN ('CSG_DEDUCTIBLE', 'CSG_NON_DEDUCTIBLE', 'CRDS', 'CSG_CRDS_BASE', 'CGSS_BASE_MULTIPLE', 'TAUX_NEUTRE');

-- ── 3. Grilles 2026 ──────────────────────────────────────────────────────────
UPDATE public.payroll_tax_grids SET effective_to = '2025-12-31'
WHERE tenant_id IS NULL AND country_code = 'FR' AND name = 'Grille paie France 2024-2025' AND effective_to IS NULL;

CREATE OR REPLACE FUNCTION pg_temp.fr2026_grid(p_name text, p_from date, p_to date, p_pas jsonb, p_pas_source text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE g uuid; b jsonb; i int := 100;
BEGIN
  SELECT id INTO g FROM payroll_tax_grids WHERE tenant_id IS NULL AND country_code = 'FR' AND name = p_name;
  IF g IS NOT NULL THEN RETURN g; END IF;
  INSERT INTO payroll_tax_grids (tenant_id, country_code, grid_type, name, description, status, source, effective_from, effective_to)
  VALUES (NULL, 'FR', 'composite', p_name,
          'Grille sourcée (276, décision D-G) : URSSAF (taux 01/01/2026, RGDU), Agirc-Arrco (circulaire 2025-16), BOFiP (taux par défaut du PAS). '
          'Mise en production conditionnée à la signature des bulletins d''or par l''expert-comptable.',
          'active', 'platform', p_from, p_to) RETURNING id INTO g;

  INSERT INTO payroll_tax_grid_lines (grid_id, sort_order, line_type, category, label, rate_employee, rate_employer,
    ceiling_type, ceiling_multiplier, floor_multiplier, section, risk, is_csg_crds, csg_type,
    eligible_reduction_generale, applies_to, company_size, min_gross_pmss, rate_employer_param, source)
  VALUES
    (g,  1, 'percentage', 'health',          'Assurance maladie, maternité, invalidité, décès', 0,     13,    'none', 1, 0, 'contribution', 'health',       false, NULL, true,  'all', NULL,   NULL, NULL, '[URSSAF-TAUX] 13 % (taux plein ; le taux réduit est fondu dans la RGDU en 2026 [URSSAF-2026])'),
    (g,  2, 'percentage', 'social_security', 'Assurance vieillesse plafonnée',                  6.90,  8.55,  'pmss', 1, 0, 'contribution', 'retirement',   false, NULL, true,  'all', NULL,   NULL, NULL, '[URSSAF-TAUX] 6,90 % salarié, 8,55 % employeur dans la limite du plafond'),
    (g,  3, 'percentage', 'social_security', 'Assurance vieillesse déplafonnée',                0.40,  2.11,  'none', 1, 0, 'contribution', 'retirement',   false, NULL, true,  'all', NULL,   NULL, NULL, '[URSSAF-TAUX] 0,40 % salarié ; [URSSAF-2026] 2,11 % employeur (2,02 % en 2025)'),
    (g,  4, 'percentage', 'social_security', 'Allocations familiales',                          0,     5.25,  'none', 1, 0, 'contribution', 'family',       false, NULL, true,  'all', NULL,   NULL, NULL, '[URSSAF-TAUX] 5,25 % (taux plein ; taux réduit fondu dans la RGDU [URSSAF-2026])'),
    (g,  5, 'percentage', 'employer_charge', 'Contribution solidarité autonomie',               0,     0.30,  'none', 1, 0, 'contribution', 'other',        false, NULL, true,  'all', NULL,   NULL, NULL, '[URSSAF-TAUX] 0,30 %'),
    (g,  6, 'percentage', 'employer_charge', 'Accidents du travail - maladies professionnelles', 0,    0,     'none', 1, 0, 'contribution', 'atmp',         false, NULL, true,  'all', NULL,   NULL, 'TAUX_ATMP', '[URSSAF-TAUX] taux notifié par la Carsat — paramètre TAUX_ATMP de la société'),
    (g,  7, 'percentage', 'employer_charge', 'FNAL (moins de 50 salariés)',                     0,     0.10,  'pmss', 1, 0, 'contribution', 'family',       false, NULL, true,  'all', 'lt50', NULL, NULL, '[URSSAF-TAUX] 0,10 % dans la limite du plafond'),
    (g,  8, 'percentage', 'employer_charge', 'FNAL (50 salariés et plus)',                      0,     0.50,  'none', 1, 0, 'contribution', 'family',       false, NULL, true,  'all', 'ge50', NULL, NULL, '[URSSAF-TAUX] 0,50 %'),
    (g,  9, 'percentage', 'employer_charge', 'Contribution au dialogue social',                 0,     0.016, 'none', 1, 0, 'contribution', 'other',        false, NULL, false, 'all', NULL,   NULL, NULL, '[URSSAF-TAUX] 0,016 %'),
    (g, 10, 'percentage', 'unemployment',    'Assurance chômage',                               0,     4.00,  'multiple_pmss', 4, 0, 'contribution', 'unemployment', false, NULL, true, 'all', NULL, NULL, NULL, '[URSSAF-TAUX] 4,00 % dans la limite de 192 240 € (4 PMSS)'),
    (g, 11, 'percentage', 'unemployment',    'Cotisation AGS',                                  0,     0.25,  'multiple_pmss', 4, 0, 'contribution', 'unemployment', false, NULL, false, 'all', NULL, NULL, NULL, '[URSSAF-TAUX] 0,25 % dans la limite de 192 240 € (4 PMSS)'),
    (g, 12, 'percentage', 'retirement',      'Retraite complémentaire Agirc-Arrco T1',          3.15,  4.72,  'pmss', 1, 0, 'contribution', 'retirement',   false, NULL, true,  'all', NULL,   NULL, NULL, '[AA-2026] T1 : 7,87 % appelés (6,20 % × 127 %), 4,72 % employeur, 3,15 % salarié'),
    (g, 13, 'percentage', 'retirement',      'Contribution d''équilibre général T1',            0.86,  1.29,  'pmss', 1, 0, 'contribution', 'retirement',   false, NULL, true,  'all', NULL,   NULL, NULL, '[AA-2026] CEG T1 : 2,15 % (1,29 % employeur, 0,86 % salarié)'),
    (g, 14, 'percentage', 'retirement',      'Retraite complémentaire Agirc-Arrco T2',          8.64,  12.95, 'multiple_pmss', 8, 1, 'contribution', 'retirement', false, NULL, false, 'all', NULL, NULL, NULL, '[AA-2026] T2 (de 1 à 8 PMSS) : 21,59 % appelés, 12,95 % employeur, 8,64 % salarié'),
    (g, 15, 'percentage', 'retirement',      'Contribution d''équilibre général T2',            1.08,  1.62,  'multiple_pmss', 8, 1, 'contribution', 'retirement', false, NULL, false, 'all', NULL, NULL, NULL, '[AA-2026] CEG T2 : 2,70 % (1,62 % employeur, 1,08 % salarié)'),
    (g, 16, 'percentage', 'retirement',      'Contribution d''équilibre technique',             0.14,  0.21,  'multiple_pmss', 8, 0, 'contribution', 'retirement', false, NULL, false, 'all', NULL, 1,    NULL, '[AA-2026] CET 0,35 % (0,21 % / 0,14 %) sur T1 + T2, due seulement si le salaire excède la tranche 1'),
    (g, 17, 'percentage', 'employee_charge', 'Cotisation Apec (cadres)',                        0.024, 0.036, 'multiple_pmss', 4, 0, 'contribution', 'other',      false, NULL, false, 'cadre', NULL, NULL, NULL, '[AA-2026] Apec 0,06 % (0,036 % / 0,024 %) dans la limite de 4 PMSS'),
    (g, 18, 'percentage', 'csg_crds',        'CSG déductible',                                  0,     0,     'none', 1, 0, 'contribution', NULL,           true,  'deductible',     false, 'all', NULL, NULL, NULL, '[URSSAF-TAUX] 6,80 % sur 98,25 % du brut (4 PMSS) — paramètre CSG_DEDUCTIBLE'),
    (g, 19, 'percentage', 'csg_crds',        'CSG non déductible',                              0,     0,     'none', 1, 0, 'contribution', NULL,           true,  'non_deductible', false, 'all', NULL, NULL, NULL, '[URSSAF-TAUX] 2,40 % sur 98,25 % du brut (4 PMSS) — paramètre CSG_NON_DEDUCTIBLE'),
    (g, 20, 'percentage', 'csg_crds',        'CRDS',                                            0,     0,     'none', 1, 0, 'contribution', NULL,           true,  'crds',           false, 'all', NULL, NULL, NULL, '[URSSAF-TAUX] 0,50 % sur 98,25 % du brut (4 PMSS) — paramètre CRDS');

  -- Taux par défaut du prélèvement à la source (métropole), base mensuelle
  FOR b IN SELECT * FROM jsonb_array_elements(p_pas) LOOP
    i := i + 1;
    INSERT INTO payroll_tax_grid_lines (grid_id, sort_order, line_type, category, label, min_amount, max_amount,
      rate_employee, rate_employer, section, source)
    VALUES (g, i, 'bracket', 'income_tax', 'Taux par défaut PAS', (b->>0)::numeric, NULLIF(b->>1, '')::numeric,
      (b->>2)::numeric, 0, 'tax', p_pas_source);
  END LOOP;
  RETURN g;
END $$;

SELECT pg_temp.fr2026_grid('Grille paie France 2026 (janvier-avril)', '2026-01-01', '2026-04-30',
  '[[0,1620,0],[1620,1683,0.5],[1683,1791,1.3],[1791,1911,2.1],[1911,2042,2.9],[2042,2151,3.5],[2151,2294,4.1],
    [2294,2714,5.3],[2714,3107,7.5],[3107,3539,9.9],[3539,3983,11.9],[3983,4648,13.8],[4648,5574,15.8],
    [5574,6974,17.9],[6974,8711,20],[8711,12091,24],[12091,16376,28],[16376,25706,33],[25706,55062,38],[55062,"",43]]',
  '[PAS-2025] BOFiP BOI-BAREME-000037-20250410 : grille métropole au 01/05/2025, en vigueur jusqu''au 30/04/2026');
SELECT pg_temp.fr2026_grid('Grille paie France 2026 (à partir du 1er mai)', '2026-05-01', NULL,
  '[[0,1635,0],[1635,1698,0.5],[1698,1807,1.3],[1807,1928,2.1],[1928,2060,2.9],[2060,2170,3.5],[2170,2315,4.1],
    [2315,2738,5.3],[2738,3135,7.5],[3135,3571,9.9],[3571,4019,11.9],[4019,4690,13.8],[4690,5624,15.8],
    [5624,7037,17.9],[7037,8789,20],[8789,12200,24],[12200,16523,28],[16523,25937,33],[25937,55558,38],[55558,"",43]]',
  '[PAS-2026] BOFiP BOI-BAREME-000037 (version du 06/07/2026) : grille métropole au 01/05/2026 (LF 2026, art. 4)');

-- ── 4. Moteur ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_payslip(p_employee_id uuid, p_period text, p_pay_run_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_emp RECORD;
  v_period_start date;
  v_period_end date;
  v_period_year int;
  v_period_month int;

  -- Paramètres légaux
  v_pmss numeric;
  v_csg_deductible_rate numeric;
  v_csg_non_deductible_rate numeric;
  v_crds_rate numeric;
  v_csg_crds_base_pct numeric;
  v_csg_crds_multiple numeric;
  v_taux_neutre numeric;
  v_reduction_gen_t numeric;
  -- X3/C6 (276) : RGDU 2026, taille de l'entreprise, catégorie du salarié
  v_smic_m numeric;
  v_rgdu_tmin numeric;
  v_rgdu_tdelta numeric;
  v_rgdu_p numeric;
  v_rgdu_mult numeric;
  v_rgdu_coef numeric := 0;
  v_rgdu_base numeric := 0;          -- cotisations patronales sur lesquelles la réduction s'impute
  v_big boolean := false;            -- effectif de 50 salariés et plus
  v_category text;
  v_line_rate_er numeric;
  v_contrib jsonb := '[]'::jsonb;    -- détail ligne à ligne (tests d'or, 0,01 €)
  v_pas_rate numeric;

  -- Éléments variables
  v_overtime_pay numeric := 0;
  v_overtime_hours numeric := 0;
  v_bonus numeric := 0;
  v_advance_deduction numeric := 0;
  v_pay_recall numeric := 0;
  v_expense_reimbursement numeric := 0;
  v_unpaid_leave_deduction numeric := 0;
  v_other_deductions numeric := 0;
  v_meal_vouchers numeric := 0;
  v_transport_allowance numeric := 0;

  -- Brut
  v_base_salary numeric;
  v_total_gross numeric;

  -- Cotisations
  v_ss_employee numeric := 0;       -- cotisations salariales (sécu + retraite + chômage + santé)
  v_ss_employer numeric := 0;       -- cotisations patronales
  v_csg_deductible numeric := 0;
  v_csg_non_deductible numeric := 0;
  v_crds numeric := 0;
  v_csg_crds_total numeric := 0;
  v_reduction_generale numeric := 0;

  -- Assiettes
  v_csg_crds_base numeric;          -- assiette CSG/CRDS
  v_ceiling_base numeric;           -- assiette plafonnée (PMSS)
  v_net_social numeric;             -- net social (brut - cotisations déductibles)
  v_net_taxable numeric;            -- net imposable
  v_income_tax numeric;
  v_total_deductions numeric;
  v_net_payable numeric;

  -- Grille fiscale
  v_grid_id uuid;
  v_grid_version text;
  v_grid_line RECORD;
  v_line_amount_emp numeric;
  v_line_amount_er numeric;
  v_line_base numeric;
  v_line_ceiling numeric;
  v_cumulative_used numeric;
  v_cumulative_available numeric;

  -- Cumuls
  v_cum_gross_ytd numeric := 0;
  v_cum_ceiling_base_ytd numeric := 0;
  v_ve_count int := 0;             -- nombre d'éléments variables intégrés

  -- Avecholding tax
  v_withholding_rate numeric;
  v_withholding_source text;

  -- Numérotation
  v_payslip_number text;
  v_payslip_id uuid;
  v_clarified_id uuid;
  v_line_order int;
  v_slip_lines jsonb := '[]'::jsonb;

  -- Pays du tenant
  v_country_code text := 'FR';
  v_tenant RECORD;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  -- X1-271 (H10) : calculer un bulletin l'écrit ; un lecteur ne le relance pas.
  IF NOT can_perform('pay_slips', 'update') THEN
    RAISE EXCEPTION 'Permission refusée : calcul des bulletins (pay_slips.update)' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Charger l'employé
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Employé non trouvé: %', p_employee_id;
  END IF;

  -- Calculer les bornes de période
  v_period_start := (p_period || '-01')::date;
  v_period_end := (v_period_start + INTERVAL '1 month - 1 day')::date;
  v_period_year := EXTRACT(YEAR FROM v_period_start)::int;
  v_period_month := EXTRACT(MONTH FROM v_period_start)::int;

  -- Pays du tenant
  SELECT country_code, legislation_pack_code INTO v_tenant
  FROM tenants WHERE id = v_tid;
  IF v_tenant.country_code IS NOT NULL THEN
    v_country_code := v_tenant.country_code;
  ELSIF v_tenant.legislation_pack_code IS NOT NULL THEN
    v_country_code := v_tenant.legislation_pack_code;
  END IF;

  -- ── Charger les paramètres légaux ──
  v_pmss := get_legal_parameter('PMSS', v_country_code, v_period_start, v_tid);
  v_csg_deductible_rate := get_legal_parameter('CSG_DEDUCTIBLE', v_country_code, v_period_start, v_tid);
  v_csg_non_deductible_rate := get_legal_parameter('CSG_NON_DEDUCTIBLE', v_country_code, v_period_start, v_tid);
  v_crds_rate := get_legal_parameter('CRDS', v_country_code, v_period_start, v_tid);
  v_csg_crds_base_pct := get_legal_parameter('CSG_CRDS_BASE', v_country_code, v_period_start, v_tid);
  v_csg_crds_multiple := get_legal_parameter('CGSS_BASE_MULTIPLE', v_country_code, v_period_start, v_tid);
  v_taux_neutre := get_legal_parameter('TAUX_NEUTRE', v_country_code, v_period_start, v_tid);
  v_reduction_gen_t := get_legal_parameter('REDUCTION_GEN_T', v_country_code, v_period_start, v_tid);
  v_smic_m := get_legal_parameter('SMIC_M', v_country_code, v_period_start, v_tid);
  v_rgdu_tmin := get_legal_parameter('RGDU_TMIN', v_country_code, v_period_start, v_tid);
  v_rgdu_p := get_legal_parameter('RGDU_P', v_country_code, v_period_start, v_tid);
  v_rgdu_mult := get_legal_parameter('RGDU_SMIC_MULTIPLE', v_country_code, v_period_start, v_tid);
  v_big := get_legal_parameter('EFFECTIF_50_PLUS', v_country_code, v_period_start, v_tid) >= 1;
  v_rgdu_tdelta := get_legal_parameter(CASE WHEN v_big THEN 'RGDU_TDELTA_GE50' ELSE 'RGDU_TDELTA_LT50' END,
                                       v_country_code, v_period_start, v_tid);
  v_category := COALESCE(v_emp.payroll_category, 'non_cadre');

  -- ── Éléments variables (si pay_run_id fourni) ──
  IF p_pay_run_id IS NOT NULL THEN
    SELECT
      COALESCE(SUM(CASE WHEN ve.element_type = 'overtime' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      -- RH-04 : les heures supplementaires ne sont comptees qu'une fois, par la
      -- ligne 'overtime' mesuree au pointage. 'timesheet_hours' reste la ligne
      -- d'heures travaillees, mais n'entre plus dans ce total (11 h pour 9 h
      -- faites).
      COALESCE(SUM(CASE WHEN ve.element_type = 'overtime' THEN COALESCE(ve.quantity, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'bonus' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'advance_deduction' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'pay_recall' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'expense_reimbursement' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'unpaid_leave_deduction' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type IN ('other_deductions', 'other') THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'meal_vouchers' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN ve.element_type = 'transport_allowance' THEN COALESCE(ve.amount, 0) ELSE 0 END), 0)
    INTO v_overtime_pay, v_overtime_hours, v_bonus, v_advance_deduction,
         v_pay_recall, v_expense_reimbursement, v_unpaid_leave_deduction,
         v_other_deductions, v_meal_vouchers, v_transport_allowance
    FROM payroll_variable_elements ve
    WHERE ve.pay_run_id = p_pay_run_id
      AND ve.employee_id = p_employee_id
      AND ve.tenant_id = v_tid
      AND COALESCE(ve.integrated, false) = false;

    -- Compter les éléments variables pour l'affichage UI
    SELECT count(*) INTO v_ve_count
    FROM payroll_variable_elements ve
    WHERE ve.pay_run_id = p_pay_run_id
      AND ve.employee_id = p_employee_id
      AND ve.tenant_id = v_tid
      AND COALESCE(ve.integrated, false) = false;
  END IF;

  -- ── Calcul du brut ──
  v_base_salary := COALESCE(COALESCE(v_emp.base_salary, v_emp.salary), 0);
  v_total_gross := v_base_salary + v_overtime_pay + v_bonus + v_pay_recall
    - v_unpaid_leave_deduction;

  IF v_total_gross < 0 THEN
    v_total_gross := 0;
  END IF;

  -- ── Assiette plafonnée (PMSS) ──
  v_ceiling_base := LEAST(v_total_gross, v_pmss);

  -- ── Assiette CSG/CRDS ──
  -- 276 : l'abattement (98,25 %) ne porte que sur la part du brut dans la limite
  -- de 4 PMSS ; au-delà, l'assiette est de 100 % (URSSAF, taux 2026). Avant : tout
  -- le brut passait à 100 % dès 4 PMSS dépassé.
  v_csg_crds_base := round(LEAST(v_total_gross, v_csg_crds_multiple * v_pmss) * v_csg_crds_base_pct / 100
                     + GREATEST(0, v_total_gross - v_csg_crds_multiple * v_pmss), 2);

  -- ── Charger la grille fiscale active ──
  SELECT g.id INTO v_grid_id
  FROM payroll_tax_grids g
  WHERE (g.tenant_id = v_tid OR g.tenant_id IS NULL)
    AND g.country_code = v_country_code
    AND g.status = 'active'
    AND g.effective_from <= v_period_start
    AND COALESCE(g.effective_to, '9999-12-31'::date) >= v_period_end
  ORDER BY g.tenant_id NULLS LAST, g.created_at DESC
  LIMIT 1;

  v_grid_version := COALESCE(v_grid_id::text, 'fallback');

  -- ── Calcul des cotisations via la grille ──
  IF v_grid_id IS NOT NULL THEN
    FOR v_grid_line IN
      SELECT * FROM payroll_tax_grid_lines
      WHERE grid_id = v_grid_id
        AND COALESCE(section, 'contribution') IN ('contribution', 'employer')
      ORDER BY sort_order
    LOOP
      -- 276 : conditions d'application de la ligne
      IF COALESCE(v_grid_line.applies_to, 'all') <> 'all' AND v_grid_line.applies_to <> v_category THEN CONTINUE; END IF;
      IF v_grid_line.company_size = 'lt50' AND v_big THEN CONTINUE; END IF;
      IF v_grid_line.company_size = 'ge50' AND NOT v_big THEN CONTINUE; END IF;
      IF v_grid_line.min_gross_pmss IS NOT NULL AND v_total_gross <= v_grid_line.min_gross_pmss * v_pmss THEN CONTINUE; END IF;

      -- Calcul de l'assiette selon base_type
      v_line_base := v_total_gross; -- défaut 'gross'

      -- Appliquer le plafond selon ceiling_type
      IF v_grid_line.ceiling_type IN ('pmss', 'multiple_pmss') THEN
        v_line_ceiling := v_pmss * COALESCE(v_grid_line.ceiling_multiplier, 1);
        v_line_base := LEAST(v_line_base, v_line_ceiling);
      ELSIF v_grid_line.ceiling_type = 'fixed' THEN
        v_line_base := LEAST(v_line_base, COALESCE(v_grid_line.ceiling_value, v_line_base));
      END IF;
      -- 276 : plancher (tranche 2 = de 1 à 8 PMSS) — `floor_multiplier` n'était pas lu
      IF COALESCE(v_grid_line.floor_multiplier, 0) > 0 THEN
        v_line_base := GREATEST(0, v_line_base - v_pmss * v_grid_line.floor_multiplier);
      END IF;

      -- 276 : taux patronal lu dans un paramètre de la société (AT/MP notifié)
      v_line_rate_er := CASE WHEN v_grid_line.rate_employer_param IS NOT NULL
                             THEN get_legal_parameter(v_grid_line.rate_employer_param, v_country_code, v_period_start, v_tid)
                             ELSE COALESCE(v_grid_line.rate_employer, 0) END;

      v_line_amount_emp := round(v_line_base * COALESCE(v_grid_line.rate_employee, 0) / 100, 2);
      v_line_amount_er := round(v_line_base * v_line_rate_er / 100, 2);

      IF v_grid_line.is_csg_crds THEN
        -- CSG/CRDS : assiette et taux propres ; comptées UNE fois (276 : elles
        -- entraient aussi dans les cotisations salariales, donc deux fois au net)
        v_line_base := v_csg_crds_base;
        v_line_amount_er := 0;
        IF v_grid_line.csg_type = 'deductible' THEN
          v_csg_deductible := round(v_csg_crds_base * v_csg_deductible_rate / 100, 2);
          v_line_amount_emp := v_csg_deductible;
        ELSIF v_grid_line.csg_type = 'non_deductible' THEN
          v_csg_non_deductible := round(v_csg_crds_base * v_csg_non_deductible_rate / 100, 2);
          v_line_amount_emp := v_csg_non_deductible;
        ELSIF v_grid_line.csg_type = 'crds' THEN
          v_crds := round(v_csg_crds_base * v_crds_rate / 100, 2);
          v_line_amount_emp := v_crds;
        END IF;
      ELSE
        v_ss_employee := v_ss_employee + v_line_amount_emp;
        v_ss_employer := v_ss_employer + v_line_amount_er;
        IF v_grid_line.eligible_reduction_generale THEN
          v_rgdu_base := v_rgdu_base + v_line_amount_er;
        END IF;
      END IF;

      v_contrib := v_contrib || jsonb_build_object(
        'label', v_grid_line.label, 'base', round(v_line_base, 2),
        'rate_employee', COALESCE(v_grid_line.rate_employee, 0), 'employee', v_line_amount_emp,
        'rate_employer', v_line_rate_er, 'employer', v_line_amount_er);
    END LOOP;

    -- ── Réduction générale : calculée UNE fois, imputée sur les cotisations éligibles ──
    -- 276 : elle était recalculée et retranchée à chaque ligne éligible.
    IF v_rgdu_mult > 0 AND v_smic_m > 0 AND v_total_gross > 0 THEN
      -- RGDU (LFSS 2025 art. 18, décret 2025-887) : Tmin + Tdelta × [½ × (3 Smic / rémunération − 1)]^P,
      -- due sous 3 Smic ; coefficient arrondi au dix-millième, plafonné à Tmin + Tdelta
      IF v_total_gross < v_rgdu_mult * v_smic_m THEN
        v_rgdu_coef := LEAST(v_rgdu_tmin + v_rgdu_tdelta,
          round(v_rgdu_tmin + v_rgdu_tdelta * power(0.5 * (v_rgdu_mult * v_smic_m / v_total_gross - 1), v_rgdu_p), 4));
        v_reduction_generale := LEAST(round(v_rgdu_coef * v_total_gross, 2), v_rgdu_base);
      END IF;
    ELSIF v_reduction_gen_t > 0 AND v_smic_m > 0 AND v_total_gross > 0 THEN
      -- Périodes antérieures à 2026 : formule historique du moteur, appliquée une fois
      v_reduction_generale := LEAST(round(
        v_reduction_gen_t * GREATEST(0, 1.3 * v_smic_m / v_total_gross - 1) / 100 * v_total_gross, 2), v_rgdu_base);
    END IF;
    v_ss_employer := GREATEST(0, v_ss_employer - v_reduction_generale);
  ELSE
    -- Fallback : taux légaux français 2025 si aucune grille configurée
    v_ss_employee := round(v_total_gross * 22.0 / 100, 2);  -- approximation légale
    v_ss_employer := round(v_total_gross * 42.0 / 100, 2);  -- approximation légale
    v_csg_deductible := round(v_csg_crds_base * v_csg_deductible_rate / 100, 2);
    v_csg_non_deductible := round(v_csg_crds_base * v_csg_non_deductible_rate / 100, 2);
    v_crds := round(v_csg_crds_base * v_crds_rate / 100, 2);
  END IF;

  v_csg_crds_total := v_csg_deductible + v_csg_non_deductible + v_crds;

  -- ── Net social et net imposable ──
  -- 276 : le net imposable garde la CSG non déductible et la CRDS (il les
  -- retranchait) ; seule la CSG déductible en sort.
  v_net_social := round(v_total_gross - v_ss_employee, 2);
  v_net_taxable := round(v_total_gross - v_ss_employee - v_csg_deductible, 2);
  IF v_net_taxable < 0 THEN v_net_taxable := 0; END IF;

  -- ── Impôt sur le revenu (PAS) ──
  v_withholding_rate := COALESCE(v_emp.withholding_tax_rate, 0);
  v_withholding_source := COALESCE(v_emp.withholding_rate_source, CASE WHEN v_emp.withholding_tax_rate IS NOT NULL THEN 'dgfip' ELSE 'neutral' END);

  IF v_withholding_rate > 0 THEN
    v_income_tax := round(v_net_taxable * v_withholding_rate / 100, 2);
  ELSE
    -- 276 : taux par défaut = GRILLE (art. 204 H CGI), lue dans la grille de la
    -- période ; un taux fixe (TAUX_NEUTRE, 10 %) ne sert qu'à défaut de grille.
    SELECT rate_employee INTO v_pas_rate
    FROM payroll_tax_grid_lines
    WHERE grid_id = v_grid_id AND section = 'tax' AND category = 'income_tax' AND line_type = 'bracket'
      AND v_net_taxable >= COALESCE(min_amount, 0)
      AND (max_amount IS NULL OR v_net_taxable < max_amount)
    ORDER BY min_amount DESC
    LIMIT 1;
    v_withholding_rate := COALESCE(v_pas_rate, v_taux_neutre);
    v_withholding_source := CASE WHEN v_pas_rate IS NOT NULL THEN 'default_grid' ELSE 'neutral' END;
    v_income_tax := round(v_net_taxable * v_withholding_rate / 100, 2);
  END IF;

  -- ── Total déductions et net à payer ──
  v_total_deductions := round(v_ss_employee + v_csg_crds_total + v_income_tax
    + v_advance_deduction + v_other_deductions, 2);

  v_net_payable := round(v_total_gross - v_total_deductions + v_expense_reimbursement
    + v_meal_vouchers + v_transport_allowance, 2);

  -- ── Cumuls YTD (régularisation progressive) ──
  SELECT COALESCE(SUM(gross), 0), COALESCE(SUM(ceiling_base), 0)
  INTO v_cum_gross_ytd, v_cum_ceiling_base_ytd
  FROM payroll_cumulative
  WHERE employee_id = p_employee_id
    AND tenant_id = v_tid
    AND year = v_period_year
    AND month < v_period_month;

  -- ── Mettre à jour les cumuls ──
  PERFORM upsert_payroll_cumulative(
    p_employee_id, v_period_year, v_period_month,
    v_total_gross, v_net_taxable, v_ceiling_base, v_pmss - v_ceiling_base,
    v_net_taxable, v_net_social,
    v_ss_employee, v_ss_employer,
    v_income_tax, v_csg_deductible, v_csg_non_deductible, v_crds,
    v_reduction_generale
  );

  -- ── Construire les lignes de détail pour audit ──
  v_slip_lines := jsonb_build_array(
    jsonb_build_object('label', 'Salaire de base', 'amount', v_base_salary, 'type', 'gross'),
    jsonb_build_object('label', 'Heures supplémentaires', 'amount', v_overtime_pay, 'type', 'overtime')
  )
  || CASE WHEN v_bonus > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Prime', 'amount', v_bonus, 'type', 'bonus')) ELSE '[]'::jsonb END
  || CASE WHEN v_pay_recall <> 0 THEN jsonb_build_array(jsonb_build_object('label', 'Rappel de paie', 'amount', v_pay_recall, 'type', 'pay_recall')) ELSE '[]'::jsonb END
  || jsonb_build_array(
    jsonb_build_object('label', 'Cotisations sociales', 'amount', -v_ss_employee, 'type', 'social_charges'),
    jsonb_build_object('label', 'CSG/CRDS', 'amount', -v_csg_crds_total, 'type', 'csg_crds'),
    jsonb_build_object('label', 'Impôt sur le revenu (PAS)', 'amount', -v_income_tax, 'type', 'income_tax')
  )
  || CASE WHEN v_advance_deduction > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Acompte sur salaire', 'amount', -v_advance_deduction, 'type', 'advance_deduction')) ELSE '[]'::jsonb END
  || CASE WHEN v_unpaid_leave_deduction > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Congé sans solde', 'amount', -v_unpaid_leave_deduction, 'type', 'unpaid_leave_deduction')) ELSE '[]'::jsonb END
  || CASE WHEN v_other_deductions > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Autres déductions', 'amount', -v_other_deductions, 'type', 'other_deductions')) ELSE '[]'::jsonb END
  || CASE WHEN v_expense_reimbursement > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Remboursement de frais', 'amount', v_expense_reimbursement, 'type', 'expense_reimbursement')) ELSE '[]'::jsonb END
  || CASE WHEN v_meal_vouchers > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Titres-restaurant', 'amount', v_meal_vouchers, 'type', 'meal_vouchers')) ELSE '[]'::jsonb END
  || CASE WHEN v_transport_allowance > 0 THEN jsonb_build_array(jsonb_build_object('label', 'Indemnité transport', 'amount', v_transport_allowance, 'type', 'transport')) ELSE '[]'::jsonb END;

  -- ── Créer ou mettre à jour le bulletin ──
  -- Chercher un bulletin existant pour cet employé et cette période
  SELECT id INTO v_payslip_id
  FROM pay_slips
  WHERE employee_id = p_employee_id
    AND tenant_id = v_tid
    AND period_start = v_period_start
  LIMIT 1;

  v_payslip_number := COALESCE(
    (SELECT number FROM pay_slips WHERE id = v_payslip_id),
    'BS-' || p_period || '-' || lpad(substr(p_employee_id::text, 1, 4), 4, '0')
  );

  IF v_payslip_id IS NOT NULL THEN
    UPDATE pay_slips SET
      gross_salary = v_base_salary,
      overtime_pay = v_overtime_pay,
      bonus = v_bonus,
      total_gross = v_total_gross,
      social_security_employee = v_ss_employee,
      income_tax = v_income_tax,
      other_deductions = v_csg_crds_total + v_advance_deduction + v_other_deductions,
      total_deductions = v_total_deductions,
      net_salary = v_net_payable,
      employer_contributions = v_ss_employer,
      calc_inputs = jsonb_build_object(
        'gridVersion', v_grid_version,
        'pmss', v_pmss,
        'ceilingBase', v_ceiling_base,
        'csgDeductible', v_csg_deductible,
        'csgNonDeductible', v_csg_non_deductible,
        'crds', v_crds,
        'netSocial', v_net_social,
        'netTaxable', v_net_taxable,
        'reductionGenerale', v_reduction_generale,
        'withholdingRate', v_withholding_rate,
        'withholdingSource', v_withholding_source,
        'overtimeHours', v_overtime_hours,
        'mealVouchers', v_meal_vouchers,
        'transportAllowance', v_transport_allowance,
        'advanceDeduction', v_advance_deduction,
        'payRecall', v_pay_recall,
        'expenseReimbursement', v_expense_reimbursement,
        'unpaidLeaveDeduction', v_unpaid_leave_deduction,
        'otherDeductions', v_other_deductions,
        'cumulativeGrossYTD', v_cum_gross_ytd + v_total_gross,
        'cumulativeCeilingBaseYTD', v_cum_ceiling_base_ytd + v_ceiling_base,
        'variableElementCount', v_ve_count,
        'countryCode', v_country_code,
        'category', v_category,
        'rgduCoefficient', v_rgdu_coef,
        'contributions', v_contrib
      )
    WHERE id = v_payslip_id AND tenant_id = v_tid;
  ELSE
    INSERT INTO pay_slips (
      tenant_id, number, pay_run_id, employee_id,
      period_start, period_end,
      gross_salary, overtime_pay, bonus, total_gross,
      social_security_employee, income_tax, other_deductions, total_deductions,
      net_salary, employer_contributions, status,
      calc_inputs
    ) VALUES (
      v_tid, v_payslip_number, p_pay_run_id, p_employee_id,
      v_period_start, v_period_end,
      v_base_salary, v_overtime_pay, v_bonus, v_total_gross,
      v_ss_employee, v_income_tax, v_csg_crds_total + v_advance_deduction + v_other_deductions, v_total_deductions,
      v_net_payable, v_ss_employer, 'draft',
      jsonb_build_object(
        'gridVersion', v_grid_version,
        'pmss', v_pmss,
        'ceilingBase', v_ceiling_base,
        'csgDeductible', v_csg_deductible,
        'csgNonDeductible', v_csg_non_deductible,
        'crds', v_crds,
        'netSocial', v_net_social,
        'netTaxable', v_net_taxable,
        'reductionGenerale', v_reduction_generale,
        'withholdingRate', v_withholding_rate,
        'withholdingSource', v_withholding_source,
        'overtimeHours', v_overtime_hours,
        'mealVouchers', v_meal_vouchers,
        'transportAllowance', v_transport_allowance,
        'advanceDeduction', v_advance_deduction,
        'payRecall', v_pay_recall,
        'expenseReimbursement', v_expense_reimbursement,
        'unpaidLeaveDeduction', v_unpaid_leave_deduction,
        'otherDeductions', v_other_deductions,
        'cumulativeGrossYTD', v_cum_gross_ytd + v_total_gross,
        'cumulativeCeilingBaseYTD', v_cum_ceiling_base_ytd + v_ceiling_base,
        'variableElementCount', v_ve_count,
        'countryCode', v_country_code,
        'category', v_category,
        'rgduCoefficient', v_rgdu_coef,
        'contributions', v_contrib
      )
    )
    RETURNING id INTO v_payslip_id;
  END IF;

  -- ── Créer ou mettre à jour pay_slip_clarified ──
  INSERT INTO pay_slip_clarified (
    tenant_id, pay_slip_id, employee_id, period,
    gross_salary, social_charges_employee, social_charges_employer,
    income_tax, net_before_tax, net_after_tax, total_deductions, lines
  ) VALUES (
    v_tid, v_payslip_id, p_employee_id, p_period,
    v_total_gross, v_ss_employee, v_ss_employer,
    v_income_tax, v_net_social, v_net_payable, v_total_deductions, v_slip_lines
  )
  ON CONFLICT (pay_slip_id) DO UPDATE SET
    gross_salary = EXCLUDED.gross_salary,
    social_charges_employee = EXCLUDED.social_charges_employee,
    social_charges_employer = EXCLUDED.social_charges_employer,
    income_tax = EXCLUDED.income_tax,
    net_before_tax = EXCLUDED.net_before_tax,
    net_after_tax = EXCLUDED.net_after_tax,
    total_deductions = EXCLUDED.total_deductions,
    lines = EXCLUDED.lines;

  -- ── Marquer les éléments variables comme intégrés ──
  IF p_pay_run_id IS NOT NULL THEN
    UPDATE payroll_variable_elements
    SET integrated = true
    WHERE pay_run_id = p_pay_run_id
      AND employee_id = p_employee_id
      AND tenant_id = v_tid;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'employee_id', p_employee_id,
    'period', p_period,
    'pay_slip_id', v_payslip_id,
    'gross_salary', v_base_salary,
    'overtime_pay', v_overtime_pay,
    'bonus', v_bonus,
    'total_gross', v_total_gross,
    'social_security_employee', v_ss_employee,
    'csg_deductible', v_csg_deductible,
    'csg_non_deductible', v_csg_non_deductible,
    'crds', v_crds,
    'csg_crds_total', v_csg_crds_total,
    'income_tax', v_income_tax,
    'other_deductions', v_csg_crds_total + v_advance_deduction + v_other_deductions,
    'total_deductions', v_total_deductions,
    'net_salary', v_net_payable,
    'employer_contributions', v_ss_employer,
    'net_social', v_net_social,
    'net_taxable', v_net_taxable,
    'ceiling_base', v_ceiling_base,
    'pmss', v_pmss,
    'reduction_generale', v_reduction_generale,
    'withholding_rate', v_withholding_rate,
    'withholding_source', v_withholding_source,
    'grid_version', v_grid_version,
    'cumulative_gross_ytd', v_cum_gross_ytd + v_total_gross,
    'cumulative_ceiling_base_ytd', v_cum_ceiling_base_ytd + v_ceiling_base,
    'country_code', v_country_code,
    'rgdu_coefficient', v_rgdu_coef,
    'contributions', v_contrib
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;
