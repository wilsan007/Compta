-- ============================================================
-- check_policy_duplicates.sql — ISO-03 / ISO-04 (vague W0.4)
--
-- LE DÉFAUT QUE CE CONTRÔLE FERME. Mesuré le 24/09/2026 sur base neuve
-- (214 migrations) : **1 739 politiques RLS**, dont **495 couples (table,
-- commande) portant DEUX politiques permissives** sur 127 tables — soit 1 001
-- politiques. Le motif est toujours le même : une politique générique
-- `tenant_select` (posée par la 74) **et** une politique par table
-- `tenant_select_<table>` (posée par la 84 et les suivantes).
--
-- POURQUOI C'EST UNE FAILLE, ET PAS UNE REDONDANCE. Deux politiques
-- **permissives** sur la même (table, commande) sont **OU**-ées par PostgreSQL :
-- la plus large gagne. Or les politiques par table portent les gardes de droits
-- (`can_perform('commercial.invoice.create')`, 38 d'entre elles) : dès qu'une
-- politique générique sans garde les accompagne, la garde devient **inopérante**,
-- y compris par appel direct à PostgREST. Un `viewer` peut alors créer une
-- facture si l'écran le lui permet n'est plus la question : la base le permet.
--
-- LA RÈGLE. Deux politiques **permissives** sur le même `(table, commande)` sont
-- refusées. Une politique **restrictive** (`AS RESTRICTIVE`) en doublon est
-- légitime : elle se combine en **ET**, donc elle restreint — le contrôle ne
-- regarde que les permissives.
--
-- LE REGISTRE A ÉTÉ VIDÉ PAR LA 238. Ces couples étaient inscrits, un par table,
-- avec les commandes concernées (`r`=SELECT, `a`=INSERT, `w`=UPDATE, `d`=DELETE) :
-- ce n'était pas une autorisation, mais un plafond daté, au périmètre exact de la
-- migration. La 238 les a tous retirés (496 politiques), et le registre a
-- disparu dans le même commit — le fichier ne garde donc plus que la règle et
-- son auto-test. Même contrat que `ci/expected_failures.sql` et
-- `ci/check_tenant_guard.sql` : si un jour un couple doublé doit être toléré, il
-- s'inscrit ici avec sa raison, et disparaît avec le défaut.
--
-- CE QUE LE CONTRÔLE NE PROUVE PAS. Il ne lit pas le corps des politiques : deux
-- politiques jumelles de même portée sémantique ne sont pas détectées comme
-- égales, et une politique permissive **unique** mais sans garde reste
-- silencieuse — c'est l'objet de la 239 (rôles opposables), puis de
-- `ci/check_roles_opposables.sql`.
-- ============================================================

\set ON_ERROR_STOP on

-- ------------------------------------------------------------
-- 1. Le détecteur
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_permissives_doubles AS
SELECT p.polrelid,
       p.polcmd,
       count(*) AS n,
       array_agg(p.polname ORDER BY p.polname) AS noms
FROM pg_policy p
WHERE p.polpermissive
GROUP BY p.polrelid, p.polcmd
HAVING count(*) > 1;

-- ------------------------------------------------------------
-- 2. L'auto-test : un contrôle qui n'a jamais vu une fixture fausse ne prouve rien
--    (§4.7, contre-épreuve par réintroduction). La fixture est une table
--    temporaire portant **deux** politiques permissives SELECT.
-- ------------------------------------------------------------
CREATE TEMP TABLE selftest_doublon (id int, tenant_id uuid);
CREATE POLICY a_selftest_doublon ON selftest_doublon FOR SELECT USING (true);
CREATE POLICY b_selftest_doublon ON selftest_doublon FOR SELECT USING (true);

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n
  FROM pg_temp.w_permissives_doubles d
  WHERE d.polrelid = 'selftest_doublon'::regclass AND d.polcmd = 'r';
  IF n <> 1 THEN
    RAISE EXCEPTION
      '[ISO-03] le détecteur est aveugle : deux politiques permissives jumelles ne sont pas vues (n=%).',
      n;
  END IF;
END $$;

DROP TABLE selftest_doublon;  -- emporte ses deux politiques

-- ------------------------------------------------------------
-- 3. Les doublons du schéma public
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pg_temp.w_doublons_publics AS
SELECT c.relname AS table_name, d.polcmd, d.n, d.noms
FROM pg_temp.w_permissives_doubles d
JOIN pg_class c ON c.oid = d.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public';

-- ------------------------------------------------------------
-- 4. Le verdict
-- ------------------------------------------------------------
DO $$
DECLARE
  v_couples int;
  v_politiques int;
  v_permissives int;
  v_liste text;
BEGIN
  SELECT count(*), coalesce(sum(n), 0) INTO v_couples, v_politiques
  FROM pg_temp.w_doublons_publics;

  SELECT count(*) INTO v_permissives
  FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE p.polpermissive;

  -- Un contrôle qui n'examine rien ne prouve rien (cf. B3 du 18/09) :
  -- 1 233 politiques permissives attendues après la 238, 1 739 avant (506
  -- retirées : 495 couples, dont 11 en portaient trois).
  IF v_permissives < 1000 THEN
    RAISE EXCEPTION '[ISO-03] le relevé ne voit que % politique(s) permissive(s) — le détecteur est cassé, ou le schéma n''est pas chargé', v_permissives;
  END IF;

  RAISE NOTICE '[ISO-03] % politique(s) permissive(s) sur le schéma public, % couple(s) (table, commande) doublé(s).',
    v_permissives, v_couples;

  IF v_couples > 0 THEN
    SELECT string_agg(format('    %s(%s) ×%s → %s', d.table_name, d.polcmd, d.n, array_to_string(d.noms, ' + ')),
                      E'\n' ORDER BY d.table_name, d.polcmd)
      INTO v_liste
    FROM pg_temp.w_doublons_publics d;

    RAISE EXCEPTION E'[ISO-03] politique(s) permissive(s) jumelle(s) : deux politiques permissives se combinent en OU, la plus large gagne, et la garde `can_perform` de l''autre est annulée.\n%',
      v_liste;
  END IF;

  RAISE NOTICE '[ISO-03] une seule politique permissive par (table, commande) — aucune garde ne peut être annulée par une jumelle.';
END $$;
