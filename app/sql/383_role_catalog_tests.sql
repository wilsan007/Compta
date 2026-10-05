-- ============================================================
-- 383_role_catalog_tests.sql — LOT 1-B : le catalogue fermé des rôles
--
--   T01  account_role_catalog porte les 67 rôles de l'annexe B.1 ;
--   T02  journal_role_catalog porte les 8 rôles de l'annexe B.2 ;
--   T03  les CHECK tiennent (normal_side, forme du nom de rôle) ;
--   T04  une table de pack ne peut mapper qu'un rôle DU catalogue (clé étrangère) ;
--   T05  RLS : lisible par un connecté, NON écrivable ;
--   T06  rejouable : un second chargement n'ajoute aucun rôle.
--
-- Vu ROUGE avant la 383 : T01/T02 (tables absentes), T03/T04/T05 (contraintes
-- absentes). T06 sans objet.
-- ============================================================
\ir ci/audit_helpers.sql
SELECT set_config('audit.file', '383', false);
DELETE FROM _audit_results WHERE file = '383';

-- ─────────────────────────────────────────────────────────────
-- T01 / T02 — le compte des rôles
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_comptes int; v_journaux int;
BEGIN
  SELECT count(*) INTO v_comptes FROM account_role_catalog;
  SELECT count(*) INTO v_journaux FROM journal_role_catalog;
  PERFORM _rec('T01', 'account_role_catalog porte les 67 rôles de l''annexe B.1',
    v_comptes = 67, format('%s rôle(s) de comptes (67 attendus)', v_comptes));
  PERFORM _rec('T02', 'journal_role_catalog porte les 8 rôles de l''annexe B.2',
    v_journaux = 8, format('%s rôle(s) de journaux (8 attendus)', v_journaux));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T01', 'account_role_catalog porte les 67 rôles de l''annexe B.1', false, SQLERRM);
  PERFORM _rec('T02', 'journal_role_catalog porte les 8 rôles de l''annexe B.2', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T03 — les CHECK des catalogues
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE a boolean := false; b boolean := false;
BEGIN
  BEGIN  -- normal_side hors debit/credit
    INSERT INTO account_role_catalog (role, family, normal_side) VALUES ('ZZ_SIDE', 'divers', 'milieu');
  EXCEPTION WHEN check_violation THEN a := true; END;
  BEGIN  -- nom de rôle en minuscules
    INSERT INTO account_role_catalog (role, family, normal_side) VALUES ('zz_minuscule', 'divers', 'debit');
  EXCEPTION WHEN check_violation THEN b := true; END;

  DELETE FROM account_role_catalog WHERE role IN ('ZZ_SIDE', 'zz_minuscule');
  PERFORM _rec('T03', 'les CHECK des catalogues tiennent (sens debit/credit, nom en MAJUSCULES)',
    a AND b, format('normal_side invalide refusé=%s ; nom minuscule refusé=%s', a, b));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T03', 'les CHECK des catalogues tiennent (sens debit/credit, nom en MAJUSCULES)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T04 — une table de pack ne mappe qu'un rôle DU catalogue
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE refuse boolean := false; accepte boolean := false;
BEGIN
  BEGIN  -- rôle inconnu → refusé
    INSERT INTO pack_account_roles (pack_code, role, account_code)
      VALUES ('FR', 'ROLE_INEXISTANT', '411000');
  EXCEPTION WHEN foreign_key_violation THEN refuse := true; END;

  BEGIN  -- rôle connu → accepté
    INSERT INTO pack_account_roles (pack_code, role, account_code)
      VALUES ('FR', 'CLIENTS', '411000')
    ON CONFLICT (pack_code, role) DO UPDATE SET account_code = EXCLUDED.account_code;
    accepte := true;
  EXCEPTION WHEN OTHERS THEN accepte := false; END;

  DELETE FROM pack_account_roles WHERE pack_code = 'FR' AND role IN ('ROLE_INEXISTANT','CLIENTS');

  PERFORM _rec('T04', 'pack_account_roles n''accepte qu''un rôle DU catalogue (clé étrangère)',
    refuse AND accepte,
    format('rôle inconnu refusé=%s ; rôle connu accepté=%s', refuse, accepte));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T04', 'pack_account_roles n''accepte qu''un rôle DU catalogue (clé étrangère)', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T05 — RLS : lisible par un connecté, non écrivable
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE ecrit text := 'accepté';
BEGIN
  PERFORM _as_user();
  BEGIN
    INSERT INTO account_role_catalog (role, family, normal_side) VALUES ('ZZ_RLS', 'divers', 'debit');
  EXCEPTION WHEN OTHERS THEN ecrit := 'refusé'; END;
  EXECUTE 'RESET ROLE';
  DELETE FROM account_role_catalog WHERE role = 'ZZ_RLS';
  PERFORM _rec('T05', 'les catalogues sont sous RLS : lecture par un connecté, écriture refusée',
    ecrit = 'refusé', format('écriture connectée=%s', ecrit));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T05', 'les catalogues sont sous RLS : lecture par un connecté, écriture refusée', false, SQLERRM);
END $$;

-- ─────────────────────────────────────────────────────────────
-- T06 — rejouable : un second chargement n'ajoute rien
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE v_av int; v_ap int;
BEGIN
  SELECT count(*) INTO v_av FROM account_role_catalog;
  INSERT INTO account_role_catalog (role, family, normal_side, required_for) VALUES
    ('CLIENTS', 'tiers', 'debit', ARRAY['sales','pos']),
    ('TVA_COLLECTEE', 'taxes', 'credit', ARRAY['sales','pos'])
  ON CONFLICT (role) DO NOTHING;
  SELECT count(*) INTO v_ap FROM account_role_catalog;
  PERFORM _rec('T06', 'rejouable : un second chargement n''ajoute aucun rôle',
    v_av = v_ap AND v_ap = 67, format('%s → %s rôle(s)', v_av, v_ap));
EXCEPTION WHEN OTHERS THEN
  PERFORM _rec('T06', 'rejouable : un second chargement n''ajoute aucun rôle', false, SQLERRM);
END $$;

SELECT _audit_assert('383');
