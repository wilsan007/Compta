-- ============================================================
-- 380_pack_model_tests.sql — LOT 1-A : le modèle de données du pack
--
--   T01  les 17 colonnes du modèle existent sur legislation_packs ;
--   T02  un référentiel par norme comptable (level='referential',
--        country_code NULL, parent NULL) ;
--   T03  chaque pack pays/secteur est raccroché à SON référentiel (même norme) ;
--   T04  LOC1-48 : SYSCOHADA n'est plus un pays ('CI') mais le référentiel,
--        et 'CI' n'a plus qu'un pack pays ;
--   T05  les deux CHECK tiennent : un secteur sans parent est refusé, et un
--        référentiel portant un country_code est refusé ;
--   T06  REJOUABLE : rejouer la partie DONNÉES de la 380 est un no-op.
--
-- Vu ROUGE avant la 380 : T01 (colonnes absentes), T02/T03 (aucun référentiel,
-- aucun parent), T04 (SYSCOHADA était un pays 'CI'). T05 était sans objet (les
-- contraintes n'existaient pas) et T06 sans objet (rien à rejouer) : la suite
-- n'aurait pas pu être verte par accident.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '380', false);
DELETE FROM _audit_results WHERE file = '380';

-- ─────────────────────────────────────────────────────────────
-- T01 — les colonnes du modèle existent
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_manque text;
BEGIN
  SELECT string_agg(c, ', ' ORDER BY c) INTO v_manque FROM (
    SELECT c FROM unnest(ARRAY[
      'level','parent_code','sector','version','status','published_at','validated_by',
      'price_decimals','quantity_decimals','rounding_mode','rounding_level','number_system',
      'ui_languages','document_languages','week_start','weekend_days','source_ref']) AS c
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'legislation_packs' AND column_name = c)
  ) m;

  PERFORM _rec('T01', 'les 17 colonnes du modèle de pack existent sur legislation_packs',
    v_manque IS NULL,
    COALESCE('colonnes absentes : ' || v_manque, 'les 17 colonnes sont présentes'));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'les 17 colonnes du modèle de pack existent sur legislation_packs', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T02 — un référentiel par norme comptable, et rien d'autre
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_normes int; v_refs int; v_ref_taches int;
BEGIN
  SELECT count(DISTINCT accounting_standard) INTO v_normes
    FROM legislation_packs WHERE level = 'country';
  SELECT count(*) INTO v_refs FROM legislation_packs WHERE level = 'referential';
  SELECT count(*) INTO v_ref_taches
    FROM legislation_packs WHERE level = 'referential'
     AND (country_code IS NOT NULL OR parent_code IS NOT NULL);

  PERFORM _rec('T02', 'un référentiel par norme comptable, sans country_code ni parent',
    v_refs = v_normes AND v_ref_taches = 0 AND v_normes > 0,
    format('normes=%s référentiels=%s référentiels « tachés »=%s', v_normes, v_refs, v_ref_taches));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'un référentiel par norme comptable, sans country_code ni parent', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — chaque pack pays/secteur est raccroché à SON référentiel
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_orphelins int; v_mal_raccroches int; v_exemple text;
BEGIN
  SELECT count(*) INTO v_orphelins
    FROM legislation_packs WHERE level IN ('country','sector') AND parent_code IS NULL;

  SELECT count(*), min(p.code) INTO v_mal_raccroches, v_exemple
    FROM legislation_packs p
   WHERE p.level IN ('country','sector')
     AND NOT EXISTS (
       SELECT 1 FROM legislation_packs r
        WHERE r.code = p.parent_code
          AND r.level = 'referential'
          AND r.accounting_standard = p.accounting_standard);

  PERFORM _rec('T03', 'chaque pack pays/secteur est raccroché à un référentiel de SA norme',
    v_orphelins = 0 AND v_mal_raccroches = 0,
    format('sans parent=%s mal raccrochés=%s%s', v_orphelins, v_mal_raccroches,
           CASE WHEN v_exemple IS NULL THEN '' ELSE ' (ex. ' || v_exemple || ')' END));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'chaque pack pays/secteur est raccroché à un référentiel de SA norme', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — LOC1-48 : le doublon 'CI' est tranché
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_ci_pays int; v_sysco_level text; v_sysco_pays text;
BEGIN
  SELECT count(*) INTO v_ci_pays
    FROM legislation_packs WHERE level = 'country' AND country_code = 'CI';
  SELECT level, country_code INTO v_sysco_level, v_sysco_pays
    FROM legislation_packs WHERE code = 'SYSCOHADA';

  PERFORM _rec('T04', 'LOC1-48 : SYSCOHADA est le référentiel (sans country_code), CI n''a plus qu''un pack pays',
    v_sysco_level = 'referential' AND v_sysco_pays IS NULL AND v_ci_pays = 1,
    format('SYSCOHADA niveau=%s country_code=%s | packs pays CI=%s (1 attendu)',
           COALESCE(v_sysco_level, 'NULL'), COALESCE(v_sysco_pays, 'NULL'), v_ci_pays));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'LOC1-48 : SYSCOHADA est le référentiel (sans country_code), CI n''a plus qu''un pack pays', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — les deux CHECK tiennent
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_secteur_refuse boolean := false; v_ref_pays_refuse boolean := false;
BEGIN
  BEGIN  -- (a) secteur SANS parent → hierarchy_chk
    INSERT INTO legislation_packs
      (code, name, country_code, country_name, accounting_standard, currency, tenant_id, level, parent_code)
    VALUES ('ZZTEST-SEC', 'test secteur', 'FR', 'test', 'PCG', 'EUR',
            '00000000-0000-0000-0000-000000000001', 'sector', NULL);
  EXCEPTION WHEN check_violation THEN v_secteur_refuse := true;
  END;

  BEGIN  -- (b) référentiel avec country_code → country_chk
    INSERT INTO legislation_packs
      (code, name, country_code, country_name, accounting_standard, currency, tenant_id, level, parent_code)
    VALUES ('ZZTEST-REF', 'test référentiel', 'FR', 'test', 'PCG', 'EUR',
            '00000000-0000-0000-0000-000000000001', 'referential', NULL);
  EXCEPTION WHEN check_violation THEN v_ref_pays_refuse := true;
  END;

  DELETE FROM legislation_packs WHERE code IN ('ZZTEST-SEC', 'ZZTEST-REF');

  PERFORM _rec('T05', 'les CHECK tiennent : secteur sans parent refusé, référentiel avec country_code refusé',
    v_secteur_refuse AND v_ref_pays_refuse,
    format('secteur sans parent refusé=%s | référentiel avec country_code refusé=%s',
           v_secteur_refuse, v_ref_pays_refuse));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'les CHECK tiennent : secteur sans parent refusé, référentiel avec country_code refusé', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — rejouable : la partie DONNÉES de la 380 est un no-op
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_refs_avant int; v_refs_apres int; v_ins int; v_upd int;
BEGIN
  SELECT count(*) INTO v_refs_avant FROM legislation_packs WHERE level = 'referential';

  WITH normes AS (
    SELECT DISTINCT ON (accounting_standard)
           accounting_standard, currency, currency_decimals, date_format, locale,
           fiscal_year_start, tax_id_label, tax_id_secondary_label, tenant_id
      FROM legislation_packs
     WHERE level = 'country' AND accounting_standard IS NOT NULL AND accounting_standard <> 'SYSCOHADA'
     ORDER BY accounting_standard, code)
  INSERT INTO legislation_packs
    (code, name, country_code, country_name, accounting_standard, currency, currency_decimals,
     date_format, locale, fiscal_year_start, tax_id_label, tax_id_secondary_label, is_default,
     active, tenant_id, level, parent_code)
  SELECT n.accounting_standard, n.accounting_standard || ' — référentiel comptable', NULL,
         n.accounting_standard || ' — référentiel comptable', n.accounting_standard,
         n.currency, n.currency_decimals, n.date_format, n.locale, n.fiscal_year_start,
         n.tax_id_label, n.tax_id_secondary_label, false, true, n.tenant_id, 'referential', NULL
    FROM normes n
   WHERE NOT EXISTS (SELECT 1 FROM legislation_packs r WHERE r.code = n.accounting_standard)
  ON CONFLICT (code) DO NOTHING;
  GET DIAGNOSTICS v_ins = ROW_COUNT;

  WITH upd AS (
    UPDATE legislation_packs p SET parent_code = p.accounting_standard
     WHERE p.level IN ('country','sector') AND p.parent_code IS NULL
       AND p.accounting_standard IS NOT NULL
       AND EXISTS (SELECT 1 FROM legislation_packs r
                    WHERE r.code = p.accounting_standard AND r.level = 'referential')
     RETURNING 1)
  SELECT count(*) INTO v_upd FROM upd;

  SELECT count(*) INTO v_refs_apres FROM legislation_packs WHERE level = 'referential';

  PERFORM _rec('T06', 'rejouable : rejouer les données de la 380 n''ajoute ni ne modifie aucune ligne',
    v_ins = 0 AND v_upd = 0 AND v_refs_avant = v_refs_apres,
    format('référentiels %s→%s | lignes insérées=%s | lignes modifiées=%s',
           v_refs_avant, v_refs_apres, v_ins, v_upd));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'rejouable : rejouer les données de la 380 n''ajoute ni ne modifie aucune ligne', false, SQLERRM);
END $$;

SELECT _audit_assert('380');
