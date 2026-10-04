-- ============================================================
-- 211_asset_deferred_entries.sql — R-01 (phase 1 du reste-à-faire du 22/09)
--
-- Trois fonctions dataient d'avant le noyau strict (187) :
--   * `generate_depreciation_entry` (152)   — en-tête inséré en `posted`
--   * `generate_residual_entry` (187)       — en-tête en `posted`, ligne unique (écriture déséquilibrée)
--   * `post_deferred_charge` (124/152)      — en-tête en `posted`, comptes fictifs `6_____` / `7_____`
-- Depuis la 187, insérer une écriture en `posted` lève « Une écriture est créée
-- en brouillard puis validée après ses lignes » : les trois appels échouaient.
--
-- Règle appliquée ici, la même que partout ailleurs :
--   1. en-tête en `draft`, lignes, puis bascule en `posted` (les triggers de
--      validation — équilibre, période, comptes du plan, permission — s'appliquent) ;
--   2. aucun compte fictif : les comptes viennent de l'immobilisation, de
--      l'écran de régularisation ou du plan comptable, et sont refusés s'ils
--      sont absents du plan ;
--   3. idempotence : une référence `AMORT:` / `ECART:` / `DEFER:` permet de
--      reconnaître une écriture déjà passée et de refuser (ou rendre) le doublon.
--
-- Scénarios : sql/211_asset_deferred_tests.sql.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Dotation aux amortissements
--    D 681x (dotation) / C 28x (amortissement cumulé)
--    Linéaire, prorata temporis en jours la première année, plafonné à la
--    base amortissable (valeur d'acquisition − valeur résiduelle).
-- ------------------------------------------------------------
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
  v_base numeric;
  v_annuel numeric;
  v_amount numeric;
  v_cumul numeric;
  v_total numeric;
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

  -- Idempotence : une dotation déjà comptabilisée est rendue telle quelle
  v_ref := 'AMORT:' || v_fa.id || ':' || v_fy.code;
  SELECT id INTO v_existe FROM journal_entries
  WHERE tenant_id = v_tid AND reference = v_ref LIMIT 1;
  IF v_existe IS NOT NULL THEN RETURN v_existe; END IF;

  IF v_fa.status <> 'active' THEN
    RAISE EXCEPTION 'Immobilisation % : statut % — aucune dotation à comptabiliser', v_fa.name, v_fa.status
      USING ERRCODE = 'check_violation';
  END IF;

  v_base := GREATEST(COALESCE(v_fa.purchase_value, 0) - COALESCE(v_fa.residual_value, 0), 0);
  IF v_base = 0 OR COALESCE(v_fa.useful_life_years, 0) <= 0 THEN
    RETURN NULL;  -- rien à amortir
  END IF;
-- Amortissements déjà dotés (l'historique fait foi, pas la valeur courante)
  SELECT COALESCE(sum(amount), 0) INTO v_cumul FROM asset_depreciations
  WHERE tenant_id = v_tid AND asset_id = v_fa.id AND depreciation_type = 'dotation';
  v_cumul := LEAST(v_cumul, v_base);

  v_annuel := round(v_base / v_fa.useful_life_years, 2);
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
          'Dotation aux amortissements ' || v_fy.code || ' - ' || v_fa.name, v_ref, v_number)
  RETURNING id INTO v_je;

  -- 2. lignes
  INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
  VALUES
    (v_tid, v_je, v_debit,  'Dotations aux amortissements', v_amount, 0, 'Dotation ' || v_fy.code),
    (v_tid, v_je, v_credit, 'Amortissements', 0, v_amount, 'Dotation ' || v_fy.code);

  -- 3. validation : les triggers de la 187 vérifient équilibre, exercice, comptes
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  -- Historique de l'immobilisation + valeur nette
  v_total := v_cumul + v_amount;
  INSERT INTO asset_depreciations (tenant_id, asset_id, fiscal_year_code, period, depreciation_type,
    amount, cumulative_amount, net_book_value, entry_number)
  VALUES (v_tid, v_fa.id, v_fy.code, 12, 'dotation', v_amount, v_total, round(v_base - v_total, 2), v_number);

  UPDATE fixed_assets
  SET current_value = GREATEST(COALESCE(purchase_value, 0) - v_total, 0),
      status = CASE WHEN v_total >= v_base THEN 'fully_depreciated' ELSE status END,
      updated_at = now()
  WHERE id = v_fa.id AND tenant_id = v_tid;

  RETURN v_je;
END $$;

REVOKE ALL ON FUNCTION public.generate_depreciation_entry(uuid, uuid) FROM PUBLIC, anon;
-- ------------------------------------------------------------
-- 2. Écart de lettrage
--    Écriture équilibrée : la charge (ou le produit) d'écart ET la
--    contrepartie sur le compte de tiers du groupe lettré.
--      escompte / perte de change / créance irrécouvrable → D 665/666/654, C tiers
--      gain de change                                      → D tiers, C 766
--    L'ancienne version n'écrivait qu'une seule ligne : l'écriture était
--    déséquilibrée, donc refusée par le noyau strict dès qu'elle était validée.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_residual_entry(
  p_group_id uuid,
  p_residual_type text,
  p_amount numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_group lettrage_groups%ROWTYPE;
  v_compte text;
  v_tiers text;
  v_ref text;
  v_number text;
  v_je uuid;
  v_existe uuid;
  v_perte boolean;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_group FROM lettrage_groups WHERE id = p_group_id AND tenant_id = v_tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Groupe de lettrage introuvable : %', p_group_id; END IF;

  v_compte := CASE p_residual_type
    WHEN 'escompte' THEN '665000'
    WHEN 'perte_change' THEN '666000'
    WHEN 'gain_change' THEN '766000'
    WHEN 'creance_irrecouvrable' THEN '654000'
  END;
  IF v_compte IS NULL THEN
    RAISE EXCEPTION 'Type d''écart inconnu : %', p_residual_type USING ERRCODE = 'check_violation';
  END IF;

  IF COALESCE(p_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Montant d''écart invalide : %', p_amount USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotence : un écart déjà comptabilisé ne se double pas
  v_ref := 'ECART:' || v_group.id;
  SELECT id INTO v_existe FROM journal_entries WHERE tenant_id = v_tid AND reference = v_ref LIMIT 1;
  IF v_existe IS NOT NULL THEN
    RAISE EXCEPTION 'L''écart du lettrage % est déjà comptabilisé (écriture %)', v_group.lettrage_code,
      (SELECT COALESCE(posting_number, number) FROM journal_entries WHERE id = v_existe)
      USING ERRCODE = 'unique_violation';
  END IF;

  -- Contrepartie : le compte de tiers des lignes lettrées du groupe
  SELECT COALESCE(jl.account_general, jl.account_code) INTO v_tiers
  FROM journal_lines jl
  WHERE jl.tenant_id = v_tid AND jl.lettrage_group_id = v_group.id
  GROUP BY 1
  ORDER BY count(*) DESC, 1
  LIMIT 1;
  IF v_tiers IS NULL THEN
    RAISE EXCEPTION 'Écart du lettrage % : aucune ligne rattachée, contrepartie inconnue', v_group.lettrage_code
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_compte) THEN
    RAISE EXCEPTION 'Compte d''écart % absent du plan comptable de la société', v_compte
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_tiers) THEN
    RAISE EXCEPTION 'Compte de tiers % absent du plan comptable de la société', v_tiers
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_perte := p_residual_type <> 'gain_change';
  v_number := 'ECART-' || v_group.lettrage_code;

  -- 1. en-tête en brouillard
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_tid, v_number, CURRENT_DATE, 'OD', 'draft',
          'Écart de règlement ' || p_residual_type || ' - ' || v_group.lettrage_code, v_ref, v_number)
  RETURNING id INTO v_je;

  -- 2. lignes équilibrées
  IF v_perte THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_compte, 'Écart de règlement ' || p_residual_type, p_amount, 0, v_group.lettrage_code),
           (v_tid, v_je, v_tiers,  'Écart de règlement ' || v_group.lettrage_code, 0, p_amount, v_group.lettrage_code);
  ELSE
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_tiers,  'Écart de règlement ' || v_group.lettrage_code, p_amount, 0, v_group.lettrage_code),
           (v_tid, v_je, v_compte, 'Écart de règlement ' || p_residual_type, 0, p_amount, v_group.lettrage_code);
  END IF;

  -- 3. validation
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  UPDATE lettrage_groups
  SET residual_amount = p_amount, residual_type = p_residual_type, status = 'closed'
  WHERE id = v_group.id AND tenant_id = v_tid;

  -- Traces d'écart de lettrage, quand l'écran en a créé
  UPDATE lettrage_differences
  SET difference_account = v_compte, generated_entry_id = v_je, status = 'posted'
  WHERE tenant_id = v_tid AND lettrage_code = v_group.lettrage_code;

  RETURN v_je;
END $$;

REVOKE ALL ON FUNCTION public.generate_residual_entry(uuid, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_residual_entry(uuid, text, numeric) TO authenticated;

-- ------------------------------------------------------------
-- 3. Charges (CCA) et produits (PCA) constatés d'avance
--    Le compte de charge/produit vient de la régularisation
--    (`regularization_entries.account_code`, saisi par l'écran) : plus de
--    `6_____` / `7_____` fictifs, qui faisaient échouer la validation.
--      CCA : initiale  D 486 / C charge    puis reprises D charge / C 486
--      PCA : initiale  D produit / C 487   puis reprises D 487 / C produit
--    L'identifiant attendu est celui de `regularization_entries` (ce que
--    l'écran transmet) : l'ancienne version cherchait dans `journal_entries`
--    et levait « Écriture non trouvée ».
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.post_deferred_charge(uuid, text, numeric, integer);

CREATE OR REPLACE FUNCTION public.post_deferred_charge(
  p_regularization_id uuid,
  p_type text DEFAULT NULL,
  p_amount numeric DEFAULT NULL,
  p_months integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_tid uuid := current_tenant_id();
  v_reg regularization_entries%ROWTYPE;
  v_type text;
  v_montant numeric;
  v_mois int;
  v_attente text;
  v_compte text;
  v_ref text;
  v_number text;
  v_date date;
  v_part numeric;
  v_je uuid;
  v_initiale uuid;
  v_entries jsonb := '[]'::jsonb;
  i int;
BEGIN
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Aucun tenant actif';
  END IF;

  SELECT * INTO v_reg FROM regularization_entries WHERE id = p_regularization_id AND tenant_id = v_tid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Régularisation introuvable : %', p_regularization_id;
  END IF;

  v_type := lower(btrim(COALESCE(NULLIF(p_type, ''), v_reg.type)));
  IF v_type NOT IN ('cca', 'pca') THEN
    RAISE EXCEPTION 'Type de report inconnu : % (attendu cca ou pca)', COALESCE(p_type, v_reg.type)
      USING ERRCODE = 'check_violation';
  END IF;

  v_montant := round(COALESCE(NULLIF(p_amount, 0), NULLIF(v_reg.remaining_amount, 0), v_reg.amount, 0), 2);
  IF v_montant <= 0 THEN
    RAISE EXCEPTION 'Montant à reporter invalide pour la régularisation % : %', v_reg.id, v_montant
      USING ERRCODE = 'check_violation';
  END IF;

  -- Idempotence : un report déjà passé ne se double pas
  v_ref := 'DEFER:' || v_reg.id;
  IF EXISTS (SELECT 1 FROM journal_entries WHERE tenant_id = v_tid AND reference = v_ref || ':0') THEN
    RAISE EXCEPTION 'La régularisation % a déjà été reportée en charge/produit constaté d''avance',
      COALESCE(v_reg.description, v_reg.id::text)
      USING ERRCODE = 'unique_violation';
  END IF;

  v_compte := btrim(v_reg.account_code);
  v_attente := CASE WHEN v_type = 'cca' THEN '486000' ELSE '487000' END;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_compte) THEN
    RAISE EXCEPTION 'Compte % absent du plan comptable de la société', v_compte
      USING ERRCODE = 'foreign_key_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM chart_accounts WHERE tenant_id = v_tid AND code = v_attente) THEN
    RAISE EXCEPTION 'Compte d''attente % absent du plan comptable de la société', v_attente
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  v_mois := COALESCE(NULLIF(p_months, 0),
    GREATEST(1, (date_part('year', age(v_reg.end_date, v_reg.start_date)) * 12
               + date_part('month', age(v_reg.end_date, v_reg.start_date)))::int));
  v_mois := LEAST(v_mois, 120);

  -- 1. écriture initiale, à la date de départ de la régularisation
  v_number := 'DEFER-' || left(replace(v_reg.id::text, '-', ''), 8) || '-0';
  INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
  VALUES (v_tid, v_number, v_reg.start_date, 'OD', 'draft',
          upper(v_type) || ' ' || v_reg.description || ' (' || v_mois || ' mois)', v_ref || ':0', v_number)
  RETURNING id INTO v_je;
  v_initiale := v_je;

  IF v_type = 'cca' THEN
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_attente, 'Charges constatées d''avance', v_montant, 0, 'CCA à répartir'),
           (v_tid, v_je, v_compte,  'Charge reportée', 0, v_montant, 'CCA à répartir');
  ELSE
    INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
    VALUES (v_tid, v_je, v_compte,  'Produit reporté', v_montant, 0, 'PCA à répartir'),
           (v_tid, v_je, v_attente, 'Produits constatés d''avance', 0, v_montant, 'PCA à répartir');
  END IF;
  UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

  v_entries := v_entries || jsonb_build_object(
    'entry_id', v_je, 'entry_number', v_number, 'date', v_reg.start_date,
    'amount', v_montant, 'account', v_attente, 'deferred_account', v_attente, 'counterpart', v_compte);

  -- 2. reprises mensuelles, au premier jour de chaque mois suivant ; la
  --    dernière absorbe l'arrondi pour que le total repris soit exact
  FOR i IN 1..v_mois LOOP
    v_date := (date_trunc('month', v_reg.start_date) + make_interval(months => i))::date;
    v_part := CASE WHEN i = v_mois THEN round(v_montant - round(v_montant / v_mois, 2) * (v_mois - 1), 2)
                   ELSE round(v_montant / v_mois, 2) END;
    v_number := 'DEFER-' || left(replace(v_reg.id::text, '-', ''), 8) || '-' || i;

    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status, description, reference, piece_number)
    VALUES (v_tid, v_number, v_date, 'OD', 'draft',
            'Reprise ' || upper(v_type) || ' ' || i || '/' || v_mois || ' - ' || v_reg.description,
            v_ref || ':1', v_number)
    RETURNING id INTO v_je;

    IF v_type = 'cca' THEN
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
      VALUES (v_tid, v_je, v_compte,  'Charge reprise', v_part, 0, 'Reprise CCA ' || i),
             (v_tid, v_je, v_attente, 'Charges constatées d''avance', 0, v_part, 'Reprise CCA ' || i);
    ELSE
      INSERT INTO journal_lines (tenant_id, journal_id, account_code, account_name, debit, credit, description)
      VALUES (v_tid, v_je, v_attente, 'Produits constatés d''avance', v_part, 0, 'Reprise PCA ' || i),
             (v_tid, v_je, v_compte,  'Produit repris', 0, v_part, 'Reprise PCA ' || i);
    END IF;
    UPDATE journal_entries SET status = 'posted' WHERE id = v_je AND tenant_id = v_tid;

    v_entries := v_entries || jsonb_build_object(
      'entry_id', v_je, 'entry_number', v_number, 'date', v_date, 'amount', v_part, 'account', v_compte);
  END LOOP;

  UPDATE regularization_entries
  SET used_amount = v_montant, remaining_amount = 0, status = 'posted',
      created_entry_id = v_initiale, updated_at = now()
  WHERE id = v_reg.id AND tenant_id = v_tid;

  RETURN jsonb_build_object(
    'success', true,
    'regularization_id', v_reg.id,
    'type', v_type,
    'total_amount', v_montant,
    'monthly_amount', round(v_montant / v_mois, 2),
    'months', v_mois,
    'entry_id', v_initiale,
    'entries', v_entries
  );
END $$;

REVOKE ALL ON FUNCTION public.post_deferred_charge(uuid, text, numeric, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_deferred_charge(uuid, text, numeric, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_depreciation_entry(uuid, uuid) TO authenticated;