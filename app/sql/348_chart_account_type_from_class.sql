-- ════════════════════════════════════════════════════════════════════════════
-- 348 — Partie 2, tâche 2.11 (F2, cpt-004) : le type d'un compte se déduit de
--       sa classe
-- ════════════════════════════════════════════════════════════════════════════
--
-- LE DÉFAUT, MESURÉ. La colonne `chart_accounts.account_type` avait pour valeur
-- par défaut 'asset_current' : tout compte créé sans type précis — un 606800
-- comme un 707000 — s'enregistrait « Actifs courants ». Sur la base de travail :
-- 23 840 comptes de classe 6 et 12 800 de classe 7 classés à l'actif. Les
-- colonnes `racine` et `classe` restaient vides.
--
-- CE QUE FAIT CE FICHIER.
--   1. `chart_account_type_from_code(code)` : le type d'un compte d'après son
--      numéro, selon le plan comptable général (classes 1 à 9, avec les racines
--      qui comptent en classes 1, 4, 5, 6 et 7).
--   2. Un déclencheur : à la création ou quand le numéro change, `classe` et
--      `racine` sont recopiées du numéro ; `account_type` est déduit s'il n'est
--      pas fourni. Un type CHOISI est respecté.
--   3. La valeur par défaut 'asset_current' est retirée.
--   4. Rattrapage : les comptes restés sur la valeur par défaut (ou sans type)
--      reçoivent leur type déduit ; `classe` et `racine` sont renseignées
--      partout. Un compte dont le type a été choisi autrement n'est pas touché.
--
-- CE QU'IL NE FAIT PAS. La colonne `type` (les cinq grandes natures) n'est pas
-- modifiée : l'écran la pose déjà d'après le numéro. La grille est celle du plan
-- comptable FRANÇAIS ; un plan étranger devra fournir ses types (D-11).
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.chart_account_type_from_code(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $fn$
  SELECT CASE
    -- Classe 1 : capitaux, provisions, emprunts
    WHEN c LIKE '12%' THEN 'equity_unaffected'            -- résultat de l'exercice
    WHEN c ~ '^1[0-4]' THEN 'equity'
    WHEN c LIKE '1%' THEN 'liability_non_current'         -- provisions, emprunts et dettes assimilées
    -- Classe 2 : immobilisations
    WHEN c LIKE '2%' THEN 'asset_fixed'
    -- Classe 3 : stocks
    WHEN c LIKE '3%' THEN 'asset_current'
    -- Classe 4 : tiers, selon la racine
    WHEN c LIKE '40%' THEN 'liability_payable'            -- fournisseurs
    WHEN c LIKE '41%' THEN 'asset_receivable'             -- clients
    WHEN c LIKE '4456%' THEN 'asset_current'              -- TVA déductible
    WHEN c LIKE '486%' THEN 'asset_prepayments'           -- charges constatées d'avance
    WHEN c LIKE '49%' THEN 'asset_receivable'             -- dépréciations des comptes de tiers
    WHEN c LIKE '4%' THEN 'liability_current'             -- personnel, organismes sociaux, État, divers
    -- Classe 5 : trésorerie
    WHEN c LIKE '519%' THEN 'liability_current'           -- concours bancaires courants
    WHEN c LIKE '50%' THEN 'asset_current'                -- valeurs mobilières de placement
    WHEN c LIKE '5%' THEN 'asset_cash'
    -- Classe 6 : charges
    WHEN c LIKE '60%' THEN 'expense_direct_cost'          -- achats
    WHEN c LIKE '68%' THEN 'expense_depreciation'         -- dotations
    WHEN c LIKE '67%' THEN 'expense_other'                -- charges exceptionnelles
    WHEN c LIKE '6%' THEN 'expense'
    -- Classe 7 : produits
    WHEN c ~ '^7[5-8]' THEN 'income_other'
    WHEN c LIKE '7%' THEN 'income'
    -- Classes 8 et 9 : comptes spéciaux et analytiques
    WHEN c ~ '^[89]' THEN 'off_balance'
    ELSE NULL
  END
  FROM (SELECT btrim(COALESCE(p_code, '')) AS c) x
$fn$;

COMMENT ON FUNCTION public.chart_account_type_from_code(text) IS
  '348 (F2) — le type d''un compte d''après son numéro, selon les classes du plan comptable général français. Sert de valeur déduite quand aucun type n''est choisi.';

REVOKE ALL ON FUNCTION public.chart_account_type_from_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chart_account_type_from_code(text) TO authenticated, service_role;

ALTER TABLE public.chart_accounts ALTER COLUMN account_type DROP DEFAULT;

CREATE OR REPLACE FUNCTION public.chart_account_derive()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code THEN
    NEW.classe := left(btrim(NEW.code), 1);
    NEW.racine := left(btrim(NEW.code), 3);
  END IF;
  IF btrim(COALESCE(NEW.account_type, '')) = '' THEN
    NEW.account_type := chart_account_type_from_code(NEW.code);
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS a_chart_account_derive ON public.chart_accounts;
CREATE TRIGGER a_chart_account_derive
  BEFORE INSERT OR UPDATE OF code, account_type ON public.chart_accounts
  FOR EACH ROW EXECUTE FUNCTION public.chart_account_derive();

REVOKE ALL ON FUNCTION public.chart_account_derive() FROM PUBLIC, anon, authenticated;

-- ── Rattrapage ────────────────────────────────────────────────────────────
DO $$
DECLARE n_type int; n_cl int;
BEGIN
  UPDATE public.chart_accounts ca
     SET account_type = chart_account_type_from_code(ca.code)
   WHERE (ca.account_type IS NULL OR btrim(ca.account_type) = '' OR ca.account_type = 'asset_current')
     AND chart_account_type_from_code(ca.code) IS NOT NULL
     AND ca.account_type IS DISTINCT FROM chart_account_type_from_code(ca.code);
  GET DIAGNOSTICS n_type = ROW_COUNT;

  UPDATE public.chart_accounts ca
     SET classe = left(btrim(ca.code), 1), racine = left(btrim(ca.code), 3)
   WHERE ca.classe IS DISTINCT FROM left(btrim(ca.code), 1)
      OR ca.racine IS DISTINCT FROM left(btrim(ca.code), 3);
  GET DIAGNOSTICS n_cl = ROW_COUNT;

  RAISE NOTICE '348 : % compte(s) reclassé(s) d''après leur numéro, % compte(s) avec classe et racine renseignées', n_type, n_cl;
END $$;
