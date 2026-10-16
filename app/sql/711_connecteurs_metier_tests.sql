-- ============================================================
-- 711_connecteurs_metier_tests.sql — F.6 / API-03 :
--   UN CONNECTEUR DÉCLARÉ, UNE URL PUBLIQUE, JAMAIS UN SECRET
--
--   T01  RLS FORCÉE sur `business_connectors`
--   T02  un connecteur HTTPS valide s'enregistre
--   T03  refus : une URL en HTTP (non HTTPS) — CONNECTOR_URL_REFUSED
--   T04  refus : une URL vers un hôte LOCAL (garde SSRF du dépôt)
--   T05  refus : un type de connecteur hors vocabulaire (CHECK)
--   T06  refus : un mode d'authentification sans référence de secret (CHECK)
--   T07  refus : deux connecteurs du MÊME nom dans la société (unicité)
--   T08  `anon` n'a aucun droit
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '711', false);
DELETE FROM _audit_results WHERE file = '711';

DO $$
DECLARE v boolean;
BEGIN
  SELECT relforcerowsecurity INTO v FROM pg_class WHERE relname = 'business_connectors';
  PERFORM _rec('T01', 'RLS FORCÉE sur `business_connectors`',
    v IS TRUE, format('relforcerowsecurity = %s', COALESCE(v::text, 'NULL')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée', false, SQLERRM);
END $$;

DO $$
DECLARE privs text;
BEGIN
  SELECT string_agg(DISTINCT privilege_type, ',') INTO privs
    FROM information_schema.role_table_grants
   WHERE grantee = 'anon' AND table_name = 'business_connectors';
  PERFORM _rec('T08', '`anon` n''a AUCUN droit sur les connecteurs',
    privs IS NULL, format('droits d''anon = %s', COALESCE(privs, 'aucun')));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T08', 'anon sans droits', false, SQLERRM);
END $$;

-- T02 → T07 : un décor partagé (un connecteur valide, puis les refus)
DO $$
DECLARE
  ta uuid := _mk_tenant('F711A');
  n int; ok boolean;
BEGIN
  -- T02 — un connecteur HTTPS public valide
  INSERT INTO business_connectors (tenant_id, name, connector_type, base_url, auth_type, auth_ref)
    VALUES (ta, 'Odoo cloud', 'odoo', 'https://erp.exemple.com/api', 'api_key', 'ODOO_API_KEY');
  SELECT count(*) INTO n FROM business_connectors WHERE tenant_id = ta;
  PERFORM _rec('T02', 'un connecteur HTTPS valide s''enregistre (et le secret n''est qu''un NOM)',
    n = 1, format('connecteurs = %s (attendu 1)', n));

  -- T03 — HTTP (non HTTPS)
  ok := false;
  BEGIN
    INSERT INTO business_connectors (tenant_id, name, connector_type, base_url)
      VALUES (ta, 'En clair', 'rest', 'http://api.exemple.com');
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%CONNECTOR_URL_REFUSED%'; END;
  PERFORM _rec('T03', 'refus : une URL en HTTP (non HTTPS) — CONNECTOR_URL_REFUSED', ok,
    format('refus nommé CONNECTOR_URL_REFUSED = %s', ok));

  -- T04 — hôte local (la garde SSRF du dépôt)
  ok := false;
  BEGIN
    INSERT INTO business_connectors (tenant_id, name, connector_type, base_url)
      VALUES (ta, 'Interne', 'rest', 'https://localhost:8069/api');
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE '%CONNECTOR_URL_REFUSED%'; END;
  PERFORM _rec('T04', 'refus : une URL vers un hôte LOCAL (garde SSRF de la 154/167)', ok,
    format('refus nommé CONNECTOR_URL_REFUSED = %s', ok));

  -- T05 — type hors vocabulaire
  ok := false;
  BEGIN
    INSERT INTO business_connectors (tenant_id, name, connector_type, base_url)
      VALUES (ta, 'Bizarre', 'pigeon_voyageur', 'https://api.exemple.com');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;
  PERFORM _rec('T05', 'refus : un type de connecteur hors vocabulaire (CHECK)', ok,
    format('check_violation 23514 obtenue = %s', ok));

  -- T06 — authentification sans référence de secret
  ok := false;
  BEGIN
    INSERT INTO business_connectors (tenant_id, name, connector_type, base_url, auth_type)
      VALUES (ta, 'Sans secret', 'rest', 'https://api.exemple.com', 'oauth2');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23514'; END;
  PERFORM _rec('T06', 'refus : un mode d''authentification SANS référence de secret (CHECK)', ok,
    format('check_violation 23514 obtenue = %s', ok));

  -- T07 — nom déjà pris
  ok := false;
  BEGIN
    INSERT INTO business_connectors (tenant_id, name, connector_type, base_url)
      VALUES (ta, 'Odoo cloud', 'rest', 'https://autre.exemple.com');
  EXCEPTION WHEN OTHERS THEN ok := SQLSTATE = '23505'; END;
  PERFORM _rec('T07', 'le nom d''un connecteur est UNIQUE par société', ok,
    format('unique_violation 23505 obtenue = %s', ok));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T02', 'connecteur valide', false, SQLERRM);
  PERFORM _rec('T03', 'URL non HTTPS refusée', false, SQLERRM);
  PERFORM _rec('T04', 'hôte local refusé', false, SQLERRM);
  PERFORM _rec('T05', 'type contraint', false, SQLERRM);
  PERFORM _rec('T06', 'authentification avec référence', false, SQLERRM);
  PERFORM _rec('T07', 'nom unique', false, SQLERRM);
END $$;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 8 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '711';
  IF n <> 8 THEN
    RAISE EXCEPTION '[711] % verdict(s) enregistré(s) au lieu de 8 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('711');

