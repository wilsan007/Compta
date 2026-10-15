-- ============================================================
-- 713_modeles_documents_tests.sql — F.6 / ADM-04 :
--   LES MODÈLES DE DOCUMENTS, TENUS PAR LA BASE
--
--   T01  RLS forcée, index de société, et UNE politique par commande
--   T02  `anon` ne lit pas, n'écrit pas, et n'exécute pas la RPC
--   T03  les trois politiques d'ÉCRITURE portent `can_perform`
--   T04  un LECTEUR n'écrit pas ; un administrateur écrit
--   T05  le rôle est FIN : un comptable insère et modifie, mais ne supprime pas
--   T06  UN SEUL modèle par défaut par type (le second est refusé)
--   T07  deux TYPES différents ont chacun leur défaut (la règle ne les confond pas)
--   T08  `set_default_document_template` bascule : l'ancien démarqué, un seul reste
--   T09  la RPC refuse un modèle d'une AUTRE société (cloisonnement)
--   T10  la RPC refuse un LECTEUR (le rôle est opposable jusque dans la fonction)
--   T11  une couleur est un HEX, et la chaîne vide vaut NULL
--   T12  le nom n'est pas vide ; `template_config` est un OBJET
--   T13  le logo est HTTPS vers un hôte public (la garde SSRF du dépôt)
--   T14  `authenticated` n'a plus REFERENCES ni TRIGGER sur ce réglage
--
--   T04→T13 sont joués SOUS LE RÔLE `authenticated` (le seul endroit où la
--   RLS et `can_perform` parlent) ; T01→T03 et T14 sont des mesures statiques,
--   prises en superutilisateur.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '713', false);
DELETE FROM _audit_results WHERE file = '713';

DROP TABLE IF EXISTS t713;
CREATE TEMP TABLE t713 (k text PRIMARY KEY, v uuid);
GRANT SELECT, INSERT, UPDATE ON t713 TO authenticated;

-- ------------------------------------------------------------
-- Décor (superutilisateur) : une société A avec TROIS rôles (admin,
-- comptable, lecteur), une société voisine B avec son modèle, deux
-- modèles chez A (une facture par défaut, un devis sans défaut).
-- ------------------------------------------------------------
DO $$
DECLARE
  ta uuid; v_voisine uuid; t1 uuid; t2 uuid; tB uuid;
  aAdmin uuid; aCompta uuid; aLecteur uuid;
BEGIN
  ta := _mk_tenant('F713A');
  SELECT auth_id INTO aAdmin FROM tenant_users
   WHERE tenant_id = ta AND name = 'Admin' LIMIT 1;

  -- le COMPTABLE et le LECTEUR, dans la même société
  aCompta := uuid_generate_v4();
  INSERT INTO auth.users (id, email) VALUES (aCompta, 'compta713@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
    VALUES (ta, aCompta, 'compta713@audit.test', 'Compta', 'accountant', 'active', now());

  aLecteur := uuid_generate_v4();
  INSERT INTO auth.users (id, email) VALUES (aLecteur, 'lecteur713@audit.test');
  INSERT INTO tenant_users (tenant_id, auth_id, email, name, role, status, created_at)
    VALUES (ta, aLecteur, 'lecteur713@audit.test', 'Lecteur', 'viewer', 'active', now());

  -- la société voisine, avec SON modèle (pour le cloisonnement)
  v_voisine := _mk_tenant('F713B');
  INSERT INTO document_templates (tenant_id, name, document_type)
    VALUES (v_voisine, 'Modele B', 'invoice') RETURNING id INTO tB;

  -- Le contexte de la société A, posé EN SESSION : un GUC personnalisé n'est
  -- jamais « désactivé », et `current_tenant_id()` fait un `::json` dessus
  -- (doctrine écrite dans la 236, lignes 36-44 ; mesurée en écrivant la 712).
  PERFORM set_config('app.active_tenant_id', ta::text, false);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', ta::text)::text, false);
  PERFORM set_config('request.jwt.claim.sub', aAdmin::text, false);

  -- les modèles de A
  INSERT INTO document_templates (tenant_id, name, document_type, is_default)
    VALUES (ta, 'Facture A', 'invoice', true) RETURNING id INTO t1;
  INSERT INTO document_templates (tenant_id, name, document_type)
    VALUES (ta, 'Devis A', 'quote') RETURNING id INTO t2;

  INSERT INTO t713 (k, v) VALUES
    ('ta', ta), ('tb', v_voisine), ('t1', t1), ('t2', t2), ('tB', tB),
    ('aAdmin', aAdmin), ('aCompta', aCompta), ('aLecteur', aLecteur);
END $$;

-- ------------------------------------------------------------
-- T01 → T03, T14 — MESURES STATIQUES (superutilisateur)
-- ------------------------------------------------------------
DO $$
DECLARE v_force boolean; v_nb int; v_all int; v_cmds text; v_idx int;
BEGIN
  SELECT relforcerowsecurity INTO v_force FROM pg_class
   WHERE oid = 'document_templates'::regclass;

  SELECT count(*) INTO v_nb FROM pg_policies WHERE tablename = 'document_templates';
  SELECT count(*) INTO v_all FROM pg_policies
   WHERE tablename = 'document_templates' AND cmd = 'ALL';
  SELECT string_agg(DISTINCT cmd, ',' ORDER BY cmd) INTO v_cmds
   FROM pg_policies WHERE tablename = 'document_templates';
  SELECT count(*) INTO v_idx FROM pg_indexes
   WHERE tablename = 'document_templates' AND indexdef LIKE '%(tenant_id)%';

  PERFORM _rec('T01', 'RLS forcée, index de société, UNE politique par commande (aucune `FOR ALL`)',
    v_force AND v_nb = 4 AND v_all = 0
    AND v_cmds = 'DELETE,INSERT,SELECT,UPDATE' AND v_idx >= 1,
    format('force = %s ; politiques = %s (dont ALL = %s) ; commandes = %s ; index de société = %s',
           v_force, v_nb, v_all, COALESCE(v_cmds, '∅'), v_idx));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'RLS forcée et politiques', false, SQLERRM);
END $$;

DO $$
DECLARE v_tab int; v_fon int;
BEGIN
  SELECT count(*) INTO v_tab FROM information_schema.role_table_grants
   WHERE table_name = 'document_templates' AND grantee = 'anon';
  SELECT count(*) INTO v_fon FROM information_schema.role_routine_grants
   WHERE routine_name = 'set_default_document_template' AND grantee = 'anon';
  PERFORM _rec('T02', '`anon` ne lit pas, n''écrit pas, et n''exécute pas la RPC',
    v_tab = 0 AND v_fon = 0,
    format('droits de table du visiteur = %s ; droits sur la RPC = %s', v_tab, v_fon));
END $$;

DO $$
DECLARE v_ecrit int; v_sans int;
BEGIN
  SELECT count(*) INTO v_ecrit FROM pg_policies
   WHERE tablename = 'document_templates' AND cmd IN ('INSERT', 'UPDATE', 'DELETE');
  SELECT count(*) INTO v_sans FROM pg_policies
   WHERE tablename = 'document_templates' AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
     AND COALESCE(qual, '') || COALESCE(with_check, '') NOT LIKE '%can_perform%';

  PERFORM _rec('T03', 'les trois politiques d''écriture portent `can_perform` (le rôle est opposable)',
    v_ecrit = 3 AND v_sans = 0,
    format('politiques d''écriture = %s ; sans can_perform = %s', v_ecrit, v_sans));
END $$;

DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM information_schema.role_table_grants
   WHERE table_name = 'document_templates' AND grantee = 'authenticated'
     AND privilege_type IN ('REFERENCES', 'TRIGGER');
  PERFORM _rec('T14', '`authenticated` n''a plus REFERENCES ni TRIGGER (il garde le CRUD, gardé)',
    v = 0, format('droits REFERENCES/TRIGGER de l''utilisateur = %s (attendu 0)', v));
END $$;

-- ------------------------------------------------------------
-- T04 → T13 — LE COMPORTEMENT, sous le rôle `authenticated`
--   Chaque refus vit dans son sous-bloc `BEGIN … EXCEPTION` : un test
--   qui s'arrête au premier refus ne mesure qu'un refus. Deux pièges
--   d'écriture sont évités ici, et ils sont la raison de `FOUND` :
--     · un `INSERT` refusé par la RLS LÈVE (WITH CHECK) ;
--     · un `UPDATE`/`DELETE` refusé par la RLS ne lève PAS — il touche
--       zéro ligne. On mesure donc `FOUND`, jamais l'absence d'erreur.
-- ------------------------------------------------------------
BEGIN;
DO $$
DECLARE
  ta uuid; t1 uuid; t2 uuid; tB uuid;
  aAdmin uuid; aCompta uuid; aLecteur uuid;
  v_id uuid; v_nb int; v_is boolean; v_couleur text;
  ok_lect_refus boolean := false; ok_admin boolean := false;
  ok_compta_ins boolean := false; ok_compta_mod boolean := false; ok_compta_del boolean := false;
  ok_second_defaut boolean := false; ok_autre_type boolean := false; ok_bascule boolean := false;
BEGIN
  SELECT v INTO ta     FROM t713 WHERE k = 'ta';
  SELECT v INTO t1     FROM t713 WHERE k = 't1';
  SELECT v INTO t2     FROM t713 WHERE k = 't2';
  SELECT v INTO tB     FROM t713 WHERE k = 'tB';
  SELECT v INTO aAdmin FROM t713 WHERE k = 'aAdmin';
  SELECT v INTO aCompta FROM t713 WHERE k = 'aCompta';
  SELECT v INTO aLecteur FROM t713 WHERE k = 'aLecteur';

  PERFORM _as_user();

  -- T04 — un LECTEUR n'écrit pas ; un administrateur écrit
  PERFORM set_config('request.jwt.claim.sub', aLecteur::text, true);
  BEGIN
    INSERT INTO document_templates (tenant_id, name, document_type)
      VALUES (ta, 'Par le lecteur', 'statement');
  EXCEPTION WHEN OTHERS THEN ok_lect_refus := true;
  END;

  PERFORM set_config('request.jwt.claim.sub', aAdmin::text, true);
  BEGIN
    INSERT INTO document_templates (tenant_id, name, document_type)
      VALUES (ta, 'Par l''admin', 'statement');
    ok_admin := true;
  EXCEPTION WHEN OTHERS THEN ok_admin := false;
  END;

  PERFORM _rec('T04', 'un LECTEUR n''écrit pas ; un administrateur écrit',
    ok_lect_refus AND ok_admin,
    format('écriture du lecteur refusée = %s ; écriture de l''admin acceptée = %s',
           ok_lect_refus, ok_admin));

  -- T05 — le rôle est FIN : le comptable insère et modifie, mais ne SUPPRIME pas
  PERFORM set_config('request.jwt.claim.sub', aCompta::text, true);
  BEGIN
    INSERT INTO document_templates (tenant_id, name, document_type)
      VALUES (ta, 'Par le comptable', 'purchase_order') RETURNING id INTO v_id;
    ok_compta_ins := true;
  EXCEPTION WHEN OTHERS THEN ok_compta_ins := false;
  END;
  BEGIN
    UPDATE document_templates SET name = 'Renommé par le comptable' WHERE id = v_id;
    ok_compta_mod := FOUND;
  EXCEPTION WHEN OTHERS THEN ok_compta_mod := false;
  END;
  BEGIN
    DELETE FROM document_templates WHERE id = v_id;
    ok_compta_del := FOUND;   -- doit rester FAUX : la matrice D-6 refuse le delete
  EXCEPTION WHEN OTHERS THEN ok_compta_del := false;
  END;
  PERFORM _rec('T05', 'le rôle est FIN : un comptable insère et modifie, mais ne SUPPRIME pas',
    ok_compta_ins AND ok_compta_mod AND NOT ok_compta_del,
    format('insert = %s ; update = %s ; delete refusé = %s',
           ok_compta_ins, ok_compta_mod, NOT ok_compta_del));

  -- T06 — UN SEUL modèle par défaut par type : le second est refusé
  PERFORM set_config('request.jwt.claim.sub', aAdmin::text, true);
  BEGIN
    INSERT INTO document_templates (tenant_id, name, document_type, is_default)
      VALUES (ta, 'Facture bis', 'invoice', true);
  EXCEPTION WHEN unique_violation THEN ok_second_defaut := true;
  END;
  PERFORM _rec('T06', 'UN SEUL modèle par défaut par type : le second est REFUSÉ (index unique partiel)',
    ok_second_defaut,
    format('second défaut refusé (23505 sur uniq_document_templates_defaut) = %s', ok_second_defaut));

  -- T07 — deux TYPES différents ont chacun leur défaut
  BEGIN
    UPDATE document_templates SET is_default = true WHERE id = t2;
    ok_autre_type := FOUND;
  EXCEPTION WHEN OTHERS THEN ok_autre_type := false;
  END;
  SELECT count(*) INTO v_nb FROM document_templates WHERE tenant_id = ta AND is_default;
  PERFORM _rec('T07', 'deux TYPES différents ont chacun leur défaut (la règle ne les confond pas)',
    ok_autre_type AND v_nb = 2,
    format('le devis devient défaut = %s ; défauts de la société = %s (attendu 2 : facture et devis)',
           ok_autre_type, v_nb));

  -- T08 — la RPC bascule : l'ancien démarqué, un seul reste pour ce type
  INSERT INTO document_templates (tenant_id, name, document_type)
    VALUES (ta, 'Facture C', 'invoice') RETURNING id INTO v_id;
  BEGIN
    PERFORM set_default_document_template(v_id);
    SELECT count(*) INTO v_nb FROM document_templates
     WHERE tenant_id = ta AND document_type = 'invoice' AND is_default;
    SELECT is_default INTO v_is FROM document_templates WHERE id = v_id;
    ok_bascule := (v_nb = 1 AND v_is);
  EXCEPTION WHEN OTHERS THEN ok_bascule := false;
  END;
  PERFORM _rec('T08', '`set_default_document_template` bascule : l''ancien démarqué, un seul reste',
    ok_bascule,
    format('défauts « invoice » après bascule = %s ; le nouveau est défaut = %s',
           v_nb, COALESCE(v_is::text, 'NULL')));
  -- T09 → T13 — la RPC, l'identité, et le logo
  DECLARE
    ok_cloison boolean := false; ok_role boolean := false; ok_hex boolean := true;
    ok_nom boolean := false; ok_config boolean := false;
    ok_http boolean := false; ok_local boolean := false; ok_https boolean := false;
    v_logo text;
  BEGIN
    BEGIN
      PERFORM set_default_document_template(tB);
    EXCEPTION WHEN OTHERS THEN
      ok_cloison := (SQLERRM LIKE '%DOCUMENT_TEMPLATE_INTROUVABLE%');
    END;

    PERFORM set_config('request.jwt.claim.sub', aLecteur::text, true);
    BEGIN
      PERFORM set_default_document_template(t2);
    EXCEPTION WHEN OTHERS THEN
      ok_role := (SQLERRM LIKE '%DOCUMENT_TEMPLATE_ROLE_REFUSE%');
    END;
    PERFORM set_config('request.jwt.claim.sub', aAdmin::text, true);

    PERFORM _rec('T09', 'la RPC refuse un modèle d''une AUTRE société (cloisonnement)',
      ok_cloison, format('refus nommé DOCUMENT_TEMPLATE_INTROUVABLE = %s', ok_cloison));

    PERFORM _rec('T10', 'la RPC refuse un LECTEUR (le rôle est opposable jusque dans la fonction)',
      ok_role, format('refus nommé DOCUMENT_TEMPLATE_ROLE_REFUSE = %s', ok_role));

    -- T11 — une couleur est un HEX, et la chaîne vide vaut NULL
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type, primary_color)
        VALUES (ta, 'Couleur bleue', 'statement', 'bleu');
      ok_hex := false;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type, primary_color)
        VALUES (ta, 'Couleur courte', 'statement', '#12345');
      ok_hex := false;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type, primary_color)
        VALUES (ta, 'Couleur rgb', 'statement', 'rgb(1,2,3)');
      ok_hex := false;
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type, primary_color, secondary_color)
        VALUES (ta, 'Couleur valide', 'statement', '#1A2B3C', '') RETURNING id INTO v_id;
    EXCEPTION WHEN OTHERS THEN ok_hex := false;
    END;
    SELECT secondary_color INTO v_couleur FROM document_templates WHERE id = v_id;
    PERFORM _rec('T11', 'une couleur est un HEX (« bleu », « #12345 », « rgb() » refusés) — la chaîne vide vaut NULL',
      ok_hex AND v_couleur IS NULL,
      format('les trois formes fausses sont refusées = %s ; HEX valide accepté et « » normalisé en NULL = %s',
             ok_hex, v_couleur IS NULL));

    -- T12 — le nom n'est pas vide ; `template_config` est un OBJET
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type)
        VALUES (ta, '   ', 'statement');
    EXCEPTION WHEN check_violation THEN ok_nom := true;
    END;
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type, template_config)
        VALUES (ta, 'Config tableau', 'statement', '["a"]'::jsonb);
    EXCEPTION WHEN check_violation THEN ok_config := true;
    END;
    PERFORM _rec('T12', 'le nom n''est pas vide ; `template_config` est un OBJET (un tableau est refusé)',
      ok_nom AND ok_config,
      format('nom vide refusé = %s ; config tableau refusée = %s', ok_nom, ok_config));

    -- T13 — le logo : HTTPS vers un hôte public
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type, logo_url)
        VALUES (ta, 'Logo http', 'statement', 'http://exemple.test/logo.png');
    EXCEPTION WHEN OTHERS THEN ok_http := (SQLERRM LIKE '%DOCUMENT_TEMPLATE_LOGO_URL_REFUSED%');
    END;
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type, logo_url)
        VALUES (ta, 'Logo local', 'statement', 'http://127.0.0.1/logo.png');
    EXCEPTION WHEN OTHERS THEN ok_local := (SQLERRM LIKE '%DOCUMENT_TEMPLATE_LOGO_URL_REFUSED%');
    END;
    BEGIN
      INSERT INTO document_templates (tenant_id, name, document_type, logo_url)
        VALUES (ta, 'Logo public', 'statement', 'https://exemple.test/logo.png')
        RETURNING id INTO v_id;
      SELECT logo_url INTO v_logo FROM document_templates WHERE id = v_id;
      ok_https := (v_logo = 'https://exemple.test/logo.png');
    EXCEPTION WHEN OTHERS THEN ok_https := false;
    END;
    PERFORM _rec('T13', 'le logo est HTTPS vers un hôte public — la garde SSRF du dépôt est APPELÉE',
      ok_http AND ok_local AND ok_https,
      format('HTTP refusé = %s ; hôte local refusé = %s ; HTTPS public accepté = %s',
             ok_http, ok_local, ok_https));
  END;
END $$;
COMMIT;

-- Garde-fou anti-faux-vert : la suite EXIGE ses 14 verdicts
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _audit_results WHERE file = '713';
  IF n <> 14 THEN
    RAISE EXCEPTION '[713] % verdict(s) enregistré(s) au lieu de 14 — un scénario n''a pas été joué', n;
  END IF;
END $$;

SELECT _audit_assert('713');
