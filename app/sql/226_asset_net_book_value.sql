-- ============================================================
-- 226_asset_net_book_value.sql — la VNC de l'historique ignorait la résiduelle (R-01)
--
-- `generate_depreciation_entry` (211) amortit correctement la base amortissable
-- (valeur d'acquisition − valeur résiduelle), mais inscrivait à l'historique
-- `asset_depreciations.net_book_value = base − cumul` : la valeur résiduelle en
-- était retranchée une seconde fois. La fiche de l'immobilisation, elle, porte
-- `current_value = valeur d'acquisition − cumul`, ce qui est juste. Les deux
-- chiffres se contredisaient dès qu'une résiduelle était saisie.
--
-- Mesuré : immobilisation 12 000, résiduelle 2 000, 5 ans → dotation 2 000
-- (juste), VNC de l'historique 8 000, valeur de la fiche 10 000.
--
-- La VNC est la valeur d'acquisition moins les amortissements pratiqués : c'est
-- la définition, et c'est celle de la fiche. Les lignes déjà écrites sont
-- reprises.
--
-- Scénarios : sql/226_asset_net_book_value_tests.sql (A08, A09).
-- ============================================================

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
  -- 226 : la VNC est la valeur d'ACQUISITION moins le cumul — la valeur
  -- résiduelle est déjà hors de la base amortissable, la retrancher ici en
  -- ferait une seconde déduction et contredirait `fixed_assets.current_value`.
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
GRANT EXECUTE ON FUNCTION public.generate_depreciation_entry(uuid, uuid) TO authenticated;

-- ------------------------------------------------------------
-- Reprise des lignes déjà écrites avec la résiduelle retranchée deux fois
-- ------------------------------------------------------------
UPDATE asset_depreciations ad
SET net_book_value = round(GREATEST(COALESCE(fa.purchase_value, 0) - COALESCE(ad.cumulative_amount, 0), 0), 2)
FROM fixed_assets fa
WHERE fa.id = ad.asset_id AND fa.tenant_id = ad.tenant_id
  AND COALESCE(fa.residual_value, 0) > 0
  AND ad.net_book_value IS DISTINCT FROM
      round(GREATEST(COALESCE(fa.purchase_value, 0) - COALESCE(ad.cumulative_amount, 0), 0), 2);
