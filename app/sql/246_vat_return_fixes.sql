-- ============================================================
-- 246_vat_return_fixes.sql — M-10 : la déclaration de TVA rend des chiffres
--
-- Six défauts trouvés en exécutant `sql/245_vat_return_tests.sql` sur base
-- neuve le 24/09/2026. Tous vus rouges avant ce fichier.
--
--   T02  la déclaration produite par le bouton « Générer » ne renseigne que
--        box1/box2/box3. VatReturnsPage.tsx affiche box5_net_vat (« TVA
--        nette »), total_sales et total_purchases : trois colonnes à 0,00 €
--        sur toutes les déclarations générées, dont la seule que l'écran met
--        en gras et en couleur.
--   T03  un crédit de TVA n'est écrit nulle part : box4_repayment_due reste 0
--        et box3 vaut 0. Une période créditrice ressemble à une période sans
--        rien à déclarer.
--   T04  relancer « Générer » sur la même période crée une deuxième
--        déclaration. Rien, ni contrainte ni fonction, ne s'y oppose.
--   T05  les deux chemins de l'écran ne comptent pas la même chose : une
--        écriture de TVA saisie à la main (OD sans code de TVA sur la ligne)
--        entre dans calculate_vat_ca3 et pas dans get_vat_summary_by_code,
--        qui filtre sur `vat_code IS NOT NULL`. Mesuré : 260 contre 200.
--   T06  get_vat_summary_by_code borne la période à l'exercice reçu
--        (GREATEST/LEAST) et le formulaire lui passe toujours l'exercice
--        COURANT (accounting.ts:172). La déclaration de décembre préparée en
--        janvier rend zéro, en silence.
--   T07  cette même fonction rend une ligne par ligne d'écriture, pas une par
--        code : l'écran l'appelle par PostgREST, plafonné à 1 000 lignes
--        (PGRST_DB_MAX_ROWS). Au-delà, la CA3 du formulaire est tronquée sans
--        un mot et la TVA déclarée est sous-évaluée.
--
-- Ce que ce fichier NE règle pas, et qui reste au registre (245 T08) : le
-- chiffre d'affaires reconstitué depuis la TVA (montant ÷ taux) ignore le
-- chiffre d'affaires non taxé — exonéré, exports, livraisons
-- intracommunautaires. Les cases correspondantes de la CA3 (A2, E1, E2)
-- demandent une base tirée des comptes de produits, pas des comptes de TVA.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Une déclaration par période (T04)
-- ─────────────────────────────────────────────────────────────
-- Reprise des données : une période qui porte plusieurs déclarations dont une
-- seule au plus est déposée garde la déposée (ou la plus récente) ; les
-- brouillons redondants partent. Deux déclarations DÉPOSÉES sur la même
-- période ne sont pas arbitrables par une migration : elle s'arrête et les
-- nomme, pour que quelqu'un tranche.
DO $$
DECLARE v_bad text; v_deleted int;
BEGIN
  SELECT string_agg(format('société %s, période %s → %s : %s déclarations déposées',
                           tenant_id, period_start, period_end, n), E'\n')
    INTO v_bad
  FROM (SELECT tenant_id, period_start, period_end, count(*) n
        FROM vat_returns WHERE status <> 'draft'
        GROUP BY 1, 2, 3 HAVING count(*) > 1) x;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'246 : plusieurs déclarations déposées sur une même période — à trancher à la main avant de rejouer :\n%', v_bad;
  END IF;

  WITH ranked AS (
    SELECT id, row_number() OVER (PARTITION BY tenant_id, period_start, period_end
                                  ORDER BY (status <> 'draft') DESC, created_at DESC, id) AS rn
    FROM vat_returns
  )
  DELETE FROM vat_returns v USING ranked r WHERE v.id = r.id AND r.rn > 1;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  IF v_deleted > 0 THEN
    RAISE NOTICE '246 : % déclaration(s) en double supprimée(s) (brouillons redondants)', v_deleted;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS vat_returns_tenant_period_uniq
  ON vat_returns (tenant_id, period_start, period_end);

-- ─────────────────────────────────────────────────────────────
-- 2. La CA3 rend aussi les bases (T02) et le crédit (T03)
-- ─────────────────────────────────────────────────────────────
-- La base hors taxe est reconstituée depuis le montant de TVA et le taux du
-- paramétrage (montant ÷ taux). C'est exact pour un compte à taux unique ;
-- un compte à taux 0 (exonéré) ne rend aucune base — voir l'avertissement
-- en tête de fichier.
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
  v_base_coll numeric; v_base_ded numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;
  IF p_period_start IS NULL OR p_period_end IS NULL OR p_period_end < p_period_start THEN
    RAISE EXCEPTION 'Période de déclaration invalide : % → %', p_period_start, p_period_end
      USING ERRCODE = '22007';
  END IF;

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
         COALESCE(sum(base) FILTER (WHERE direction = 'collected'), 0),
         COALESCE(sum(base) FILTER (WHERE direction = 'deductible'), 0)
    INTO v_lines, v_coll, v_ded, v_rc_due, v_rc_ded, v_base_coll, v_base_ded
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
    'total_sales', v_base_coll,
    'total_purchases', v_base_ded,
    'lines', v_lines
  );
END $function$;

-- ─────────────────────────────────────────────────────────────
-- 3. « Générer » renseigne toutes les colonnes que l'écran lit (T02, T03)
--    et ne crée plus de doublon (T04)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_vat_return(p_period_start date, p_period_end date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tid uuid := current_tenant_id();
  v_result jsonb;
  v_return_id uuid;
  v_existing record;
  v_coll numeric; v_ded numeric; v_net numeric;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucune société active' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_result FROM calculate_vat_ca3(p_period_start, p_period_end);

  v_coll := COALESCE((v_result->>'vat_collected')::numeric, 0);
  v_ded  := COALESCE((v_result->>'vat_deductible')::numeric, 0);
  v_net  := v_coll - v_ded;

  SELECT id, status INTO v_existing FROM vat_returns
  WHERE tenant_id = v_tid AND period_start = p_period_start AND period_end = p_period_end;

  -- Une déclaration déjà déposée ou payée ne se réécrit pas en silence.
  IF v_existing.id IS NOT NULL AND v_existing.status <> 'draft' THEN
    RAISE EXCEPTION 'La déclaration du % au % est déjà « % » : elle ne peut plus être recalculée',
      p_period_start, p_period_end, v_existing.status USING ERRCODE = '23505';
  END IF;

  INSERT INTO vat_returns (
    tenant_id, period_start, period_end,
    box1_output_vat, box2_input_vat, box3_vat_due, box4_repayment_due, box5_net_vat,
    total_sales, total_purchases,
    vat_collected, vat_deductible, vat_to_pay,
    status, created_at
  )
  VALUES (
    v_tid, p_period_start, p_period_end,
    v_coll, v_ded, GREATEST(v_net, 0), GREATEST(-v_net, 0), v_net,
    COALESCE((v_result->>'total_sales')::numeric, 0),
    COALESCE((v_result->>'total_purchases')::numeric, 0),
    v_coll, v_ded, GREATEST(v_net, 0),
    'draft', NOW()
  )
  ON CONFLICT (tenant_id, period_start, period_end) DO UPDATE SET
    box1_output_vat    = EXCLUDED.box1_output_vat,
    box2_input_vat     = EXCLUDED.box2_input_vat,
    box3_vat_due       = EXCLUDED.box3_vat_due,
    box4_repayment_due = EXCLUDED.box4_repayment_due,
    box5_net_vat       = EXCLUDED.box5_net_vat,
    total_sales        = EXCLUDED.total_sales,
    total_purchases    = EXCLUDED.total_purchases,
    vat_collected      = EXCLUDED.vat_collected,
    vat_deductible     = EXCLUDED.vat_deductible,
    vat_to_pay         = EXCLUDED.vat_to_pay
  RETURNING id INTO v_return_id;

  RETURN jsonb_build_object('id', v_return_id, 'data', v_result);
END;
$function$;

-- ─────────────────────────────────────────────────────────────
-- 4. La synthèse par code compte les mêmes écritures que la CA3 (T05),
--    respecte la période demandée (T06) et rend une ligne par code (T07)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_vat_summary_by_code(p_fiscal_year_id uuid, p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date)
RETURNS TABLE(vat_code text, direction text, account_code text, ca3_box text, base_ht numeric, vat_amount numeric, rate numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Les dates reçues priment : le formulaire passe toujours l'exercice courant
  -- (accounting.ts:172), et borner décembre à l'exercice suivant rendait zéro.
  -- L'exercice ne sert plus que de repli quand aucune date n'est donnée.
  WITH bornes AS (
    SELECT COALESCE(p_date_from, fy.start_date) AS d1, COALESCE(p_date_to, fy.end_date) AS d2
    FROM (SELECT start_date, end_date FROM fiscal_years
          WHERE id = p_fiscal_year_id AND tenant_id = current_tenant_id()) fy
    RIGHT JOIN (SELECT 1) one ON true
  ), l AS (
    SELECT a.acc,
           -- une ligne saisie à la main n'a pas de code : le déduire du compte
           COALESCE(NULLIF(jl.vat_code, ''), m0.vat_code, a.acc) AS vat_code,
           c.direction,
           CASE c.direction WHEN 'collected' THEN jl.credit - jl.debit
                            ELSE jl.debit - jl.credit END AS amount,
           jl.tenant_id
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_id AND je.tenant_id = jl.tenant_id
    CROSS JOIN bornes b
    CROSS JOIN LATERAL (SELECT COALESCE(jl.account_general, jl.account_code) AS acc) a
    CROSS JOIN LATERAL vat_account_class(jl.tenant_id, a.acc) c
    LEFT JOIN LATERAL (SELECT x.vat_code FROM vat_account_mapping x
                       WHERE x.tenant_id IN (jl.tenant_id, '00000000-0000-0000-0000-000000000000')
                         AND x.account_code = a.acc AND x.direction = c.direction
                       ORDER BY (x.tenant_id = jl.tenant_id) DESC, x.rate DESC, x.vat_code LIMIT 1) m0 ON true
    WHERE jl.tenant_id = current_tenant_id()
      AND je.status = 'posted'
      AND je.date >= b.d1 AND je.date <= b.d2
      AND COALESCE(je.journal_code, '') NOT IN ('AN', 'CL')
      AND c.direction IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM journal_lines x
                      WHERE x.journal_id = je.id
                        AND COALESCE(x.account_general, x.account_code) ~ '^(4455|44567)')
  ), g AS (
    SELECT l.vat_code, l.direction, l.acc, l.tenant_id, round(sum(l.amount), 2) AS amount
    FROM l GROUP BY 1, 2, 3, 4
  )
  SELECT g.vat_code, g.direction, g.acc, m.ca3_box,
         CASE WHEN COALESCE(m.rate, 0) > 0 THEN round(g.amount / (m.rate / 100), 2) ELSE 0 END,
         g.amount,
         COALESCE(m.rate, 0)
  FROM g
  LEFT JOIN LATERAL (SELECT x.ca3_box, x.rate FROM vat_account_mapping x
                     WHERE x.tenant_id IN (g.tenant_id, '00000000-0000-0000-0000-000000000000')
                       AND x.vat_code = g.vat_code AND x.direction = g.direction
                     ORDER BY (x.tenant_id = g.tenant_id) DESC LIMIT 1) m ON true
  ORDER BY g.direction, g.vat_code;
$function$;

COMMENT ON FUNCTION public.get_vat_summary_by_code(uuid, date, date) IS
  'CA3 par code de TVA, une ligne par (code, sens, compte). 246 : agrégée (le plafond PostgREST de 1 000 lignes tronquait la CA3 du formulaire), bornée par les dates reçues et non plus par l''exercice, et incluant les lignes de TVA sans code de TVA.';
