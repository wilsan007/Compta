-- ============================================================
-- 238_policy_dedup_tests.sql — ISO-03 / ISO-04 : la politique jumelle
--
-- Constat du 23/09, mesuré le 24/09 sur base neuve : **1 739 politiques RLS**,
-- dont **495 couples (table, commande) portant DEUX politiques permissives**.
-- Deux politiques permissives se combinent en **OU** : la plus large gagne, et
-- les 57 gardes `can_perform` portées par les politiques par table ne sont
-- jamais atteintes. Ces scénarios mesurent la propriété, pas la migration :
--   T01  plus aucun couple doublé                          (la forme)
--   T02  plus aucune garde accompagnée d'une jumelle       (la conséquence)
--   T03  la garde est OPPOSABLE : un viewer ne peut plus écrire (l'effet)
--   T04  et le rôle légitime écrit toujours               (non-régression)
--   T05  la lecture n'a pas été fermée au passage          (N1)
--   T06  plus aucun index en double                        (ISO-04)
--   T07  aucune table cloisonnée sans politique            (le retrait n'a pas vidé une table)
--   T08  le volume de politiques reste celui attendu       (le détecteur n'est pas aveugle)
--
-- Le test décisif est T03 : avant la 238, la politique générique `tenant_insert`
-- laissait passer ; après, seule `tenant_insert_machines` subsiste, et
-- `can_perform('machines','insert')` est faux pour un `viewer`.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '238', false);
DELETE FROM _audit_results WHERE file = '238';

-- Un utilisateur d'un rôle donné, connecté par le même chemin que PostgREST.
-- `_mk_tenant` crée déjà un administrateur ; ce second compte mesure ce que le
-- rôle permet RÉELLEMENT, appel direct à l'API compris.
CREATE OR REPLACE FUNCTION _as238(p_tenant uuid, p_role text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_email text;
BEGIN
  SELECT auth_id INTO v_user FROM tenant_users
  WHERE tenant_id = p_tenant AND role = p_role AND status = 'active'
  ORDER BY created_at LIMIT 1;
  IF v_user IS NULL THEN
    v_email := p_role || '-' || left(p_tenant::text, 8) || '@dedup.test';
    v_user := uuid_generate_v4();
    INSERT INTO auth.users (id, email) VALUES (v_user, v_email);
    INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status)
    VALUES (p_tenant, v_user, v_email, initcap(p_role), p_role, 'active');
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_user::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, false);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', p_tenant::text)::text, false);
  PERFORM set_config('app.active_tenant_id', p_tenant::text, true);
  PERFORM set_config('role', 'authenticated', true);
  IF current_user_role() IS DISTINCT FROM p_role THEN
    RAISE EXCEPTION 'Rôle % non établi — le test ne prouverait rien', p_role;
  END IF;
  RETURN v_user;
END $$;

CREATE OR REPLACE FUNCTION _mesure238() RETURNS void LANGUAGE sql AS $$
  SELECT set_config('role', 'postgres', true)
$$;

-- ── T01/T02/T08 : la forme, mesurée sur le catalogue ──────────────────────
DO $$
DECLARE v_doubles int; v_gardees_doubles int; v_permissives int; v_noms text;
BEGIN
  SELECT count(*), string_agg(c.relname || '(' || x.polcmd::text || ')', ', ' ORDER BY c.relname)
    INTO v_doubles, v_noms
  FROM (SELECT p.polrelid, p.polcmd FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND p.polpermissive
        GROUP BY 1, 2 HAVING count(*) > 1) x
  JOIN pg_class c ON c.oid = x.polrelid;

  SELECT count(*) INTO v_gardees_doubles
  FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND (coalesce(pg_get_expr(p.polqual, p.polrelid), '') LIKE '%can_perform%'
      OR coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') LIKE '%can_perform%')
    AND (p.polrelid, p.polcmd) IN (SELECT p2.polrelid, p2.polcmd FROM pg_policy p2
                                   WHERE p2.polpermissive GROUP BY 1, 2 HAVING count(*) > 1);

  SELECT count(*) INTO v_permissives FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND p.polpermissive;

  PERFORM _rec('T01', 'aucun couple (table, commande) ne porte deux politiques permissives',
    v_doubles = 0, format('couples doublés=%s%s', v_doubles,
                          CASE WHEN v_noms IS NULL THEN '' ELSE ' [' || left(v_noms, 150) || ']' END));

  PERFORM _rec('T02', 'aucune garde can_perform n''est accompagnée d''une politique jumelle',
    v_gardees_doubles = 0, format('gardes neutralisées=%s (attendu 0)', v_gardees_doubles));

  -- 1 739 politiques permissives avant la 238, 1 233 après (506 retirées : 495
  -- couples, dont 11 en portaient trois). Le plancher est volontairement large :
  -- ce qui compte est qu'une exécution à vide ou un détecteur cassé ne fasse pas
  -- tout passer au vert.
  PERFORM _rec('T08', 'le volume de politiques permissives reste celui attendu (détecteur vivant)',
    v_permissives BETWEEN 1200 AND 1300,
    format('politiques permissives=%s (attendu ~1233)', v_permissives));
END $$;

-- ── T03/T04/T05 : la garde devient opposable, sans fermer la porte légitime
-- T03 est le scénario décisif : avant la 238, la politique générique
-- `tenant_insert` (société seule) laissait passer le `viewer` ; la garde
-- `can_perform('machines','insert')` était annulée par le OU.
DO $$
DECLARE ta uuid; v_state text := NULL; v_err text := '—'; v_crochets int; v_viewer uuid; v_attendues int;
BEGIN
  ta := _mk_tenant('ISO238A1');
  PERFORM _as238(ta, 'viewer');
  BEGIN
    INSERT INTO machines (tenant_id, code, name) VALUES (ta, 'M-VIEWER', 'Machine du viewer');
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;

  PERFORM _mesure238();
  SELECT count(*) INTO v_crochets FROM machines WHERE tenant_id = ta;
  PERFORM _rec('T03', 'un viewer ne peut plus insérer par appel direct (la garde est opposable)',
    v_state = '42501' AND v_crochets = 0,
    format('SQLSTATE=%s, lignes créées=%s | %s', COALESCE(v_state, 'aucune erreur'), v_crochets, left(v_err, 60)));

  -- T04 — le rôle légitime écrit toujours : administrateur, puis comptable.
  -- Le compte est fait SUR LES CODES écrits par ce scénario, jamais sur le total
  -- de la table : sinon l'échec de T03 (une ligne de plus) ferait échouer T04
  -- pour la mauvaise raison, et un scénario ne doit mesurer que son geste.
  PERFORM _as238(ta, 'admin');
  INSERT INTO machines (tenant_id, code, name) VALUES (ta, 'M-ADMIN', 'Machine de l''admin');
  PERFORM _mesure238();
  PERFORM _as238(ta, 'accountant');
  INSERT INTO machines (tenant_id, code, name) VALUES (ta, 'M-COMPTA', 'Machine du comptable');
  PERFORM _mesure238();
  SELECT count(*) INTO v_crochets FROM machines WHERE tenant_id = ta AND code IN ('M-ADMIN', 'M-COMPTA');
  PERFORM _rec('T04', 'les rôles légitimes écrivent toujours (admin, comptable)',
    v_crochets = 2, format('lignes créées par les rôles légitimes=%s (attendu 2)', v_crochets));

  -- T05 — la lecture n'est pas fermée par le dédoublonnage (N1 non régressé).
  -- On compare ce que voit le `viewer` à ce qui existe : aucune politique de
  -- lecture ne porte de garde, le retrait ne devait donc rien lui cacher.
  PERFORM _mesure238();
  SELECT count(*) INTO v_attendues FROM machines WHERE tenant_id = ta;
  v_viewer := _as238(ta, 'viewer');
  SELECT count(*) INTO v_crochets FROM machines WHERE tenant_id = ta;
  PERFORM _mesure238();
  PERFORM _rec('T05', 'un viewer lit toujours ce que sa société voit (la lecture n''est pas fermée)',
    v_crochets = v_attendues AND v_attendues > 0,
    format('lignes visibles par le viewer=%s, lignes existantes=%s', v_crochets, v_attendues));
END $$;

-- ── T06/T07 : les index, et les tables laissées sans politique ─────────────
DO $$
DECLARE v_index int; v_orphelines text; v_noms text;
BEGIN
  SELECT count(*), string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_index, v_noms
  FROM (SELECT i.indrelid, i.indkey::text, i.indisunique, i.indexprs::text, i.indpred::text
        FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
        GROUP BY 1, 2, 3, 4, 5 HAVING count(*) > 1) x
  JOIN pg_class c ON c.oid = x.indrelid;

  PERFORM _rec('T06', 'aucun index en double (mêmes colonnes, même unicité)',
    v_index = 0, format('couples d''index jumeaux=%s%s', v_index,
                        CASE WHEN v_noms IS NULL THEN '' ELSE ' [' || left(v_noms, 120) || ']' END));

  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_orphelines
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relkind = 'r' AND c.relrowsecurity
    -- Deux tables portent la RLS SANS aucune politique sur base neuve, avant
    -- cette vague : `chart_provisional_fallbacks` et `platform_admins` sont
    -- fermées à tout le monde hors `service_role`. Mesuré avant la 238, pas
    -- causé par elle — elles sont donc gelées ici pour que le scénario parle du
    -- retrait et non d'un état antérieur.
    AND c.relname NOT IN ('chart_provisional_fallbacks', 'platform_admins')
    AND NOT EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid);

  PERFORM _rec('T07', 'aucune table cloisonnée ne reste sans politique après le retrait',
    v_orphelines IS NULL, format('tables sans politique : %s', COALESCE(left(v_orphelines, 150), 'aucune')));
END $$;

SELECT _audit_assert('238');

