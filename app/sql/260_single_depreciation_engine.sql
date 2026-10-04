-- ============================================================
-- 260_single_depreciation_engine.sql — vague W5 (IMMO-01 → IMMO-05, RH-04)
--
-- LE DÉFAUT N'EST PAS LE CALCUL : C'EST QU'IL Y EN A PLUSIEURS.
--
-- Mesuré le 27/09/2026 sur base neuve (259 migrations) :
--
--   IMMO-01  TROIS moteurs d'amortissement cohabitent, et ils se contredisent :
--            `generate_depreciation_entry` (211/226, correct, comptabilise) ;
--            `calculate_depreciation(uuid, text)` (RPC historique, 88/158) ;
--            `calculateDepreciation` (front, `misc.ts`), qui calcule avec
--            `floor(jours / 365,25)` et écrit `current_value` directement.
--   IMMO-02  « Calculer les amortissements » (bouton de l'écran) appelle le
--            calcul du FRONT : rien n'est comptabilisé, aucune écriture
--            n'existe — le bouton n'amortit pas, il réécrit une valeur.
--   IMMO-03  Ce recalcul part de `Date.now()` : relancé après clôture, il
--            écrase `current_value` de l'exercice clos (le passé change).
--   IMMO-04  Les trois méthodes offertes à l'écran (`straight_line`,
--            `declining_balance`, `units_of_production`) n'ont AUCUN effet :
--            `depreciation_method` est stockée et aucun moteur ne la lit.
--   IMMO-05  Le lot (`calculateAllDepreciation`, front) enveloppe chaque
--            immobilisation dans un `try/catch { console.error }` : une dotation
--            en échec est SAUTÉE EN SILENCE et la fonction rend une liste
--            partielle comme un succès.
--   RH-04    Les heures supplémentaires avaient trois moteurs et deux seuils :
--            `calculate_lateness_on_timesheet` → `overtime_minutes` (jamais
--            facturé), `sync_timesheet_to_payroll` (heures sup au MONTANT 0) et
--            `importTimesheetElements` (front, seuil 8 h, taux × 1,25 codé en
--            dur). La 256 a ramené le seuil à l'horaire prévu — il restait le
--            montant nul et le second calcul du front.
--
-- CE QUE CETTE MIGRATION POSE (décisions exécutées, pas proposées) :
--
--   1. UN SEUL moteur d'amortissement : `generate_depreciation_entry`.
--      `calculate_depreciation(uuid, text)` est SUPPRIMÉE ; le calcul du front
--      disparaît avec elle (le front lit le moteur). `depreciation_method` est
--      enfin LUE :
--        - `linear` / `straight_line` → linéaire, prorata temporis en jours la
--          première année (le comportement de 211/226, inchangé) ;
--        - `declining_balance` → dégressif, coefficient légal PARAMÉTRÉ
--          (`payroll_legal_parameters`, AMORT_COEFF_DEGRESSIF_*) et bascule sur
--          le linéaire du restant ;
--        - `units_of_production` → RETIRÉE : refus explicite et nommé. Le plan
--          prévoyait « réellement implémentées ou retirées de l'écran » ; la
--          fiche ne porte AUCUN compteur d'unités produites, l'implémenter
--          aurait inventé une donnée ;
--        - toute autre valeur → refus nommé (plus de linéaire silencieux).
--   2. L'exercice est BORNÉ : une dotation d'exercice clos est refusée. Le
--      calcul ne part plus de la date du jour mais de l'exercice demandé, et
--      l'historique est la seule base du cumul.
--   3. UN LOT QUI DIT CE QU'IL A FAIT : `generate_depreciation_entries(uuid)`
--      rend un verdict PAR immobilisation (`comptabilisees`, `sans_objet`,
--      `echecs` nommés). L'écran affiche les échecs.
--   4. UN SEUL CALCUL D'HEURES SUPPLÉMENTAIRES : `payroll_overtime_amount`
--      (taux horaire de la société × majoration). Le déclencheur du pointage
--      l'utilise et pose le MONTANT ; le front ne calcule plus rien, il lit
--      (`payroll_overtime_preview`). Le seuil reste l'horaire prévu.
--
-- Scénarios : sql/260_single_depreciation_engine_tests.sql (T01 → T10).
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Les paramètres, semés avec leur défaut CALCULÉ — même table et même
--    précédence que la 256 : société, puis global.
-- ─────────────────────────────────────────────────────────────
INSERT INTO payroll_legal_parameters (tenant_id, country_code, code, value, valid_from)
SELECT NULL, 'FR', v.code, v.value, DATE '2025-01-01'
FROM (VALUES
  ('AMORT_COEFF_DEGRESSIF_3_4',    1.5),   -- durées 3 et 4 ans
  ('AMORT_COEFF_DEGRESSIF_5_6',    2.0),   -- durées 5 et 6 ans
  ('AMORT_COEFF_DEGRESSIF_7_PLUS', 2.5),   -- durées 7 ans et plus
  ('MAJORATION_HEURES_SUP',        1.25)   -- première tranche : 25 %
) AS v(code, value)
WHERE NOT EXISTS (
  SELECT 1 FROM payroll_legal_parameters
  WHERE tenant_id IS NULL AND country_code = 'FR' AND code = v.code AND valid_from = DATE '2025-01-01'
);

-- Le coefficient dégressif est une fonction, pas un littéral : il dépend de la
-- durée d'utilité et reste paramétrable par société (localisation D-11).
CREATE OR REPLACE FUNCTION public.depreciation_coefficient(
  p_tenant uuid,
  p_life_years integer
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_code text;
  v_defaut numeric;
BEGIN
  IF COALESCE(p_life_years, 0) <= 0 THEN
    RETURN 1;  -- durée inconnue : aucun dégressif
  END IF;
  IF p_life_years <= 2 THEN
    v_code := NULL; v_defaut := 1;            -- sous 3 ans, le dégressif n'existe pas
  ELSIF p_life_years <= 4 THEN
    v_code := 'AMORT_COEFF_DEGRESSIF_3_4';    v_defaut := 1.5;
  ELSIF p_life_years <= 6 THEN
    v_code := 'AMORT_COEFF_DEGRESSIF_5_6';    v_defaut := 2.0;
  ELSE
    v_code := 'AMORT_COEFF_DEGRESSIF_7_PLUS'; v_defaut := 2.5;
  END IF;
  IF v_code IS NULL THEN RETURN v_defaut; END IF;
  RETURN COALESCE(NULLIF(get_legal_parameter(v_code, 'FR', CURRENT_DATE, p_tenant), 0), v_defaut);
END $$;

COMMENT ON FUNCTION public.depreciation_coefficient(uuid, integer) IS
  'IMMO-04 — coefficient de l''amortissement dégressif : paramètre AMORT_COEFF_DEGRESSIF_* de la société (puis global), défaut légal 1,5 / 2 / 2,5 selon la durée. Jamais un littéral dans le moteur.';

-- Droits : `depreciation_coefficient` prend une société en paramètre, elle est
-- appelée depuis le moteur (SECURITY DEFINER) et n'est PAS une API. La
-- révocation complète est écrite en fin de §4, avec les autres fonctions qui
-- prennent une société.
REVOKE ALL ON FUNCTION public.depreciation_coefficient(uuid, integer) FROM PUBLIC, anon;

-- ─────────────────────────────────────────────────────────────
-- 2. UN SEUL moteur d'amortissement (IMMO-01 → IMMO-04)
--    D 681x (dotation) / C 28x (amortissement cumulé) : brouillard, lignes,
--    validation (noyau strict 187), historique, valeur nette.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_depreciation_entry(
  p_fixed_asset_id uuid,
  p_fiscal_year_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fa fixed_assets%ROWTYPE;
  v_fy fiscal_years%ROWTYPE;
  v_methode text;
  v_base numeric;
  v_annuel numeric;
  v_amount numeric;
  v_cumul numeric;
  v_total numeric;
  v_annees int;
  v_taux numeric;
  v_debit text;
  v_credit text;
  v_number text;
  v_ref text;
  v_je uuid;
  v_existe uuid;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_fa FROM fixed_assets WHERE id = p_fixed_asset_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Immobilisation introuvable : %', p_fixed_asset_id; END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exercice introuvable : %', p_fiscal_year_id; END IF;

  -- IMMO-03 : une dotation d'exercice CLOS ne se recalcule pas. Le cumul vient
  -- de l'historique, l'exercice de la demande — jamais de la date du jour.
  IF v_fy.status <> 'open' THEN
    RAISE EXCEPTION 'Exercice % : statut % — une dotation d''exercice clos ne se recalcule pas', v_fy.code, v_fy.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotence : une dotation déjà comptabilisée est rendue telle quelle
  v_ref := 'AMORT:' || v_fa.id || ':' || v_fy.code;
  SELECT id INTO v_existe FROM journal_entries
  WHERE tenant_id = v_tid AND reference = v_ref LIMIT 1;
  IF v_existe IS NOT NULL THEN RETURN v_existe; END IF;

  IF v_fa.status <> 'active' THEN
    RAISE EXCEPTION 'Immobilisation % : statut % — aucune dotation à comptabiliser', v_fa.name, v_fa.status
      USING ERRCODE = 'check_violation';
  END IF;

  -- IMMO-04 : la méthode est LUE. Les deux façons d'écrire le linéaire que le
  -- dépôt connaît (l'écran écrit `straight_line`, les reprises `linear`)
  -- désignent le MÊME moteur.
  v_methode := lower(COALESCE(NULLIF(btrim(v_fa.depreciation_method), ''), 'linear'));
  IF v_methode NOT IN ('linear', 'straight_line', 'declining', 'declining_balance') THEN
    IF v_methode = 'units_of_production' THEN
      RAISE EXCEPTION 'Immobilisation % : méthode « units_of_production » RETIRÉE — la fiche ne porte aucun compteur d''unités produites, une dotation par unité serait une donnée inventée ; utilisez linear ou declining_balance', v_fa.name
        USING ERRCODE = 'feature_not_supported';
    END IF;
    RAISE EXCEPTION 'Immobilisation % : méthode d''amortissement « % » inconnue (attendu : linear, straight_line, declining_balance)', v_fa.name, v_methode
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_base := GREATEST(COALESCE(v_fa.purchase_value, 0) - COALESCE(v_fa.residual_value, 0), 0);
  IF v_base = 0 OR COALESCE(v_fa.useful_life_years, 0) <= 0 THEN
    RETURN NULL;  -- rien à amortir
  END IF;

  -- Amortissements déjà dotés : l'historique fait foi, pas la valeur courante.
  -- `v_annees` compte les exercices déjà dotés (la bascule du dégressif en
  -- dépend) ; le cumul est plafonné à la base amortissable.
  SELECT COALESCE(sum(amount), 0), count(*) INTO v_cumul, v_annees
  FROM asset_depreciations
  WHERE tenant_id = v_tid AND asset_id = v_fa.id AND depreciation_type = 'dotation';
  v_cumul := LEAST(v_cumul, v_base);

  IF v_methode IN ('declining', 'declining_balance') THEN
    -- Taux dégressif = coefficient légal / durée, avec BASCULE sur le linéaire
    -- du restant dès que celui-ci devient plus favorable.
    v_taux := depreciation_coefficient(v_tid, v_fa.useful_life_years) / v_fa.useful_life_years;
    v_taux := GREATEST(v_taux, 1.0 / GREATEST(v_fa.useful_life_years - v_annees, 1));
    v_annuel := round(GREATEST(v_base - v_cumul, 0) * v_taux, 2);
  ELSE
    v_annuel := round(v_base / v_fa.useful_life_years, 2);
  END IF;
  v_amount := v_annuel;

  -- Prorata temporis en jours pour l'exercice d'acquisition
  IF v_fa.purchase_date > v_fy.start_date THEN
    v_amount := round(v_annuel * ((v_fy.end_date - v_fa.purchase_date) + 1)::numeric
                             / ((v_fy.end_date - v_fy.start_date) + 1), 2);
  END IF;

  -- Jamais plus que la base amortissable
  v_amount := LEAST(v_amount, round(v_base - v_cumul, 2));
  IF v_amount <= 0 THEN RETURN NULL; END IF;

  -- Comptes : ceux de l'immobilisation, sinon les comptes généraux du PCG
  v_debit := COALESCE(NULLIF(btrim(v_fa.account_expense_depreciation_code), ''), '681200');
  v_credit := COALESCE(NULLIF(btrim(v_fa.account_depreciation_code), ''), '281000');
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_debit) THEN
    RAISE EXCEPTION 'Compte de dotation % absent du plan comptable de la société', v_debit
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_credit) THEN
    RAISE EXCEPTION 'Compte d''amortissement % absent du plan comptable de la société', v_credit
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- 1. en-tête en brouillard (AUD-C02)
  v_number := 'AMORT-' || COALESCE(NULLIF(btrim(v_fa.code), ''), NULLIF(btrim(v_fa.asset_number), ''),
                                   left(v_fa.id::text, 8)) || '-' || v_fy.code;
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_tid, v_number, v_fy.end_date, 'OD', 'draft',
          'Dotation aux amortissements ' || v_fy.code || ' ('
            || CASE WHEN v_methode IN ('declining', 'declining_balance') THEN 'dégressif' ELSE 'linéaire' END
            || ') - ' || v_fa.name,
          v_ref, v_number)
  RETURNING id INTO v_je;

  -- 2. lignes
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
  VALUES
    (v_tid, v_je, v_debit,  'Dotations aux amortissements', v_amount, 0, 'Dotation ' || v_fy.code),
    (v_tid, v_je, v_credit, 'Amortissements', 0, v_amount, 'Dotation ' || v_fy.code);

  -- 3. validation : les triggers de la 187 vérifient équilibre, exercice, comptes
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  -- Historique de l'immobilisation + valeur nette.
  -- 226 : la VNC est la valeur d'ACQUISITION moins le cumul — la résiduelle est
  -- déjà hors de la base amortissable, la retrancher ici la déduirait deux fois.
  v_total := v_cumul + v_amount;
  INSERT INTO asset_depreciations (tenant_id, asset_id, fiscal_year_code, period, depreciation_type,
    amount, cumulative_amount, net_book_value, entry_number)
  VALUES (v_tid, v_fa.id, v_fy.code, 12, 'dotation', v_amount, v_total,
    round(GREATEST(COALESCE(v_fa.purchase_value, 0) - v_total, 0), 2), v_number);

  UPDATE fixed_assets
  SET current_value = GREATEST(COALESCE(purchase_value, 0) - v_total, 0),
      status = CASE WHEN v_total >= v_base THEN 'fully_depreciated' ELSE status END,
      updated_at = now()
  WHERE id = v_fa.id AND tenant_id = v_tid;

  RETURN v_je;
END $$;

REVOKE ALL ON FUNCTION public.generate_depreciation_entry(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_depreciation_entry(uuid, uuid) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 3. UN LOT QUI DIT CE QU'IL A FAIT (IMMO-02, IMMO-05)
--    Chaque immobilisation est tentée dans SA sous-transaction : un échec est
--    NOMMÉ dans `echecs` et n'annule pas les autres dotations. Le front ne
--    compte plus les succès tout seul — il lit ce verdict.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_depreciation_entries(
  p_fiscal_year_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_fy fiscal_years%ROWTYPE;
  v_total int := 0;
  v_ok int := 0;
  v_rien int := 0;
  v_entrees jsonb := '{}'::jsonb;
  v_echecs jsonb := '[]'::jsonb;
  r record;
  v_je uuid;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Amortissements : aucune société active' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_fy FROM fiscal_years WHERE id = p_fiscal_year_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exercice introuvable : %', p_fiscal_year_id USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF v_fy.status <> 'open' THEN
    RAISE EXCEPTION 'Exercice % : statut % — aucune dotation ne se recalcule sur un exercice clos', v_fy.code, v_fy.status
      USING ERRCODE = 'check_violation';
  END IF;

  FOR r IN
    SELECT id, COALESCE(NULLIF(btrim(name), ''), '—') AS nom
    FROM fixed_assets
    WHERE tenant_id = v_tid AND status = 'active'
    ORDER BY code NULLS LAST, created_at, id
  LOOP
    v_total := v_total + 1;
    BEGIN
      v_je := generate_depreciation_entry(r.id, p_fiscal_year_id);
      IF v_je IS NULL THEN
        v_rien := v_rien + 1;                 -- rien à amortir : dit, pas caché
      ELSE
        v_ok := v_ok + 1;
        v_entrees := v_entrees || jsonb_build_object(r.id::text, v_je::text);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- La sous-transaction est annulée (aucune écriture partielle ne survit) et
      -- l'échec est NOMMÉ : c'est exactement ce que le `try/catch` du front
      -- avalait.
      v_echecs := v_echecs || jsonb_build_object(
        'asset_id', r.id::text, 'asset', r.nom, 'message', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'exercice', v_fy.code,
    'total', v_total,
    'comptabilisees', v_ok,
    'sans_objet', v_rien,
    'echecs', v_echecs,
    'entrees', v_entrees);
END $$;

COMMENT ON FUNCTION public.generate_depreciation_entries(uuid) IS
  'IMMO-02/05 — dotation de toutes les immobilisations actives d''un exercice : rend un verdict PAR immobilisation (comptabilisees, sans_objet, echecs nommés). Remplace le lot du front qui sautait les échecs en silence.';

REVOKE ALL ON FUNCTION public.generate_depreciation_entries(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_depreciation_entries(uuid) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 4. UN SEUL CALCUL D'HEURES SUPPLÉMENTAIRES (RH-04)
--    Le seuil est l'HORAIRE PRÉVU (104 : `overtime_minutes`), la majoration est
--    un PARAMÈTRE, le taux horaire est celui de la 256 (`payroll_hourly_rate`).
--    Il n'existe plus qu'un endroit qui multiplie des heures par un taux.
-- ─────────────────────────────────────────────────────────────
-- LE taux de majoration d'une société : la première tranche si elle en a
-- configuré, sinon le paramètre MAJORATION_HEURES_SUP, sinon 25 %.
CREATE OR REPLACE FUNCTION public.overtime_majoration(p_tenant uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_mult numeric;
BEGIN
  SELECT ot.rate_multiplier INTO v_mult
  FROM overtime_tiers ot
  WHERE ot.tenant_id = p_tenant
  ORDER BY ot.from_hour
  LIMIT 1;

  RETURN COALESCE(
    v_mult,
    NULLIF(get_legal_parameter('MAJORATION_HEURES_SUP', 'FR', CURRENT_DATE, p_tenant), 0),
    1.25);
END $$;

COMMENT ON FUNCTION public.overtime_majoration(uuid) IS
  'RH-04 — la majoration des heures supplémentaires d''une société : première tranche d''overtime_tiers, sinon paramètre MAJORATION_HEURES_SUP. Aucun littéral dans les chemins de paie.';

CREATE OR REPLACE FUNCTION public.payroll_overtime_amount(
  p_tenant uuid,
  p_employee_id uuid,
  p_hours numeric
)
RETURNS TABLE(unit_price numeric, amount numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_taux numeric;
BEGIN
  IF COALESCE(p_hours, 0) <= 0 THEN
    RETURN QUERY SELECT 0::numeric, 0::numeric;
    RETURN;
  END IF;

  v_taux := round(payroll_hourly_rate(p_tenant, p_employee_id) * overtime_majoration(p_tenant), 4);

  unit_price := v_taux;
  amount := round(p_hours * v_taux, 2);
  RETURN NEXT;
END $$;

COMMENT ON FUNCTION public.payroll_overtime_amount(uuid, uuid, numeric) IS
  'RH-04 — LE calcul des heures supplémentaires : taux horaire de la société (payroll_hourly_rate) × majoration (première tranche d''overtime_tiers, sinon paramètre MAJORATION_HEURES_SUP). Le seuil, lui, vient de l''horaire prévu.';

-- La porte du front : elle ne calcule rien, elle rend ce que la base applique.
CREATE OR REPLACE FUNCTION public.payroll_overtime_preview(
  p_employee_id uuid,
  p_hours numeric
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_taux numeric := 0;
  v_montant numeric := 0;
  v_source text;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Heures supplémentaires : aucune société active' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT a.unit_price, a.amount INTO v_taux, v_montant
  FROM payroll_overtime_amount(v_tid, p_employee_id, p_hours) a;

  SELECT CASE WHEN EXISTS (SELECT 1 FROM overtime_tiers ot WHERE ot.tenant_id = v_tid)
              THEN 'tranches' ELSE 'parametre' END INTO v_source;

  RETURN jsonb_build_object(
    'heures', COALESCE(p_hours, 0),
    'taux_horaire_majore', COALESCE(v_taux, 0),
    'montant', COALESCE(v_montant, 0),
    'source', v_source);
END $$;

COMMENT ON FUNCTION public.payroll_overtime_preview(uuid, numeric) IS
  'RH-04 — ce que la base applique à N heures supplémentaires pour un salarié de la société active (taux majoré, montant, origine du taux). L''écran LIT ce chiffre ; il ne le calcule plus.';

-- La majoration de la société active, pour les écrans qui SIMULENT un bulletin
-- (le simulateur ne peut pas lire un paramètre légal tout seul, et il ne doit
-- pas porter une constante légale en dur).
CREATE OR REPLACE FUNCTION public.payroll_overtime_majoration()
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Majoration des heures supplémentaires : aucune société active' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN overtime_majoration(v_tid);
END $$;

COMMENT ON FUNCTION public.payroll_overtime_majoration() IS
  'RH-04 — la majoration des heures supplémentaires de la société active, lue par les écrans de simulation (aucune constante légale côté front).';

-- ── Droits : deux RPC (société ACTIVE), et trois fonctions INTERNES ──
-- `overtime_majoration`, `depreciation_coefficient` et `payroll_overtime_amount`
-- prennent une société en paramètre : elles s'appellent depuis les fonctions
-- SECURITY DEFINER (déclencheurs, moteur d'amortissement), jamais depuis le
-- client. Même règle et même geste que le socle des diviseurs (256) : ne pas
-- les exposer, sinon `check_tenant_guard` a raison de refuser un identifiant de
-- société venu du client.
REVOKE ALL ON FUNCTION public.depreciation_coefficient(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.overtime_majoration(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.payroll_overtime_amount(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;

-- Les deux seules RPC : elles prennent la société de `current_tenant_id()`.
REVOKE ALL ON FUNCTION public.payroll_overtime_preview(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payroll_overtime_preview(uuid, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.payroll_overtime_majoration() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payroll_overtime_majoration() TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 5. Le déclencheur du pointage pose le MONTANT (RH-04)
--    La version de la 256 écrivait les heures supplémentaires avec
--    `unit_price = 0, amount = 0` : la paie comptait des heures qui ne valaient
--    rien. Le seuil reste `overtime_minutes` (l'horaire prévu) ; le montant
--    vient de `payroll_overtime_amount` — la seule multiplication du dépôt.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sync_timesheet_to_payroll()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_period text;
  v_pay_run_id uuid;
  v_overtime_hours numeric;
  v_taux numeric := 0;
  v_montant numeric := 0;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'approved' THEN
    IF NEW.employee_id IS NULL THEN RETURN NEW; END IF;

    -- RH-03 : une seule exécution par pointage à la fois. Un verrou
    -- consultatif évite la course entre deux approbations simultanées, sans
    -- index unique sur des données historiques déjà dupliquées.
    PERFORM pg_advisory_xact_lock(hashtext('sync_timesheet_to_payroll:' || NEW.id::text));

    v_period := to_char(NEW.date, 'YYYY-MM');

    SELECT id INTO v_pay_run_id FROM pay_runs
      WHERE tenant_id = NEW.tenant_id AND to_char(period_start, 'YYYY-MM') = v_period
        AND status IN ('draft', 'processing')
      ORDER BY created_at DESC LIMIT 1;

    -- RH-04 : les heures supplémentaires sont celles que le pointage a mesurées
    -- sur l'horaire prévu. Un seul seuil, celui de la 104.
    v_overtime_hours := ROUND(COALESCE(NEW.overtime_minutes, 0) / 60.0, 2);
    IF v_overtime_hours > 0 THEN
      SELECT a.unit_price, a.amount INTO v_taux, v_montant
      FROM payroll_overtime_amount(NEW.tenant_id, NEW.employee_id, v_overtime_hours) a;
    END IF;

    -- Heures travaillées du jour (ligne d'information, montant nul)
    IF EXISTS (SELECT 1 FROM payroll_variable_elements
               WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
                 AND element_type = 'timesheet_hours') THEN
      UPDATE payroll_variable_elements
         SET quantity = NEW.hours,
             pay_run_id = COALESCE(v_pay_run_id, pay_run_id),
             period = v_period,
             description = 'Heures ' || to_char(NEW.date, 'DD/MM')
       WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
         AND element_type = 'timesheet_hours'
         AND COALESCE(integrated, false) = false;
    ELSE
      INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period,
        element_type, description, quantity, unit_price, amount, source, source_id, integrated)
      VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period,
        'timesheet_hours', 'Heures ' || to_char(NEW.date, 'DD/MM'), NEW.hours, 0, 0, 'timesheet', NEW.id, false)
      ON CONFLICT DO NOTHING;
    END IF;

    -- Heures supplémentaires du jour : quantité ET montant (jamais 0)
    IF v_overtime_hours > 0 THEN
      IF EXISTS (SELECT 1 FROM payroll_variable_elements
                 WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
                   AND element_type = 'overtime') THEN
        UPDATE payroll_variable_elements
           SET quantity = v_overtime_hours,
               unit_price = v_taux,
               amount = v_montant,
               pay_run_id = COALESCE(v_pay_run_id, pay_run_id),
               period = v_period,
               description = 'Heures supp ' || to_char(NEW.date, 'DD/MM')
         WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
           AND element_type = 'overtime'
           AND COALESCE(integrated, false) = false;
      ELSE
        INSERT INTO payroll_variable_elements (tenant_id, employee_id, pay_run_id, period,
          element_type, description, quantity, unit_price, amount, source, source_id, integrated)
        VALUES (NEW.tenant_id, NEW.employee_id, v_pay_run_id, v_period,
          'overtime', 'Heures supp ' || to_char(NEW.date, 'DD/MM'), v_overtime_hours, v_taux, v_montant,
          'timesheet', NEW.id, false)
      ON CONFLICT DO NOTHING;
      END IF;
    ELSE
      -- Le pointage corrigé ne porte plus d'heure supplémentaire : la ligne
      -- non encore intégrée disparaît, celle d'un bulletin calculé reste.
      DELETE FROM payroll_variable_elements
       WHERE tenant_id = NEW.tenant_id AND source_id = NEW.id
         AND element_type = 'overtime'
         AND COALESCE(integrated, false) = false;
    END IF;
  END IF;

  RETURN NEW;
END $function$;

REVOKE ALL ON FUNCTION public.sync_timesheet_to_payroll() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_timesheet_to_payroll() TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────
-- 6. Le second moteur d'amortissement est SUPPRIMÉ (IMMO-01)
--    `calculate_depreciation(uuid, text)` (88/152/158) recalculait la VNC avec
--    `floor(jours / 365,25)` et n'était appelée que par le front. Aucune
--    fonction du schéma ne l'appelle plus : la variante à six arguments qui
--    vivait dans la 124 n'a jamais existé dans le socle déployé (elle était
--    remplacée par la 211/226 avant sa mise en service). Le test T08 le
--    constate par `to_regprocedure`.
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.calculate_depreciation(uuid, text);
DROP FUNCTION IF EXISTS public.calculate_depreciation(uuid, numeric, integer, text, date, date);

-- ─────────────────────────────────────────────────────────────
-- 7. Ce que cette migration NE fait pas (dit, pour ne pas le croire fait)
--    * Côté FRONT, le calcul d'heures supplémentaires de `importTimesheetElements`
--      et le lot `calculateAllDepreciation` sont retirés dans le même commit ;
--      le contrôle statique `src/lib/__tests__/single-engine.test.ts` vérifie
--      qu'aucun fichier de `src/` ne les réintroduit.
--    * `units_of_production` n'est pas implémentée : elle est refusée. La fiche
--      ne porte aucun compteur d'unités produites — l'ajouter est un chantier,
--      pas un raccourci.
--    * Les coefficients dégressifs et la majoration des heures supplémentaires
--      sont français et semés globalement : la localisation (`D-11`) les fera
--      varier par pays, la table et la précédence sont déjà en place.
--    * `calculate_overtime_pay` (le calcul par TRANCHES, avec l'exonération
--      annuelle de 7 500 €) survit, mais il n'a plus AUCUN appelant (mesuré :
--      0 fonction et 0 fichier de `src/` le citent). Le chemin de paie applique
--      le taux de la première tranche (`overtime_majoration`). Conséquence dite :
--      les bandes supérieures et l'exonération ne sont PAS appliquées par la
--      paie — c'est un point ouvert (phase 6), pas un résultat de W5.
--    * Le simulateur (`src/lib/payroll.ts`) garde une valeur de REPLI documentée
--      (1,25) pour ses appels hors société ; l'écran, lui, lit la majoration
--      réelle de la société (`payroll_overtime_majoration`).
-- ─────────────────────────────────────────────────────────────
