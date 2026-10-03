-- ============================================================
-- 310_legislation_packs_readable_tests.sql — recette /qa du 29/09/2026
--
--   QA-01 🔴 L'inscription s'arrête à l'étape « législation » : la liste des
--            pays est VIDE. La migration 24 a rangé le référentiel
--            `legislation_packs` sous la société technique `…0001` (tenant_id
--            NOT NULL), et la seule politique de lecture est
--            `tenant_id IS NULL OR tenant_id = current_tenant_id()`. Un inscrit
--            sans société ne voit donc aucun pack, et une société réelle non
--            plus (`getLegislationPack(code)` rend 406).
--
-- Ce fichier tient la fermeture : le référentiel est lisible par tout
-- utilisateur connecté, il n'est toujours pas écrivable, et un pack propre à une
-- autre société reste invisible.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '310', false);
DELETE FROM _audit_results WHERE file = '310';

-- T01 — un inscrit SANS société (l'écran d'inscription) voit les packs, dont FR
DO $$
DECLARE a uuid := uuid_generate_v4(); n int; fr int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (a, 'qa01-' || a || '@audit.test');
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM set_config('app.active_tenant_id', '', true);
  PERFORM _as_user();
  SELECT count(*), count(*) FILTER (WHERE code = 'FR') INTO n, fr
  FROM legislation_packs WHERE active;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T01', 'un inscrit sans société voit les packs actifs, dont FR',
    n > 0 AND fr = 1, format('%s pack(s) visible(s), FR visible : %s', n, fr = 1));
END $$;

-- T02 — une société réelle lit son pack par son code (getLegislationPack)
DO $$
DECLARE t uuid; fr int;
BEGIN
  t := _mk_tenant('QA01B');
  PERFORM _as_user();
  SELECT count(*) INTO fr FROM legislation_packs WHERE code = 'FR';
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T02', 'une société réelle lit le pack FR par son code',
    fr = 1, format('%s ligne(s) pour FR (1 attendue)', fr));
END $$;

-- T03 — le référentiel reste en lecture seule pour un utilisateur connecté
DO $$
DECLARE t uuid; ins text := 'refusé'; upd int := 0;
BEGIN
  t := _mk_tenant('QA01C');
  PERFORM _as_user();
  BEGIN
    INSERT INTO legislation_packs (code, name, country_code, country_name, accounting_standard, tenant_id)
      VALUES ('QA01', 'Faux pack', 'ZZ', 'Nulle part', 'TEST', '00000000-0000-0000-0000-000000000001');
    ins := 'accepté';
  EXCEPTION WHEN OTHERS THEN ins := 'refusé';
  END;
  UPDATE legislation_packs SET name = 'altéré' WHERE code = 'FR';
  GET DIAGNOSTICS upd = ROW_COUNT;
  EXECUTE 'RESET ROLE';
  PERFORM _rec('T03', 'un utilisateur connecté ne crée ni ne modifie un pack du référentiel',
    ins = 'refusé' AND upd = 0, format('insertion %s ; %s ligne(s) modifiée(s)', ins, upd));
END $$;

-- T04 — un pack propre à une AUTRE société réelle reste invisible
DO $$
DECLARE ta uuid; tb uuid; n int;
BEGIN
  ta := _mk_tenant('QA01D');
  INSERT INTO legislation_packs (code, name, country_code, country_name, accounting_standard, tenant_id, active)
    VALUES ('QA01-PRIVE', 'Pack privé de A', 'ZZ', 'Nulle part', 'TEST', ta, true);
  tb := _mk_tenant('QA01E');
  PERFORM _as_user();
  SELECT count(*) INTO n FROM legislation_packs WHERE code = 'QA01-PRIVE';
  EXECUTE 'RESET ROLE';
  DELETE FROM legislation_packs WHERE code = 'QA01-PRIVE';
  PERFORM _rec('T04', 'le pack privé d''une autre société reste invisible',
    n = 0, format('%s ligne(s) visible(s) (0 attendue)', n));
END $$;

SELECT _audit_assert('310');
