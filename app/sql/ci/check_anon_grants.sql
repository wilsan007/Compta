-- ============================================================
-- check_anon_grants.sql — ce qu'un visiteur non connecté peut appeler
--
-- LE DÉFAUT QUE CE CONTRÔLE FERME (H09). Le 23/09, sur base neuve :
-- 332 des 389 fonctions de `public` étaient exécutables par `anon`, le rôle
-- du visiteur non connecté — dont 75 des 96 RPC de l'écran, et trois fonctions
-- SECURITY DEFINER qui écrivent, vérifiées en les appelant sans jeton
-- (auto_revoke_expired_auditors, generate_recurring_tasks,
-- cleanup_expired_idempotency). Personne n'avait écrit ces GRANT :
-- `CREATE FUNCTION` accorde EXECUTE à PUBLIC par défaut, et l'image Supabase
-- accorde en plus `anon` par ALTER DEFAULT PRIVILEGES. La migration 78 avait
-- révoqué en son temps ; 149 migrations plus tard, tout était revenu.
--
-- LA RÈGLE. Aucune fonction de `public` n'est exécutable par `anon` ni par
-- PUBLIC, sauf celles inscrites au registre ci-dessous avec leur raison.
-- La 228 révoque et modifie les privilèges par défaut du schéma ; ce contrôle
-- est là pour le jour où une migration les rétablira sans le vouloir.
--
-- POURQUOI UN CONTRÔLE ET PAS UN PRIVILÈGE PAR DÉFAUT. Parce que le droit
-- PUBLIC de `CREATE FUNCTION` ne se retire pas d'avance : mesuré le 23/09,
-- après `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`,
-- une fonction créée ensuite a `proacl = NULL` — le droit par défaut, EXECUTE à
-- PUBLIC — et `has_function_privilege('anon', …)` rend toujours vrai. La
-- révocation des privilèges par défaut ne mord que sur les GRANT stockés
-- (`anon`, posé par l'image Supabase). Toute migration qui crée une fonction
-- ramène donc PUBLIC, et c'est ici qu'on l'apprend.
--
-- CE QUE LE CONTRÔLE NE PROUVE PAS. Il lit des droits, pas des corps : une
-- fonction réservée à `authenticated` peut rester dangereuse (c'est l'objet de
-- ci/check_tenant_guard.sql), et une fonction du registre peut le devenir si
-- on lui ajoute un effet. Le registre se relit à chaque ajout.
--
-- LE REGISTRE. Une ligne par exception justifiée, arguments compris (une
-- surcharge inscrite ne couvre pas les autres). Dès qu'un nom y figure sans
-- être exposé — droit retiré, fonction disparue — la CI échoue aussi : le
-- registre doit être nettoyé dans le même commit, sinon il pourrit.
-- Même contrat que ci/expected_failures.sql et ci/check_tenant_guard.sql.
-- ============================================================

CREATE TEMP TABLE anon_grants_registre (nom text, args text, raison text);

INSERT INTO anon_grants_registre (nom, args, raison) VALUES
  ('current_tenant_id', '',
   'Appelée par les politiques RLS des tables de référence lisibles sans connexion (currencies, legislation_packs, tax_rates) : sans ce droit, la page d''inscription reçoit « permission denied for function current_tenant_id ». Rend NULL pour un visiteur.'),
  ('available_signup_countries', '',
   'Liste des pays ouverts à l''inscription, lue par l''écran d''inscription. Référentiel, aucune donnée de société.');

CREATE TEMP TABLE anon_grants_corpus AS
SELECT p.oid,
       p.proname AS nom,
       pg_get_function_identity_arguments(p.oid) AS args,
       -- proacl NULL = droit par défaut de PostgreSQL, c'est-à-dire EXECUTE à
       -- PUBLIC : le cas d'une fonction toute neuve, celui qu'on cherche.
       (p.proacl IS NULL
        OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                   WHERE (a).privilege_type = 'EXECUTE' AND (a).grantee = 0)) AS via_public,
       EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
               WHERE (a).privilege_type = 'EXECUTE'
                 AND (a).grantee = (SELECT oid FROM pg_roles WHERE rolname = 'anon')) AS via_anon,
       p.prosecdef
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
  -- L'outillage des suites de test (_rec, _mk_tenant, _as_user…) est créé par
  -- ci/audit_helpers.sql dans la base de CI, jamais par une migration : il
  -- n'existe pas en production. Ce contrôle passe d'ailleurs AVANT les suites.
  AND p.proname NOT LIKE '\_%';

CREATE TEMP TABLE anon_grants_verdicts AS
SELECT c.nom, c.args, c.via_public, c.via_anon, c.prosecdef,
       EXISTS (SELECT 1 FROM anon_grants_registre r WHERE r.nom = c.nom AND r.args = c.args) AS inscrite
FROM anon_grants_corpus c
WHERE c.via_public OR c.via_anon;

DO $$
DECLARE
  v_corpus int; v_exposees int; v_inscrites int; v_definer int;
  v_hors text; v_perimees text; v_row record;
BEGIN
  SELECT count(*) INTO v_corpus FROM anon_grants_corpus;
  IF v_corpus = 0 THEN
    RAISE EXCEPTION 'check_anon_grants : aucune fonction examinée — le contrôle ne vérifie rien';
  END IF;

  SELECT count(*), count(*) FILTER (WHERE inscrite), count(*) FILTER (WHERE prosecdef)
    INTO v_exposees, v_inscrites, v_definer FROM anon_grants_verdicts;

  FOR v_row IN SELECT * FROM anon_grants_verdicts WHERE NOT inscrite ORDER BY nom, args LOOP
    RAISE NOTICE '❌ appelable sans connexion : %(%) [%]',
      v_row.nom, left(v_row.args, 60),
      trim(CASE WHEN v_row.via_public THEN 'PUBLIC ' ELSE '' END ||
           CASE WHEN v_row.via_anon THEN 'anon' ELSE '' END);
  END LOOP;

  SELECT string_agg(nom || '(' || left(args, 60) || ')', ', ' ORDER BY nom) INTO v_hors
  FROM anon_grants_verdicts WHERE NOT inscrite;

  SELECT string_agg(x, ', ' ORDER BY x) INTO v_perimees FROM (
    SELECT reg.nom || '(' || left(reg.args, 60) || ')' AS x
    FROM anon_grants_registre reg
    LEFT JOIN anon_grants_verdicts v ON v.nom = reg.nom AND v.args = reg.args
    WHERE v.nom IS NULL
  ) s;

  RAISE NOTICE 'check_anon_grants : % fonction(s) dans public, % exposée(s) sans connexion (% SECURITY DEFINER), % inscrite(s) au registre',
    v_corpus, v_exposees, v_definer, v_inscrites;

  IF v_hors IS NOT NULL THEN
    RAISE EXCEPTION E'check_anon_grants : % fonction(s) appelables par un visiteur non connecté :\n  %\n'
      '  Révoquez-les (REVOKE EXECUTE … FROM PUBLIC, anon) dans une migration, ou inscrivez-les au registre de ci/check_anon_grants.sql avec leur raison.',
      (SELECT count(*) FROM anon_grants_verdicts WHERE NOT inscrite), v_hors;
  END IF;
  IF v_perimees IS NOT NULL THEN
    RAISE EXCEPTION E'check_anon_grants : registre périmé — ces lignes ne sont plus exposées ou ont disparu :\n  %\n'
      '  Retirez-les de ci/check_anon_grants.sql dans le même commit.', v_perimees;
  END IF;

  RAISE NOTICE 'Droits du visiteur : OK — % fonction(s) examinée(s), % exposée(s), toutes inscrites', v_corpus, v_exposees;
END;
$$;
