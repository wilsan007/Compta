-- ============================================================
-- 239_roles_opposables_tests.sql — PERM-01 : le rôle devient opposable
--
-- Constat d'entrée, `doc/audit/scenarios/M18_role_non_opposable.sql` rejoué sous
-- le vrai rôle `authenticated` : un `viewer` CRÉAIT une facture et SUPPRIMAIT un
-- client par appel direct. Ces scénarios mesurent les deux sens, parce qu'un
-- correctif qui ferme tout n'est pas un correctif :
--   P1  un viewer ne peut plus CRÉER une facture          (le défaut)
--   P2  un viewer ne peut plus SUPPRIMER un client        (le défaut)
--   P4  un viewer ne peut plus MODIFIER une facture       (le défaut, en écriture)
--   P5  et il LIT toujours ce que sa société voit         (non-régression, N1)
--   P3  l'auto-promotion reste refusée                    (N8, non régressé)
--   P6  un administrateur écrit et supprime normalement   (non-régression)
--   P7  un comptable écrit la comptabilité, mais pas tout (la matrice est mesurée)
--   P8  un auditeur lit sans écrire                       (le rôle garde son sens)
--   P9  un manager écrit le commercial, pas la comptabilité
--
-- Chaque refus est vérifié par son SQLSTATE (42501 : politique RLS) ET par
-- l'absence d'effet sur les lignes : un refus sans message qui laisserait la
-- ligne modifiée ne serait pas un refus.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '239', false);
DELETE FROM _audit_results WHERE file = '239';

-- Un utilisateur d'un rôle donné, connecté comme PostgREST le ferait.
CREATE OR REPLACE FUNCTION _as239(p_tenant uuid, p_role text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_user uuid; v_email text;
BEGIN
  SELECT auth_id INTO v_user FROM tenant_users
  WHERE tenant_id = p_tenant AND role = p_role AND status = 'active'
  ORDER BY created_at LIMIT 1;
  IF v_user IS NULL THEN
    v_email := p_role || '-' || left(p_tenant::text, 8) || '@perm.test';
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

CREATE OR REPLACE FUNCTION _mesure239() RETURNS void LANGUAGE sql AS $$
  SELECT set_config('role', 'postgres', true)
$$;

-- ── P1 à P5 : le viewer — ce qu'il ne peut plus faire, ce qu'il garde ──────
DO $$
DECLARE
  ta uuid; v_client uuid; v_facture uuid; v_state text; v_err text;
  v_n int;
BEGIN
  ta := _mk_tenant('PERM239A1');
  -- Le jeu de données est posé en administrateur : c'est l'état dans lequel le
  -- `viewer` arrive, pas un état qu'il fabrique.
  PERFORM _as239(ta, 'admin');
  INSERT INTO customers (tenant_id, name) VALUES (ta, 'Client du viewer') RETURNING id INTO v_client;
  INSERT INTO invoices (tenant_id, number, customer_id, due_date, status, subtotal, vat_total, total)
  VALUES (ta, 'FA-PERM-1', v_client, '2026-04-01', 'draft', 100, 20, 120) RETURNING id INTO v_facture;
  PERFORM _mesure239();

  -- P1 — créer une facture
  PERFORM _as239(ta, 'viewer');
  v_state := NULL;
  BEGIN
    INSERT INTO invoices (tenant_id, number, customer_id, due_date, status, subtotal, vat_total, total)
    VALUES (ta, 'FA-PERM-VIEWER', v_client, '2026-04-01', 'draft', 100, 20, 120);
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _rec('P1', 'un viewer ne peut plus CRÉER une facture par appel direct',
    v_state = '42501', format('SQLSTATE=%s (attendu 42501) | %s',
                              COALESCE(v_state, 'aucune erreur'), left(v_err, 60)));

  -- P2 — supprimer un client
  v_state := NULL;
  BEGIN
    DELETE FROM customers WHERE id = v_client;
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _mesure239();
  SELECT count(*) INTO v_n FROM customers WHERE id = v_client;
  PERFORM _rec('P2', 'un viewer ne peut plus SUPPRIMER un client',
    (v_state = '42501' OR v_state IS NULL) AND v_n = 1,
    format('SQLSTATE=%s, client encore présent=%s (attendu 1)', COALESCE(v_state, 'aucune erreur'), v_n));

  -- P3 — s'auto-promouvoir administrateur (N8, non régressé)
  v_state := NULL;
  BEGIN
    UPDATE tenant_users SET role = 'admin' WHERE auth_id = auth.uid();
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _mesure239();
  SELECT count(*) INTO v_n FROM tenant_users WHERE tenant_id = ta AND role = 'admin' AND auth_id = (
    SELECT auth_id FROM tenant_users WHERE tenant_id = ta AND role = 'viewer' LIMIT 1);
  PERFORM _rec('P3', 'un viewer ne peut toujours pas s''auto-promouvoir (N8 non régressé)',
    v_n = 0, format('viewers devenus admin=%s (attendu 0) | %s', v_n, left(v_err, 50)));

  -- P4 — modifier une facture existante
  PERFORM _as239(ta, 'viewer');
  v_state := NULL;
  BEGIN
    UPDATE invoices SET total = 1 WHERE id = v_facture;
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _mesure239();
  SELECT count(*) INTO v_n FROM invoices WHERE id = v_facture AND total = 1;
  PERFORM _rec('P4', 'un viewer ne peut plus MODIFIER une facture',
    (v_state = '42501' OR v_state IS NULL) AND v_n = 0,
    format('SQLSTATE=%s, facture réécrite=%s (attendu 0)', COALESCE(v_state, 'aucune erreur'), v_n));

  -- P5 — la lecture reste ouverte au viewer. Le compte porte sur l'IDENTIFIANT de
  -- la facture du jeu de données, et non sur son numéro : la numérotation légale
  -- réécrit `number` à l'insertion d'un brouillon (`BROUILLON-…`), et non sur le
  -- total de la table, sinon la réussite de P1 (une facture de plus) ferait
  -- échouer P5 pour la mauvaise raison — un scénario ne mesure que son geste.
  PERFORM _as239(ta, 'viewer');
  SELECT count(*) INTO v_n FROM invoices WHERE id = v_facture;
  PERFORM _mesure239();
  PERFORM _rec('P5', 'un viewer LIT toujours les factures de sa société (la garde ne ferme pas la lecture)',
    v_n = 1, format('factures visibles pour le viewer=%s (attendu 1)', v_n));
END $$;


-- ── P6 à P9 : les rôles qui DOIVENT écrire, et jusqu'où ───────────────────
-- La garde est une matrice, pas un mur : chaque rôle est mesuré sur un geste
-- qu'il doit pouvoir faire et sur un geste qu'il ne doit pas pouvoir faire.
DO $$
DECLARE
  ta uuid; v_client uuid; v_facture uuid; v_entree uuid; v_state text; v_err text;
  v_state_ecriture text; v_n int;
BEGIN
  ta := _mk_tenant('PERM239A6');
  PERFORM _as239(ta, 'admin');
  INSERT INTO customers (tenant_id, name) VALUES (ta, 'Client des rôles') RETURNING id INTO v_client;
  PERFORM _mesure239();

  -- P6 — administrateur : écrit et supprime
  PERFORM _as239(ta, 'admin');
  v_state := NULL;
  BEGIN
    INSERT INTO invoices (tenant_id, number, customer_id, due_date, status, subtotal, vat_total, total)
    VALUES (ta, 'FA-PERM-ADMIN', v_client, '2026-04-01', 'draft', 100, 20, 120) RETURNING id INTO v_facture;
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  DELETE FROM customers WHERE id = v_client;
  PERFORM _mesure239();
  SELECT count(*) INTO v_n FROM customers WHERE id = v_client;
  PERFORM _rec('P6', 'un administrateur écrit et supprime toujours (non-régression)',
    v_state IS NULL AND v_n = 0,
    format('création=%s, client supprimé=%s (attendu 0) | %s',
           CASE WHEN v_state IS NULL THEN 'acceptée' ELSE 'refusée ' || v_state END, v_n, left(v_err, 40)));

  -- P7 — comptable : écrit la comptabilité, ne supprime pas un tiers
  PERFORM _as239(ta, 'accountant');
  INSERT INTO customers (tenant_id, name) VALUES (ta, 'Client comptable') RETURNING id INTO v_client;
  v_state := NULL;
  BEGIN
    INSERT INTO invoices (tenant_id, number, customer_id, due_date, status, subtotal, vat_total, total)
    VALUES (ta, 'FA-PERM-CPT', v_client, '2026-04-01', 'draft', 100, 20, 120) RETURNING id INTO v_facture;
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  DELETE FROM customers WHERE id = v_client;
  PERFORM _mesure239();
  SELECT count(*) INTO v_n FROM customers WHERE id = v_client;
  PERFORM _rec('P7', 'un comptable écrit les factures mais ne supprime pas un tiers (la matrice est mesurée)',
    v_state IS NULL AND v_n = 1,
    format('création=%s, tiers encore présent=%s (attendu 1)',
           CASE WHEN v_state IS NULL THEN 'acceptée' ELSE 'refusée ' || v_state END, v_n));

  -- P8 — auditeur : lit, n'écrit pas. La mesure porte sur l'identifiant de la
  -- facture écrite par le comptable : chercher par numéro ne mesurerait rien,
  -- puisque la numérotation réécrit le numéro du brouillon.
  PERFORM _as239(ta, 'auditor');
  v_state := NULL;
  BEGIN
    UPDATE invoices SET total = 3 WHERE id = v_facture;
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  PERFORM _mesure239();
  SELECT count(*) INTO v_n FROM invoices WHERE id = v_facture AND total = 3;
  PERFORM _rec('P8', 'un auditeur lit sans écrire',
    (v_state = '42501' OR v_state IS NULL) AND v_n = 0,
    format('SQLSTATE=%s, lignes réécrites=%s (attendu 0)', COALESCE(v_state, 'aucune erreur'), v_n));

  -- P9 — manager : le commercial oui, la comptabilité non
  PERFORM _as239(ta, 'manager');
  v_state := NULL;
  BEGIN
    INSERT INTO customers (tenant_id, name) VALUES (ta, 'Client manager');
  EXCEPTION WHEN others THEN v_state := SQLSTATE; v_err := SQLERRM;
  END;
  v_state_ecriture := NULL;
  BEGIN
    INSERT INTO journal_entries (tenant_id, number, date, journal_code, status)
    VALUES (ta, 'OD-PERM', CURRENT_DATE, 'OD', 'draft');
  EXCEPTION WHEN others THEN v_state_ecriture := SQLSTATE;
  END;
  PERFORM _mesure239();
  PERFORM _rec('P9', 'un manager écrit le commercial, pas la comptabilité',
    v_state IS NULL AND v_state_ecriture = '42501',
    format('création de tiers=%s, écriture comptable=%s (attendu 42501)',
           COALESCE(v_state, 'acceptée'), COALESCE(v_state_ecriture, 'acceptée')));
END $$;

SELECT _audit_assert('239');

