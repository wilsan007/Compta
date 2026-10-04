-- ============================================================
-- 226_asset_net_book_value_tests.sql — VNC et valeur résiduelle (R-01)
--
-- A08 — première dotation d'une immobilisation à valeur résiduelle : la VNC de
--       l'historique et celle de la fiche disent le même chiffre.
--       Avant la 226 : 8 000 contre 10 000.
-- A09 — au terme du plan, le cumul s'arrête à la base amortissable et la VNC
--       tombe sur la valeur résiduelle, pas sur zéro.
-- A10 — non-régression sans résiduelle : VNC = acquisition − cumul (inchangé).
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '226', false);
DELETE FROM _audit_results WHERE file = '226';

-- Exercice supplémentaire (les reprises de la 211 en créent aussi)
CREATE OR REPLACE FUNCTION _mk_year226(t uuid, p_code text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE fy uuid;
BEGIN
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = p_code;
  IF fy IS NULL THEN
    INSERT INTO fiscal_years (tenant_id, code, start_date, end_date, status)
    VALUES (t, p_code, (p_code || '-01-01')::date, (p_code || '-12-31')::date, 'open')
    RETURNING id INTO fy;
  END IF;
  RETURN fy;
END $$;

-- Immobilisation linéaire acquise au premier jour de l'exercice 2026
CREATE OR REPLACE FUNCTION _mk_asset226(t uuid, p_code text, p_val numeric, p_res numeric, p_years int)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE fa uuid;
BEGIN
  INSERT INTO fixed_assets (tenant_id, name, code, purchase_date, purchase_value, residual_value,
    useful_life_years, depreciation_method, status, current_value)
  VALUES (t, 'Immo ' || p_code, p_code, '2026-01-01', p_val, p_res, p_years, 'linear', 'active', p_val)
  RETURNING id INTO fa;
  RETURN fa;
END $$;

-- A08 — valeur résiduelle 2 000 : historique et fiche d'accord
DO $$
DECLARE t uuid := _mk_tenant('A08'); fa uuid; fy uuid; je uuid; v record; err text := '—';
BEGIN
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
  fa := _mk_asset226(t, 'A08', 12000, 2000, 5);
  PERFORM _as_user();
  BEGIN je := generate_depreciation_entry(fa, fy);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT ad.amount, ad.cumulative_amount, ad.net_book_value, f.current_value
    INTO v FROM asset_depreciations ad JOIN fixed_assets f ON f.id = ad.asset_id AND f.tenant_id = ad.tenant_id
    WHERE ad.asset_id = fa;
  PERFORM _rec('A08', 'immobilisation 12 000 résiduelle 2 000 : dotation 2 000, VNC 10 000 des deux côtés',
    v.amount = 2000 AND v.cumulative_amount = 2000 AND v.net_book_value = 10000 AND v.current_value = 10000,
    format('dotation=%s cumul=%s VNC historique=%s valeur fiche=%s | %s',
           v.amount, v.cumulative_amount, v.net_book_value, v.current_value, left(err, 80)));
END $$;

-- A09 — au terme du plan : cumul plafonné à 10 000, VNC égale à la résiduelle
DO $$
DECLARE t uuid := _mk_tenant('A09'); fa uuid; fy uuid; i int; v record; err text := '—'; n int;
BEGIN
  fa := _mk_asset226(t, 'A09', 12000, 2000, 5);
  PERFORM _as_user();
  BEGIN
    FOR i IN 0..4 LOOP
      fy := _mk_year226(t, (2026 + i)::text);
      PERFORM generate_depreciation_entry(fa, fy);
    END LOOP;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT count(*) INTO n FROM asset_depreciations WHERE asset_id = fa;
  SELECT ad.cumulative_amount, ad.net_book_value, f.current_value, f.status
    INTO v FROM asset_depreciations ad JOIN fixed_assets f ON f.id = ad.asset_id AND f.tenant_id = ad.tenant_id
    WHERE ad.asset_id = fa ORDER BY ad.cumulative_amount DESC LIMIT 1;
  PERFORM _rec('A09', 'plan achevé : cumul 10 000 (base amortissable), VNC 2 000 (la résiduelle), statut amorti',
    n = 5 AND v.cumulative_amount = 10000 AND v.net_book_value = 2000 AND v.current_value = 2000
      AND v.status = 'fully_depreciated',
    format('dotations=%s cumul=%s VNC historique=%s valeur fiche=%s statut=%s | %s',
           n, v.cumulative_amount, v.net_book_value, v.current_value, v.status, left(err, 80)));
END $$;

-- A10 — non-régression : sans résiduelle, rien ne change
DO $$
DECLARE t uuid := _mk_tenant('A10N'); fa uuid; fy uuid; v record; err text := '—';
BEGIN
  SELECT id INTO fy FROM fiscal_years WHERE tenant_id = t AND code = '2026';
  fa := _mk_asset226(t, 'A10N', 12000, 0, 5);
  PERFORM _as_user();
  BEGIN PERFORM generate_depreciation_entry(fa, fy);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM;
  END;
  SELECT ad.amount, ad.net_book_value, f.current_value
    INTO v FROM asset_depreciations ad JOIN fixed_assets f ON f.id = ad.asset_id AND f.tenant_id = ad.tenant_id
    WHERE ad.asset_id = fa;
  PERFORM _rec('A10n', 'sans valeur résiduelle : dotation 2 400 et VNC 9 600 des deux côtés (inchangé)',
    v.amount = 2400 AND v.net_book_value = 9600 AND v.current_value = 9600,
    format('dotation=%s VNC historique=%s valeur fiche=%s | %s',
           v.amount, v.net_book_value, v.current_value, left(err, 80)));
END $$;

DROP FUNCTION _mk_year226(uuid, text);
DROP FUNCTION _mk_asset226(uuid, text, numeric, numeric, int);
SELECT _audit_assert('226');
