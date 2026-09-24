-- ============================================================
-- 237_composite_foreign_keys_tests.sql — ISO-02 : référencer chez le voisin
--
-- Constat d'entrée (audit du 23/09, `scenarios/ISO_ecriture_inter_societes.sql`,
-- rejoué sous le vrai rôle `authenticated`) : la société A pouvait désigner une
-- ligne de la société B — un client, une tâche, un article, une facture — que la
-- RLS lui cachait pourtant en lecture. La 236 a fermé l'ÉCRITURE chez le voisin
-- par les déclencheurs `SECURITY DEFINER` ; la RÉFÉRENCE restait ouverte, et son
-- `T02` est resté au registre des échecs attendus jusqu'ici.
--
-- CE QUE CES SCÉNARIOS MESURENT. Non pas « la requête a échoué », mais « la
-- référence inter-sociétés n'existe pas », et dans les deux sens :
--   * refusée pour l'utilisateur de la société (la clé composite) ;
--   * refusée AUSSI hors contexte applicatif, rôle `postgres`, RLS hors jeu :
--     c'est la différence entre une garde de droits et une garde de données ;
--   * et les références LÉGITIMES de la même société continuent de passer, y
--     compris les suppressions en cascade — un correctif qui casse le métier
--     n'est pas un correctif.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '237', false);
DELETE FROM _audit_results WHERE file = '237';

-- L'utilisateur actif d'une société, par le même chemin que PostgREST : JWT +
-- en-tête `x-tenant-id`. En-tête posé en SESSION (voir le piège documenté dans
-- la suite 236 : un GUC personnalisé local revient en chaîne vide, pas en NULL).
CREATE OR REPLACE FUNCTION _as237(p_tenant uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_user uuid;
BEGIN
  SELECT auth_id INTO v_user FROM tenant_users
  WHERE tenant_id = p_tenant AND status = 'active' ORDER BY created_at LIMIT 1;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Aucun utilisateur actif pour la société %', p_tenant; END IF;
  PERFORM set_config('request.jwt.claim.sub', v_user::text, false);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, false);
  PERFORM set_config('request.headers',
    json_build_object('x-tenant-id', p_tenant::text)::text, false);
  PERFORM set_config('app.active_tenant_id', p_tenant::text, true);
  PERFORM set_config('role', 'authenticated', true);
  IF current_tenant_id() IS DISTINCT FROM p_tenant THEN
    RAISE EXCEPTION 'Contexte tenant non établi — le test ne prouverait rien';
  END IF;
  RETURN v_user;
END $$;

-- Reprend le rôle privilégié pour MESURER : sous `authenticated`, la lecture
-- croisée est refusée par la RLS et l'assertion serait vraie par aveuglement.
CREATE OR REPLACE FUNCTION _mesure237() RETURNS void LANGUAGE sql AS $$
  SELECT set_config('role', 'postgres', true)
$$;

-- Une société et ses objets, tous de la même société : le cas légitime.
CREATE OR REPLACE FUNCTION _fixture237(p_tenant uuid)
RETURNS TABLE (client uuid, projet uuid, tache uuid, article uuid, facture uuid)
LANGUAGE plpgsql AS $$
DECLARE v_client uuid; v_projet uuid; v_tache uuid; v_article uuid; v_facture uuid;
BEGIN
  INSERT INTO customers (tenant_id, name) VALUES (p_tenant, 'Client ' || left(p_tenant::text, 8))
  RETURNING id INTO v_client;
  INSERT INTO projects (tenant_id, name) VALUES (p_tenant, 'Projet ' || left(p_tenant::text, 8))
  RETURNING id INTO v_projet;
  INSERT INTO project_tasks (tenant_id, project_id, title, status, progress)
  VALUES (p_tenant, v_projet, 'Tâche racine', 'todo', 0) RETURNING id INTO v_tache;
  INSERT INTO products (tenant_id, name, type, sale_price) VALUES (p_tenant, 'Article', 'stock', 10)
  RETURNING id INTO v_article;
  INSERT INTO invoices (tenant_id, number, customer_id, due_date, status, subtotal, vat_total, total)
  VALUES (p_tenant, 'FAC-' || left(p_tenant::text, 8), v_client, '2026-04-01', 'draft', 0, 0, 0)
  RETURNING id INTO v_facture;
  client := v_client; projet := v_projet; tache := v_tache; article := v_article; facture := v_facture;
  RETURN NEXT;
END $$;


-- ── T01/T02/T03 : les références inter-sociétés sont refusées ─────────────
-- Le chemin d'attaque est celui du constat : un utilisateur de A, dont la RLS
-- cache les lignes de B, les désigne par leur identifiant. Deux gardes peuvent
-- répondre — la clé composite (`23503`) ou, en amont, une politique RLS qui lit
-- le parent (`42501`) : les deux sont des refus, et le test exige l'un ou
-- l'autre. Une erreur d'une autre nature ferait échouer le scénario : il doit
-- mesurer un refus, pas n'importe quelle erreur.
DO $$
DECLARE ta uuid; tb uuid; fa record; fb record; v_state text; v_err text;
BEGIN
  ta := _mk_tenant('ISO237A1'); tb := _mk_tenant('ISO237B1');
  SELECT * INTO fa FROM _fixture237(ta);
  SELECT * INTO fb FROM _fixture237(tb);
  PERFORM _as237(ta);

  -- T01 — la facture de A désigne le client de B
  v_state := NULL;
  BEGIN
    INSERT INTO invoices (tenant_id, number, customer_id, due_date, status, subtotal, vat_total, total)
    VALUES (ta, 'FA-T01', fb.client, '2026-04-01', 'draft', 0, 0, 0);
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T01', 'une facture ne peut plus désigner le client d''une autre société',
    v_state IN ('23503', '42501'),
    format('SQLSTATE=%s (attendu 23503 clé composite ou 42501 politique) | %s',
           COALESCE(v_state, 'aucune erreur'), left(v_err, 60)));

  -- T02 — la sous-tâche de A désigne la tâche de B (clé réflexive)
  v_state := NULL;
  BEGIN
    INSERT INTO project_tasks (tenant_id, project_id, parent_id, title, status, progress)
    VALUES (ta, fa.projet, fb.tache, 'Sous-tâche de A sur la tâche de B', 'todo', 0);
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T02', 'une sous-tâche ne peut plus désigner la tâche d''une autre société',
    v_state IN ('23503', '42501'),
    format('SQLSTATE=%s (attendu 23503 ou 42501) | %s', COALESCE(v_state, 'aucune erreur'), left(v_err, 60)));

  -- T03 — la ligne de facture de A désigne la facture de B
  v_state := NULL;
  BEGIN
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, total)
    VALUES (ta, fb.facture, 'Ligne de A sur la facture de B', 1, 10, 10);
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T03', 'une ligne ne peut plus désigner la facture d''une autre société',
    v_state IN ('23503', '42501'),
    format('SQLSTATE=%s (attendu 23503 ou 42501) | %s', COALESCE(v_state, 'aucune erreur'), left(v_err, 60)));
END $$;

-- ── T04/T05 : la clé vit dans les DONNÉES, pas dans les droits ────────────
-- Les deux mêmes références, exécutées sans contexte applicatif — rôle
-- `postgres`, qui contourne la RLS par construction — sont refusées tout
-- autant. C'est la propriété que la 236 ne pouvait pas donner : elle empêche un
-- utilisateur d'écrire chez le voisin, pas un appel privilégié de RÉFÉRENCER
-- une ligne. La sonde qui précède le test (documentée dans la preuve de vague)
-- a montré que ces deux insertions étaient ACCEPTÉES avant la migration.
DO $$
DECLARE ta uuid; tb uuid; fb record; v_state text; v_err text;
BEGIN
  ta := _mk_tenant('ISO237A4'); tb := _mk_tenant('ISO237B4');
  PERFORM _fixture237(ta);
  SELECT * INTO fb FROM _fixture237(tb);
  PERFORM _mesure237();

  v_state := NULL; v_err := NULL;
  BEGIN
    INSERT INTO project_tasks (tenant_id, parent_id, title)
    VALUES (ta, fb.tache, 'Sous-tâche de A sur la tâche de B');
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T04', 'une sous-tâche ne peut plus désigner la tâche d''une autre société, même sans RLS',
    v_state = '23503',
    format('SQLSTATE=%s (attendu 23503) | %s', COALESCE(v_state, 'aucune erreur'), left(v_err, 60)));

  v_state := NULL; v_err := NULL;
  BEGIN
    INSERT INTO invoice_lines (tenant_id, invoice_id, description)
    VALUES (ta, fb.facture, 'Ligne de A sur la facture de B, sans contexte applicatif');
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('T05', 'une ligne ne peut plus désigner la facture d''une autre société, même sans RLS',
    v_state = '23503',
    format('SQLSTATE=%s sous le rôle postgres (attendu 23503) | %s',
           COALESCE(v_state, 'aucune erreur'), left(v_err, 60)));
END $$;

-- ── T06/T07 : les références de la MÊME société, et leurs suppressions ────
-- La clé composite ne doit pas gêner le métier. Ces deux scénarios couvrent les
-- deux règles de suppression que le générateur a recopiées telles quelles
-- (`ON DELETE CASCADE` sur les lignes, `SET NULL` sur le client) : une clé
-- recréée sans ses actions casserait la suppression d'un brouillon, ou pire,
-- effacerait la facture avec son client.
DO $$
DECLARE ta uuid; fa record; v_facture2 uuid; v_lignes int; v_detache uuid;
BEGIN
  ta := _mk_tenant('ISO237A6');
  SELECT * INTO fa FROM _fixture237(ta);
  PERFORM _as237(ta);

  -- T06 — facture + ligne + sous-tâche, toutes de la même société : acceptées
  BEGIN
    INSERT INTO invoice_lines (tenant_id, invoice_id, description, quantity, unit_price, total)
    VALUES (ta, fa.facture, 'Ligne de A sur sa propre facture', 1, 10, 10);
    INSERT INTO project_tasks (tenant_id, project_id, parent_id, title, status, progress)
    VALUES (ta, fa.projet, fa.tache, 'Sous-tâche de A sur sa propre tâche', 'todo', 0);
    PERFORM _rec('T06', 'les références de la même société passent toujours',
      true, 'facture, ligne, sous-tâche acceptées');
  EXCEPTION WHEN others THEN
    PERFORM _rec('T06', 'les références de la même société passent toujours',
      false, left(SQLERRM, 160));
  END;

  -- T07 — ON DELETE CASCADE : supprimer la facture emporte sa ligne ;
  --       ON DELETE SET NULL : supprimer le client détache la facture. Les deux
  --       comportements viennent du relevé du générateur ; les mesurer est le
  --       seul moyen de savoir qu'ils ont été recopiés et non réinventés.
  INSERT INTO invoices (tenant_id, number, customer_id, due_date, status, subtotal, vat_total, total)
  VALUES (ta, 'FA-T07', fa.client, '2026-04-01', 'draft', 0, 0, 0) RETURNING id INTO v_facture2;
  DELETE FROM invoices WHERE id = fa.facture;          -- emporte sa ligne (CASCADE)
  SELECT count(*) INTO v_lignes FROM invoice_lines WHERE invoice_id = fa.facture;
  DELETE FROM customers WHERE id = fa.client;          -- détache la facture (SET NULL)
  SELECT customer_id INTO v_detache FROM invoices WHERE id = v_facture2;
  PERFORM _rec('T07', 'les suppressions gardent leur action d''origine (CASCADE et SET NULL)',
    v_lignes = 0 AND v_detache IS NULL,
    format('lignes restantes=%s (attendu 0), client de la seconde facture=%s (attendu NULL)',
           v_lignes, COALESCE(v_detache::text, 'NULL')));
END $$;

-- ── T08 : la couverture, mesurée sur le schéma ────────────────────────────
-- Le scénario le plus important de la vague : il ne regarde pas une table, il
-- regarde la PROPRIÉTÉ. Tant qu'une clé mono-colonne relie deux tables
-- cloisonnées, elle est une porte — et c'est ce relevé qui a servi à générer la
-- migration, donc ce qui n'y figurait pas n'a pas été corrigé.
DO $$
DECLARE v_n int; v_reste text; v_composites int;
BEGIN
  SELECT count(*),
         string_agg(cc.relname || '.' || a.attname || ' → ' || cp.relname, ', ' ORDER BY cc.relname)
    INTO v_n, v_reste
  FROM pg_constraint f
  JOIN pg_class cc     ON cc.oid = f.conrelid
  JOIN pg_namespace nc ON nc.oid = cc.relnamespace AND nc.nspname = 'public'
  JOIN pg_class cp     ON cp.oid = f.confrelid
  JOIN pg_namespace np ON np.oid = cp.relnamespace AND np.nspname = 'public'
  JOIN pg_attribute a  ON a.attrelid = f.conrelid AND a.attnum = f.conkey[1]
  WHERE f.contype = 'f' AND array_length(f.conkey, 1) = 1 AND a.attname <> 'tenant_id'
    AND EXISTS (SELECT 1 FROM information_schema.columns x
                WHERE x.table_schema = 'public' AND x.table_name = cc.relname
                  AND x.column_name = 'tenant_id')
    AND EXISTS (SELECT 1 FROM information_schema.columns y
                WHERE y.table_schema = 'public' AND y.table_name = cp.relname
                  AND y.column_name = 'tenant_id');

  SELECT count(*) INTO v_composites
  FROM pg_constraint f
  JOIN pg_class cc     ON cc.oid = f.conrelid
  JOIN pg_namespace nc ON nc.oid = cc.relnamespace AND nc.nspname = 'public'
  JOIN pg_attribute a  ON a.attrelid = f.conrelid AND a.attnum = f.conkey[1]
  WHERE f.contype = 'f' AND array_length(f.conkey, 1) = 2 AND a.attname = 'tenant_id';

  PERFORM _rec('T08', 'aucune clé étrangère mono-colonne ne relie deux tables cloisonnées',
    v_n = 0, format('restantes=%s%s ; clés composites (tenant_id, …)=%s',
                   v_n, COALESCE(' [' || left(v_reste, 120) || ']', ''), v_composites));
END $$;

SELECT _audit_assert('237');

