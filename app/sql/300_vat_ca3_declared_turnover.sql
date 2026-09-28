-- ============================================================
-- 268_vat_ca3_declared_turnover.sql — W7 : le chiffre d'affaires déclaré se lit
--                                    sur les comptes de produits
--
-- LE DÉFAUT (245 T08, inscrit au registre `ci/expected_failures.sql`).
-- La base hors taxe de la CA3 était reconstituée **depuis la TVA** :
-- `base = montant ÷ taux` (246, §2). C'est exact pour une vente taxée et faux
-- pour tout le reste : une vente **exonérée**, un **export** ou une **livraison
-- intracommunautaire** ne porte aucune TVA, donc aucune base — ni dans
-- `total_sales`, ni dans les cases A2 / E1 / E2 de la CA3. Mesuré sur base neuve
-- le 28/09/2026, avant ce fichier :
--
--   1 000 € taxés à 20 % + 500 € exonérés + 250 € intracommunautaires
--   → CA déclaré = 1 000,00 (au lieu de 1 750,00), TVA = 200,00 (juste)
--
-- LE CORRECTIF. Le chiffre d'affaires est un solde de **comptes de produits**
-- (classe 70), pas une reconstitution : on le lit là où les écritures le
-- portent. Un avoir client débite 707000, l'export crédite 707000 — le solde
-- créditeur net est le CA de la période, taxé ou non.
--
-- CE QUI NE CHANGE PAS. La TVA collectée / déductible reste lue sur les soldes
-- des comptes 445x (`vat_account_class`), les lignes par code de TVA restent
-- celles de la 246, et la ventilation par exercice/date ne bouge pas.
--
-- LES LIMITES, DITES. (1) `total_purchases` reste reconstitué depuis la TVA
-- déductible : la CA3 ne déclare pas de base d'achat, et le défaut inscrit ne
-- portait que sur le chiffre d'affaires — un achat non taxé n'entre donc pas
-- dans cette colonne. (2) La **ventilation par case** (A2 / E1 / E2) n'est pas
-- produite ici : elle demande les pièces de vente (le code de TVA de la ligne),
-- pas seulement le grand livre — c'est le lot de chaînages L14. La **somme**
-- déclarée, elle, est juste, et c'est elle que 245 T08 mesure.
-- ============================================================

CREATE OR REPLACE FUNCTION public.calculate_vat_ca3(p_period_start date, p_period_end date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_lines jsonb;
  v_coll numeric; v_ded numeric; v_rc_due numeric; v_rc_ded numeric;
  v_base_ded numeric; v_base_coll numeric;
  v_total_sales numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;
  IF p_period_start IS NULL OR p_period_end IS NULL OR p_period_end < p_period_start THEN
    RAISE EXCEPTION 'Période de déclaration invalide : % → %', p_period_start, p_period_end
      USING ERRCODE = '22007';
  END IF;

  -- Le chiffre d'affaires : solde des comptes de produits (classe 70) de la
  -- période. `AN` (à-nouveaux) et `CL` (clôture) sont exclus comme partout
  -- ailleurs dans la déclaration : ce ne sont pas des opérations de la période.
  SELECT COALESCE(sum(jl.credit - jl.debit), 0) INTO v_total_sales
  FROM journal_lines jl
  JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
  WHERE jl.tenant_id = v_tid
    AND je.status = 'posted'
    AND je.date BETWEEN p_period_start AND p_period_end
    AND COALESCE(je.journal_code, '') NOT IN ('AN', 'CL')
    AND COALESCE(jl.account_general, jl.account_code) ~ '^70';

  WITH mv AS (
    SELECT COALESCE(jl.account_general, jl.account_code) AS acc, jl.debit, jl.credit
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    WHERE jl.tenant_id = v_tid
      AND je.status = 'posted'
      AND je.date BETWEEN p_period_start AND p_period_end
      AND COALESCE(je.journal_code, '') NOT IN ('AN', 'CL')
      AND COALESCE(jl.account_general, jl.account_code) ~ '^445(2|6|7)'
      AND NOT EXISTS (SELECT 1 FROM journal_lines x
                      WHERE x.journal_id = je.id AND COALESCE(x.account_general, x.account_code) ~ '^(4455|44567)')
  ), acc AS (
    SELECT mv.acc, c.direction, c.reverse_charge, r.rate,
           round(sum(CASE c.direction WHEN 'collected' THEN mv.credit - mv.debit ELSE mv.debit - mv.credit END), 2) AS amount
    FROM mv
    CROSS JOIN LATERAL vat_account_class(v_tid, mv.acc) c
    LEFT JOIN LATERAL (SELECT x.rate FROM vat_account_mapping x
                       WHERE x.tenant_id IN (v_tid, '00000000-0000-0000-0000-000000000000')
                         AND x.account_code = mv.acc AND x.direction = c.direction
                       ORDER BY (x.tenant_id = v_tid) DESC, x.rate DESC LIMIT 1) r ON true
    WHERE c.direction IS NOT NULL
    GROUP BY 1, 2, 3, 4
  ), b AS (
    SELECT acc.*, CASE WHEN COALESCE(acc.rate, 0) > 0
                       THEN round(acc.amount / (acc.rate / 100), 2) ELSE 0 END AS base
    FROM acc
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('account_code', acc, 'direction', direction,
                                               'reverse_charge', reverse_charge, 'rate', rate,
                                               'base_ht', base, 'amount', amount)
                            ORDER BY direction, acc), '[]'::jsonb),
         COALESCE(sum(amount) FILTER (WHERE direction = 'collected'), 0),
         COALESCE(sum(amount) FILTER (WHERE direction = 'deductible'), 0),
         COALESCE(sum(amount) FILTER (WHERE direction = 'collected' AND reverse_charge), 0),
         COALESCE(sum(amount) FILTER (WHERE direction = 'deductible' AND reverse_charge), 0),
         COALESCE(sum(base) FILTER (WHERE direction = 'deductible'), 0),
         COALESCE(sum(base) FILTER (WHERE direction = 'collected'), 0)
    INTO v_lines, v_coll, v_ded, v_rc_due, v_rc_ded, v_base_ded, v_base_coll
  FROM b;

  RETURN jsonb_build_object(
    'period_start', p_period_start,
    'period_end', p_period_end,
    'source', 'ledger',
    'vat_collected', v_coll,
    'vat_deductible', v_ded,
    'reverse_charge_due', v_rc_due,
    'reverse_charge_deductible', v_rc_ded,
    'vat_to_pay', GREATEST(v_coll - v_ded, 0),
    'vat_credit', GREATEST(v_ded - v_coll, 0),
    'net_vat', v_coll - v_ded,
    -- 300 : le CA se lit sur les comptes de produits (taxés et non taxés) ;
    -- la base reconstituée depuis la TVA ne voit pas les opérations exonérées.
    'total_sales', v_total_sales,
    'total_sales_taxed_base', v_base_coll,
    'total_purchases', v_base_ded,
    'lines', v_lines
  );
END $function$;

COMMENT ON FUNCTION public.calculate_vat_ca3(date, date) IS
  'CA3 de la période : TVA sur les soldes des comptes 445x, chiffre d''affaires sur les comptes de produits (classe 70). 300 : la base du CA n''est plus reconstituée depuis la TVA — un CA exonéré, exporté ou intracommunautaire y entre désormais.';
